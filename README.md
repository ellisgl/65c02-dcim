# 65C02 + DCIM zero page

A 65C02 whose zero page lives on-die in a digital compute-in-memory (DCIM)
macro. Read-modify-write and bit instructions on zero page execute inside the
array in one cycle, and zero-page traffic never reaches the external bus.

Base core: Arlet Ottens' 6502 with the Banks/Spittles 65C02 extensions
(github.com/hoglet67/verilog-6502), original copyright notice retained.

The goal is to match the 65C02 instruction set, not its cycle timing. DCIM and FIND are always built in; the core has no configuration parameters.

## Files

```
rtl/cpu_65c02_dcim.v   CPU core (FSM) plus DCIM glue
rtl/decode_65c02.v     combinational instruction decoder
rtl/ALU.v              core ALU (module is ALU6502; "ALU" clashes with a Gowin primitive)
rtl/zp_dcim.v          DCIM macro: 2x128x8 even/odd banks, periphery compute, FIND CAM
rtl/video_timing.v     640x480@60 sync/active generator (demo)
rtl/tmds_encoder.v     DVI TMDS 8b/10b encoder (demo)

sim/tb_unit.v          runs a small program, prints per-instruction cycle counts and final state
sim/unit.hex           INW/DEW/INC/ASL/TSB/FIND checks
sim/rmw.hex            read-modify-write cycle counts
sim/wrap.hex           INW across $FF/$00
sim/bits.hex           RMB/SMB/BBR/BBS and D-clear-on-BRK checks
sim/tb_dormann.v       Klaus Dormann 6502 functional test harness (binary not included)

syn/top.v              minimal board top: CPU + 32KB RAM + 4KB ROM at $8000-$FFFF (mirrored)
syn/nano20k.cst        pins for top.v
syn/run.sh             build top.v (yowasp toolchain)
syn/top_demo.v         Tang Nano 20K DVI text demo
syn/nano20k_demo.cst   pins for the demo
syn/run_demo.sh        build the demo (oss-cad-suite toolchain)
syn/gen_demo.py        generates demo.hex (demo ROM)
syn/gen_font.py        generates font.hex (8x16 font, ASCII 32-126)
```

## Instruction set

All documented 65C02 opcodes from the base core, plus:

| Opcode        | Instruction      | Behaviour                                                        | Cycles |
|---------------|------------------|------------------------------------------------------------------|--------|
| `$07`..`$77`  | `RMB0-7 zp`      | clear one bit of a zero-page byte, no flags                      | 3 |
| `$87`..`$F7`  | `SMB0-7 zp`      | set one bit of a zero-page byte, no flags                        | 3 |
| `$0F`..`$7F`  | `BBR0-7 zp,rel`  | branch if bit clear                                              | 4, 5 taken |
| `$8F`..`$FF`  | `BBS0-7 zp,rel`  | branch if bit set                                                | 4, 5 taken |
| `$E3`         | `INW zp`         | 16-bit increment of zp, zp+1 (65CE02 encoding); N, Z from result | 3 |
| `$C3`         | `DEW zp`         | 16-bit decrement of zp, zp+1 (65CE02 encoding); N, Z from result | 3 |
| `$5B`         | `FIND`           | compare A with all 256 zero-page bytes: X = lowest matching address, C = found, Z = not found | 2 |

RMB/SMB/BBR/BBS follow the WDC/Rockwell encodings. INW, DEW and FIND are
extensions placed on opcodes that are 1-byte NOPs on a 65C02.

Not implemented: `WAI` (`$CB`) and `STP` (`$DB`) execute as 1-byte NOPs.

The D flag is cleared on BRK, IRQ, NMI and reset, as on a 65C02. The copy of P
pushed to the stack still holds the previous D.

## How the DCIM path works

- `dcim_ir` latches the opcode at DECODE.
- In ZP0 / ZPX1, `dcim_fire` asserts for read-modify-write opcodes, INW/DEW and
  RMB/SMB. The macro reads the operand, computes, and writes back on the same
  clock edge; flags return from the macro and the next state is FETCH, skipping
  READ and WRITE.
- The two banks hold even and odd addresses, so a 16-bit operation at A, A+1
  touches exactly one byte in each bank.
- Zero-page reads come from the macro through the DI mux, and `WE` is suppressed
  for `$00xx`, so the external bus sees no zero-page writes.
- BBR/BBS read the byte in ZP0, test the bit in BBX0 while the offset is
  fetched, then run the ordinary branch states.
- Reset is synchronous.

Cycle counts against the stock core:

| Instruction                         | Stock  | DCIM |
|-------------------------------------|--------|------|
| INC/DEC/ASL/LSR/ROL/ROR/TSB/TRB zp  | 5      | 3    |
| INC zp,X                            | 6      | 4    |
| RMB/SMB zp                          | 5 (WDC 65C02) | 3 |

The other zp,X read-modify-write opcodes take the same path as INC zp,X but
have not been measured individually.

## Verification

Unit programs, run with `tb_unit.v` (all pass on the current core):

| Program    | Checks |
|------------|--------|
| `unit.hex` | INW, INC, INC zp,X, ASL, TSB, DEW, FIND; zero ZP bus writes |
| `rmw.hex`  | cycle counts for the read-modify-write group |
| `wrap.hex` | INW across `$FF`/`$00` |
| `bits.hex` | RMB/SMB results with flags untouched, BBR/BBS taken/not taken forwards and backwards, D clear inside a BRK handler |

