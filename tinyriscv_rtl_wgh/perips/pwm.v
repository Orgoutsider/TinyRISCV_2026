/*
 * 4-channel PWM peripheral for tinyriscv project.
 * Address map, after RIB removes high nibble:
 *   0x0000_0000 : A0 period
 *   0x0001_0000 : A1 period
 *   0x0002_0000 : A2 period
 *   0x0003_0000 : A3 period
 *   0x0010_0000 : B0 high time
 *   0x0011_0000 : B1 high time
 *   0x0012_0000 : B2 high time
 *   0x0013_0000 : B3 high time
 *   0x0004_0000 : C[3:0] enable
 */
`include "defines.v"

module pwm(
    input  wire        clk,
    input  wire        rst,
    input  wire        we_i,
    input  wire[31:0]  addr_i,
    input  wire[31:0]  data_i,
    output reg [31:0]  data_o,
    output wire[3:0]   pwm_o
);

    reg[31:0] period[0:3];
    reg[31:0] high_time[0:3];
    reg[3:0]  enable;
    reg[31:0] cnt[0:3];

    integer i;

    wire[3:0] reg_hi = addr_i[23:20];
    wire[3:0] reg_lo = addr_i[19:16];

    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            for (i = 0; i < 4; i = i + 1) begin
                period[i]    <= 32'd1000;
                high_time[i] <= 32'd500;
                cnt[i]       <= 32'd0;
            end
            enable <= 4'b0000;
        end else begin
            if (we_i == `WriteEnable) begin
                case ({reg_hi, reg_lo})
                    8'h00: period[0]    <= (data_i == 32'd0) ? 32'd1 : data_i;
                    8'h01: period[1]    <= (data_i == 32'd0) ? 32'd1 : data_i;
                    8'h02: period[2]    <= (data_i == 32'd0) ? 32'd1 : data_i;
                    8'h03: period[3]    <= (data_i == 32'd0) ? 32'd1 : data_i;
                    8'h10: high_time[0] <= data_i;
                    8'h11: high_time[1] <= data_i;
                    8'h12: high_time[2] <= data_i;
                    8'h13: high_time[3] <= data_i;
                    8'h04: enable       <= data_i[3:0];
                    default: begin end
                endcase
            end

            for (i = 0; i < 4; i = i + 1) begin
                if (enable[i] == 1'b0) begin
                    cnt[i] <= 32'd0;
                end else if (cnt[i] >= (period[i] - 1'b1)) begin
                    cnt[i] <= 32'd0;
                end else begin
                    cnt[i] <= cnt[i] + 1'b1;
                end
            end
        end
    end

    always @(*) begin
        data_o = `ZeroWord;
        case ({reg_hi, reg_lo})
            8'h00: data_o = period[0];
            8'h01: data_o = period[1];
            8'h02: data_o = period[2];
            8'h03: data_o = period[3];
            8'h10: data_o = high_time[0];
            8'h11: data_o = high_time[1];
            8'h12: data_o = high_time[2];
            8'h13: data_o = high_time[3];
            8'h04: data_o = {28'h0, enable};
            default: data_o = `ZeroWord;
        endcase
    end

    assign pwm_o[0] = enable[0] & (cnt[0] < high_time[0]);
    assign pwm_o[1] = enable[1] & (cnt[1] < high_time[1]);
    assign pwm_o[2] = enable[2] & (cnt[2] < high_time[2]);
    assign pwm_o[3] = enable[3] & (cnt[3] < high_time[3]);

endmodule
