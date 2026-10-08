`timescale 1ns / 1ps

module tmds_encoder (
    input            clk,
    input            reset,
    input      [7:0] data,
    input      [1:0] ctrl,
    input            de,
    output reg [9:0] tmds
);

wire [3:0] ones = data[0] + data[1] + data[2] + data[3] +
                  data[4] + data[5] + data[6] + data[7];

wire use_xnor = (ones > 4) || (ones == 4 && !data[0]);

reg [8:0] q_m;

always @* begin
    q_m[0] = data[0];
    q_m[1] = use_xnor ? ~(q_m[0] ^ data[1]) : (q_m[0] ^ data[1]);
    q_m[2] = use_xnor ? ~(q_m[1] ^ data[2]) : (q_m[1] ^ data[2]);
    q_m[3] = use_xnor ? ~(q_m[2] ^ data[3]) : (q_m[2] ^ data[3]);
    q_m[4] = use_xnor ? ~(q_m[3] ^ data[4]) : (q_m[3] ^ data[4]);
    q_m[5] = use_xnor ? ~(q_m[4] ^ data[5]) : (q_m[4] ^ data[5]);
    q_m[6] = use_xnor ? ~(q_m[5] ^ data[6]) : (q_m[5] ^ data[6]);
    q_m[7] = use_xnor ? ~(q_m[6] ^ data[7]) : (q_m[6] ^ data[7]);
    q_m[8] = use_xnor ? 1'b0 : 1'b1;
end

wire [3:0] q_m_ones = q_m[0] + q_m[1] + q_m[2] + q_m[3] +
                      q_m[4] + q_m[5] + q_m[6] + q_m[7];

// ones minus zeros in q_m[7:0]
wire [4:0] bal = {q_m_ones, 1'b0} - 5'd8;

reg signed [4:0] disparity;

always @(posedge clk) begin
    if (reset) begin
        tmds      <= 10'b1101010100;
        disparity <= 0;
    end else if (!de) begin
        disparity <= 0;
        case (ctrl)
            2'b00:   tmds <= 10'b1101010100;
            2'b01:   tmds <= 10'b0010101011;
            2'b10:   tmds <= 10'b0101010100;
            default: tmds <= 10'b1010101011;
        endcase
    end else begin
        if (disparity == 0 || q_m_ones == 4) begin
            tmds[9]   <= ~q_m[8];
            tmds[8]   <= q_m[8];
            tmds[7:0] <= q_m[8] ? q_m[7:0] : ~q_m[7:0];
            if (q_m[8])
                disparity <= disparity + bal;
            else
                disparity <= disparity - bal;
        end else if ((disparity > 0 && q_m_ones > 4) ||
                     (disparity < 0 && q_m_ones < 4)) begin
            tmds[9]   <= 1'b1;
            tmds[8]   <= q_m[8];
            tmds[7:0] <= ~q_m[7:0];
            disparity <= disparity + {3'b0, q_m[8], 1'b0} - bal;
        end else begin
            tmds[9]   <= 1'b0;
            tmds[8]   <= q_m[8];
            tmds[7:0] <= q_m[7:0];
            disparity <= disparity - {3'b0, ~q_m[8], 1'b0} + bal;
        end
    end
end

endmodule
