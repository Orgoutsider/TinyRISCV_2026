`timescale 1ns/1ps
`include "defines.v"

module tb_chip_sel;
    reg clk;
    reg rst;
    reg chip_sel;
    wire over;
    wire succ;
    wire halted_ind;
    wire uart_tx_pin;
    wire jtag_TDO;
    wire[7:0] chip_to_fpga;
    wire[7:0] fpga_to_chip;
    wire[3:0] pwm_o;
    wire i2c_scl;
    tri1 i2c_sda;

    tinyriscv_soc_top dut(
        .clk(clk),
        .rst(rst),
        .chip_sel_i(chip_sel),
        .over(over),
        .succ(succ),
        .halted_ind(halted_ind),
        .uart_debug_pin(1'b0),
        .uart_tx_pin(uart_tx_pin),
        .uart_rx_pin(1'b1),
        .jtag_TCK(1'b0),
        .jtag_TMS(1'b1),
        .jtag_TDI(1'b1),
        .jtag_TDO(jtag_TDO),
        .fpga_data_i(fpga_to_chip),
        .fpga_data_o(chip_to_fpga),
        .pwm_o(pwm_o),
        .i2c_scl(i2c_scl),
        .i2c_sda(i2c_sda)
    );

    fpga_mem_bridge fpga(
        .clk(clk),
        .rst(rst),
        .chip_data_i(chip_to_fpga),
        .chip_data_o(fpga_to_chip)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        rst = `RstEnable;
        chip_sel = 1'b0;
        fpga.rom[0] = 32'h00000013;
        repeat (5) @(negedge clk);
        rst = `RstDisable;
        repeat (40) @(negedge clk);

        if (dut.core_rst !== `RstEnable || dut.u_tinyriscv.u_pc_reg.pc_o !== `CpuResetAddr) begin
            $display("FAIL: deselected chip not held reset core_rst=%b pc=%h",
                     dut.core_rst, dut.u_tinyriscv.u_pc_reg.pc_o);
            $finish;
        end

        chip_sel = 1'b1;
        repeat (250) @(negedge clk);
        if (dut.core_rst !== `RstDisable || dut.u_tinyriscv.u_pc_reg.pc_o === `CpuResetAddr) begin
            $display("FAIL: selected chip did not run core_rst=%b pc=%h",
                     dut.core_rst, dut.u_tinyriscv.u_pc_reg.pc_o);
            $finish;
        end

        $display("PASS: tb_chip_sel");
        $finish;
    end
endmodule
