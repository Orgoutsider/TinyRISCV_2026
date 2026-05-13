`timescale 1 ns / 1 ps

`include "defines.v"

// UART-download based PWM testbench.
// Flow:
//   1) TB emulates inst/tinyriscv_fw_downloader.py and downloads
//      inst/Other_Example/PWM/PWM_inst_fast.data through uart_debug.
//   2) DUT uart_debug writes the program into fpga_mem_bridge.rom.
//   3) TB resets the core and then runs the same PWM register/waveform
//      checking logic as tinyriscv_soc_pwm_tb.v.
module tinyriscv_soc_uart_download_pwm_tb;

    reg clk;
    reg rst;
    reg uart_debug_pin;
    reg uart_rx_pin;

    wire chip_sel_i;
    wire over;
    wire succ;
    wire halted_ind;
    wire uart_tx_pin;
    wire[7:0] fpga_data_i;
    wire[7:0] fpga_data_o;
    wire[3:0] pwm_o;
    wire i2c_scl;
    tri1 i2c_sda;

    reg jtag_TCK;
    reg jtag_TMS;
    reg jtag_TDI;
    wire jtag_TDO;

    reg[1023:0] fw_file;

    localparam integer UART_BIT_PERIOD_NS = 8680;
    localparam integer UART_TX_BIT_CLKS   = 441;
    localparam integer ACK_TIMEOUT_CYCLES = 2000000;

    reg[31:0] fw_words [0:255];
    reg[7:0]  fw_bytes [0:1023];
    reg[7:0]  packet   [0:34];

    integer fw_word_count;
    integer fw_size_bytes;
    integer packet_num;
    integer packet_index;
    integer download_pass;
    integer i;

    reg pwm_test_start;
    integer pwm_pass;
    integer wait_cycles;
    integer ch0_pass;
    integer ch1_pass;
    integer ch2_pass;
    integer ch3_pass;

    assign chip_sel_i = 1'b1;

    always #10 clk = ~clk;     // 50MHz

    task fail_and_finish;
        input [1023:0] reason;
        begin
            $display("~~~~~~~~~~~~~~~~~~~ UART DOWNLOAD PWM TEST_FAIL ~~~~~~~~~~~~~~~~~~~");
            $display("%0s", reason);
            $finish;
        end
    endtask

    task uart_send_byte;
        input [7:0] data;
        integer bit_i;
        begin
            @(negedge clk);
            uart_rx_pin = 1'b0;  // start bit
            repeat (UART_TX_BIT_CLKS) @(posedge clk);

            for (bit_i = 0; bit_i < 8; bit_i = bit_i + 1) begin
                @(negedge clk);
                uart_rx_pin = data[bit_i];
                repeat (UART_TX_BIT_CLKS) @(posedge clk);
            end

            @(negedge clk);
            uart_rx_pin = 1'b1;  // stop bit
            repeat (UART_TX_BIT_CLKS) @(posedge clk);
        end
    endtask

    task uart_recv_byte_timeout;
        output [7:0] data;
        output integer ok;
        integer bit_i;
        integer timeout_i;
        reg prev_tx;
        begin
            data = 8'h00;
            ok = 0;
            timeout_i = 0;
            prev_tx = uart_tx_pin;

            // Wait for a real falling edge of ACK/NAK start bit.
            while (ok == 0 && timeout_i < ACK_TIMEOUT_CYCLES) begin
                @(posedge clk);
                if (prev_tx == 1'b1 && uart_tx_pin == 1'b0) begin
                    ok = 1;
                end
                prev_tx = uart_tx_pin;
                timeout_i = timeout_i + 1;
            end

            if (ok) begin
                #(UART_BIT_PERIOD_NS + UART_BIT_PERIOD_NS / 2);
                for (bit_i = 0; bit_i < 8; bit_i = bit_i + 1) begin
                    data[bit_i] = uart_tx_pin;
                    #(UART_BIT_PERIOD_NS);
                end
                if (uart_tx_pin !== 1'b1) begin
                    $display("UART STOP BIT ERROR: stop bit = %b", uart_tx_pin);
                end
            end
        end
    endtask

    task calc_packet_crc;
        output [15:0] crc;
        integer byte_i;
        integer bit_i;
        reg[7:0] crc_byte;
        begin
            crc = 16'hffff;
            for (byte_i = 1; byte_i <= 32; byte_i = byte_i + 1) begin
                crc_byte = packet[byte_i];
                for (bit_i = 0; bit_i < 8; bit_i = bit_i + 1) begin
                    if ((crc[0] ^ crc_byte[0]) == 1'b1) begin
                        crc = (crc >> 1) ^ 16'ha001;
                    end else begin
                        crc = (crc >> 1);
                    end
                    crc_byte = {1'b0, crc_byte[7:1]};
                end
            end
        end
    endtask

    task clear_packet;
        integer clear_i;
        begin
            for (clear_i = 0; clear_i < 35; clear_i = clear_i + 1) begin
                packet[clear_i] = 8'h00;
            end
        end
    endtask

    task set_default_packet_name;
        begin
            packet[1]  = "i";
            packet[2]  = "n";
            packet[3]  = "s";
            packet[4]  = "t";
            packet[5]  = ".";
            packet[6]  = "d";
            packet[7]  = "a";
            packet[8]  = "t";
            packet[9]  = "a";
        end
    endtask

    task build_first_packet;
        reg[15:0] crc;
        begin
            clear_packet();
            packet[0] = 8'h00;
            set_default_packet_name();
            packet[25] = fw_size_bytes[31:24];
            packet[26] = fw_size_bytes[23:16];
            packet[27] = fw_size_bytes[15:8];
            packet[28] = fw_size_bytes[7:0];
            calc_packet_crc(crc);
            packet[33] = crc[7:0];
            packet[34] = crc[15:8];
        end
    endtask

    task build_data_packet;
        input integer pkt_index;
        integer byte_i;
        integer data_index;
        reg[15:0] crc;
        begin
            clear_packet();
            packet[0] = pkt_index[7:0];
            data_index = (pkt_index - 1) * 32;
            for (byte_i = 0; byte_i < 32; byte_i = byte_i + 1) begin
                if ((data_index + byte_i) < fw_size_bytes) begin
                    packet[byte_i + 1] = fw_bytes[data_index + byte_i];
                end else begin
                    packet[byte_i + 1] = 8'h00;
                end
            end
            calc_packet_crc(crc);
            packet[33] = crc[7:0];
            packet[34] = crc[15:8];

            if (pkt_index == 11) begin
                $display("PKT11 bytes[13..16] = %02x %02x %02x %02x",
                        packet[13], packet[14], packet[15], packet[16]);
                $display("PKT11 word3 = 0x%02x%02x%02x%02x",
                        packet[16], packet[15], packet[14], packet[13]);
            end
        end
    endtask

    task send_packet_and_check_ack;
        input integer pkt_index;
        output integer pass;
        integer byte_i;
        integer ack_ok;
        reg[7:0] ack;
        begin
            pass = 1;
            $display("send packet index %0d", pkt_index);

            // Start listening for ACK while the last byte is being transmitted, so
            // the TB does not miss the ACK start bit.
            for (byte_i = 0; byte_i < 34; byte_i = byte_i + 1) begin
                uart_send_byte(packet[byte_i]);
                repeat (1000) @(posedge clk);
            end
            fork
                begin
                    uart_send_byte(packet[34]);
                end
                begin
                    uart_recv_byte_timeout(ack, ack_ok);
                end
            join

            if (ack_ok == 0) begin
                pass = 0;
                $display("ACK timeout at packet index %0d", pkt_index);
            end else if (ack != 8'h06) begin
                pass = 0;
                $display("Bad ACK at packet index %0d: expected 0x06, received 0x%02x", pkt_index, ack);
            end else begin
                $display("ACK packet index %0d", pkt_index);
            end
        end
    endtask

    task load_firmware_data;
        integer fd;
        integer scan_ok;
        reg[31:0] word_data;
        begin
            fw_word_count = 0;
            fw_size_bytes = 0;
            packet_num = 0;
            for (i = 0; i < 256; i = i + 1) begin
                fw_words[i] = 32'h00000013;
            end
            for (i = 0; i < 1024; i = i + 1) begin
                fw_bytes[i] = 8'h00;
            end

            fd = $fopen(fw_file, "r");
            if (fd == 0) begin
                fail_and_finish("Cannot open FW_DATA file.");
            end

            scan_ok = $fscanf(fd, "%h\n", word_data);
            while (scan_ok == 1) begin
                if (fw_word_count >= 256) begin
                    $fclose(fd);
                    fail_and_finish("FW_DATA is larger than 256 words.");
                end
                fw_words[fw_word_count] = word_data;
                fw_bytes[fw_word_count * 4 + 0] = word_data[7:0];
                fw_bytes[fw_word_count * 4 + 1] = word_data[15:8];
                fw_bytes[fw_word_count * 4 + 2] = word_data[23:16];
                fw_bytes[fw_word_count * 4 + 3] = word_data[31:24];
                fw_word_count = fw_word_count + 1;
                scan_ok = $fscanf(fd, "%h\n", word_data);
            end
            $fclose(fd);

            if (fw_word_count == 0) begin
                fail_and_finish("FW_DATA contains no words.");
            end

            fw_size_bytes = fw_word_count * 4;
            packet_num = (fw_size_bytes + 31) / 32;

            $display("FW file path: %0s", fw_file);
            $display("FW size in bytes: %0d", fw_size_bytes);
            $display("total data packets: %0d", packet_num);
        end
    endtask

    task run_download;
        integer pkt_pass;
        integer ready_wait;
        begin
            download_pass = 1;

            ready_wait = 0;
            while (!((tinyriscv_soc_top_0.u_uart_debug.state == 5'd6 ||
                      tinyriscv_soc_top_0.u_uart_debug.state == 5'd7) &&
                     tinyriscv_soc_top_0.u_uart_debug.rx_index == 6'd0) &&
                   ready_wait < ACK_TIMEOUT_CYCLES) begin
                @(posedge clk);
                ready_wait = ready_wait + 1;
            end
            if (ready_wait >= ACK_TIMEOUT_CYCLES) begin
                fail_and_finish("Timeout waiting for uart_debug first-packet receive state.");
            end
            repeat (100) @(posedge clk);

            build_first_packet();
            send_packet_and_check_ack(0, pkt_pass);
            if (pkt_pass == 0) begin
                download_pass = 0;
                fail_and_finish("First packet ACK failed.");
            end

            for (packet_index = 1; packet_index <= packet_num; packet_index = packet_index + 1) begin
                build_data_packet(packet_index);
                send_packet_and_check_ack(packet_index, pkt_pass);
                if (pkt_pass == 0) begin
                    download_pass = 0;
                    fail_and_finish("Data packet ACK failed.");
                end
            end

            $display("UART DOWNLOAD PASS: all packets ACKed");
        end
    endtask

    task check_rom_content;
        begin
            for (i = 0; i < fw_word_count; i = i + 1) begin
                if (fpga_mem_bridge_0.rom[i] !== fw_words[i]) begin
                    $display("ROM MISMATCH at word[%0d]: rom=0x%08x expected=0x%08x", i, fpga_mem_bridge_0.rom[i], fw_words[i]);
                    fail_and_finish("Downloaded ROM content mismatch.");
                end
            end
            $display("ROM CHECK PASS: downloaded ROM matches FW_DATA.");
        end
    endtask

    // -------------------------------------------------------------------------
    // PWM checking logic copied from tinyriscv_soc_pwm_tb.v.
    // The check sequence after pwm_test_start is intentionally kept unchanged.
    // -------------------------------------------------------------------------
    function pwm_sample;
        input integer ch;
        begin
            case (ch)
                0: pwm_sample = pwm_o[0];
                1: pwm_sample = pwm_o[1];
                2: pwm_sample = pwm_o[2];
                3: pwm_sample = pwm_o[3];
                default: pwm_sample = 1'b0;
            endcase
        end
    endfunction

    task print_pwm_regs;
        begin
            $display("PWM regs:");
            $display("  period[0]    = %0d", tinyriscv_soc_top_0.u_pwm.period[0]);
            $display("  high_time[0] = %0d", tinyriscv_soc_top_0.u_pwm.high_time[0]);
            $display("  period[1]    = %0d", tinyriscv_soc_top_0.u_pwm.period[1]);
            $display("  high_time[1] = %0d", tinyriscv_soc_top_0.u_pwm.high_time[1]);
            $display("  period[2]    = %0d", tinyriscv_soc_top_0.u_pwm.period[2]);
            $display("  high_time[2] = %0d", tinyriscv_soc_top_0.u_pwm.high_time[2]);
            $display("  period[3]    = %0d", tinyriscv_soc_top_0.u_pwm.period[3]);
            $display("  high_time[3] = %0d", tinyriscv_soc_top_0.u_pwm.high_time[3]);
            $display("  enable       = 0x%0h", tinyriscv_soc_top_0.u_pwm.enable);
        end
    endtask

    task check_pwm_reg;
        input integer ch;
        input integer expected_period;
        input integer expected_high;
        output integer pass;
        begin
            pass = 1;
            case (ch)
                0: begin
                    if (tinyriscv_soc_top_0.u_pwm.period[0] !== expected_period) pass = 0;
                    if (tinyriscv_soc_top_0.u_pwm.high_time[0] !== expected_high) pass = 0;
                end
                1: begin
                    if (tinyriscv_soc_top_0.u_pwm.period[1] !== expected_period) pass = 0;
                    if (tinyriscv_soc_top_0.u_pwm.high_time[1] !== expected_high) pass = 0;
                end
                2: begin
                    if (tinyriscv_soc_top_0.u_pwm.period[2] !== expected_period) pass = 0;
                    if (tinyriscv_soc_top_0.u_pwm.high_time[2] !== expected_high) pass = 0;
                end
                3: begin
                    if (tinyriscv_soc_top_0.u_pwm.period[3] !== expected_period) pass = 0;
                    if (tinyriscv_soc_top_0.u_pwm.high_time[3] !== expected_high) pass = 0;
                end
                default: pass = 0;
            endcase

            if (pass == 0) begin
                $display("PWM channel %0d register mismatch: expected period=%0d high=%0d", ch, expected_period, expected_high);
            end
        end
    endtask

    task check_pwm_channel;
        input integer ch;
        input integer expected_period;
        input integer expected_high;
        output integer pass;
        reg prev;
        reg cur;
        integer guard;
        integer found_rise;
        integer period_count;
        integer high_count;
        begin
            pass = 0;
            prev = pwm_sample(ch);
            found_rise = 0;

            for (guard = 0; guard < 1000 && found_rise == 0; guard = guard + 1) begin
                @(posedge clk);
                #1;
                cur = pwm_sample(ch);
                if (prev == 1'b0 && cur == 1'b1) begin
                    found_rise = 1;
                end
                prev = cur;
            end

            if (found_rise == 0) begin
                $display("PWM channel %0d failed: no rising edge observed", ch);
                $display("  expected period=%0d high=%0d, measured period=timeout high=timeout", expected_period, expected_high);
            end else begin
                period_count = 0;
                high_count = 0;
                found_rise = 0;
                prev = 1'b1;

                for (guard = 0; guard < 1000 && found_rise == 0; guard = guard + 1) begin
                    @(posedge clk);
                    #1;
                    cur = pwm_sample(ch);
                    period_count = period_count + 1;
                    if (cur == 1'b1) begin
                        high_count = high_count + 1;
                    end
                    if (prev == 1'b0 && cur == 1'b1) begin
                        found_rise = 1;
                    end
                    prev = cur;
                end

                if (found_rise == 0) begin
                    $display("PWM channel %0d failed: second rising edge timeout", ch);
                    $display("  expected period=%0d high=%0d, measured period=%0d high=%0d", expected_period, expected_high, period_count, high_count);
                end else if (((period_count >= expected_period - 1) && (period_count <= expected_period + 1)) &&
                             ((high_count >= expected_high - 1) && (high_count <= expected_high + 1))) begin
                    pass = 1;
                    $display("PWM channel %0d ok: expected period=%0d high=%0d, measured period=%0d high=%0d", ch, expected_period, expected_high, period_count, high_count);
                end else begin
                    $display("PWM channel %0d failed: expected period=%0d high=%0d, measured period=%0d high=%0d", ch, expected_period, expected_high, period_count, high_count);
                end
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = `RstEnable;
        uart_rx_pin = 1'b1;
        uart_debug_pin = 1'b0;
        jtag_TCK = 1'b0;
        jtag_TMS = 1'b1;
        jtag_TDI = 1'b0;
        download_pass = 0;
        pwm_test_start = 1'b0;

        if (!$value$plusargs("FW_DATA=%s", fw_file)) begin
            fw_file = "E://learn/thu/digital_work/tinyriscv_2026/inst/Other_Example/PWM/PWM_inst_fast.data";
        end

        $display("UART download PWM test running...");
        load_firmware_data();

        #200;
        rst = `RstDisable;
        repeat (200) @(posedge clk);
        uart_debug_pin = 1'b1;
        repeat (200) @(posedge clk);

        run_download();
        uart_debug_pin = 1'b0;
        check_rom_content();

        repeat (20) @(posedge clk);
        rst = `RstEnable;
        repeat (20) @(posedge clk);
        rst = `RstDisable;
        pwm_test_start = 1'b1;
    end

    initial begin
        wait(pwm_test_start == 1'b1);

        pwm_pass = 1;
        ch0_pass = 0;
        ch1_pass = 0;
        ch2_pass = 0;
        ch3_pass = 0;

        wait(rst == `RstDisable);

        wait_cycles = 0;
        while (tinyriscv_soc_top_0.u_pwm.enable !== 4'hF && wait_cycles < 50000) begin
            @(posedge clk);
            wait_cycles = wait_cycles + 1;
        end

        if (tinyriscv_soc_top_0.u_pwm.enable !== 4'hF) begin
            $display("~~~~~~~~~~~~~~~~~~~ PWM TEST_FAIL ~~~~~~~~~~~~~~~~~~~");
            $display("Timeout waiting for PWM enable == 4'hF.");
            print_pwm_regs();
            $finish;
        end

        repeat (20) @(posedge clk);

        check_pwm_reg(0, 100, 50, ch0_pass);
        if (ch0_pass == 0) pwm_pass = 0;
        check_pwm_reg(1, 80, 40, ch1_pass);
        if (ch1_pass == 0) pwm_pass = 0;
        check_pwm_reg(2, 40, 20, ch2_pass);
        if (ch2_pass == 0) pwm_pass = 0;
        check_pwm_reg(3, 20, 10, ch3_pass);
        if (ch3_pass == 0) pwm_pass = 0;

        if (tinyriscv_soc_top_0.u_pwm.enable !== 4'hF) begin
            pwm_pass = 0;
            $display("PWM enable mismatch: expected 0xF, actual 0x%0h", tinyriscv_soc_top_0.u_pwm.enable);
        end

        check_pwm_channel(0, 100, 50, ch0_pass);
        if (ch0_pass == 0) pwm_pass = 0;
        check_pwm_channel(1, 80, 40, ch1_pass);
        if (ch1_pass == 0) pwm_pass = 0;
        check_pwm_channel(2, 40, 20, ch2_pass);
        if (ch2_pass == 0) pwm_pass = 0;
        check_pwm_channel(3, 20, 10, ch3_pass);
        if (ch3_pass == 0) pwm_pass = 0;

        if (pwm_pass == 1) begin
            $display("~~~~~~~~~~~~~~~~~~~ UART DOWNLOAD PWM TEST_PASS ~~~~~~~~~~~~~~~~~~~");
            $display("~~~~~~~~~~~~~~~~~~~ PWM TEST_PASS ~~~~~~~~~~~~~~~~~~~");
        end else begin
            $display("~~~~~~~~~~~~~~~~~~~ UART DOWNLOAD PWM TEST_FAIL ~~~~~~~~~~~~~~~~~~~");
            $display("~~~~~~~~~~~~~~~~~~~ PWM TEST_FAIL ~~~~~~~~~~~~~~~~~~~");
            print_pwm_regs();
        end

        $finish;
    end

    initial begin
        wait(pwm_test_start == 1'b1);
        #2000000
        $display("~~~~~~~~~~~~~~~~~~~ UART DOWNLOAD PWM TEST_FAIL ~~~~~~~~~~~~~~~~~~~");
        $display("~~~~~~~~~~~~~~~~~~~ PWM TEST_FAIL ~~~~~~~~~~~~~~~~~~~");
        $display("Time Out.");
        print_pwm_regs();
        $finish;
    end

    // VCD can be very large. Enable only when needed.
    // initial begin
    //     $dumpfile("tinyriscv_soc_uart_download_pwm_tb.vcd");
    //     $dumpvars(0, tinyriscv_soc_uart_download_pwm_tb);
    // end

    tinyriscv_soc_top tinyriscv_soc_top_0(
        .clk(clk),
        .rst(rst),
        .chip_sel_i(chip_sel_i),
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
