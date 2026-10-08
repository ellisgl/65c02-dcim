`timescale 1ns/1ps

module tb_dormann;

parameter [15:0] SUCCESS = 16'h346a;

reg          clk   = 0;
reg          reset = 1;
wire [15:0]  AB;
wire [7:0]   DO;
wire         WE;
wire         SYNC;
reg  [7:0]   DI;
reg  [7:0]   mem [0:65535];
reg  [15:0]  last = 16'hffff;
integer      i;
integer      cycles = 0;
integer      zpbus  = 0;

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

initial begin
    $readmemh("func.hex", mem);
    mem[16'hfffc] = 8'h00;
    mem[16'hfffd] = 8'h04;

    for (i = 0; i < 128; i = i + 1) begin
        cpu.u_zp.ev[i] = mem[2 * i];
        cpu.u_zp.od[i] = mem[2 * i + 1];
    end

    #22 reset = 0;
end

always @(posedge clk) begin
    if (!reset) begin
        cycles = cycles + 1;

        if (WE && AB[15:8] == 0)
            zpbus = zpbus + 1;

        if (SYNC) begin
            if (AB == last) begin
                $display("trap at %h after %0d cycles  (%s)  zp-bus-writes=%0d",
                    AB, cycles, AB == SUCCESS ? "PASS" : "FAIL", zpbus);
                $finish;
            end

            last = AB;
        end

        if (cycles % 100_000_000 == 0)
            $display("  %0d cycles, PC=%h", cycles, AB);

        if (cycles > 1_500_000_000) begin
            $display("timeout");
            $finish;
        end
    end
end

endmodule
