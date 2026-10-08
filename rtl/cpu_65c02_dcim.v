`timescale 1ns / 1ps
/*
 * verilog model of 65C02 CPU.
 *
 * Based on original 6502 "Arlet 6502 Core" by Arlet Ottens
 *
 * (C) Arlet Ottens, <arlet@c-scape.nl>
 *
 * Feel free to use this code in any project (commercial or not), as long as you
 * keep this message, and the copyright notice. This code is provided "as is",
 * without any warranties of any kind.
 *
 * Support for 65C02 instructions and addressing modes by David Banks and Ed Spittles
 *
 * (C) 2016 David Banks and Ed Spittles
 *
 * Feel free to use this code in any project (commercial or not), as long as you
 * keep this message, and the copyright notice. This code is provided "as is",
 * without any warranties of any kind.
 *
 */

/*
 * The data bus is implemented as separate read/write buses. Combine them
 * on the output pads if external memory is required.
 */

/*
 * Two things were needed to correctly implement 65C02 NOPs
 * 1. Ensure the microcode state machine uses an appropriate addressing mode for the opcode length
 * 2. Ensure there are no side-effects (e.g. register updates, memory stores, etc)
 *
 */

/*
 * Two things were needed to correctly implement 65C02 BCD arithmentic
 * 1. The Z flag needs calculating over the BCD adjusted ALU output
 * 2. The N flag needs calculating over the BCD adjusted ALU output
 *
 */

module cpu_65c02_dcim (
    input             clk,
    input             reset,
    output reg [15:0] AB,
    input      [7:0]  DI,
    output reg [7:0]  DO,
    output            WE,
    input             IRQ,
    input             NMI,
    input             RDY,
    output reg        SYNC
);

/*
 * internal signals
 */

reg  [15:0] PC;
reg  [7:0]  ABL;
reg  [7:0]  ABH;
wire [7:0]  ADD;

reg  [7:0]  DIHOLD;
wire [7:0]  DIMUX;

reg  [7:0]  IRHOLD;
reg         IRHOLD_valid;

reg  [7:0]  AXYS[3:0];

reg         C;
reg         Z;
reg         I;
reg         D;
reg         V;
reg         N;

initial begin
    C = 0;
    Z = 0;
    I = 0;
    D = 0;
    V = 0;
    N = 0;
end

wire        AZ;
wire        AZ1;
reg         AZ2;
wire        AV;
wire        AN;
wire        AN1;
wire        HC;
reg  [7:0]  AI;
reg  [7:0]  BI;
wire [7:0]  IR;
wire [7:0]  AO;
reg         WE_i;
reg         CI;
wire        CO;
wire [7:0]  PCH = PC[15:8];
wire [7:0]  PCL = PC[7:0];

reg         NMI_edge;

initial begin
    NMI_edge = 0;
end

reg  [1:0]  regsel;
wire [7:0]  regfile = AXYS[regsel];

parameter
    SEL_A = 2'd0,
    SEL_S = 2'd1,
    SEL_X = 2'd2,
    SEL_Y = 2'd3;

/*
 * define some signals for watching in simulator output
 */
`ifdef SIM
wire [7:0] A = AXYS[SEL_A];
wire [7:0] X = AXYS[SEL_X];
wire [7:0] Y = AXYS[SEL_Y];
wire [7:0] S = AXYS[SEL_S];
`endif

wire [7:0] P = {N, V, 2'b11, D, I, Z, C};

/*
 * instruction decoder/sequencer
 */
reg [5:0] state;

/*
 * control signals
 */
reg        PC_inc;
reg [15:0] PC_temp;

reg [1:0]  src_reg;
reg [1:0]  dst_reg;

reg        index_y;
reg        load_reg;
reg        inc;
reg        write_back;
reg        load_only;
reg        store;
reg        adc_sbc;
reg        compare;
reg        shift;
reg        rotate;
reg        backwards;
reg        cond_true;
reg [3:0]  cond_code;
reg        shift_right;
reg        alu_shift_right;
reg [3:0]  op;
reg [3:0]  alu_op;
reg        adc_bcd;
reg        adj_bcd;

/*
 * some flip flops to remember we're doing special instructions. These
 * get loaded at the DECODE state, and used later
 */
reg        store_zero;
reg        trb_ins;
reg        txb_ins;
reg        bit_ins;
reg        bit_ins_nv;
reg        plp;
reg        php;
reg        clc;
reg        sec;
reg        cld;
reg        sed;
reg        cli;
reg        sei;
reg        clv;

reg        res;

reg        bb_ins;
reg        bb_taken;

initial begin
    bb_ins   = 0;
    bb_taken = 0;
end

/*
 * ALU operations
 */
parameter
    OP_ADD = 4'b0011,
    OP_SUB = 4'b0111;

/*
 * Microcode state machine. Basically, every addressing mode has its own
 * path through the state machine. Additional information, such as the
 * operation, source and destination registers are decoded in parallel, and
 * kept in separate flops.
 */

parameter
    ABS0   = 6'd0,
    ABS1   = 6'd1,
    ABSX0  = 6'd2,
    ABSX1  = 6'd3,
    ABSX2  = 6'd4,
    BRA0   = 6'd5,
    BRA1   = 6'd6,
    BRA2   = 6'd7,
    BRK0   = 6'd8,
    BRK1   = 6'd9,
    BRK2   = 6'd10,
    BRK3   = 6'd11,
    DECODE = 6'd12,
    FETCH  = 6'd13,
    INDX0  = 6'd14,
    INDX1  = 6'd15,
    INDX2  = 6'd16,
    INDX3  = 6'd17,
    INDY0  = 6'd18,
    INDY1  = 6'd19,
    INDY2  = 6'd20,
    INDY3  = 6'd21,
    JMP0   = 6'd22,
    JMP1   = 6'd23,
    JMPI0  = 6'd24,
    JMPI1  = 6'd25,
    JSR0   = 6'd26,
    JSR1   = 6'd27,
    JSR2   = 6'd28,
    JSR3   = 6'd29,
    PULL0  = 6'd30,
    PULL1  = 6'd31,
    PULL2  = 6'd32,
    PUSH0  = 6'd33,
    PUSH1  = 6'd34,
    READ   = 6'd35,
    REG    = 6'd36,
    RTI0   = 6'd37,
    RTI1   = 6'd38,
    RTI2   = 6'd39,
    RTI3   = 6'd40,
    RTI4   = 6'd41,
    RTS0   = 6'd42,
    RTS1   = 6'd43,
    RTS2   = 6'd44,
    RTS3   = 6'd45,
    WRITE  = 6'd46,
    ZP0    = 6'd47,
    ZPX0   = 6'd48,
    ZPX1   = 6'd49,
    IND0   = 6'd50,
    JMPIX0 = 6'd51,
    JMPIX1 = 6'd52,
    JMPIX2 = 6'd53,
    BBX0   = 6'd54;

`ifdef SIM

