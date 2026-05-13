`timescale 1 ns / 1 ps

`include "defines.v"

// Select exactly one extension test.
// You can also override the downloaded program with +FW_DATA=path/to/file.data.
// `define TEST_EXT_IF 1
// `define TEST_EXT_sID 1
`define TEST_EXT_Temp 1

// UART-download based extension instruction testbench.
// Flow:
//   1) TB emulates inst/tinyriscv_fw_downloader.py and downloads the selected
//      .data file through uart_debug_pin + uart_rx_pin.
//   2) DUT uart_debug writes the program into fpga_mem_bridge.rom.
//   3) TB resets the core and checks the selected extension program result.
module tinyriscv_soc_uart_download_ext_tb;

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
    localparam integer EXT_TIMEOUT_CYCLES = 20000000;

    reg[31:0] fw_words [0:255];
    reg[7:0]  fw_bytes [0:1023];
    reg[7:0]  packet   [0:34];

    integer fw_word_count;
    integer fw_size_bytes;
    integer packet_num;
    integer packet_index;
    integer download_pass;
    integer ext_pass;
    integer i;

`ifdef TEST_EXT_sID
    reg[7:0] expected_id [0:9];
    reg[7:0] sid_recv_data [0:9];
    integer sid_i;
    integer sid_pass;
`endif

`ifdef TEST_EXT_Temp
    reg lm75_sda_drive_low;
    reg[7:0] lm75_addr_rw;
    reg lm75_master_ack;
    integer lm75_transactions;
    assign i2c_sda = lm75_sda_drive_low ? 1'b0 : 1'bz;
