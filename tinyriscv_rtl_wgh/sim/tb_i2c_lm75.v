`timescale 1ns/1ps
`include "defines.v"

module tb_i2c_lm75;
    reg clk;
    reg rst;
    reg we;
    reg[31:0] addr;
    reg[31:0] data_i;
    wire[31:0] data_o;
    reg custom_req;
    wire custom_valid;
    wire[7:0] custom_data;
    wire busy;
    wire scl;
    tri1 sda;

    i2c_lm75 #(.CLK_DIV(16'd1)) dut(
        .clk(clk),
        .rst(rst),
        .we_i(we),
        .addr_i(addr),
        .data_i(data_i),
        .data_o(data_o),
        .custom_temp_req_i(custom_req),
        .custom_temp_valid_o(custom_valid),
        .custom_temp_data_o(custom_data),
        .busy_o(busy),
        .i2c_scl(scl),
        .i2c_sda(sda)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        rst = `RstEnable;
        we = `WriteDisable;
        addr = 32'h0;
        data_i = 32'h0;
        custom_req = 1'b0;
        repeat (3) @(negedge clk);
        rst = `RstDisable;

        @(negedge clk);
        custom_req = 1'b1;
        @(negedge clk);
        custom_req = 1'b0;
        wait (custom_valid);
        @(negedge clk);
        addr = 32'h0000_0000;
        #1;
        if (data_o[2] != 1'b1 || busy != 1'b0) begin
            $display("FAIL: i2c done/busy status data_o=%h busy=%b", data_o, busy);
            $finish;
        end
        $display("PASS: tb_i2c_lm75");
        $finish;
    end
endmodule
