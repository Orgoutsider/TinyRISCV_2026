`timescale 1ns/1ps

`include "defines.v"

module tb_tinyriscv_soc();

    reg clk;
    reg rst;
    wire[3:0] PWM_o;
    wire uart_tx;


    always #10 clk = ~clk;     // 50MHz

    // wire[`RegBus] x3 = tinyriscv_soc_top_0.u_tinyriscv.u_regs.regs[3];
    // wire[`RegBus] x26 = tinyriscv_soc_top_0.u_tinyriscv.u_regs.regs[26];
    // wire[`RegBus] x27 = tinyriscv_soc_top_0.u_tinyriscv.u_regs.regs[27];

    integer r;

    initial begin
        clk = 0;
        rst = `RstEnable;

        $display("test running...");
        #40
        rst = `RstDisable;
        
//        #1000000
//        rst = `RstEnable;
//        #40 rst = `RstDisable;
    end

    // sim timeout
    initial begin
        #2500000000;
        $display("Time Out.");
        $finish;
    end

    // read mem data
    initial begin
        $readmemh ("Temp.data", tinyriscv_soc_top_0.u_rom._rom);
    end

    tinyriscv_soc_top tinyriscv_soc_top_0(
        .clk(clk),
        .rst(rst),
        .uart_debug_pin(1'b0),
        .PWM_o(PWM_o),
        .uart_tx_pin(uart_tx) 
    );

endmodule