Klaus Dormann's 6502 functional test passed in 95,613,064 cycles with zero
zero-page bus writes (the stock core took 96,241,374 cycles with 512,089). That
run predates RMB/SMB/BBR/BBS and the D-flag change and has not been repeated
since.

Not covered by any test: IRQ, NMI and RDY (both testbenches tie them off), and
Dormann's 65C02 extended-opcode and decimal tests.

## FPGA results

Tang Nano 20K demo (GW2AR-18, oss-cad-suite yosys + nextpnr-himbaechel),
current core:

| LUT4          | DFF           | BSRAM   | Fmax (post-route) |
|---------------|---------------|---------|-------------------|
| 5303 / 20736  | 2323 / 15552  | 11 / 46 | 93 MHz            |

Earlier comparison, from when DCIM and FIND were build options (`top.v`, whole
design including 32KB RAM + 4KB ROM, 27 MHz constraint):

| Build        | LUT4 | MUX2_LUT5 | ALU | DFF  | RAM16SDP4 | BSRAM | 9K Fmax          | 20K Fmax |
|--------------|------|-----------|-----|------|-----------|-------|------------------|----------|
| stock        | 1110 | 277       | 56  | 134  | 2         | 18    | 34-35 MHz        | 68 MHz   |
| DCIM         | 1828 | 370       | 100 | 355  | 36        | 18    | 30-32 MHz        | 57 MHz   |
| DCIM + FIND  | 5340 | 666       | 100 | 2211 | 4         | 18    | ~46 MHz (1 seed) | 93 MHz   |

FIND is what moves the array from distributed RAM into flip-flops, since every
byte must be compared at once.

GW1NR-9 (Nano 9K): 8640 LUT4 / 6480 DFF / 270 RAM16SDP4 / 26 BSRAM.
GW2AR-18 (Nano 20K): 20736 LUT4 / 15552 DFF / 46 BSRAM.
9K Fmax ranges are from a 4-seed placer sweep.

## Tang Nano 20K DVI demo

`syn/top_demo.v` runs the CPU at the 25.2 MHz pixel clock and shows an 80x30
text screen (640x480@60, 8x16 font) over the HDMI connector, with a title and a
live 16-bit counter.

Clocking: 27 MHz -> rPLL -> 126 MHz serial clock -> CLKDIV /5 -> 25.2 MHz pixel
clock. On the Gowin rPLL, `CLKOUT = FCLKIN * (FBDIV_SEL+1) / (IDIV_SEL+1)` and
`VCO = CLKOUT * ODIV_SEL`; the VCO must stay within 500-1250 MHz on the GW2AR-18
or the PLL will not lock. `gowin_pll -i 27 -o 126 -d "GW2AR-18 C8/I7"` prints
valid settings.

Memory map:

| Range           | Contents |
|-----------------|----------|
| `$0000-$00FF`   | zero page (DCIM, inside the CPU) |
| `$0100-$1FFF`   | RAM |
| `$2000-$2FFF`   | video RAM, character at `$2000 + row*80 + column` |
| `$3000-$EFFF`   | unmapped |
| `$F000-$FFFF`   | ROM (`demo.hex`) |

LEDs (`led[0..5]` on pins 20, 19, 18, 17, 16, 15):

| LED      | Meaning |
|----------|---------|
| `led[0]` | always on: bitstream loaded |
| `led[1]` | PLL locked |
| `led[2]` | reset released |
| `led[3]` | blinks about once a second: video timing running |
| `led[4]` | button input reads high |
| `led[5]` | off |

The button on pin 88 resets the design. Its level at power-up is taken as
"released", so the polarity does not matter.

## Reproduce

Unit tests (Verilator):

```sh
cd sim
for p in unit rmw wrap bits; do
  verilator --binary --timing -Wno-fatal -GPROG="\"$p.hex\"" --top-module tb_unit \
      --Mdir obj_$p -o t tb_unit.v ../rtl/ALU.v ../rtl/decode_65c02.v \
      ../rtl/zp_dcim.v ../rtl/cpu_65c02_dcim.v
  ./obj_$p/t
done
```

Expected final line for `bits.hex`:
`A=37 X=05 ... $10/$11=7e 82  $20=05 $77=37  ZP bus writes=0`.

Dormann functional test (needs `6502_functional_test.bin` in `sim/`):

```sh
cd sim
python3 -c "d=open('6502_functional_test.bin','rb').read();open('func.hex','w').write('\n'.join('%02x'%b for b in d)+'\n')"
verilator --binary --timing -Wno-fatal --top-module tb_dormann --Mdir obj_dormann -o t \
    tb_dormann.v ../rtl/ALU.v ../rtl/decode_65c02.v ../rtl/zp_dcim.v ../rtl/cpu_65c02_dcim.v
./obj_dormann/t
```

Demo bitstream (expects oss-cad-suite at the path set in `run_demo.sh`):

```sh
cd syn
python3 gen_font.py && python3 gen_demo.py
./run_demo.sh demo            # writes demo.fs
```

Minimal top (expects the yowasp tools at the path set in `run.sh`):

```sh
cd syn && ./run.sh dcim
```

## License

BSD 3-Clause, see [LICENSE](LICENSE).

`rtl/cpu_65c02_dcim.v`, `rtl/decode_65c02.v` and `rtl/ALU.v` derive from the
Arlet Ottens 6502 core and the Banks/Spittles 65C02 extensions. Their original
notice, kept at the top of `rtl/cpu_65c02_dcim.v`, continues to apply to that
code and must be retained.
