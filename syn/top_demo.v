`timescale 1ns / 1ps

module top_demo (
    input        clk,
    input        rst_n,
    output       tmds_clk_p,
    output       tmds_clk_n,
    output [2:0] tmds_d_p,
    output [2:0] tmds_d_n,
    output [5:0] led
);

/* ================================================================
 * Clock generation
 * 27 MHz -> rPLL -> 126 MHz (serial) -> CLKDIV /5 -> 25.2 MHz (pixel)
 * ================================================================ */
wire ser_clk, pix_clk, pll_lock;

rPLL #(
    .FCLKIN      ("27"),
    .IDIV_SEL    (2),       // PFD    = 27 / 3        = 9 MHz
    .FBDIV_SEL   (13),      // CLKOUT = 9 * 14        = 126 MHz
    .ODIV_SEL    (4),       // VCO    = CLKOUT * 4    = 504 MHz (500-1250)
    .DEVICE      ("GW2AR-18C")
) pll_inst (
    .CLKIN       (clk),
    .CLKOUT      (ser_clk),
    .LOCK        (pll_lock),
    /* verilator lint_off PINCONNECTEMPTY */
    .CLKOUTP     (),
    .CLKOUTD     (),
    .CLKOUTD3    (),
    /* verilator lint_on PINCONNECTEMPTY */
    .RESET       (1'b0),
    .RESET_P     (1'b0),
    .CLKFB       (1'b0),
    .FBDSEL      (6'b0),
    .IDSEL       (6'b0),
    .ODSEL       (6'b0),
    .PSDA        (4'b0),
    .DUTYDA      (4'b0),
    .FDLY        (4'b0)
);

CLKDIV #(
    .DIV_MODE    ("5"),
    .GSREN       ("false")
) clkdiv_inst (
    .HCLKIN      (ser_clk),
    .CLKOUT      (pix_clk),
    .RESETN      (pll_lock),
    .CALIB       (1'b0)
);

/* ================================================================
 * Reset synchronizer (pixel clock domain)
 * ================================================================ */
reg [3:0] por;
reg [1:0] rs;
reg       btn_idle;
reg       reset;

initial begin
    por      = 0;
    rs       = 0;
    btn_idle = 0;
    reset    = 1;
end

// Button polarity differs between Tang Nano boards, so the level seen at
// power-up is taken as "released" and any other level asserts reset.
always @(posedge pix_clk) begin
    rs <= {rs[0], rst_n};
    if (~pll_lock) begin
        por   <= 0;
        reset <= 1;
    end else if (~&por) begin
        por      <= por + 1;
        btn_idle <= rs[1];
        reset    <= 1;
    end else begin
        reset <= (rs[1] != btn_idle);
    end
end

/* ================================================================
 * CPU
 * ================================================================ */
wire [15:0] AB;
wire [7:0]  DO;
wire        WE;
wire        SYNC;
reg  [7:0]  DI;

cpu_65c02_dcim cpu (
    .clk   (pix_clk),
    .reset (reset),
    .AB    (AB),
    .DI    (DI),
    .DO    (DO),
    .WE    (WE),
    .IRQ   (1'b0),
    .NMI   (1'b0),
    .RDY   (1'b1),
    .SYNC  (SYNC)
);

/* ================================================================
 * Memory map
 *   $0000-$00FF : zero page (DCIM, internal to CPU)
 *   $0100-$1FFF : RAM (8 KB)
 *   $2000-$2FFF : video RAM (4 KB, dual-port)
 *   $3000-$EFFF : unmapped (reads as $00)
 *   $F000-$FFFF : ROM (4 KB)
 * ================================================================ */
wire sel_vram = (AB[15:12] == 4'h2);
wire sel_rom  = (AB[15:12] == 4'hF);
wire sel_ram  = ~AB[15] & ~AB[14] & ~AB[13] & ~sel_vram;

// --- General RAM (8 KB) ---
reg [7:0] ram [0:8191];
reg [7:0] ram_q;

always @(posedge pix_clk) begin
    if (WE && sel_ram)
        ram[AB[12:0]] <= DO;
    ram_q <= ram[AB[12:0]];
end

// --- ROM (4 KB) ---
reg [7:0] rom [0:4095];
reg [7:0] rom_q;

initial $readmemh("demo.hex", rom);

always @(posedge pix_clk) begin
    rom_q <= rom[AB[11:0]];
end

// --- Video RAM (4 KB, dual-port) ---
reg [7:0] vram [0:4095];
reg [7:0] vram_cpu_q;
reg [7:0] vram_vid_q;

integer vi;
initial begin
    for (vi = 0; vi < 4096; vi = vi + 1)
        vram[vi] = 8'h20;
end

// CPU port
always @(posedge pix_clk) begin
    if (WE && sel_vram)
        vram[AB[11:0]] <= DO;
    vram_cpu_q <= vram[AB[11:0]];
end

// --- DI mux (active one cycle after address) ---
reg sel_rom_r, sel_vram_r;

always @(posedge pix_clk) begin
    sel_rom_r  <= sel_rom;
    sel_vram_r <= sel_vram;
end

always @* begin
    if (sel_rom_r)
        DI = rom_q;
    else if (sel_vram_r)
        DI = vram_cpu_q;
    else
        DI = ram_q;
end

/* ================================================================
 * Video timing (640x480 @ 60 Hz, 25.2 MHz pixel clock)
 * ================================================================ */
wire       vt_hsync, vt_vsync, vt_active;
wire [9:0] pixel_x, pixel_y;

video_timing vt (
    .clk     (pix_clk),
    .reset   (reset),
    .hsync   (vt_hsync),
    .vsync   (vt_vsync),
    .active  (vt_active),
    .pixel_x (pixel_x),
    .pixel_y (pixel_y)
);

/* ================================================================
 * Character display (80x30, 8x16 font)
 *
 * 2-stage pipeline:
 *   Stage 0: present vram address -> vram_vid_q ready next cycle
 *   Stage 1: present font address -> font_q ready next cycle
 *   Stage 2: bit-select and output RGB
 *
 * Sync/active signals are delayed 2 cycles to match.
 * ================================================================ */

// --- Font ROM (2 KB: 128 chars x 16 rows) ---
reg [7:0] font [0:2047];
reg [7:0] font_q;

initial $readmemh("font.hex", font);

// --- Stage 0: VRAM address ---
wire [6:0] char_x  = pixel_x[9:3];
wire [4:0] char_y  = pixel_y[8:4];
wire [11:0] vid_addr = {1'b0, char_y, 6'b0} + {3'b0, char_y, 4'b0} + {5'b0, char_x};

// Video port read
always @(posedge pix_clk) begin
    vram_vid_q <= vram[vid_addr];
end

// --- Stage 1: font address ---
reg [9:0] px_d1;
reg       active_d1, hs_d1, vs_d1;

always @(posedge pix_clk) begin
    px_d1     <= pixel_x;
    active_d1 <= vt_active;
    hs_d1     <= vt_hsync;
    vs_d1     <= vt_vsync;
end

wire [10:0] font_addr = {vram_vid_q[6:0], pixel_y[3:0]};

always @(posedge pix_clk) begin
    font_q <= font[font_addr];
end

// --- Stage 2: bit select and RGB output ---
// video_timing registers hsync/vsync/active once already, so one more
// stage puts them level with font_q (two cycles behind pixel_x).
reg [9:0] px_d2;
wire      active_d2 = active_d1;
wire      hs_d2     = hs_d1;
wire      vs_d2     = vs_d1;

always @(posedge pix_clk) begin
    px_d2 <= px_d1;
end

wire [2:0] bit_sel = 3'd7 - px_d2[2:0];
wire       pixel_on = font_q[bit_sel] & active_d2;

wire [7:0] red   = pixel_on ? 8'h33 : 8'h00;
wire [7:0] green = pixel_on ? 8'hFF : 8'h00;
wire [7:0] blue  = pixel_on ? 8'h33 : 8'h00;

/* ================================================================
 * TMDS encoding (3 channels)
 * ================================================================ */
wire [9:0] tmds_d0_enc, tmds_d1_enc, tmds_d2_enc;

tmds_encoder enc_b (
    .clk   (pix_clk),
    .reset (reset),
    .data  (blue),
    .ctrl  ({vs_d2, hs_d2}),
    .de    (active_d2),
    .tmds  (tmds_d0_enc)
);

tmds_encoder enc_g (
    .clk   (pix_clk),
    .reset (reset),
    .data  (green),
    .ctrl  (2'b00),
    .de    (active_d2),
    .tmds  (tmds_d1_enc)
);

tmds_encoder enc_r (
    .clk   (pix_clk),
    .reset (reset),
    .data  (red),
    .ctrl  (2'b00),
    .de    (active_d2),
    .tmds  (tmds_d2_enc)
);

/* ================================================================
 * OSER10 serializers + ELVDS output buffers
 * ================================================================ */
wire tmds_clk_ser, tmds_d0_ser, tmds_d1_ser, tmds_d2_ser;
wire dvi_reset = ~pll_lock;

OSER10 #(.GSREN("false"), .LSREN("true")) ser_clk_inst (
    .Q    (tmds_clk_ser),
    .D0   (1'b1), .D1(1'b1), .D2(1'b1), .D3(1'b1), .D4(1'b1),
    .D5   (1'b0), .D6(1'b0), .D7(1'b0), .D8(1'b0), .D9(1'b0),
    .PCLK (pix_clk),
    .FCLK (ser_clk),
    .RESET(dvi_reset)
);

OSER10 #(.GSREN("false"), .LSREN("true")) ser_d0 (
    .Q    (tmds_d0_ser),
    .D0   (tmds_d0_enc[0]), .D1(tmds_d0_enc[1]),
    .D2   (tmds_d0_enc[2]), .D3(tmds_d0_enc[3]),
    .D4   (tmds_d0_enc[4]), .D5(tmds_d0_enc[5]),
    .D6   (tmds_d0_enc[6]), .D7(tmds_d0_enc[7]),
    .D8   (tmds_d0_enc[8]), .D9(tmds_d0_enc[9]),
    .PCLK (pix_clk),
    .FCLK (ser_clk),
    .RESET(dvi_reset)
);

OSER10 #(.GSREN("false"), .LSREN("true")) ser_d1 (
    .Q    (tmds_d1_ser),
    .D0   (tmds_d1_enc[0]), .D1(tmds_d1_enc[1]),
    .D2   (tmds_d1_enc[2]), .D3(tmds_d1_enc[3]),
    .D4   (tmds_d1_enc[4]), .D5(tmds_d1_enc[5]),
    .D6   (tmds_d1_enc[6]), .D7(tmds_d1_enc[7]),
    .D8   (tmds_d1_enc[8]), .D9(tmds_d1_enc[9]),
    .PCLK (pix_clk),
    .FCLK (ser_clk),
    .RESET(dvi_reset)
);

OSER10 #(.GSREN("false"), .LSREN("true")) ser_d2 (
    .Q    (tmds_d2_ser),
    .D0   (tmds_d2_enc[0]), .D1(tmds_d2_enc[1]),
    .D2   (tmds_d2_enc[2]), .D3(tmds_d2_enc[3]),
    .D4   (tmds_d2_enc[4]), .D5(tmds_d2_enc[5]),
    .D6   (tmds_d2_enc[6]), .D7(tmds_d2_enc[7]),
    .D8   (tmds_d2_enc[8]), .D9(tmds_d2_enc[9]),
    .PCLK (pix_clk),
    .FCLK (ser_clk),
    .RESET(dvi_reset)
);

TLVDS_OBUF obuf_clk (.I(tmds_clk_ser), .O(tmds_clk_p), .OB(tmds_clk_n));
TLVDS_OBUF obuf_d0  (.I(tmds_d0_ser),  .O(tmds_d_p[0]), .OB(tmds_d_n[0]));
TLVDS_OBUF obuf_d1  (.I(tmds_d1_ser),  .O(tmds_d_p[1]), .OB(tmds_d_n[1]));
TLVDS_OBUF obuf_d2  (.I(tmds_d2_ser),  .O(tmds_d_p[2]), .OB(tmds_d_n[2]));

/* ================================================================
 * Debug LEDs (active low on Tang Nano 20K)
 *   led[0] = always ON (bitstream loaded, LED pins correct)
 *   led[1] = ON when PLL locked
 *   led[2] = ON when reset released
 *   led[3] = ~1 Hz blink from the frame counter (video timing running)
 *   led[4] = ON while the button input reads high
 *   led[5] = off
 * ================================================================ */
reg [5:0] frames = 0;
reg       vs_prev = 0;
always @(posedge pix_clk) begin
    vs_prev <= vt_vsync;
    if (vt_vsync & ~vs_prev)
        frames <= frames + 1;
end

assign led[0] = 1'b0;
assign led[1] = ~pll_lock;
assign led[2] = reset;
assign led[3] = ~frames[5];
assign led[4] = ~rs[1];
assign led[5] = 1'b1;

endmodule