`endif

    assign chip_sel_i = 1'b1;

    always #10 clk = ~clk;  // 50MHz

    task fail_and_finish;
        input [1023:0] reason;
        begin
            $display("~~~~~~~~~~~~~~~~~~~ UART DOWNLOAD EXT TEST_FAIL ~~~~~~~~~~~~~~~~~~~");
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
        begin
            data = 8'h00;
            ok = 0;
            timeout_i = 0;

            while (uart_tx_pin !== 1'b0 && timeout_i < ACK_TIMEOUT_CYCLES) begin
                @(posedge clk);
                timeout_i = timeout_i + 1;
            end

            if (uart_tx_pin === 1'b0) begin
                ok = 1;
                #(UART_BIT_PERIOD_NS + UART_BIT_PERIOD_NS / 2);
                for (bit_i = 0; bit_i < 8; bit_i = bit_i + 1) begin
                    data[bit_i] = uart_tx_pin;
                    #(UART_BIT_PERIOD_NS);
                end
                if (uart_tx_pin !== 1'b1) begin
                    $display("UART STOP BIT ERROR: stop bit = %b", uart_tx_pin);
                end
                #(UART_BIT_PERIOD_NS);
            end
        end
    endtask

    task uart_recv_byte_clean;
        output [7:0] data;
        integer bit_i;
        begin
            data = 8'h00;

            // 必须等待真正的 start bit 下降沿
            @(negedge uart_tx_pin);

            // 到 bit0 中心采样
            #(UART_BIT_PERIOD_NS + UART_BIT_PERIOD_NS / 2);

            for (bit_i = 0; bit_i < 8; bit_i = bit_i + 1) begin
                data[bit_i] = uart_tx_pin;
                #(UART_BIT_PERIOD_NS);
            end

            // 此时位于 stop bit 中心
            if (uart_tx_pin !== 1'b1) begin
                $display("UART STOP BIT ERROR: stop bit = %b", uart_tx_pin);
            end

            // 关键：这里不要再额外等待一个完整 bit
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
            // $display("send packet index %0d", pkt_index);
            // for (byte_i = 0; byte_i < 35; byte_i = byte_i + 1) begin
            //     uart_send_byte(packet[byte_i]);
            //     repeat (1000) @(posedge clk);
            // end
            for (byte_i = 0; byte_i < 34; byte_i = byte_i + 1) begin
                uart_send_byte(packet[byte_i]);
                repeat (1000) @(posedge clk);
            end
            uart_send_byte(packet[34]);
            uart_recv_byte_timeout(ack, ack_ok);
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
                if (u_fpga_mem_bridge.rom[i] !== fw_words[i]) begin
                    $display("ROM MISMATCH at word[%0d]: rom=0x%08x expected=0x%08x", i, u_fpga_mem_bridge.rom[i], fw_words[i]);
                    fail_and_finish("Downloaded ROM content mismatch.");
                end
            end
            $display("ROM CHECK PASS: downloaded ROM matches FW_DATA.");
        end
    endtask

    task check_if_result;
        integer ok;
        reg[7:0] data;
        begin
            ext_pass = 0;
            $display("start IF extension check");
            uart_recv_byte_timeout(data, ok);
            if (ok && data == 8'h8A) begin
                ext_pass = 1;
                $display("~~~~~~~~~~~~~~~~~~~ UART DOWNLOAD IF TEST_PASS ~~~~~~~~~~~~~~~~~~~");
                $display("UART output = 0x%02x, expected = 0x8A", data);
            end else begin
                $display("~~~~~~~~~~~~~~~~~~~ UART DOWNLOAD IF TEST_FAIL ~~~~~~~~~~~~~~~~~~~");
                if (ok) begin
                    $display("UART output = 0x%02x, expected = 0x8A", data);
                end else begin
                    $display("No UART byte received from uart_tx_pin.");
                end
            end
        end
    endtask

`ifdef TEST_EXT_sID
    task check_sid_result;
        integer ok;
        begin
            ext_pass = 0;
            sid_pass = 1;
            expected_id[0] = 8'h32; // '2'
            expected_id[1] = 8'h30; // '0'
            expected_id[2] = 8'h32; // '2'
            expected_id[3] = 8'h35; // '5'
            expected_id[4] = 8'h32; // '2'
            expected_id[5] = 8'h31; // '1'
            expected_id[6] = 8'h30; // '0'
            expected_id[7] = 8'h39; // '9'
            expected_id[8] = 8'h31; // '1'
            expected_id[9] = 8'h31; // '1'

            $display("start sID extension check");
            // for (sid_i = 0; sid_i < 10; sid_i = sid_i + 1) begin
            //     uart_recv_byte_timeout(sid_recv_data[sid_i], ok);
            //     if (!ok) begin
            //         sid_pass = 0;
            //         $display("sID timeout at byte index %0d", sid_i);
                // end else if (sid_recv_data[sid_i] !== expected_id[sid_i]) begin
                //     sid_pass = 0;
                // end
            // end

            for (sid_i = 0; sid_i < 10; sid_i = sid_i + 1) begin
                uart_recv_byte_clean(sid_recv_data[sid_i]);
            end

            for (sid_i = 0; sid_i < 10; sid_i = sid_i + 1) begin
                if (sid_recv_data[sid_i] !== expected_id[sid_i]) begin
                    sid_pass = 0;
                end
            end
            if (sid_pass) begin
                ext_pass = 1;
                $display("~~~~~~~~~~~~~~~~~~~ UART DOWNLOAD sID TEST_PASS ~~~~~~~~~~~~~~~~~~~");
            end else begin
                $display("~~~~~~~~~~~~~~~~~~~ UART DOWNLOAD sID TEST_FAIL ~~~~~~~~~~~~~~~~~~~");
                for (sid_i = 0; sid_i < 10; sid_i = sid_i + 1) begin
                    $display("byte index %0d: received = 0x%02x, expected = 0x%02x", sid_i, sid_recv_data[sid_i], expected_id[sid_i]);
                end
            end
        end
    endtask
