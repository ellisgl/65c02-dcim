`timescale 1ns / 1ps

module video_timing (
    input            clk,
    input            reset,
    output reg       hsync,
    output reg       vsync,
    output           active,
    output reg [9:0] pixel_x,
    output reg [9:0] pixel_y
);

parameter H_ACTIVE = 640;
parameter H_FRONT  = 16;
parameter H_SYNC   = 96;
parameter H_BACK   = 48;
parameter H_TOTAL  = 800;

parameter V_ACTIVE = 480;
parameter V_FRONT  = 10;
parameter V_SYNC   = 2;
parameter V_BACK   = 33;
parameter V_TOTAL  = 525;

always @(posedge clk) begin
    if (reset) begin
        pixel_x <= 0;
        pixel_y <= 0;
    end else begin
        if (pixel_x == H_TOTAL - 1) begin
            pixel_x <= 0;
            if (pixel_y == V_TOTAL - 1)
                pixel_y <= 0;
            else
                pixel_y <= pixel_y + 1;
        end else
            pixel_x <= pixel_x + 1;
    end
end

always @(posedge clk) begin
    if (reset) begin
        hsync <= 1;
        vsync <= 1;
    end else begin
        hsync <= ~(pixel_x >= H_ACTIVE + H_FRONT &&
                   pixel_x <  H_ACTIVE + H_FRONT + H_SYNC);
        vsync <= ~(pixel_y >= V_ACTIVE + V_FRONT &&
                   pixel_y <  V_ACTIVE + V_FRONT + V_SYNC);
    end
end

reg active_r;
always @(posedge clk) begin
    if (reset)
        active_r <= 0;
    else
        active_r <= (pixel_x < H_ACTIVE) && (pixel_y < V_ACTIVE);
end
assign active = active_r;

endmodule
