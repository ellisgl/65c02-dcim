// Board top: 65C02 DCIM + 32KB RAM + 4KB ROM @ $8000
`timescale 1ns/1ps

module top (
    input        clk,
    input        rst_n
);

reg [3:0] por;
reg [1:0] rs;
reg       reset;

initial begin
    por   = 0;
    rs    = 0;
    reset = 1;
end

always @(posedge clk) begin
    if (~&por) begin
        por <= por + 1;
    end

    rs    <= {rs[0], rst_n};
    reset <= ~&por | ~rs[1];
end

wire [15:0] AB;
wire [7:0]  DO;
wire        WE;
reg  [7:0]  ram [0:32767];
reg  [7:0]  rom [0:4095];
reg  [7:0]  ram_q;
reg  [7:0]  rom_q;
reg         sel_rom;

initial begin
    $readmemh("rom.hex", rom);
end

always @(posedge clk) begin
    if (WE && !AB[15]) begin
        ram[AB[14:0]] <= DO;
    end

    ram_q   <= ram[AB[14:0]];
    rom_q   <= rom[AB[11:0]];
    sel_rom <= AB[15];
end

wire [7:0] DI = sel_rom ? rom_q : ram_q;

cpu_65c02_dcim cpu (
    .clk   (clk),
    .reset (reset),
    .AB    (AB),
    .DI    (DI),
    .DO    (DO),
    .WE    (WE),
    .IRQ   (1'b0),
    .NMI   (1'b0),
    .RDY   (1'b1),
    /* verilator lint_off PINCONNECTEMPTY */
    .SYNC  ()
    /* verilator lint_on PINCONNECTEMPTY */
);

endmodule