`endif

`ifdef TEST_EXT_Temp
    task i2c_wait_start;
        while (!(i2c_scl === 1'b1 && i2c_sda === 1'b0)) begin
            @(negedge i2c_sda);
        end
    endtask

    task i2c_read_byte_from_master;
        output [7:0] data;
        integer bit_i;
        begin
            data = 8'h00;
            for (bit_i = 7; bit_i >= 0; bit_i = bit_i - 1) begin
                @(posedge i2c_scl);
                data[bit_i] = i2c_sda;
                @(negedge i2c_scl);
            end
        end
    endtask

    task i2c_send_ack;
        begin
            @(negedge i2c_scl);
            lm75_sda_drive_low = 1'b1;
            @(posedge i2c_scl);
            @(negedge i2c_scl);
            lm75_sda_drive_low = 1'b0;
        end
    endtask

    task i2c_send_byte_to_master;
        input [7:0] data;
        output master_ack;
        integer bit_i;
        begin
            for (bit_i = 7; bit_i >= 0; bit_i = bit_i - 1) begin
                lm75_sda_drive_low = (data[bit_i] == 1'b0) ? 1'b1 : 1'b0;
                @(posedge i2c_scl);
                @(negedge i2c_scl);
            end
            lm75_sda_drive_low = 1'b0;
            @(posedge i2c_scl);
            master_ack = (i2c_sda == 1'b0);
            @(negedge i2c_scl);
        end
    endtask

    initial begin
        lm75_sda_drive_low = 1'b0;
        lm75_transactions = 0;
        forever begin
            i2c_wait_start();
            i2c_read_byte_from_master(lm75_addr_rw);
            if (lm75_addr_rw[7:1] == 7'h48 && lm75_addr_rw[0] == 1'b1) begin
                lm75_transactions = lm75_transactions + 1;
                i2c_send_ack();
                i2c_send_byte_to_master(8'h00, lm75_master_ack);
                i2c_send_byte_to_master(8'h80, lm75_master_ack);
                lm75_sda_drive_low = 1'b0;
            end else begin
                i2c_send_ack();
                lm75_sda_drive_low = 1'b0;
            end
        end
    end

    task check_temp_result;
        integer ok;
        reg[7:0] data;
        begin
            ext_pass = 0;
            $display("start Temp/rT extension check");
            uart_recv_byte_timeout(data, ok);
            if (ok && data == 8'h01) begin
                ext_pass = 1;
                $display("~~~~~~~~~~~~~~~~~~~ UART DOWNLOAD Temp TEST_PASS ~~~~~~~~~~~~~~~~~~~");
                $display("UART output = 0x%02x, expected = 0x01", data);
            end else begin
                $display("~~~~~~~~~~~~~~~~~~~ UART DOWNLOAD Temp TEST_FAIL ~~~~~~~~~~~~~~~~~~~");
                if (ok) begin
                    $display("UART output = 0x%02x, expected = 0x01", data);
                end else begin
                    $display("No UART byte received from uart_tx_pin.");
                end
            end
        end
    endtask
`endif

    initial begin
        clk = 1'b0;
        rst = `RstEnable;
        uart_rx_pin = 1'b1;
        uart_debug_pin = 1'b0;
        jtag_TCK = 1'b0;
        jtag_TMS = 1'b1;
        jtag_TDI = 1'b0;
        download_pass = 0;
        ext_pass = 0;

        if (!$value$plusargs("FW_DATA=%s", fw_file)) begin
`ifdef TEST_EXT_IF
            fw_file = "E://learn/thu/digital_work/tinyriscv_2026/inst/Extend_Inst_Example/IF/IF_inst.data";
`elsif TEST_EXT_sID
            fw_file = "E://learn/thu/digital_work/tinyriscv_2026/inst/Extend_Inst_Example/sID/sID_inst.data";
`elsif TEST_EXT_Temp
            fw_file = "E://learn/thu/digital_work/tinyriscv_2026/inst/Extend_Inst_Example/Temp/Temp.data";
`else
            fw_file = "E://learn/thu/digital_work/tinyriscv_2026/inst/Extend_Inst_Example/IF/IF_inst.data";
`endif
        end

        $display("UART download extension test running...");
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
        repeat (100) @(posedge clk);

`ifdef TEST_EXT_IF
        check_if_result();
`elsif TEST_EXT_sID
        check_sid_result();
`elsif TEST_EXT_Temp
        check_temp_result();
`else
        fail_and_finish("No extension test macro selected.");
`endif

        if (download_pass == 1 && ext_pass == 1) begin
            $display("~~~~~~~~~~~~~~~~~~~ UART DOWNLOAD EXT TEST_PASS ~~~~~~~~~~~~~~~~~~~");
        end else begin
            $display("~~~~~~~~~~~~~~~~~~~ UART DOWNLOAD EXT TEST_FAIL ~~~~~~~~~~~~~~~~~~~");
        end
        $finish;
    end

    initial begin
        #3000000000;
        $display("~~~~~~~~~~~~~~~~~~~ UART DOWNLOAD EXT TEST_FAIL ~~~~~~~~~~~~~~~~~~~");
        $display("Global timeout.");
        $finish;
    end

    // Enable this only when needed. VCD files can be very large.
    // initial begin
    //     $dumpfile("tinyriscv_soc_uart_download_ext_tb.vcd");
    //     $dumpvars(0, tinyriscv_soc_uart_download_ext_tb);
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
    ) u_fpga_mem_bridge (
        .clk(clk),
        .rst(rst),
        .chip_data_i(fpga_data_o),
        .chip_data_o(fpga_data_i)
    );

endmodule
