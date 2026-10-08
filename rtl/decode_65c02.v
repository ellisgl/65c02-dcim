`timescale 1ns / 1ps

module decode_65c02 (
    input      [7:0]  IR,
    output reg        load_reg,
    output reg [1:0]  dst_reg,
    output reg [1:0]  src_reg,
    output reg        index_y,
    output reg        store,
    output reg        write_back,
    output reg        load_only,
    output reg        inc,
    output reg        adc_sbc,
    output reg        is_adc,
    output reg        shift,
    output reg        compare,
    output reg        shift_right,
    output reg        rotate,
    output reg [3:0]  op,
    output reg        bit_ins,
    output reg        bit_ins_nv,
    output reg        txb_ins,
    output reg        trb_ins,
    output reg        store_zero,
    output reg        php,
    output reg        clc,
    output reg        plp,
    output reg        sec,
    output reg        cli,
    output reg        sei,
    output reg        clv,
    output reg        cld,
    output reg        sed
);

parameter
    SEL_A = 2'd0,
    SEL_S = 2'd1,
    SEL_X = 2'd2,
    SEL_Y = 2'd3;

parameter
    OP_OR  = 4'b1100,
    OP_AND = 4'b1101,
    OP_ADD = 4'b0011,
    OP_SUB = 4'b0111,
    OP_ROL = 4'b1011,
    OP_A   = 4'b1111;

always @* begin
    casez (IR)
        8'b0??1_0010,
        8'b1?11_0010,
        8'b0???_1010,
        8'b0???_??01,
        8'b100?_10?0,
        8'b1010_???0,
        8'b1011_1010,
        8'b1011_?1?0,
        8'b1100_1010,
        8'b11?1_1010,
        8'b1?1?_??01,
        8'b???0_1000: load_reg = 1;
        default:      load_reg = 0;
    endcase
end

always @* begin
    casez (IR)
        8'b1110_1000,
        8'b1100_1010,
        8'b1111_1010,
        8'b1010_0010,
        8'b101?_?110,
        8'b101?_1?10: dst_reg = SEL_X;
        8'b0?00_1000,
        8'b?101_1010,
        8'b1001_1010: dst_reg = SEL_S;
        8'b1?00_1000,
        8'b0111_1010,
        8'b101?_?100,
        8'b1010_?000: dst_reg = SEL_Y;
        default:      dst_reg = SEL_A;
    endcase
end

always @* begin
    casez (IR)
        8'b1011_1010: src_reg = SEL_S;
        8'b100?_?110,
        8'b100?_1?10,
        8'b1110_??00,
        8'b1101_1010,
        8'b1100_1010: src_reg = SEL_X;
        8'b100?_?100,
        8'b1001_1000,
        8'b1100_??00,
        8'b0101_1010,
        8'b1?00_1000: src_reg = SEL_Y;
        default:      src_reg = SEL_A;
    endcase
end

always @* begin
    casez (IR)
        8'b???1_0001,
        8'b10?1_0110,
        8'b1011_1110,
        8'b????_1001: index_y = 1;
        default:      index_y = 0;
    endcase
end

always @* begin
    casez (IR)
        8'b1001_0010,
        8'b100?_?1?0,
        8'b011?_0100,
        8'b100?_??01: store = 1;
        default:      store = 0;
    endcase
end

always @* begin
    casez (IR)
        8'b0???_?110,
        8'b000?_?100,
        8'b11??_?110: write_back = 1;
        default:      write_back = 0;
    endcase
end

always @* begin
    casez (IR)
        8'b101?_????: load_only = 1;
        default:      load_only = 0;
    endcase
end

always @* begin
    casez (IR)
        8'b0001_1010,
        8'b111?_?110,
        8'b11?0_1000: inc = 1;
        default:      inc = 0;
    endcase
end

always @* begin
    casez (IR)
        8'b?111_0010,
        8'b?11?_??01: adc_sbc = 1;
        default:      adc_sbc = 0;
    endcase
end

always @* begin
    casez (IR)
        8'b0111_0010,
        8'b011?_??01: is_adc = 1;
        default:      is_adc = 0;
    endcase
end

always @* begin
    casez (IR)
        8'b0???_?110,
        8'b0??0_1010: shift = 1;
        default:      shift = 0;
    endcase
end

always @* begin
    casez (IR)
        8'b1101_0010,
        8'b11?0_0?00,
        8'b11?0_1100,
        8'b110?_??01: compare = 1;
        default:      compare = 0;
    endcase
end

always @* begin
    casez (IR)
        8'b01??_?110,
        8'b01??_1?10: shift_right = 1;
        default:      shift_right = 0;
    endcase
end

always @* begin
    casez (IR)
        8'b0?10_1010,
        8'b0?1?_?110: rotate = 1;
        default:      rotate = 0;
    endcase
end

always @* begin
    casez (IR)
        8'b0000_?100: op = OP_OR;
        8'b0001_?100: op = OP_AND;
        8'b00??_?110,
        8'b00?0_1010: op = OP_ROL;
        8'b1000_1001,
        8'b001?_?100: op = OP_AND;
        8'b01??_?110,
        8'b01??_1?10: op = OP_A;
        8'b11?1_0010,
        8'b0011_1010,
        8'b1000_1000,
        8'b1100_1010,
        8'b110?_?110,
        8'b11??_??01,
        8'b11?0_0?00,
        8'b11?0_1100: op = OP_SUB;
        8'b00?1_0010,
        8'b0?01_0010,
        8'b010?_??01,
        8'b00??_??01: op = {2'b11, IR[6:5]};
        default:      op = OP_ADD;
    endcase
end

always @* begin
    casez (IR)
        8'b001?_?100: {bit_ins, bit_ins_nv} = 2'b11;
        8'b1000_1001: {bit_ins, bit_ins_nv} = 2'b10;
        default:      {bit_ins, bit_ins_nv} = 2'b00;
    endcase
end

always @* begin
    casez (IR)
        8'b000?_?100: txb_ins = 1;
        default:      txb_ins = 0;
    endcase
end

always @* begin
    casez (IR)
        8'b0001_?100: trb_ins = 1;
        default:      trb_ins = 0;
    endcase
end

always @* begin
    casez (IR)
        8'b1001_11?0,
        8'b011?_0100: store_zero = 1;
        default:      store_zero = 0;
    endcase
end

always @* begin
    php = (IR == 8'h08);
    clc = (IR == 8'h18);
    plp = (IR == 8'h28);
    sec = (IR == 8'h38);
    cli = (IR == 8'h58);
    sei = (IR == 8'h78);
    clv = (IR == 8'hb8);
    cld = (IR == 8'hd8);
    sed = (IR == 8'hf8);
end

endmodule
