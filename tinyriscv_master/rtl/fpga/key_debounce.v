`timescale 1ns / 1ps

module key_debounce #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer DEBOUNCE_MS = 20,
    parameter         ACTIVE_LOW  = 1'b1
)(
    input  wire clk,
    // input  wire rst_n,

    // raw key input from FPGA pin
    input  wire key_i,

    // debounced outputs
    output reg  key_up_o,
    output reg  key_press_pulse_o,
    output reg  key_release_pulse_o
);

    localparam integer DEBOUNCE_CNT_MAX = CLK_FREQ_HZ / 1000 * DEBOUNCE_MS;

    reg key_sync_0;
    reg key_sync_1;

    reg key_sample;
    reg key_stable;
    reg [31:0] cnt;

    wire key_norm;

    // 统一成：1 表示按下，0 表示松开
    assign key_norm = ACTIVE_LOW ? ~key_sync_1 : key_sync_1;

    // 两级同步，消除异步输入亚稳态风险
    always @(posedge clk) begin
        key_sync_0 <= key_i;
        key_sync_1 <= key_sync_0;
    end

    // 消抖逻辑
    always @(posedge clk) begin
        key_press_pulse_o   <= 1'b0;
        key_release_pulse_o <= 1'b0;

        if (key_norm != key_sample) begin
            // 检测到输入状态变化，重新计数
            key_sample <= key_norm;
            cnt        <= 32'd0;
        end else begin
            if (cnt < DEBOUNCE_CNT_MAX - 1) begin
                cnt <= cnt + 1'b1;
            end else begin
                // 状态已经稳定足够长时间
                if (key_stable != key_sample) begin
                    key_stable <= key_sample;
                    key_up_o <= ~key_sample;

                    if (key_sample == 1'b1) begin
                        key_press_pulse_o <= 1'b1;
                    end else begin
                        key_release_pulse_o <= 1'b1;
                    end
                end
            end
        end
    end

endmodule