/*
 * easy to read names in simulator output
 */
reg [8*6-1:0] statename;

always @* begin
    case (state)
        DECODE: statename = "DECODE";
        REG:    statename = "REG";
        ZP0:    statename = "ZP0";
        ZPX0:   statename = "ZPX0";
        ZPX1:   statename = "ZPX1";
        ABS0:   statename = "ABS0";
        ABS1:   statename = "ABS1";
        ABSX0:  statename = "ABSX0";
        ABSX1:  statename = "ABSX1";
        ABSX2:  statename = "ABSX2";
        IND0:   statename = "IND0";
        INDX0:  statename = "INDX0";
        INDX1:  statename = "INDX1";
        INDX2:  statename = "INDX2";
        INDX3:  statename = "INDX3";
        INDY0:  statename = "INDY0";
        INDY1:  statename = "INDY1";
        INDY2:  statename = "INDY2";
        INDY3:  statename = "INDY3";
        READ:   statename = "READ";
        WRITE:  statename = "WRITE";
        FETCH:  statename = "FETCH";
        PUSH0:  statename = "PUSH0";
        PUSH1:  statename = "PUSH1";
        PULL0:  statename = "PULL0";
        PULL1:  statename = "PULL1";
        PULL2:  statename = "PULL2";
        JSR0:   statename = "JSR0";
        JSR1:   statename = "JSR1";
        JSR2:   statename = "JSR2";
        JSR3:   statename = "JSR3";
        RTI0:   statename = "RTI0";
        RTI1:   statename = "RTI1";
        RTI2:   statename = "RTI2";
        RTI3:   statename = "RTI3";
        RTI4:   statename = "RTI4";
        RTS0:   statename = "RTS0";
        RTS1:   statename = "RTS1";
        RTS2:   statename = "RTS2";
        RTS3:   statename = "RTS3";
        BRK0:   statename = "BRK0";
        BRK1:   statename = "BRK1";
        BRK2:   statename = "BRK2";
        BRK3:   statename = "BRK3";
        BRA0:   statename = "BRA0";
        BRA1:   statename = "BRA1";
        BRA2:   statename = "BRA2";
        JMP0:   statename = "JMP0";
        JMP1:   statename = "JMP1";
        JMPI0:  statename = "JMPI0";
        JMPI1:  statename = "JMPI1";
        JMPIX0: statename = "JMPIX0";
        JMPIX1: statename = "JMPIX1";
        JMPIX2: statename = "JMPIX2";
        BBX0:   statename = "BBX0";
        default: statename = "???";
    endcase
