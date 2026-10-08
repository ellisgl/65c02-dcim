`timescale 1ns / 1ps
/*
 * zp_dcim.v -- Zero-page Digital Compute-In-Memory macro for a 65C02.
 *
 * 256x8 array, organised as two 128x8 banks (even / odd addresses) so a
 * 16-bit op at A, A+1 always touches exactly one byte per bank. That keeps
 * each bank at a single read port and a single write port, like a real
 * CIM macro with one wordline decoder per bank.
 *
 * One address bus (the core's AB[7:0]) serves every port:
 *   - core read  : registered, data valid the cycle after re
 *   - core write : we / wdata
 *   - op port    : in-array read-modify-write, ONE cycle. Reads M (and M+1),
 *                  computes in the periphery, writes back on the same edge,
 *                  returns N/Z/C to the core.
 *   - FIND       : 256-way CAM match of KEY against every ZP byte.
 *
 * Op decode is done from the latched opcode:
 *   06/16 ASL   26/36 ROL   46/56 LSR   66/76 ROR
 *   C6/D6 DEC   E6/F6 INC   04 TSB      14 TRB
 *   E3    INW   (16-bit increment, 65CE02 encoding)
 *   C3    DEW   (16-bit decrement, 65CE02 encoding)
 *   x7    RMB0-7 (07..77) / SMB0-7 (87..F7), no flags
 */
module zp_dcim (
    input             clk,
    input      [7:0]  addr,

    // core port
    input             re,
    output reg [7:0]  rdata,
    input             we,
    input      [7:0]  wdata,

    // in-array op port
    input             op_fire,
    input      [7:0]  op_ir,
    input      [7:0]  a_in,
    input             c_in,
    output reg        n_out,
    output reg        z_out,
    output reg        c_out,
    output reg        n_upd,
    output reg        z_upd,
    output reg        c_upd,

    // FIND (CAM) port
    input      [7:0]  key,
    output            found,
    output     [7:0]  find_idx
);

reg [7:0] ev [0:127];
reg [7:0] od [0:127];

integer i;
initial begin
    for (i = 0; i < 128; i = i + 1) begin
        ev[i] = 8'h00;
        od[i] = 8'h00;
    end
end

/* ---------------- periphery: operand fetch ---------------- */
wire       odd   = addr[0];
wire [6:0] o_idx = addr[7:1];
wire [6:0] e_idx = addr[7:1] + {6'd0, odd};
wire [7:0] ev_q  = ev[e_idx];
wire [7:0] od_q  = od[o_idx];
wire [7:0] m0    = odd ? od_q : ev_q;
wire [7:0] m1    = odd ? ev_q : od_q;

/* ---------------- periphery: compute ---------------------- */
reg  [7:0] r0, r1;
reg        word;
reg        zmask;
wire [7:0] bit_mask = 8'd1 << op_ir[6:4];

always @* begin
    r0    = m0;
    r1    = m1;
    word  = 1'b0;
    zmask = 1'b0;
    c_out = c_in;
    c_upd = 1'b0;
    n_upd = 1'b1;
    z_upd = 1'b1;

    casez (op_ir)
        8'b000?_0110: begin {c_out, r0} = {m0, 1'b0};            c_upd = 1; end // ASL
        8'b001?_0110: begin {c_out, r0} = {m0, c_in};            c_upd = 1; end // ROL
        8'b010?_0110: begin r0 = {1'b0, m0[7:1]}; c_out = m0[0]; c_upd = 1; end // LSR
        8'b011?_0110: begin r0 = {c_in, m0[7:1]}; c_out = m0[0]; c_upd = 1; end // ROR
        8'b110?_0110: r0 = m0 - 8'd1;                                            // DEC
        8'b111?_0110: r0 = m0 + 8'd1;                                            // INC
        8'h04:        begin r0 = m0 |  a_in; zmask = 1; n_upd = 0; end           // TSB
        8'h14:        begin r0 = m0 & ~a_in; zmask = 1; n_upd = 0; end           // TRB
        8'hE3:        begin {r1, r0} = {m1, m0} + 16'd1; word = 1; end           // INW
        8'hC3:        begin {r1, r0} = {m1, m0} - 16'd1; word = 1; end           // DEW
        8'b0???_0111: begin r0 = m0 & ~bit_mask; n_upd = 0; z_upd = 0; end       // RMB
        8'b1???_0111: begin r0 = m0 |  bit_mask; n_upd = 0; z_upd = 0; end       // SMB
        default:      begin n_upd = 0; z_upd = 0; end
    endcase

    if (zmask)      z_out = ~|(m0 & a_in);
    else if (word)  z_out = ~|{r1, r0};
    else            z_out = ~|r0;

    n_out = word ? r1[7] : r0[7];
end

/* ---------------- array write-back ------------------------ */
wire       w_lo = op_fire | we;
wire       w_hi = op_fire & word;
wire [7:0] d_lo = op_fire ? r0 : wdata;

wire       ev_we = odd ? w_hi : w_lo;
wire       od_we = odd ? w_lo : w_hi;
wire [7:0] ev_d  = odd ? r1   : d_lo;
wire [7:0] od_d  = odd ? d_lo : r1;

always @(posedge clk) begin
    if (ev_we) ev[e_idx] <= ev_d;
    if (od_we) od[o_idx] <= od_d;
    if (re)    rdata     <= m0;
end

/* ---------------- FIND: 256-way CAM ----------------------- */
integer    j;
reg        f_found;
reg  [7:0] f_idx;

always @* begin
    f_found = 1'b0;
    f_idx   = 8'h00;
    for (j = 127; j >= 0; j = j - 1) begin
        if (od[j] == key) begin f_found = 1'b1; f_idx = {j[6:0], 1'b1}; end
        if (ev[j] == key) begin f_found = 1'b1; f_idx = {j[6:0], 1'b0}; end
    end
end

assign found    = f_found;
assign find_idx = f_idx;

endmodule
