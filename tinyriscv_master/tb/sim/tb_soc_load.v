`timescale 1ns/1ps
`include "defines.v"

module tb_soc_load;
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

    initial clk = 1'b0;
    always #5 clk = ~clk;

`ifdef TRACE
    always @(posedge clk) begin
        if (rst == `RstDisable) begin
            $display("t=%0t pc=%h if=%h ie=%h x2=%h x5=%h rib_st=%0d owner=%0d hold=%b full=%b s0_req=%b busy=%b s0_addr=%h s0_rdata=%h regs_we=%b regs_waddr=%0d regs_wdata=%h",
                     $time,
                     dut.u_tinyriscv.u_pc_reg.pc_o,
                     dut.u_tinyriscv.if_inst_o,
                     dut.u_tinyriscv.ie_inst_o,
                     dut.u_tinyriscv.u_regs.regs[2],
                     dut.u_tinyriscv.u_regs.regs[5],
                     dut.u_rib.state,
                     dut.u_rib.owner,
                     dut.rib_hold_flag_o,
                     dut.rib_hold_flag_full_o,
                     dut.s0_req_o,
                     dut.s0_busy_i,
                     dut.s0_addr_o,
                     dut.s0_data_i,
                     dut.u_tinyriscv.regs_we,
                     dut.u_tinyriscv.regs_waddr,
                     dut.u_tinyriscv.regs_wdata);
        end
    end
`endif

    initial begin
        rst = `RstEnable;
        chip_sel = 1'b1;
        uart_debug_pin = 1'b0;
        uart_rx_pin = 1'b1;
        jtag_TCK = 1'b0;
        jtag_TMS = 1'b1;
        jtag_TDI = 1'b1;

        fpga.rom[0] = 32'h10000137; // lui x2,0x10000 结果：x2 = 0x10000000
        fpga.rom[1] = 32'h00012283; // lw x5,0(x2)
        fpga.rom[2] = 32'h00000013; // nop
        fpga.rom[3] = 32'h00000013; // nop
        fpga.ram[0] = 32'ha5a55a5a;

        repeat (5) @(negedge clk);
        rst = `RstDisable;
        repeat (300) @(negedge clk);

        if (dut.u_tinyriscv.u_regs.regs[5] !== 32'ha5a55a5a) begin
            $display("FAIL: soc load x5=%h", dut.u_tinyriscv.u_regs.regs[5]);
            $finish;
        end

        $display("PASS: tb_soc_load");
        $finish;
    end
endmodule
