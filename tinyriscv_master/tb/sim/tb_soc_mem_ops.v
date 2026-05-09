`timescale 1ns/1ps
`include "defines.v"

module tb_soc_mem_ops;
    reg clk;
    reg rst;
    reg chip_sel;
    reg uart_debug_pin;
    reg uart_rx_pin;
    reg jtag_TCK;
    reg jtag_TMS;
    reg jtag_TDI;
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
        .uart_debug_pin(uart_debug_pin),
        .uart_tx_pin(uart_tx_pin),
        .uart_rx_pin(uart_rx_pin),
        .jtag_TCK(jtag_TCK),
        .jtag_TMS(jtag_TMS),
        .jtag_TDI(jtag_TDI),
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

    function [31:0] inst_lui;
        input [4:0] rd;
        input [19:0] imm20;
        begin
            inst_lui = {imm20, rd, 7'b0110111};
        end
    endfunction

    function [31:0] inst_load;
        input [4:0] rd;
        input [4:0] rs1;
        input [2:0] funct3;
        input [11:0] imm;
        begin
            inst_load = {imm, rs1, funct3, rd, 7'b0000011};
        end
    endfunction

    function [31:0] inst_store;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        input [11:0] imm;
        begin
            inst_store = {imm[11:5], rs2, rs1, funct3, imm[4:0], 7'b0100011};
        end
    endfunction

    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        rst = `RstEnable;
        chip_sel = 1'b1;
        uart_debug_pin = 1'b0;
        uart_rx_pin = 1'b1;
        jtag_TCK = 1'b0;
        jtag_TMS = 1'b1;
        jtag_TDI = 1'b1;

        fpga.rom[0] = inst_lui(5'd2, 20'h10000);                  // x2 = RAM base
        fpga.rom[1] = inst_load(5'd5, 5'd2, `INST_LW, 12'd0);     // x5 = ram[0]
        fpga.rom[2] = inst_load(5'd6, 5'd2, `INST_LB, 12'd2);     // sign byte 0xff 字节加载（8位，符号扩展）
        fpga.rom[3] = inst_load(5'd7, 5'd2, `INST_LBU, 12'd2);    // zero byte 0xff 字节加载（8位，零扩展）
        fpga.rom[4] = inst_load(5'd8, 5'd2, `INST_LH, 12'd2);     // sign half 0x80ff 半字加载（16位，符号扩展）
        fpga.rom[5] = inst_load(5'd9, 5'd2, `INST_LHU, 12'd2);    // zero half 0x80ff 半字加载（16位，零扩展）
        fpga.rom[6] = inst_store(5'd5, 5'd2, `INST_SW, 12'd4);    // ram[1] = x5  字存储（32位写入）
        fpga.rom[7] = 32'h00000013;
        fpga.rom[8] = 32'h00000013;

        fpga.ram[0] = 32'h80ff7f5a;
        fpga.ram[1] = 32'h00000000;

        repeat (5) @(negedge clk);
        rst = `RstDisable;
        repeat (1200) @(negedge clk);

        if (dut.u_tinyriscv.u_regs.regs[5] !== 32'h80ff7f5a) begin
            $display("FAIL: lw x5=%h", dut.u_tinyriscv.u_regs.regs[5]);
            $finish;
        end
        if (dut.u_tinyriscv.u_regs.regs[6] !== 32'hffffffff) begin
            $display("FAIL: lb x6=%h", dut.u_tinyriscv.u_regs.regs[6]);
            $finish;
        end
        if (dut.u_tinyriscv.u_regs.regs[7] !== 32'h000000ff) begin
            $display("FAIL: lbu x7=%h", dut.u_tinyriscv.u_regs.regs[7]);
            $finish;
        end
        if (dut.u_tinyriscv.u_regs.regs[8] !== 32'hffff80ff) begin
            $display("FAIL: lh x8=%h", dut.u_tinyriscv.u_regs.regs[8]);
            $finish;
        end
        if (dut.u_tinyriscv.u_regs.regs[9] !== 32'h000080ff) begin
            $display("FAIL: lhu x9=%h", dut.u_tinyriscv.u_regs.regs[9]);
            $finish;
        end
        if (fpga.ram[1] !== 32'h80ff7f5a) begin
            $display("FAIL: sw ram1=%h", fpga.ram[1]);
            $finish;
        end

        $display("PASS: tb_soc_mem_ops");
        $finish;
    end
endmodule
