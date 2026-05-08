`timescale 1ns/1ps
`include "defines.v"

module tb_pwm;
    reg clk;
    reg rst;
    reg we;
    reg[31:0] addr;
    reg[31:0] data_i;
    wire[31:0] data_o;
    wire[3:0] pwm_o;

    pwm dut(
        .clk(clk),
        .rst(rst),
        .we_i(we),
        .addr_i(addr),
        .data_i(data_i),
        .data_o(data_o),
        .pwm_o(pwm_o)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task wr;
        input[31:0] a;
        input[31:0] d;
        begin
            @(negedge clk);
            addr = a;
            data_i = d;
            we = `WriteEnable;
            @(negedge clk);
            we = `WriteDisable;
        end
    endtask

    initial begin
        rst = `RstEnable;
        we = `WriteDisable;
        addr = 32'h0;
        data_i = 32'h0;
        repeat (3) @(negedge clk);
        rst = `RstDisable;

        wr(32'h0000_0000, 32'd4);
        wr(32'h0010_0000, 32'd2);
        wr(32'h0004_0000, 32'h1);
        repeat (1) @(posedge clk);
        if (pwm_o[0] !== 1'b1) begin
            $display("FAIL: pwm high phase missing");
            $finish;
        end
        repeat (2) @(posedge clk);
        if (pwm_o[0] !== 1'b0) begin
            $display("FAIL: pwm low phase missing");
            $finish;
        end

        addr = 32'h0004_0000;
        #1;
        if (data_o[3:0] != 4'h1) begin
            $display("FAIL: pwm enable readback");
            $finish;
        end
        #10;
        $display("PASS: tb_pwm");
        $finish;
    end
endmodule