end

`endif

/*
 * Program Counter Increment/Load. First calculate the base value in
 * PC_temp.
 */
always @* begin
    case (state)
        DECODE: begin
            if ((~I & IRQ) | NMI_edge)
                PC_temp = {ABH, ABL};
            else
                PC_temp = PC;
        end

        JMP1,
        JMPI1,
        JMPIX1,
        JSR3,
        RTS3,
        RTI4:    PC_temp = {DIMUX, ADD};

        BRA1:    PC_temp = {ABH, ADD};

        JMPIX2,
        BRA2:    PC_temp = {ADD, PCL};

        BRK2:    PC_temp = res      ? 16'hfffc :
                            NMI_edge ? 16'hfffa : 16'hfffe;

        default: PC_temp = PC;
    endcase
end

/*
 * Determine whether we need PC_temp, or PC_temp + 1
 */
always @* begin
    case (state)
        DECODE: begin
            if ((~I & IRQ) | NMI_edge)
                PC_inc = 0;
            else
                PC_inc = 1;
        end

        ABS0,
        JMPIX0,
        JMPIX2,
        ABSX0,
        FETCH,
        BRA0,
        BBX0,
        BRA2,
        BRK3,
        JMPI1,
        JMP1,
        RTI4,
        RTS3:    PC_inc = 1;

        JMPIX1:  PC_inc = ~CO;
        BRA1:    PC_inc = CO ^~ backwards;
        default: PC_inc = 0;
    endcase
end

/*
 * Set new PC
 */
always @(posedge clk) begin
    if (RDY)
        PC <= PC_temp + PC_inc;
end

/*
 * Address Generator
 */

parameter
    ZEROPAGE  = 8'h00,
    STACKPAGE = 8'h01;

always @* begin
    case (state)
        JMPIX1,
        ABSX1,
        INDX3,
        INDY2,
        JMP1,
        JMPI1,
        RTI4,
        ABS1:    AB = {DIMUX, ADD};

        BRA2,
        INDY3,
        JMPIX2,
        ABSX2:   AB = {ADD, ABL};

        BRA1:    AB = {ABH, ADD};

        JSR0,
        PUSH1,
        RTS0,
        RTI0,
        BRK0:    AB = {STACKPAGE, regfile};

        BRK1,
        JSR1,
        PULL1,
        RTS1,
        RTS2,
        RTI1,
        RTI2,
        RTI3,
        BRK2:    AB = {STACKPAGE, ADD};

        INDY1,
        INDX1,
        ZPX1,
        INDX2:   AB = {ZEROPAGE, ADD};

        ZP0,
        INDY0:   AB = {ZEROPAGE, DIMUX};

        REG,
        READ,
        WRITE:   AB = {ABH, ABL};

        default: AB = PC;
    endcase
end

/*
 * ABH/ABL pair is used for registering previous address bus state.
 * This can be used to keep the current address, freeing up the original
 * source of the address, such as the ALU or DI.
 */
always @(posedge clk) begin
    if (state != PUSH0 && state != PUSH1 && RDY &&
        state != PULL0 && state != PULL1 && state != PULL2) begin
        ABL <= AB[7:0];
        ABH <= AB[15:8];
    end
end

/*
 * Data Out MUX
 */
always @* begin
    case (state)
        WRITE:   DO = ADD;
        JSR0,
        BRK0:    DO = PCH;
        JSR1,
        BRK1:    DO = PCL;
        PUSH1:   DO = php ? P : ADD;
        BRK2:    DO = (IRQ | NMI_edge) ? (P & 8'b1110_1111) : P;
        default: DO = store_zero ? 8'b0 : regfile;
    endcase
end

/*
 * Write Enable Generator
 */
always @* begin
    case (state)
        BRK0,
        BRK1,
        BRK2,
        JSR0,
        JSR1,
        PUSH1,
        WRITE:   WE_i = 1;

        INDX3,
        INDY3,
        ABSX2,
        ABS1,
        ZPX1,
        ZP0:     WE_i = store;

        default: WE_i = 0;
    endcase
end

/*
 * register file, contains A, X, Y and S (stack pointer) registers. At each
 * cycle only 1 of those registers needs to be accessed, so they combined
 * in a small memory, saving resources.
 */

reg write_register;

always @* begin
    case (state)
        DECODE:  write_register = load_reg & ~plp;
        PULL1,
        RTS2,
        RTI3,
        BRK3,
        JSR0,
        JSR2:    write_register = 1;
        default: write_register = 0;
    endcase
end

/*
 * BCD adjust logic
 */
always @(posedge clk) begin
    adj_bcd <= adc_sbc & D;
end

reg [3:0] ADJL;
reg [3:0] ADJH;

always @* begin
    casez ({adj_bcd, adc_bcd, HC})
        3'b0??: ADJL = 4'd0;
        3'b100: ADJL = 4'd10;
        3'b101: ADJL = 4'd0;
        3'b110: ADJL = 4'd0;
        3'b111: ADJL = 4'd6;
    endcase
end

always @* begin
    casez ({adj_bcd, adc_bcd, CO})
        3'b0??: ADJH = 4'd0;
        3'b100: ADJH = 4'd10;
        3'b101: ADJH = 4'd0;
        3'b110: ADJH = 4'd0;
        3'b111: ADJH = 4'd6;
    endcase
end

assign AO = {ADD[7:4] + ADJH, ADD[3:0] + ADJL};

assign AN1 = AO[7];
assign AZ1 = ~|AO;

/*
 * write to a register. Usually this is the (BCD corrected) output of the
 * ALU, but in case of the JSR0 we use the S register to temporarily store
 * the PCL. This is possible, because the S register itself is stored in
 * the ALU during those cycles.
 */
always @(posedge clk) begin
    if (find_fire)
        AXYS[SEL_X] <= find_idx;
    else if (write_register & RDY)
        AXYS[regsel] <= (state == JSR0) ? DIMUX : AO;
end

/*
 * register select logic. This determines which of the A, X, Y or
 * S registers will be accessed.
 */
always @* begin
    case (state)
        INDY1,
        INDX0,
        ZPX0,
        JMPIX0,
        ABSX0:   regsel = index_y ? SEL_Y : SEL_X;

        DECODE:  regsel = dst_reg;

        BRK0,
        BRK3,
        JSR0,
        JSR2,
        PULL0,
        PULL1,
        PUSH1,
        RTI0,
        RTI3,
        RTS0,
        RTS2:    regsel = SEL_S;

        default: regsel = src_reg;
    endcase
end

/*
 * ALU
 */
ALU6502 ALU (
    .clk   (clk),
    .op    (alu_op),
    .right (alu_shift_right),
    .AI    (AI),
    .BI    (BI),
    .CI    (CI),
    .BCD   (adc_bcd & (state == FETCH)),
    .CO    (CO),
    .OUT   (ADD),
    .V     (AV),
    .Z     (AZ),
    .N     (AN),
    .HC    (HC),
    .RDY   (RDY)
);

/*
 * Select current ALU operation
 */
always @* begin
    case (state)
        READ:    alu_op = op;
        BRA1:    alu_op = backwards ? OP_SUB : OP_ADD;
        FETCH,
        REG:     alu_op = op;
        PUSH1,
        BRK0,
        BRK1,
        BRK2,
        JSR0,
        JSR1:    alu_op = OP_SUB;
        default: alu_op = OP_ADD;
    endcase
end

/*
 * Determine shift right signal to ALU
 */
always @* begin
    if (state == FETCH || state == REG || state == READ)
        alu_shift_right = shift_right;
    else
        alu_shift_right = 0;
end

/*
 * Sign extend branch offset.
 */
always @(posedge clk) begin
    if (RDY)
        backwards <= DIMUX[7];
end

/*
 * ALU A Input MUX
 */
always @* begin
    case (state)
        JSR1,
        RTS1,
        RTI1,
        RTI2,
        BRK1,
        BRK2,
        INDX1:   AI = ADD;

        REG,
        ZPX0,
        INDX0,
        JMPIX0,
        ABSX0,
        RTI0,
        RTS0,
        JSR0,
        JSR2,
        BRK0,
        PULL0,
        INDY1,
        PUSH0,
        PUSH1:   AI = regfile;

        BRA0,
        READ:    AI = DIMUX;

        BRA1:    AI = ABH;

        FETCH:   AI = load_only ? 8'b0 : regfile;

        default: AI = 0;
    endcase
end

/*
 * ALU B Input mux
 */
always @* begin
    case (state)
        BRA1,
        RTS1,
        RTI0,
        RTI1,
        RTI2,
        INDX1,
        REG,
        JSR0,
        JSR1,
        JSR2,
        BRK0,
        BRK1,
        BRK2,
        PUSH0,
        PUSH1,
        PULL0,
        RTS0:    BI = 8'h00;

        READ:    BI = txb_ins ? (trb_ins ? ~regfile : regfile) : 8'h00;

        BRA0:    BI = PCL;

        default: BI = DIMUX;
    endcase
end

/*
 * ALU CI (carry in) mux
 */
always @* begin
    case (state)
        INDY2,
        BRA1,
        JMPIX1,
        ABSX1:   CI = CO;

        READ,
        REG:     CI = rotate ? C :
                      shift  ? 1'b0 : inc;

        FETCH:   CI = rotate             ? C :
                      compare            ? 1'b1 :
                      (shift | load_only) ? 1'b0 : C;

        PULL0,
        RTI0,
        RTI1,
        RTI2,
        RTS0,
        RTS1,
        INDY0,
        INDX1:   CI = 1;

        default: CI = 0;
    endcase
end

/*
 * Processor Status Register update
 *
 */

/*
 * Update C flag when doing ADC/SBC, shift/rotate, compare
 */
always @(posedge clk) begin
    if (dcim_fire & dcim_c_upd)
        C <= dcim_c;
    else if (find_fire)
        C <= find_found;
    else if (shift && state == WRITE)
        C <= CO;
    else if (state == RTI2)
        C <= DIMUX[0];
    else if (~write_back && state == DECODE) begin
        if (adc_sbc | shift | compare)
            C <= CO;
        else if (plp)
            C <= ADD[0];
        else begin
            if (sec) C <= 1;
            if (clc) C <= 0;
        end
    end
end

/*
 * Special Z flag for TRB/TSB
 */
always @(posedge clk) begin
    if (RDY)
        AZ2 <= ~|(AI & regfile);
end

/*
 * Update Z, N flags when writing A, X, Y, Memory, or when doing compare
 */
always @(posedge clk) begin
    if (dcim_fire & dcim_z_upd)
        Z <= dcim_z;
    else if (find_fire)
        Z <= ~find_found;
    else if (state == WRITE)
        Z <= txb_ins ? AZ2 : AZ1;
    else if (state == RTI2)
        Z <= DIMUX[1];
    else if (state == DECODE) begin
        if (plp)
            Z <= ADD[1];
        else if ((load_reg & (regsel != SEL_S)) | compare | bit_ins)
            Z <= AZ1;
    end
end

always @(posedge clk) begin
    if (dcim_fire & dcim_n_upd)
        N <= dcim_n;
    else if (state == WRITE && ~txb_ins)
        N <= AN1;
    else if (state == RTI2)
        N <= DIMUX[7];
    else if (state == DECODE) begin
        if (plp)
            N <= ADD[7];
        else if ((load_reg & (regsel != SEL_S)) | compare)
            N <= AN1;
    end else if (state == FETCH && bit_ins_nv)
        N <= DIMUX[7];
end

/*
 * Update I flag
 */
always @(posedge clk) begin
    if (state == BRK3)
        I <= 1;
    else if (state == RTI2)
        I <= DIMUX[2];
    else if (state == REG) begin
        if (sei) I <= 1;
        if (cli) I <= 0;
    end else if (state == DECODE) begin
        if (plp) I <= ADD[2];
    end
end

/*
 * Update D flag
 */
always @(posedge clk) begin
    if (state == RTI2)
        D <= DIMUX[3];
    else if (state == BRK3)
        D <= 0;
    else if (state == DECODE) begin
        if (sed) D <= 1;
        if (cld) D <= 0;
        if (plp) D <= ADD[3];
    end
end

/*
 * Update V flag
 */
always @(posedge clk) begin
    if (state == RTI2)
        V <= DIMUX[6];
    else if (state == DECODE) begin
        if (adc_sbc) V <= AV;
        if (clv)     V <= 0;
        if (plp)     V <= ADD[6];
    end else if (state == FETCH && bit_ins_nv)
        V <= DIMUX[6];
end

/*
 * Instruction decoder
 */

/*
 * IR register/mux. Hold previous DI value in IRHOLD in PULL0 and PUSH0
 * states. In these states, the IR has been prefetched, and there is no
 * time to read the IR again before the next decode.
 */
always @(posedge clk) begin
    if (reset)
        IRHOLD_valid <= 0;
    else if (RDY) begin
        if (state == PULL0 || state == PUSH0) begin
            IRHOLD       <= DIMUX;
            IRHOLD_valid <= 1;
        end else if (state == DECODE)
            IRHOLD_valid <= 0;
    end
end

assign IR    = (IRQ & ~I) | NMI_edge ? 8'h00 :
               IRHOLD_valid           ? IRHOLD : DIMUX;

always @(posedge clk) begin
    if (RDY)
        DIHOLD <= DI_int;
end

assign DIMUX = ~RDY ? DIHOLD : DI_int;

/*
 * Microcode state machine
 */
always @(posedge clk) begin
    if (reset)
        state <= BRK0;
    else if (RDY) begin
        case (state)
            DECODE: begin
                if (IR == 8'hE3 || IR == 8'hC3)
                    state <= ZP0;
                else if (IR == 8'h5B)
                    state <= REG;
                else if (IR[2:0] == 3'b111)
                    state <= ZP0;
                else begin
                    /* verilator lint_off CASEOVERLAP */
                    casez (IR)
                        8'b????_??11: state <= REG;
                        8'b???0_0010: state <= FETCH;
                        8'b0101_1100,
                        8'b1101_1100,
                        8'b1111_1100: state <= ABS0;
                        8'b0000_0000: state <= BRK0;
                        8'b0010_0000: state <= JSR0;
                        8'b0010_1100: state <= ABS0;
                        8'b1001_1100: state <= ABS0;
                        8'b000?_1100: state <= ABS0;
                        8'b0100_0000: state <= RTI0;
                        8'b0100_1100: state <= JMP0;
                        8'b0110_0000: state <= RTS0;
                        8'b0110_1100: state <= JMPI0;
                        8'b0111_1100: state <= JMPIX0;
                        8'b0?00_1000: state <= PUSH0;
                        8'b0?10_1000: state <= PULL0;
                        8'b0??1_1000: state <= REG;
                        8'b11?0_00?0: state <= FETCH;
                        8'b1?10_00?0: state <= FETCH;
                        8'b1??0_1100: state <= ABS0;
                        8'b1???_1000: state <= REG;
                        8'b???0_0001: state <= INDX0;
                        8'b???1_0010: state <= IND0;
                        8'b000?_0100: state <= ZP0;
                        8'b???0_01??: state <= ZP0;
                        8'b???0_1001: state <= FETCH;
                        8'b???0_1101: state <= ABS0;
                        8'b???0_1110: state <= ABS0;
                        8'b???1_0000: state <= BRA0;
                        8'b1000_0000: state <= BRA0;
                        8'b???1_0001: state <= INDY0;
                        8'b???1_01??: state <= ZPX0;
                        8'b???1_1001: state <= ABSX0;
                        8'b?011_1100: state <= ABSX0;
                        8'b???1_11?1: state <= ABSX0;
                        8'b???1_111?: state <= ABSX0;
                        8'b?101_1010: state <= PUSH0;
                        8'b?111_1010: state <= PULL0;
                        8'b?0??_1010: state <= REG;
                        8'b???0_1010: state <= REG;
                        default:      state <= REG;
                    endcase
                    /* verilator lint_on CASEOVERLAP */
                end
            end

            ZP0:    state <= bb_ins ? BBX0 :
                             dcim_fire ? FETCH : write_back ? READ : FETCH;
            BBX0:   state <= BRA0;

            ZPX0:   state <= ZPX1;
            ZPX1:   state <= dcim_fire ? FETCH : write_back ? READ : FETCH;

            ABS0:   state <= ABS1;
            ABS1:   state <= write_back ? READ : FETCH;

            ABSX0:  state <= ABSX1;
            ABSX1:  state <= (CO | store | write_back) ? ABSX2 : FETCH;
            ABSX2:  state <= write_back ? READ : FETCH;

            JMPIX0: state <= JMPIX1;
            JMPIX1: state <= CO ? JMPIX2 : JMP0;
            JMPIX2: state <= JMP0;

            IND0:   state <= INDX1;

            INDX0:  state <= INDX1;
            INDX1:  state <= INDX2;
            INDX2:  state <= INDX3;
            INDX3:  state <= FETCH;

            INDY0:  state <= INDY1;
            INDY1:  state <= INDY2;
            INDY2:  state <= (CO | store) ? INDY3 : FETCH;
            INDY3:  state <= FETCH;

            READ:   state <= WRITE;
            WRITE:  state <= FETCH;
            FETCH:  state <= DECODE;

            REG:    state <= DECODE;

            PUSH0:  state <= PUSH1;
            PUSH1:  state <= DECODE;

            PULL0:  state <= PULL1;
            PULL1:  state <= PULL2;
            PULL2:  state <= DECODE;

            JSR0:   state <= JSR1;
            JSR1:   state <= JSR2;
            JSR2:   state <= JSR3;
            JSR3:   state <= FETCH;

            RTI0:   state <= RTI1;
            RTI1:   state <= RTI2;
            RTI2:   state <= RTI3;
            RTI3:   state <= RTI4;
            RTI4:   state <= DECODE;

            RTS0:   state <= RTS1;
            RTS1:   state <= RTS2;
            RTS2:   state <= RTS3;
            RTS3:   state <= FETCH;

            BRA0:   state <= cond_true ? BRA1 : DECODE;
            BRA1:   state <= (CO ^ backwards) ? BRA2 : DECODE;
            BRA2:   state <= DECODE;

            JMP0:   state <= JMP1;
            JMP1:   state <= DECODE;

            JMPI0:  state <= JMPI1;
            JMPI1:  state <= JMP0;

            BRK0:   state <= BRK1;
            BRK1:   state <= BRK2;
            BRK2:   state <= BRK3;
            BRK3:   state <= JMP0;

            default: state <= BRK0;
        endcase
    end
end

/*
 * Sync state machine
 */
always @(posedge clk) begin
    if (reset)
        SYNC <= 1'b0;
    else if (RDY) begin
        case (state)
            BRA0:    SYNC <= !cond_true;
            BRA1:    SYNC <= !(CO ^ backwards);
            BRA2,
            FETCH,
            REG,
            PUSH1,
            PULL2,
            RTI4,
            JMP1:    SYNC <= 1'b1;
            default: SYNC <= 1'b0;
        endcase
    end
end

/*
 * Additional control signals
 */
always @(posedge clk) begin
    if (reset)
        res <= 1;
    else if (state == DECODE)
        res <= 0;
end

/*
 * Combinational instruction decoder
 */
wire       dec_load_reg, dec_index_y, dec_store, dec_write_back;
wire       dec_load_only, dec_inc, dec_adc_sbc, dec_is_adc;
wire       dec_shift, dec_compare, dec_shift_right, dec_rotate;
wire       dec_bit_ins, dec_bit_ins_nv, dec_txb_ins, dec_trb_ins;
wire       dec_store_zero;
wire       dec_php, dec_clc, dec_plp, dec_sec;
wire       dec_cli, dec_sei, dec_clv, dec_cld, dec_sed;
wire [1:0] dec_dst_reg, dec_src_reg;
wire [3:0] dec_op;

decode_65c02 dec (
    .IR          (IR),
    .load_reg    (dec_load_reg),
    .dst_reg     (dec_dst_reg),
    .src_reg     (dec_src_reg),
    .index_y     (dec_index_y),
    .store       (dec_store),
    .write_back  (dec_write_back),
    .load_only   (dec_load_only),
    .inc         (dec_inc),
    .adc_sbc     (dec_adc_sbc),
    .is_adc      (dec_is_adc),
    .shift       (dec_shift),
    .compare     (dec_compare),
    .shift_right (dec_shift_right),
    .rotate      (dec_rotate),
    .op          (dec_op),
    .bit_ins     (dec_bit_ins),
    .bit_ins_nv  (dec_bit_ins_nv),
    .txb_ins     (dec_txb_ins),
    .trb_ins     (dec_trb_ins),
    .store_zero  (dec_store_zero),
    .php         (dec_php),
    .clc         (dec_clc),
    .plp         (dec_plp),
    .sec         (dec_sec),
    .cli         (dec_cli),
    .sei         (dec_sei),
    .clv         (dec_clv),
    .cld         (dec_cld),
    .sed         (dec_sed)
);

always @(posedge clk) begin
    if (state == DECODE && RDY) begin
        load_reg    <= dec_load_reg;
        dst_reg     <= dec_dst_reg;
        src_reg     <= dec_src_reg;
        index_y     <= dec_index_y;
        store       <= dec_store;
        write_back  <= dec_write_back;
        load_only   <= dec_load_only;
        inc         <= dec_inc;
        shift       <= dec_shift;
        compare     <= dec_compare;
        shift_right <= dec_shift_right;
        rotate      <= dec_rotate;
        op          <= dec_op;
        bit_ins     <= dec_bit_ins;
        bit_ins_nv  <= dec_bit_ins_nv;
        txb_ins     <= dec_txb_ins;
        trb_ins     <= dec_trb_ins;
        store_zero  <= dec_store_zero;
        php         <= dec_php;
        clc         <= dec_clc;
        plp         <= dec_plp;
        sec         <= dec_sec;
        cli         <= dec_cli;
        sei         <= dec_sei;
        clv         <= dec_clv;
        cld         <= dec_cld;
        sed         <= dec_sed;
    end
end

always @(posedge clk) begin
    if ((state == DECODE || state == BRK0) && RDY) begin
        adc_sbc <= dec_adc_sbc;
        adc_bcd <= dec_is_adc ? D : 1'b0;
    end
end

always @(posedge clk) begin
    if (RDY)
        cond_code <= IR[7:4];
end

always @* begin
    if (bb_ins)
        cond_true = bb_taken;
    else case (cond_code)
        4'b0001: cond_true = ~N;
        4'b0011: cond_true = N;
        4'b0101: cond_true = ~V;
        4'b0111: cond_true = V;
        4'b1001: cond_true = ~C;
        4'b1011: cond_true = C;
        4'b1101: cond_true = ~Z;
        4'b1111: cond_true = Z;
        default: cond_true = 1;
    endcase
end

reg NMI_1;

initial begin
    NMI_1 = 0;
end

always @(posedge clk) begin
    NMI_1 <= NMI;
end

always @(posedge clk) begin
    if (NMI_edge && state == BRK3)
        NMI_edge <= 0;
    else if (NMI & ~NMI_1)
        NMI_edge <= 1;
end

/*
 * ===================== DCIM zero page =====================
 */
reg  [7:0] dcim_ir;
wire       dcim_word = (dcim_ir == 8'hE3) | (dcim_ir == 8'hC3);
wire       find_ins  = (dcim_ir == 8'h5B);
wire       dcim_bit  = (dcim_ir[3:0] == 4'h7);

always @(posedge clk) begin
    if (RDY && state == DECODE)
        dcim_ir <= IR;
end

/*
 * BBR/BBS ($xF): ZP0 reads the byte, BBX0 tests the bit while fetching the
 * offset, then the normal branch states run with cond_true = bb_taken.
 */
always @(posedge clk) begin
    if (RDY && state == DECODE)
        bb_ins <= (IR[3:0] == 4'hF);
    if (RDY && state == BBX0)
        bb_taken <= (DIMUX[dcim_ir[6:4]] == dcim_ir[7]);
end

wire       zp_cycle  = (AB[15:8] == 8'h00);
wire       dcim_fire = RDY &&
                       (state == ZP0 || state == ZPX1) &&
                       (write_back | dcim_word | dcim_bit);
wire       find_fire = RDY && state == REG && find_ins;

wire [7:0] zp_rdata, find_idx;
wire       dcim_n, dcim_z, dcim_c, dcim_n_upd, dcim_z_upd, dcim_c_upd, find_found;
reg        zp_rsel;
wire [7:0] DI_int;

zp_dcim u_zp (
    .clk      (clk),
    .addr     (AB[7:0]),
    .re       (RDY & zp_cycle & ~WE_i),
    .rdata    (zp_rdata),
    .we       (RDY & zp_cycle & WE_i),
    .wdata    (DO),
    .op_fire  (dcim_fire),
    .op_ir    (dcim_ir),
    .a_in     (AXYS[SEL_A]),
    .c_in     (C),
    .n_out    (dcim_n),
    .z_out    (dcim_z),
    .c_out    (dcim_c),
    .n_upd    (dcim_n_upd),
    .z_upd    (dcim_z_upd),
    .c_upd    (dcim_c_upd),
    .key      (AXYS[SEL_A]),
    .found    (find_found),
    .find_idx (find_idx)
);

always @(posedge clk) begin
    if (RDY)
        zp_rsel <= zp_cycle & ~WE_i;
end

assign DI_int = zp_rsel ? zp_rdata : DI;
assign WE     = WE_i & ~zp_cycle;

endmodule
