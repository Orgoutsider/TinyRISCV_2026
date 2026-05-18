`timescale 1 ns / 1 ps

`include "defines.v"

// select one option only
// `define TEST_PROG  1
// `define TEST_EXT_IF 1
`define TEST_EXT_sID 1
// `define TEST_EXT_Temp 1
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

    localparam integer UART_BAUD_PERIOD_NS = 8680;
    reg[7:0] uart_recv_data;
    reg uart_recv_done;
    integer uart_i;

`ifdef TEST_EXT_sID
    reg[7:0] sid_recv_data [0:9];
    reg[7:0] expected_id [0:9];
    integer sid_i;
    integer sid_pass;
    integer sid_recv_count;
`endif

`ifdef TEST_EXT_Temp
    reg[7:0] temp_recv_data;
    reg temp_recv_done;
    reg lm75_sda_drive_low;
    integer lm75_transactions;
    reg[7:0] lm75_addr_rw;
    reg[7:0] lm75_pointer;
    reg lm75_master_ack;
    assign i2c_sda = lm75_sda_drive_low ? 1'b0 : 1'bz;
`endif

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

    task uart_recv_byte;
        output [7:0] data;
        integer i;
        begin
            data = 8'h00;

            // wait start bit
            wait(uart_tx_pin == 1'b0);

            // sample at the center of data[0]
            #(UART_BAUD_PERIOD_NS + UART_BAUD_PERIOD_NS / 2);

            for (i = 0; i < 8; i = i + 1) begin
                data[i] = uart_tx_pin;
                #(UART_BAUD_PERIOD_NS);
            end

            if (uart_tx_pin !== 1'b1) begin
                $display("UART STOP BIT ERROR: stop bit = %b", uart_tx_pin);
            end

            // #(UART_BAUD_PERIOD_NS);
        end
    endtask

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
        #200;

`ifdef TEST_PROG
`ifndef TEST_EXT_IF
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

`ifndef TEST_EXT_IF
`ifndef TEST_EXT_sID
`ifndef TEST_EXT_Temp
        $finish;
`endif
`endif
`endif
    end

`ifdef TEST_EXT_IF
`ifndef TEST_EXT_Temp
`ifndef TEST_EXT_sID
    initial begin
        uart_recv_done = 1'b0;
        uart_recv_data = 8'h00;

        wait(rst == `RstDisable);
        repeat (20) @(posedge clk);

        uart_recv_byte(uart_recv_data);
        uart_recv_done = 1'b1;

        if (uart_recv_data == 8'h8A) begin
            $display("~~~~~~~~~~~~~~~~~~~ IF TEST_PASS ~~~~~~~~~~~~~~~~~~~");
            $display("UART output = 0x%02x, expected = 0x8A", uart_recv_data);
            $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
        end else begin
            $display("~~~~~~~~~~~~~~~~~~~ IF TEST_FAIL ~~~~~~~~~~~~~~~~~~~");
            $display("UART output = 0x%02x, expected = 0x8A", uart_recv_data);
            $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
        end

        $finish;
    end
`endif
`endif
`endif

`ifdef TEST_EXT_sID
`ifndef TEST_EXT_Temp
    initial begin
        sid_pass = 1;
        sid_recv_count = 0;

        expected_id[0] = 8'h32; // '2'
        expected_id[1] = 8'h30; // '0'
        expected_id[2] = 8'h32; // '2'
        expected_id[3] = 8'h35; // '5'
        expected_id[4] = 8'h32; // '2'
        expected_id[5] = 8'h31; // '1'
        expected_id[6] = 8'h30; // '0'
        expected_id[7] = 8'h39; // '9'
        expected_id[8] = 8'h32; // '2'
        expected_id[9] = 8'h32; // '2'

        for (sid_i = 0; sid_i < 10; sid_i = sid_i + 1) begin
            sid_recv_data[sid_i] = 8'h00;
        end

        wait(rst == `RstDisable);
        repeat (20) @(posedge clk);

        for (sid_i = 0; sid_i < 10; sid_i = sid_i + 1) begin
            uart_recv_byte(sid_recv_data[sid_i]);
            sid_recv_count = sid_i + 1;
        end

        for (sid_i = 0; sid_i < 10; sid_i = sid_i + 1) begin
            if (sid_recv_data[sid_i] != expected_id[sid_i]) begin
                sid_pass = 0;
            end
        end

        if (sid_pass == 1) begin
            $display("~~~~~~~~~~~~~~~~~~~ sID TEST_PASS ~~~~~~~~~~~~~~~~~~~");
        end else begin
            $display("~~~~~~~~~~~~~~~~~~~ sID TEST_FAIL ~~~~~~~~~~~~~~~~~~~");
            for (sid_i = 0; sid_i < 10; sid_i = sid_i + 1) begin
                $display("byte index %0d: received = 0x%02x, expected = 0x%02x",
                         sid_i, sid_recv_data[sid_i], expected_id[sid_i]);
            end
        end

        $finish;
    end
`endif
`endif

`ifdef TEST_EXT_Temp
    task lm75_wait_start;
        begin
            while (!(i2c_scl === 1'b1 && i2c_sda === 1'b0)) begin
                @(negedge i2c_sda);
            end
        end
    endtask

    task lm75_recv_byte;
        output [7:0] data;
        integer bit_i;
        begin
            data = 8'h00;
            for (bit_i = 7; bit_i >= 0; bit_i = bit_i - 1) begin
                @(posedge i2c_scl);
                data[bit_i] = i2c_sda;
            end
        end
    endtask

    task lm75_send_ack;
        begin
            @(negedge i2c_scl);
            lm75_sda_drive_low = 1'b1;
            @(posedge i2c_scl);
            @(negedge i2c_scl);
            lm75_sda_drive_low = 1'b0;
        end
    endtask

    // task lm75_send_byte;
    //     input [7:0] data;
    //     output master_ack;
    //     integer bit_i;
    //     begin
    //         for (bit_i = 7; bit_i >= 0; bit_i = bit_i - 1) begin
    //             @(negedge i2c_scl);
    //             lm75_sda_drive_low = (data[bit_i] == 1'b0) ? 1'b1 : 1'b0;
    //             @(posedge i2c_scl);
    //         end

    //         @(negedge i2c_scl);
    //         lm75_sda_drive_low = 1'b0;
    //         @(posedge i2c_scl);
    //         master_ack = (i2c_sda == 1'b0);
    //     end
    // endtask

    task lm75_send_byte;
        input [7:0] data;
        output master_ack;
        integer bit_i;
        begin
            for (bit_i = 7; bit_i >= 0; bit_i = bit_i - 1) begin
                // 在 SCL 低电平期间准备 SDA
                lm75_sda_drive_low = (data[bit_i] == 1'b0) ? 1'b1 : 1'b0;

                // DUT 在 SCL 高电平采样
                @(posedge i2c_scl);

                // 等待本 bit 结束，回到低电平
                @(negedge i2c_scl);
            end

            // 第 9 个 clock，释放 SDA，让 master 发送 ACK/NACK
            lm75_sda_drive_low = 1'b0;
            @(posedge i2c_scl);
            master_ack = (i2c_sda == 1'b0);
            @(negedge i2c_scl);
        end
    endtask

    initial begin
        lm75_sda_drive_low = 1'b0;
        lm75_transactions = 0;
        lm75_addr_rw = 8'h00;
        lm75_pointer = 8'h00;
        lm75_master_ack = 1'b0;

        wait(rst == `RstDisable);

        forever begin
            lm75_wait_start();
            lm75_recv_byte(lm75_addr_rw);

            if (lm75_addr_rw[7:1] == 7'h48) begin
                lm75_send_ack();

                if (lm75_addr_rw[0] == 1'b0) begin
                    lm75_recv_byte(lm75_pointer);
                    lm75_send_ack();
                end else begin
                    lm75_send_byte(8'h00, lm75_master_ack);
                    lm75_send_byte(8'h80, lm75_master_ack);
                    lm75_transactions = lm75_transactions + 1;
                    lm75_sda_drive_low = 1'b0;
                end
            end else begin
                lm75_sda_drive_low = 1'b0;
            end
        end
    end

    initial begin
        temp_recv_done = 1'b0;
        temp_recv_data = 8'h00;

        wait(rst == `RstDisable);
        repeat (20) @(posedge clk);

        uart_recv_byte(temp_recv_data);
        temp_recv_done = 1'b1;

        if (temp_recv_data == 8'h01) begin
            $display("~~~~~~~~~~~~~~~~~~~ Temp TEST_PASS ~~~~~~~~~~~~~~~~~~~");
        end else begin
            $display("~~~~~~~~~~~~~~~~~~~ Temp TEST_FAIL ~~~~~~~~~~~~~~~~~~~");
            $display("UART output = 0x%02x, expected = 0x01", temp_recv_data);
        end

        $finish;
    end
`endif

    // sim timeout: instruction fetch now goes through chip_mem_bridge + fpga_mem_bridge.
    initial begin
`ifdef TEST_EXT_Temp
        #100000000;
        if (temp_recv_done == 1'b0) begin
            $display("~~~~~~~~~~~~~~~~~~~ Temp TEST_TIMEOUT ~~~~~~~~~~~~~~~~~~~");
            $display("No UART byte received from uart_tx_pin. LM75 transactions = %0d", lm75_transactions);
            $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
        end
`elsif TEST_EXT_sID
        #100000000;
        if (sid_recv_count < 10) begin
            $display("~~~~~~~~~~~~~~~~~~~ sID TEST_TIMEOUT ~~~~~~~~~~~~~~~~~~~");
            $display("Only %0d UART byte(s) received from uart_tx_pin.", sid_recv_count);
            $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
        end
`elsif TEST_EXT_IF
        #10000000;
        if (uart_recv_done == 1'b0) begin
            $display("~~~~~~~~~~~~~~~~~~~ IF TEST_TIMEOUT ~~~~~~~~~~~~~~~~~~~");
            $display("No UART byte received from uart_tx_pin.");
            $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
        end
`else
        #2500000000;
        $display("Time Out.");
`endif
        $finish;
    end

    // Current ROM/RAM live on the FPGA side in fpga_mem_bridge.
    // If your simulator runs from another directory, pass +INST=path/to/inst.data.
    initial begin
        if (!$value$plusargs("INST=%s", inst_file)) begin
`ifdef TEST_EXT_Temp
            inst_file = "E://learn/thu/digital_work/tinyriscv_2026/inst/Extend_Inst_Example/Temp/Temp.data";
`elsif TEST_EXT_sID
            inst_file = "E://learn/thu/digital_work/tinyriscv_2026/inst/Extend_Inst_Example/sID/sID_inst.data";
`else
            inst_file = "E://learn/thu/digital_work/tinyriscv_2026/inst/Extend_Inst_Example/IF/IF_inst.data";
`endif
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
