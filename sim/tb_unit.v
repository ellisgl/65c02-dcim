`timescale 1ns/1ps

module tb_unit;

parameter PROG = "unit.hex";

reg          clk    = 0;
reg          reset  = 1;
wire [15:0]  AB;
wire [7:0]   DO;
wire         WE;
wire         SYNC;
reg  [7:0]   DI;
reg  [7:0]   mem [0:65535];
reg  [15:0]  last   = 0;
reg  [7:0]   lastop = 0;
integer      i;
integer      cycles = 0;
integer      lastc  = 0;
integer      busw   = 0;

always #5 clk = ~clk;

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
    .SYNC  (SYNC)
);

always @(posedge clk) begin
    if (WE)
        mem[AB] <= DO;

    DI <= mem[AB];
end

function [7:0] zp(input [7:0] a);
    zp = a[0] ? cpu.u_zp.od[a[7:1]] : cpu.u_zp.ev[a[7:1]];
endfunction

initial begin
    for (i = 0; i < 65536; i = i + 1)
        mem[i] = 0;

    $readmemh(PROG, mem, 16'h0400);
    mem[16'hfffc] = 8'h00;
    mem[16'hfffd] = 8'h04;

    #22 reset = 0;
end

always @(posedge clk) begin
    if (!reset) begin
        cycles = cycles + 1;

        if (WE && AB[15:8] == 0)
            busw = busw + 1;

        if (SYNC) begin
            if (last != 0 && AB != last)
                $display("  op %h @%h : %0d cycles",
                    lastop, last - 16'd1, cycles - lastc);

            if (AB == last) begin
                $display("done: A=%h X=%h P(NVZC)=%b%b%b%b  $10/$11=%h %h  $20=%h $77=%h  ZP bus writes=%0d  $FF/$00=%h %h $31/$32=%h %h",
                    cpu.AXYS[0], cpu.AXYS[2],
                    cpu.N, cpu.V, cpu.Z, cpu.C,
                    zp(8'h10), zp(8'h11),
                    zp(8'h20), zp(8'h77),
                    busw,
                    zp(8'hff), zp(8'h00),
                    zp(8'h31), zp(8'h32));
                $finish;
            end

            last   = AB;
            lastc  = cycles;
            lastop = mem[AB - 16'd1];
        end

        if (cycles > 1000) begin
            $finish;
        end
    end
end

endmodule
