#!/usr/bin/env python3
"""Generate demo ROM hex file for 65C02 DVI text display."""

ROM_SIZE = 4096
BASE = 0xF000

rom = bytearray(ROM_SIZE)
pc = 0

def emit(*bs):
    global pc
    for b in bs:
        rom[pc] = b & 0xFF
        pc += 1

def org(addr):
    global pc
    pc = addr - BASE

def put_string(addr, s):
    off = addr - BASE
    for c in s:
        rom[off] = ord(c)
        off += 1
    rom[off] = 0

# ---- Data tables (at $F100+, safely past program code) ----

# Hex lookup table at $F100
org(0xF100)
put_string(0xF100, "0123456789ABCDEF")

# Title string at $F120
put_string(0xF120, "65C02 DCIM CPU")

# Subtitle at $F140
put_string(0xF140, "Tang Nano 20K - DVI Demo")

# Counter label at $F160
put_string(0xF160, "Counter: $")

# ---- Program ----
org(0xF000)

# -- Clear screen: fill $2000-$29FF with $20 (space) --
# Set up ZP pointer: $02/$03 = $2000
emit(0xA9, 0x00)        # LDA #$00
emit(0x85, 0x02)        # STA $02
emit(0xA9, 0x20)        # LDA #$20
emit(0x85, 0x03)        # STA $03
emit(0xA0, 0x00)        # LDY #$00
emit(0xA9, 0x20)        # LDA #$20       ; space character

# clear_loop ($F00C):
clear_loop = BASE + pc
emit(0x91, 0x02)        # STA ($02),Y
emit(0xC8)              # INY
emit(0xD0, 0xFB)        # BNE clear_loop (-5)
emit(0xE6, 0x03)        # INC $03
emit(0xA6, 0x03)        # LDX $03
emit(0xE0, 0x2A)        # CPX #$2A       ; stop at page $2A
emit(0xD0, 0xF3)        # BNE clear_loop (-13)

# -- Copy title to row 0 ($2000) --
emit(0xA2, 0x00)        # LDX #$00
copy_title = BASE + pc
emit(0xBD, 0x20, 0xF1)  # LDA $F120,X
emit(0xF0, 0x06)        # BEQ +8 (skip to next section)
emit(0x9D, 0x00, 0x20)  # STA $2000,X
emit(0xE8)              # INX
emit(0xD0, 0xF5)        # BNE copy_title (-11)

# -- Copy subtitle to row 1 ($2050 = $2000 + 80) --
emit(0xA2, 0x00)        # LDX #$00
copy_sub = BASE + pc
emit(0xBD, 0x40, 0xF1)  # LDA $F140,X
emit(0xF0, 0x06)        # BEQ +8
emit(0x9D, 0x50, 0x20)  # STA $2050,X
emit(0xE8)              # INX
emit(0xD0, 0xF5)        # BNE copy_sub (-11)

# -- Copy counter label to row 3 ($20F0 = $2000 + 240) --
emit(0xA2, 0x00)        # LDX #$00
copy_lbl = BASE + pc
emit(0xBD, 0x60, 0xF1)  # LDA $F160,X
emit(0xF0, 0x06)        # BEQ +8
emit(0x9D, 0xF0, 0x20)  # STA $20F0,X
emit(0xE8)              # INX
emit(0xD0, 0xF5)        # BNE copy_lbl (-11)

# -- Initialize counter at $10/$11 to 0 --
emit(0xA9, 0x00)        # LDA #$00
emit(0x85, 0x10)        # STA $10
emit(0x85, 0x11)        # STA $11

# -- Main loop: delay, increment, display --
main_loop = BASE + pc

# Delay loop (~330K cycles ≈ 13ms at 25MHz)
emit(0xA2, 0x00)        # LDX #$00
emit(0xA0, 0x00)        # LDY #$00
delay = BASE + pc
emit(0x88)              # DEY
emit(0xD0, 0xFD)        # BNE delay (-3)
emit(0xCA)              # DEX
emit(0xD0, 0xFA)        # BNE delay (-6)

# Increment 16-bit counter at $10/$11
emit(0xE6, 0x10)        # INC $10
emit(0xD0, 0x02)        # BNE +4 (skip high byte inc)
emit(0xE6, 0x11)        # INC $11

# Display $11 high nibble at row 3, col 10 ($20FA)
emit(0xA5, 0x11)        # LDA $11
emit(0x4A)              # LSR A
emit(0x4A)              # LSR A
emit(0x4A)              # LSR A
emit(0x4A)              # LSR A
emit(0xAA)              # TAX
emit(0xBD, 0x00, 0xF1)  # LDA $F100,X
emit(0x8D, 0xFA, 0x20)  # STA $20FA

# Display $11 low nibble
emit(0xA5, 0x11)        # LDA $11
emit(0x29, 0x0F)        # AND #$0F
emit(0xAA)              # TAX
emit(0xBD, 0x00, 0xF1)  # LDA $F100,X
emit(0x8D, 0xFB, 0x20)  # STA $20FB

# Display $10 high nibble
emit(0xA5, 0x10)        # LDA $10
emit(0x4A)              # LSR A
emit(0x4A)              # LSR A
emit(0x4A)              # LSR A
emit(0x4A)              # LSR A
emit(0xAA)              # TAX
emit(0xBD, 0x00, 0xF1)  # LDA $F100,X
emit(0x8D, 0xFC, 0x20)  # STA $20FC

# Display $10 low nibble
emit(0xA5, 0x10)        # LDA $10
emit(0x29, 0x0F)        # AND #$0F
emit(0xAA)              # TAX
emit(0xBD, 0x00, 0xF1)  # LDA $F100,X
emit(0x8D, 0xFD, 0x20)  # STA $20FD

# Loop back
jmp_target = main_loop - BASE
emit(0x4C, jmp_target & 0xFF, (jmp_target >> 8) & 0xFF | 0xF0)

# ---- Vectors ----
org(0xFFFA)
emit(0x00, 0xF0)        # NMI   → $F000
emit(0x00, 0xF0)        # RESET → $F000
emit(0x00, 0xF0)        # IRQ   → $F000

# ---- Output ----
with open("demo.hex", "w") as f:
    for b in rom:
        f.write(f"{b:02X}\n")

print(f"Generated demo.hex ({ROM_SIZE} bytes, program {pc} bytes used)")
