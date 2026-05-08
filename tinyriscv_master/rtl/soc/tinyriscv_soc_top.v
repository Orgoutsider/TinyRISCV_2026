 /*                                                                      
 * Project SoC top for area-constrained tinyriscv tapeout/FPGA validation.
 *
 * Modifications vs. original:
 *   1. Remove on-chip ROM/RAM, Timer, SPI, GPIO.
 *   2. Add 8-bit chip<->FPGA bridge for off-chip ROM/RAM.
 *   3. Add PWM and I2C peripherals.
 *   4. Add custom instruction sideband for sID/rT/if.
 *   5. Add chip_sel_i for multi-chip IO-ring sharing.
 *
 * chip_sel_i:
 *   1'b1: this chip is selected and works normally.
 *   1'b0: this chip is held in reset and top-level outputs are clamped to
 *         safe values. This RTL does not use internal three-state busses.
 *         True shared-IO selection should be implemented by IO-ring/pad-level
 *         mux or output-enable logic controlled by chip_sel_i.
 */

`include "../core/defines.v"

// tinyriscv soc顶层模块
module tinyriscv_soc_top(

    input wire clk,
    input wire rst,

    input  wire       chip_sel_i,
    output wire       over,
    output wire       succ,

    output wire halted_ind,  // jtag是否已经halt住CPU信号

    input wire uart_debug_pin, // 串口下载使能引脚

    output wire uart_tx_pin, // UART发送引脚
    input wire uart_rx_pin,  // UART接收引脚
    // inout wire[1:0] gpio,    // GPIO引脚

    input wire jtag_TCK,     // JTAG TCK引脚
    input wire jtag_TMS,     // JTAG TMS引脚
    input wire jtag_TDI,     // JTAG TDI引脚
    output wire jtag_TDO,    // JTAG TDO引脚

    // Off-chip ROM/RAM bridge, 8-bit each direction.
    input  wire[7:0]  fpga_data_i,
    output wire[7:0]  fpga_data_o,

    // Project peripherals.
    output wire[3:0]  pwm_o,
    output wire       i2c_scl,
    inout  wire       i2c_sda
    
    // input wire spi_miso,     // SPI MISO引脚
    // output wire spi_mosi,    // SPI MOSI引脚
    // output wire spi_ss,      // SPI SS引脚
    // output wire spi_clk      // SPI CLK引脚

    );

    // rst is active-low. A deselected chip is held in reset and silent.
    wire core_rst = rst & chip_sel_i;

    reg over_raw;
    reg succ_raw;
    wire halted_ind_raw;
    wire uart_tx_pin_raw;
    wire jtag_TDO_raw;
    wire[7:0] fpga_data_o_raw;
    wire[3:0] pwm_o_raw;
    wire i2c_scl_raw;

    // master 0: CPU data access
    wire[`MemAddrBus] m0_addr_i;
    wire[`MemBus]     m0_data_i;
    wire[`MemBus]     m0_data_o;
    wire              m0_req_i;
    wire              m0_we_i;

    // master 1: CPU instruction fetch
    wire[`MemAddrBus] m1_addr_i;
    wire[`MemBus] m1_data_i;
    wire[`MemBus] m1_data_o;
    wire m1_req_i;
    wire m1_we_i;

    // master 2 interface
    wire[`MemAddrBus] m2_addr_i;
    wire[`MemBus] m2_data_i;
    wire[`MemBus] m2_data_o;
    wire m2_req_i;
    wire m2_we_i;

    // master 3 interface
    wire[`MemAddrBus] m3_addr_i;
    wire[`MemBus] m3_data_i;
    wire[`MemBus] m3_data_o;
    wire m3_req_i;
    wire m3_we_i;

    // slave 0: off-chip bridge
    wire[`MemAddrBus] s0_addr_o;
    wire[`MemBus]     s0_data_o;
    wire[`MemBus]     s0_data_i;
    wire              s0_we_o;
    // TODO: check new wire
    wire              s0_req_o;
    wire              s0_is_ram_o;
    wire              s0_busy_i;

    // slave 1: UART
    wire[`MemAddrBus] s1_addr_o;
    wire[`MemBus]     s1_data_o;
    wire[`MemBus]     s1_data_i;
    wire              s1_we_o;

    // slave 2: PWM
    wire[`MemAddrBus] s2_addr_o;
    wire[`MemBus] s2_data_o;
    wire[`MemBus] s2_data_i;
    wire s2_we_o;

    // slave 3: I2C
    wire[`MemAddrBus] s3_addr_o;
    wire[`MemBus] s3_data_o;
    wire[`MemBus] s3_data_i;
    wire s3_we_o;

    // // slave 4 interface
    // wire[`MemAddrBus] s4_addr_o;
    // wire[`MemBus] s4_data_o;
    // wire[`MemBus] s4_data_i;
    // wire s4_we_o;

    // // slave 5 interface
    // wire[`MemAddrBus] s5_addr_o;
    // wire[`MemBus] s5_data_o;
    // wire[`MemBus] s5_data_i;
    // wire s5_we_o;

    // rib
    wire rib_hold_flag_o;
    wire rib_hold_flag_full_o;

    // JTAG <-> core register interface
    wire jtag_halt_req_o;
    wire jtag_reset_req_o;
    wire[`RegAddrBus] jtag_reg_addr_o;
    wire[`RegBus] jtag_reg_data_o;
    wire jtag_reg_we_o;
    wire[`RegBus] jtag_reg_data_i;

    // // tinyriscv
    // wire[`INT_BUS] int_flag;

    // // timer0
    // wire timer0_int;

    // // gpio
    // wire[1:0] io_in;
    // wire[31:0] gpio_ctrl;
    // wire[31:0] gpio_data;

    // assign int_flag = {7'h0, timer0_int};

    // custom instruction sideband
    wire custom_uart_valid;
    wire[7:0] custom_uart_data;
    wire custom_uart_ready;
    wire custom_i2c_req;
    wire custom_i2c_valid;
    wire[7:0] custom_i2c_data;
    wire custom_i2c_busy;

    // Top-level output isolation. No internal high-Z is used here.
    assign over = chip_sel_i ? over_raw : 1'b1;
    assign succ = chip_sel_i ? succ_raw : 1'b1;
    assign halted_ind = chip_sel_i ? halted_ind_raw : 1'b0;
    assign uart_tx_pin = chip_sel_i ? uart_tx_pin_raw : 1'b1;
    assign jtag_TDO = chip_sel_i ? jtag_TDO_raw : 1'b0;
    assign fpga_data_o = chip_sel_i ? fpga_data_o_raw : 8'h00;
    assign pwm_o = chip_sel_i ? pwm_o_raw : 4'b0000;
    assign i2c_scl = chip_sel_i ? i2c_scl_raw : 1'b1;

    // I2C SDA is controlled by the existing I2C open-drain implementation.
    // When chip_sel_i is 0, core_rst resets the I2C block so it releases SDA.
    assign halted_ind_raw = ~jtag_halt_req_o;

    always @(posedge clk) begin
        if (core_rst == `RstEnable) begin
            over_raw <= 1'b1;
            succ_raw <= 1'b1;
        end else begin
            over_raw <= ~u_tinyriscv.u_regs.regs[26];  // when = 1, run over
            succ_raw <= ~u_tinyriscv.u_regs.regs[27];  // when = 1, run succ, otherwise fail
        end
    end

    // tinyriscv处理器核模块例化
    tinyriscv u_tinyriscv(
        .clk(clk),
        .rst(core_rst),

        .rib_ex_addr_o(m0_addr_i),
        .rib_ex_data_i(m0_data_o),
        .rib_ex_data_o(m0_data_i),
        .rib_ex_req_o(m0_req_i),
        .rib_ex_we_o(m0_we_i),

        .rib_pc_addr_o(m1_addr_i),
        .rib_pc_data_i(m1_data_o),

        .jtag_reg_addr_i(jtag_reg_addr_o),
        .jtag_reg_data_i(jtag_reg_data_o),
        .jtag_reg_we_i(jtag_reg_we_o & chip_sel_i),
        .jtag_reg_data_o(jtag_reg_data_i),

        .rib_hold_flag_i(rib_hold_flag_o),
        .rib_hold_flag_full_i(rib_hold_flag_full_o),
        .jtag_halt_flag_i(jtag_halt_req_o & chip_sel_i),
        .jtag_reset_flag_i(jtag_reset_req_o & chip_sel_i),

        .int_i(8'h00), // no interrupt

        .offchip_mem_rdata_i(s0_data_i),

        .custom_uart_tx_valid_o(custom_uart_valid),
        .custom_uart_tx_data_o(custom_uart_data),
        .custom_uart_tx_ready_i(custom_uart_ready),
        .custom_i2c_temp_req_o(custom_i2c_req),
        .custom_i2c_temp_valid_i(custom_i2c_valid),
        .custom_i2c_temp_data_i(custom_i2c_data),
        .custom_i2c_busy_i(custom_i2c_busy)
    );

    // // rom模块例化
    // rom u_rom(
    //     .clk(clk),
    //     .rst(rst),
    //     .we_i(s0_we_o),
    //     .addr_i(s0_addr_o),
    //     .data_i(s0_data_o),
    //     .data_o(s0_data_i)
    // );

    // // ram模块例化
    // ram u_ram(
    //     .clk(clk),
    //     .rst(rst),
    //     .we_i(s1_we_o),
    //     .addr_i(s1_addr_o),
    //     .data_i(s1_data_o),
    //     .data_o(s1_data_i)
    // );

    // // timer模块例化
    // timer timer_0(
    //     .clk(clk),
    //     .rst(rst),
    //     .data_i(s2_data_o),
    //     .addr_i(s2_addr_o),
    //     .we_i(s2_we_o),
    //     .data_o(s2_data_i),
    //     .int_sig_o(timer0_int)
    // );

    // // io0
    // assign gpio[0] = (gpio_ctrl[1:0] == 2'b01)? gpio_data[0]: 1'bz;
    // assign io_in[0] = gpio[0];
    // // io1
    // assign gpio[1] = (gpio_ctrl[3:2] == 2'b01)? gpio_data[1]: 1'bz;
    // assign io_in[1] = gpio[1];

    // // gpio模块例化
    // gpio gpio_0(
    //     .clk(clk),
    //     .rst(rst),
    //     .we_i(s4_we_o),
    //     .addr_i(s4_addr_o),
    //     .data_i(s4_data_o),
    //     .data_o(s4_data_i),
    //     .io_pin_i(io_in),
    //     .reg_ctrl(gpio_ctrl),
    //     .reg_data(gpio_data)
    // );

    // // spi模块例化
    // spi spi_0(
    //     .clk(clk),
    //     .rst(rst),
    //     .data_i(s5_data_o),
    //     .addr_i(s5_addr_o),
    //     .we_i(s5_we_o),
    //     .data_o(s5_data_i),
    //     .spi_mosi(spi_mosi),
    //     .spi_miso(spi_miso),
    //     .spi_ss(spi_ss),
    //     .spi_clk(spi_clk)
    // );

    // rib模块例化
    rib u_rib(
        .clk(clk),
        .rst(core_rst),

        // master 0 interface
        .m0_addr_i(m0_addr_i),
        .m0_data_i(m0_data_i),
        .m0_data_o(m0_data_o),
        .m0_req_i(m0_req_i & chip_sel_i),
        .m0_we_i(m0_we_i),

        // master 1 interface
        .m1_addr_i(m1_addr_i),
        .m1_data_i(`ZeroWord),
        .m1_data_o(m1_data_o),
        .m1_req_i(chip_sel_i ? `RIB_REQ : `RIB_NREQ),
        .m1_we_i(`WriteDisable),

        // master 2 interface
        .m2_addr_i(m2_addr_i),
        .m2_data_i(m2_data_i),
        .m2_data_o(m2_data_o),
        .m2_req_i(m2_req_i & chip_sel_i),
        .m2_we_i(m2_we_i),

        // master 3 interface
        .m3_addr_i(m3_addr_i),
        .m3_data_i(m3_data_i),
        .m3_data_o(m3_data_o),
        .m3_req_i(m3_req_i & chip_sel_i),
        .m3_we_i(m3_we_i),

        // slave 0 interface
        .s0_addr_o(s0_addr_o),
        .s0_data_o(s0_data_o),
        .s0_data_i(s0_data_i),
        .s0_we_o(s0_we_o),
        .s0_req_o(s0_req_o),
        .s0_is_ram_o(s0_is_ram_o),
        .s0_busy_i(s0_busy_i),

        // slave 1 interface
        .s1_addr_o(s1_addr_o),
        .s1_data_o(s1_data_o),
        .s1_data_i(s1_data_i),
        .s1_we_o(s1_we_o),

        // slave 2 interface
        .s2_addr_o(s2_addr_o),
        .s2_data_o(s2_data_o),
        .s2_data_i(s2_data_i),
        .s2_we_o(s2_we_o),

        // slave 3 interface
        .s3_addr_o(s3_addr_o),
        .s3_data_o(s3_data_o),
        .s3_data_i(s3_data_i),
        .s3_we_o(s3_we_o),

        // // slave 4 interface
        // .s4_addr_o(s4_addr_o),
        // .s4_data_o(s4_data_o),
        // .s4_data_i(s4_data_i),
        // .s4_we_o(s4_we_o),

        // // slave 5 interface
        // .s5_addr_o(s5_addr_o),
        // .s5_data_o(s5_data_o),
        // .s5_data_i(s5_data_i),
        // .s5_we_o(s5_we_o),

        .hold_flag_o(rib_hold_flag_o),
        .hold_flag_full_o(rib_hold_flag_full_o)
    );

    // TODO: check this new module
    chip_mem_bridge u_chip_mem_bridge(
        .clk(clk),
        .rst(core_rst),
        .req_i(s0_req_o & chip_sel_i),
        .we_i(s0_we_o),
        .is_ram_i(s0_is_ram_o),
        .addr_i(s0_addr_o),
        .wdata_i(s0_data_o),
        .rdata_o(s0_data_i),
        .busy_o(s0_busy_i),
        .chip_data_o(fpga_data_o_raw),
        .chip_data_i(fpga_data_i)
    );

    // uart模块例化
    // TODO: uart -> uart_shared, check new module
    uart_shared u_uart_0(
        .clk(clk),
        .rst(core_rst),
        .we_i(s1_we_o & chip_sel_i),
        .addr_i(s1_addr_o),
        .data_i(s1_data_o),
        .data_o(s1_data_i),
        .tx_pin(uart_tx_pin_raw),
        .rx_pin(uart_rx_pin),
        .custom_tx_valid_i(custom_uart_valid & chip_sel_i),
        .custom_tx_data_i(custom_uart_data),
        .custom_tx_ready_o(custom_uart_ready)
    );

    // 串口下载模块例化
    // TODO: check this new module
    uart_debug u_uart_debug(
        .clk(clk),
        .rst(core_rst),
        .debug_en_i(uart_debug_pin & chip_sel_i),
        .req_o(m3_req_i),
        .mem_we_o(m3_we_i),
        .mem_addr_o(m3_addr_i),
        .mem_wdata_o(m3_data_i),
        .mem_rdata_i(m3_data_o)
    );

    // pwm模块例化
    // TODO: check this new module
    pwm u_pwm(
        .clk(clk),
        .rst(core_rst),
        .we_i(s2_we_o & chip_sel_i),
        .addr_i(s2_addr_o),
        .data_i(s2_data_o),
        .data_o(s2_data_i),
        .pwm_o(pwm_o_raw)
    );

    // TODO: check this new module
    i2c_lm75 u_i2c(
        .clk(clk),
        .rst(core_rst),
        .we_i(s3_we_o & chip_sel_i),
        .addr_i(s3_addr_o),
        .data_i(s3_data_o),
        .data_o(s3_data_i),
        .custom_temp_req_i(custom_i2c_req & chip_sel_i),
        .custom_temp_valid_o(custom_i2c_valid),
        .custom_temp_data_o(custom_i2c_data),
        .busy_o(custom_i2c_busy),
        .i2c_scl(i2c_scl_raw),
        .i2c_sda(i2c_sda)
    );

    // jtag模块例化
    jtag_top #(
        .DMI_ADDR_BITS(6),
        .DMI_DATA_BITS(32),
        .DMI_OP_BITS(2)
    ) u_jtag_top(
        .clk(clk),
        .jtag_rst_n(core_rst),
        .jtag_pin_TCK(jtag_TCK),
        .jtag_pin_TMS(jtag_TMS),
        .jtag_pin_TDI(jtag_TDI),
        .jtag_pin_TDO(jtag_TDO_raw),
        .reg_we_o(jtag_reg_we_o),
        .reg_addr_o(jtag_reg_addr_o),
        .reg_wdata_o(jtag_reg_data_o),
        .reg_rdata_i(jtag_reg_data_i),
        .mem_we_o(m2_we_i),
        .mem_addr_o(m2_addr_i),
        .mem_wdata_o(m2_data_i),
        .mem_rdata_i(m2_data_o),
        .op_req_o(m2_req_i),
        .halt_req_o(jtag_halt_req_o),
        .reset_req_o(jtag_reset_req_o)
    );

endmodule
