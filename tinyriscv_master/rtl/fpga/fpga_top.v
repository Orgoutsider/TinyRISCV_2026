/*
 * FPGA validation top.
 *
 * This top integrates:
 *   1. tinyriscv_soc_top  : chip-side SoC logic
 *   2. fpga_mem_bridge    : FPGA-side ROM/RAM bridge
 *
 * The 8-bit chip<->FPGA memory bridge interface is connected internally
 * for FPGA validation. PC-facing UART/JTAG/PWM/I2C pins are preserved.
 */

module fpga_top #(
    // may delete
    parameter ROM_INIT_FILE = ""
)(
    input  wire       clk,
    input  wire       rst,

    // For single-chip FPGA validation, this can be tied to 1'b1 in XDC/top.
    // input  wire       chip_sel_i,

    output wire       over,
    output wire       succ,
    output wire       halted_ind,

    // UART download/debug/program output interface.
    input  wire       uart_debug_pin,
    output wire       uart_tx_pin,
    input  wire       uart_rx_pin,

    // JTAG interface.
    // input  wire       jtag_TCK,
    // input  wire       jtag_TMS,
    // input  wire       jtag_TDI,
    // output wire       jtag_TDO,

    // PWM output.
    output wire[3:0]  PWM_o,

    // I2C interface for LM75.
    output wire       io_scl,
    inout  wire       io_sda
);

    // Internal 8-bit bridge wires.
    // SoC -> FPGA memory bridge
    wire[7:0] chip_to_fpga_data;

    // FPGA memory bridge -> SoC
    wire[7:0] fpga_to_chip_data;

    wire jtag_TDO_unused;

    /*
     * Chip-side SoC.
     *
     * This module contains CPU/RIB/UART/UART_DEBUG/PWM/I2C/JTAG/chip_mem_bridge.
     * Its fpga_data_o/fpga_data_i ports are the chip-side 8-bit external
     * memory interface.
     */
    tinyriscv_soc_top u_tinyriscv_soc_top (
        .clk             (clk),
        .rst             (rst),

        .chip_sel_i      (1'b1), // always selected in FPGA validation
        .over            (over),
        .succ            (succ),
        .halted_ind      (halted_ind),

        .uart_debug_pin  (uart_debug_pin),
        .uart_tx_pin     (uart_tx_pin),
        .uart_rx_pin     (uart_rx_pin),

        .jtag_TCK (1'b0),
        .jtag_TMS (1'b1),
        .jtag_TDI (1'b0),
        .jtag_TDO (jtag_TDO_unused),

        .fpga_data_i     (fpga_to_chip_data),
        .fpga_data_o     (chip_to_fpga_data),

        .pwm_o           (PWM_o),
        .i2c_scl         (io_scl),
        .i2c_sda         (io_sda)
    );

    /*
     * FPGA-side external memory.
     *
     * This module contains:
     *   ROM: 256 x 32-bit
     *   RAM: 16  x 32-bit
     *
     * It matches the protocol of chip_mem_bridge in tinyriscv_soc_top.
     */
    fpga_mem_bridge #(
        .ROM_INIT_FILE   (ROM_INIT_FILE)
    ) u_fpga_mem_bridge (
        .clk             (clk),
        .rst             (rst),
        .chip_data_i     (chip_to_fpga_data),
        .chip_data_o     (fpga_to_chip_data)
    );

endmodule