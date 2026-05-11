`timescale 1 ns / 1 ps

`include "defines.v"

// select one option only
`define TEST_PROG  1
//`define TEST_JTAG  1


// testbench module
module tinyriscv_soc_tb;

    reg clk;
    reg rst;

    wire chip_sel_i;
    wire over;
    wire succ;
    wire halted_ind;
    wire uart_tx_pin;
    wire uart_rx_pin;
    wire[7:0] fpga_data_i;
    wire[7:0] fpga_data_o;
    wire[3:0] pwm_o;
    wire i2c_scl;
    tri1 i2c_sda;

    reg jtag_TCK;
    reg jtag_TMS;
    reg jtag_TDI;
    wire jtag_TDO;

    reg[1023:0] inst_file;

    assign chip_sel_i = 1'b1;
    assign uart_rx_pin = 1'b1;  // UART idle level

    always #10 clk = ~clk;     // 50MHz

    wire[`RegBus] x3 = tinyriscv_soc_top_0.u_tinyriscv.u_regs.regs[3];
    wire[`RegBus] x26 = tinyriscv_soc_top_0.u_tinyriscv.u_regs.regs[26];
    wire[`RegBus] x27 = tinyriscv_soc_top_0.u_tinyriscv.u_regs.regs[27];

    integer r;

`ifdef TEST_JTAG
    integer i;
    reg[39:0] shift_reg;
    reg in;
    wire[39:0] req_data = tinyriscv_soc_top_0.u_jtag_top.u_jtag_driver.dtm_req_data;
    wire[4:0] ir_reg = tinyriscv_soc_top_0.u_jtag_top.u_jtag_driver.ir_reg;
    wire dtm_req_valid = tinyriscv_soc_top_0.u_jtag_top.u_jtag_driver.dtm_req_valid;
    wire[31:0] dmstatus = tinyriscv_soc_top_0.u_jtag_top.u_jtag_dm.dmstatus;
`endif

    initial begin
        clk = 1'b0;
        rst = `RstEnable;
        jtag_TCK = 1'b0;
        jtag_TMS = 1'b1;
        jtag_TDI = 1'b0;
`ifdef TEST_JTAG
        jtag_TCK = 1'b1;
        jtag_TDI = 1'b1;
`endif
        $display("test running...");
        #40
        rst = `RstDisable;
        #200

`ifdef TEST_PROG
        wait(x26 == 32'b1)   // wait sim end, when x26 == 1
        #1000
        if (x27 == 32'b1) begin
            $display("~~~~~~~~~~~~~~~~~~~ TEST_PASS ~~~~~~~~~~~~~~~~~~~");
            $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
            $display("~~~~~~~~~ #####     ##     ####    #### ~~~~~~~~~");
            $display("~~~~~~~~~ #    #   #  #   #       #     ~~~~~~~~~");
            $display("~~~~~~~~~ #    #  #    #   ####    #### ~~~~~~~~~");
            $display("~~~~~~~~~ #####   ######       #       #~~~~~~~~~");
            $display("~~~~~~~~~ #       #    #  #    #  #    #~~~~~~~~~");
            $display("~~~~~~~~~ #       #    #   ####    #### ~~~~~~~~~");
            $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
        end else begin
            $display("~~~~~~~~~~~~~~~~~~~ TEST_FAIL ~~~~~~~~~~~~~~~~~~~~");
            $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
            $display("~~~~~~~~~~######    ##       #    #     ~~~~~~~~~~");
            $display("~~~~~~~~~~#        #  #      #    #     ~~~~~~~~~~");
            $display("~~~~~~~~~~#####   #    #     #    #     ~~~~~~~~~~");
            $display("~~~~~~~~~~#       ######     #    #     ~~~~~~~~~~");
            $display("~~~~~~~~~~#       #    #     #    #     ~~~~~~~~~~");
            $display("~~~~~~~~~~#       #    #     #    ######~~~~~~~~~~");
            $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
            $display("fail testnum = %2d", x3);
            for (r = 0; r < 32; r = r + 1)
                $display("x%2d = 0x%x", r, tinyriscv_soc_top_0.u_tinyriscv.u_regs.regs[r]);
        end
`endif

`ifdef TEST_JTAG
        // reset
        for (i = 0; i < 8; i = i + 1) begin
            jtag_TMS = 1'b1;
            jtag_TCK = 1'b0;
            #100
            jtag_TCK = 1'b1;
            #100
            jtag_TCK = 1'b0;
        end

        // IR
        shift_reg = 40'b10001;

        // IDLE
        jtag_TMS = 1'b0;
        jtag_TCK = 1'b0;
        #100
        jtag_TCK = 1'b1;
        #100
        jtag_TCK = 1'b0;

        // SELECT-DR
        jtag_TMS = 1'b1;
        jtag_TCK = 1'b0;
        #100
        jtag_TCK = 1'b1;
        #100
        jtag_TCK = 1'b0;

        // SELECT-IR
        jtag_TMS = 1'b1;
        jtag_TCK = 1'b0;
        #100
        jtag_TCK = 1'b1;
        #100
        jtag_TCK = 1'b0;

        // CAPTURE-IR
        jtag_TMS = 1'b0;
        jtag_TCK = 1'b0;
        #100
        jtag_TCK = 1'b1;
        #100
        jtag_TCK = 1'b0;

        // SHIFT-IR
        jtag_TMS = 1'b0;
        jtag_TCK = 1'b0;
        #100
        jtag_TCK = 1'b1;
        #100
        jtag_TCK = 1'b0;

        // SHIFT-IR & EXIT1-IR
        for (i = 5; i > 0; i = i - 1) begin
            if (shift_reg[0] == 1'b1)
                jtag_TDI = 1'b1;
            else
                jtag_TDI = 1'b0;

            if (i == 1)
                jtag_TMS = 1'b1;

            jtag_TCK = 1'b0;
            #100
            in = jtag_TDO;
            jtag_TCK = 1'b1;
            #100
            jtag_TCK = 1'b0;

            shift_reg = {{(35){1'b0}}, in, shift_reg[4:1]};
        end

        // PAUSE-IR
        jtag_TMS = 1'b0;
        jtag_TCK = 1'b0;
        #100
        jtag_TCK = 1'b1;
        #100
        jtag_TCK = 1'b0;

        // EXIT2-IR
        jtag_TMS = 1'b1;
        jtag_TCK = 1'b0;
        #100
        jtag_TCK = 1'b1;
        #100
        jtag_TCK = 1'b0;

        // UPDATE-IR
        jtag_TMS = 1'b1;
        jtag_TCK = 1'b0;
        #100
        jtag_TCK = 1'b1;
        #100
        jtag_TCK = 1'b0;

        // IDLE
        jtag_TMS = 1'b0;
        jtag_TCK = 1'b0;
        #100
        jtag_TCK = 1'b1;
        #100
        jtag_TCK = 1'b0;

        // IDLE
        jtag_TMS = 1'b0;
        jtag_TCK = 1'b0;
        #100
        jtag_TCK = 1'b1;
        #100
        jtag_TCK = 1'b0;

        // IDLE
        jtag_TMS = 1'b0;
        jtag_TCK = 1'b0;
        #100
        jtag_TCK = 1'b1;
        #100
        jtag_TCK = 1'b0;

        // IDLE
        jtag_TMS = 1'b0;
        jtag_TCK = 1'b0;
        #100
        jtag_TCK = 1'b1;
        #100
        jtag_TCK = 1'b0;

        // dmi write
        shift_reg = {6'h10, {(32){1'b0}}, 2'b10};

        // SELECT-DR
        jtag_TMS = 1'b1;
        jtag_TCK = 1'b0;
        #100
        jtag_TCK = 1'b1;
        #100
        jtag_TCK = 1'b0;

        // CAPTURE-DR
        jtag_TMS = 1'b0;
        jtag_TCK = 1'b0;
        #100
        jtag_TCK = 1'b1;
        #100
        jtag_TCK = 1'b0;

        // SHIFT-DR
        jtag_TMS = 1'b0;
        jtag_TCK = 1'b0;
        #100
        jtag_TCK = 1'b1;
        #100
        jtag_TCK = 1'b0;

        // SHIFT-DR & EXIT1-DR
        for (i = 40; i > 0; i = i - 1) begin
            if (shift_reg[0] == 1'b1)
                jtag_TDI = 1'b1;
            else
                jtag_TDI = 1'b0;

            if (i == 1)
                jtag_TMS = 1'b1;

            jtag_TCK = 1'b0;
            #100
            in = jtag_TDO;
            jtag_TCK = 1'b1;
            #100
            jtag_TCK = 1'b0;

            shift_reg = {in, shift_reg[39:1]};
        end

        // PAUSE-DR
        jtag_TMS = 1'b0;
        jtag_TCK = 1'b0;
        #100
        jtag_TCK = 1'b1;
        #100
        jtag_TCK = 1'b0;

        // EXIT2-DR
        jtag_TMS = 1'b1;
        jtag_TCK = 1'b0;
        #100
        jtag_TCK = 1'b1;
        #100
        jtag_TCK = 1'b0;

        // UPDATE-DR
        jtag_TMS = 1'b1;
        jtag_TCK = 1'b0;
        #100
        jtag_TCK = 1'b1;
        #100
        jtag_TCK = 1'b0;

        // IDLE
        jtag_TMS = 1'b0;
        jtag_TCK = 1'b0;
        #100
        jtag_TCK = 1'b1;
        #100
        jtag_TCK = 1'b0;

        $display("ir_reg = 0x%x", ir_reg);
        $display("dtm_req_valid = %d", dtm_req_valid);
        $display("req_data = 0x%x", req_data);

        // IDLE
        jtag_TMS = 1'b0;
        jtag_TCK = 1'b0;
        #100
        jtag_TCK = 1'b1;
        #100
        jtag_TCK = 1'b0;

        // IDLE
        jtag_TMS = 1'b0;
        jtag_TCK = 1'b0;
        #100
        jtag_TCK = 1'b1;
        #100
        jtag_TCK = 1'b0;

        $display("dmstatus = 0x%x", dmstatus);

        // IDLE
        jtag_TMS = 1'b0;
        jtag_TCK = 1'b0;
        #100
        jtag_TCK = 1'b1;
        #100
        jtag_TCK = 1'b0;

        // SELECT-DR
        jtag_TMS = 1'b1;
        jtag_TCK = 1'b0;
        #100
        jtag_TCK = 1'b1;
        #100
        jtag_TCK = 1'b0;

        // dmi read
        shift_reg = {6'h11, {(32){1'b0}}, 2'b01};

        // CAPTURE-DR
        jtag_TMS = 1'b0;
        jtag_TCK = 1'b0;
        #100
        jtag_TCK = 1'b1;
        #100
        jtag_TCK = 1'b0;

        // SHIFT-DR
        jtag_TMS = 1'b0;
        jtag_TCK = 1'b0;
        #100
        jtag_TCK = 1'b1;
        #100
        jtag_TCK = 1'b0;

        // SHIFT-DR & EXIT1-DR
        for (i = 40; i > 0; i = i - 1) begin
            if (shift_reg[0] == 1'b1)
                jtag_TDI = 1'b1;
            else
                jtag_TDI = 1'b0;

            if (i == 1)
                jtag_TMS = 1'b1;

            jtag_TCK = 1'b0;
            #100
            in = jtag_TDO;
            jtag_TCK = 1'b1;
            #100
            jtag_TCK = 1'b0;

            shift_reg = {in, shift_reg[39:1]};
        end

        // PAUSE-DR
        jtag_TMS = 1'b0;
        jtag_TCK = 1'b0;
        #100
        jtag_TCK = 1'b1;
        #100
        jtag_TCK = 1'b0;

        // EXIT2-DR
        jtag_TMS = 1'b1;
        jtag_TCK = 1'b0;
        #100
        jtag_TCK = 1'b1;
        #100
        jtag_TCK = 1'b0;

        // UPDATE-DR
        jtag_TMS = 1'b1;
        jtag_TCK = 1'b0;
        #100
        jtag_TCK = 1'b1;
        #100
        jtag_TCK = 1'b0;

        // IDLE
        jtag_TMS = 1'b0;
        jtag_TCK = 1'b0;
        #100
        jtag_TCK = 1'b1;
        #100
        jtag_TCK = 1'b0;

        // IDLE
        jtag_TMS = 1'b0;
        jtag_TCK = 1'b0;
        #100
        jtag_TCK = 1'b1;
        #100
        jtag_TCK = 1'b0;

        // IDLE
        jtag_TMS = 1'b0;
        jtag_TCK = 1'b0;
        #100
        jtag_TCK = 1'b1;
        #100
        jtag_TCK = 1'b0;

        // IDLE
        jtag_TMS = 1'b0;
        jtag_TCK = 1'b0;
        #100
        jtag_TCK = 1'b1;
        #100
        jtag_TCK = 1'b0;

        // SELECT-DR
        jtag_TMS = 1'b1;
        jtag_TCK = 1'b0;
        #100
        jtag_TCK = 1'b1;
        #100
        jtag_TCK = 1'b0;

        // dmi read
        shift_reg = {6'h11, {(32){1'b0}}, 2'b00};

        // CAPTURE-DR
        jtag_TMS = 1'b0;
        jtag_TCK = 1'b0;
        #100
        jtag_TCK = 1'b1;
        #100
        jtag_TCK = 1'b0;

        // SHIFT-DR
        jtag_TMS = 1'b0;
        jtag_TCK = 1'b0;
        #100
        jtag_TCK = 1'b1;
        #100
        jtag_TCK = 1'b0;

        // SHIFT-DR & EXIT1-DR
        for (i = 40; i > 0; i = i - 1) begin
            if (shift_reg[0] == 1'b1)
                jtag_TDI = 1'b1;
            else
                jtag_TDI = 1'b0;

            if (i == 1)
                jtag_TMS = 1'b1;

            jtag_TCK = 1'b0;
            #100
            in = jtag_TDO;
            jtag_TCK = 1'b1;
            #100
            jtag_TCK = 1'b0;

            shift_reg = {in, shift_reg[39:1]};
        end

        #100

        $display("shift_reg = 0x%x", shift_reg[33:2]);

        if (dmstatus == shift_reg[33:2]) begin
            $display("######################");
            $display("### jtag test pass ###");
            $display("######################");
        end else begin
            $display("######################");
            $display("!!! jtag test fail !!!");
            $display("######################");
        end
`endif

        $finish;
    end

    // sim timeout: instruction fetch now goes through chip_mem_bridge + fpga_mem_bridge.
    initial begin
        #5000000
        $display("Time Out.");
        $finish;
    end

    // Current ROM/RAM live on the FPGA side in fpga_mem_bridge.
    // If your simulator runs from another directory, pass +INST=path/to/inst.data.
    initial begin
        if (!$value$plusargs("INST=%s", inst_file)) begin
            inst_file = "E://learn/thu/digital_work/tinyriscv_2026/inst/Baisc_Inst_Example/inst_xori.data";
        end
        $display("load inst file: %0s", inst_file);
        $readmemh(inst_file, fpga_mem_bridge_0.rom);
    end

    // generate wave file, used by gtkwave
    initial begin
        $dumpfile("tinyriscv_soc_tb.vcd");
        $dumpvars(0, tinyriscv_soc_tb);
    end

    tinyriscv_soc_top tinyriscv_soc_top_0(
        .clk(clk),
        .rst(rst),
        .chip_sel_i(chip_sel_i),
        .over(over),
        .succ(succ),
        .halted_ind(halted_ind),
        .uart_debug_pin(1'b0),
        .uart_tx_pin(uart_tx_pin),
        .uart_rx_pin(uart_rx_pin),
        .jtag_TCK(jtag_TCK),
        .jtag_TMS(jtag_TMS),
        .jtag_TDI(jtag_TDI),
        .jtag_TDO(jtag_TDO),
        .fpga_data_i(fpga_data_i),
        .fpga_data_o(fpga_data_o),
        .pwm_o(pwm_o),
        .i2c_scl(i2c_scl),
        .i2c_sda(i2c_sda)
    );

    fpga_mem_bridge #(
        .ROM_INIT_FILE("")
    ) fpga_mem_bridge_0 (
        .clk(clk),
        .rst(rst),
        .chip_data_i(fpga_data_o),
        .chip_data_o(fpga_data_i)
    );

endmodule
