`timescale 1 ns / 1 ps

`include "defines.v"

// Verify UART firmware download path:
// uart_debug_pin -> uart_debug -> RIB -> chip_mem_bridge -> fpga_mem_bridge.rom
module tinyriscv_soc_uart_download_tb;

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

    // localparam integer UART_RX_BIT_PERIOD_NS = 8820;
    localparam integer UART_RX_BIT_PERIOD_NS = 8680;
    localparam integer UART_TX_BIT_CLKS = 441;
    localparam integer ACK_TIMEOUT_CYCLES = 2000000;
    localparam integer BASIC_TIMEOUT_CYCLES = 5000000;

    reg[31:0] fw_words [0:255];
    reg[7:0] fw_bytes [0:1023];
    reg[7:0] packet [0:34];

    integer fw_word_count;
    integer fw_size_bytes;
    integer packet_num;
    integer packet_index;
    integer download_pass;
    integer basic_pass;
    integer i;
    integer r;

    wire[`RegBus] x3 = tinyriscv_soc_top_0.u_tinyriscv.u_regs.regs[3];
    wire[`RegBus] x26 = tinyriscv_soc_top_0.u_tinyriscv.u_regs.regs[26];
    wire[`RegBus] x27 = tinyriscv_soc_top_0.u_tinyriscv.u_regs.regs[27];

    assign chip_sel_i = 1'b1;

    always #10 clk = ~clk;     // 50MHz

    task fail_and_finish;
        input [1023:0] reason;
        begin
            $display("~~~~~~~~~~~~~~~~~~~ UART DOWNLOAD BASIC TEST_FAIL ~~~~~~~~~~~~~~~~~~~");
            $display("%0s", reason);
            $finish;
        end
    endtask

    task uart_send_byte;
        input [7:0] data;
        integer bit_i;
        begin
            @(negedge clk);
            uart_rx_pin = 1'b0;
            repeat (UART_TX_BIT_CLKS) @(posedge clk);
            for (bit_i = 0; bit_i < 8; bit_i = bit_i + 1) begin
                @(negedge clk);
                uart_rx_pin = data[bit_i];
                repeat (UART_TX_BIT_CLKS) @(posedge clk);
            end
            @(negedge clk);
            uart_rx_pin = 1'b1;
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
                #(UART_RX_BIT_PERIOD_NS + UART_RX_BIT_PERIOD_NS / 2);
                for (bit_i = 0; bit_i < 8; bit_i = bit_i + 1) begin
                    data[bit_i] = uart_tx_pin;
                    #(UART_RX_BIT_PERIOD_NS);
                end
                #(UART_RX_BIT_PERIOD_NS);
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

    task send_packet_and_check_ack;
        input integer pkt_index;
        output integer pass;
        integer byte_i;
        integer start_byte;
        integer ack_ok;
        reg[7:0] ack;
        begin
            pass = 1;
            $display("send packet index %0d", pkt_index);
            start_byte = 0;
            // if (tinyriscv_soc_top_0.u_uart_debug.rx_index == 6'd1 &&
            //     tinyriscv_soc_top_0.u_uart_debug.rx_data[0] == pkt_index[7:0]) begin
            //     start_byte = 1;
            //     $display("packet index %0d: header byte already captured by DUT, send byte1..byte34", pkt_index);
            // end
            for (byte_i = start_byte; byte_i < 34; byte_i = byte_i + 1) begin
                uart_send_byte(packet[byte_i]);
                repeat (1000) @(posedge clk);
            end
            uart_send_byte(packet[34]);
            uart_recv_byte_timeout(ack, ack_ok);

            // fork
            //     begin
            //         uart_send_byte(packet[34]);
            //     end
            //     begin
            //         uart_recv_byte_timeout(ack, ack_ok);
            //     end
            // join

            if (ack_ok == 0) begin
                pass = 0;
                $display("ACK timeout at packet index %0d", pkt_index);
                $display("uart_debug state=%0d rx_index=%0d packet_type=%0d response_type=%0d remain_packet_count=%0d",
                         tinyriscv_soc_top_0.u_uart_debug.state,
                         tinyriscv_soc_top_0.u_uart_debug.rx_index,
                         tinyriscv_soc_top_0.u_uart_debug.packet_type,
                         tinyriscv_soc_top_0.u_uart_debug.response_type,
                         tinyriscv_soc_top_0.u_uart_debug.remain_packet_count);
                $display("uart status=0x%08x rx=0x%08x crc16=0x%04x expect=0x%02x%02x",
                         tinyriscv_soc_top_0.u_uart_0.uart_status,
                         tinyriscv_soc_top_0.u_uart_0.uart_rx,
                         tinyriscv_soc_top_0.u_uart_debug.crc16,
                         tinyriscv_soc_top_0.u_uart_debug.rx_data[34],
                         tinyriscv_soc_top_0.u_uart_debug.rx_data[33]);
                $display("rx_data[0..4]=%02x %02x %02x %02x %02x",
                         tinyriscv_soc_top_0.u_uart_debug.rx_data[0],
                         tinyriscv_soc_top_0.u_uart_debug.rx_data[1],
                         tinyriscv_soc_top_0.u_uart_debug.rx_data[2],
                         tinyriscv_soc_top_0.u_uart_debug.rx_data[3],
                         tinyriscv_soc_top_0.u_uart_debug.rx_data[4]);
                $display("uart tx_state=%0d tx_reg=%0d tx_data=0x%02x tx_valid=%0d tx_ready=%0d uart_tx_pin=%0d",
                         tinyriscv_soc_top_0.u_uart_0.tx_state,
                         tinyriscv_soc_top_0.u_uart_0.tx_reg,
                         tinyriscv_soc_top_0.u_uart_0.tx_data,
                         tinyriscv_soc_top_0.u_uart_0.tx_data_valid,
                         tinyriscv_soc_top_0.u_uart_0.tx_data_ready,
                         uart_tx_pin);
                $display("uart_ctrl=0x%08x s1_we=%0d s1_addr=0x%08x s1_data=0x%08x m3_addr=0x%08x m3_we=%0d",
                         tinyriscv_soc_top_0.u_uart_0.uart_ctrl,
                         tinyriscv_soc_top_0.s1_we_o,
                         tinyriscv_soc_top_0.s1_addr_o,
                         tinyriscv_soc_top_0.s1_data_o,
                         tinyriscv_soc_top_0.m3_addr_i,
                         tinyriscv_soc_top_0.m3_we_i);
            end else if (ack != 8'h06) begin
                pass = 0;
                $display("Bad ACK at packet index %0d: expected 0x06, received 0x%02x",
                         pkt_index, ack);
            end else begin
                $display("ACK packet index %0d", pkt_index);
            end
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
            $display("total packets: %0d", packet_num);
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
                     (tinyriscv_soc_top_0.u_uart_debug.rx_index == 6'd0 ||
                      (tinyriscv_soc_top_0.u_uart_debug.rx_index == 6'd1 &&
                       tinyriscv_soc_top_0.u_uart_debug.rx_data[0] == 8'h00))) &&
                   ready_wait < ACK_TIMEOUT_CYCLES) begin
                @(posedge clk);
                ready_wait = ready_wait + 1;
            end
            if (ready_wait >= ACK_TIMEOUT_CYCLES) begin
                $display("uart_debug not ready: state=%0d rx_index=%0d debug_pin=%0d req=%0d",
                         tinyriscv_soc_top_0.u_uart_debug.state,
                         tinyriscv_soc_top_0.u_uart_debug.rx_index,
                         uart_debug_pin,
                         tinyriscv_soc_top_0.m3_req_i);
                $display("pre-download rx_data[0]=0x%02x uart_status=0x%08x uart_rx=0x%08x",
                         tinyriscv_soc_top_0.u_uart_debug.rx_data[0],
                         tinyriscv_soc_top_0.u_uart_0.uart_status,
                         tinyriscv_soc_top_0.u_uart_0.uart_rx);
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

    task check_basic_program;
        integer timeout_i;
        begin
            basic_pass = 0;
            timeout_i = 0;
            $display("start basic program check");

            // 先等 x26 变成 0，说明新程序已经开始执行初始化
            while (x26 !== 32'd0 && timeout_i < BASIC_TIMEOUT_CYCLES) begin
                @(posedge clk);
                timeout_i = timeout_i + 1;
            end

            // 再等 x26 变成 1，说明新程序跑完
            while (x26 !== 32'd1 && timeout_i < BASIC_TIMEOUT_CYCLES) begin
                @(posedge clk);
                timeout_i = timeout_i + 1;
            end

            // while (x26 !== 32'b1 && timeout_i < BASIC_TIMEOUT_CYCLES) begin
            //     @(posedge clk);
            //     timeout_i = timeout_i + 1;
            // end

            if (x26 !== 32'b1) begin
                $display("Basic program timeout waiting for x26 == 1.");
                $display("x26 = 0x%x, x27 = 0x%x", x26, x27);
                fail_and_finish("Basic program run timeout.");
            end

            #1000;
            if (x27 == 32'b1) begin
                basic_pass = 1;
                $display("Basic program PASS: x26=0x%x, x27=0x%x", x26, x27);
            end else begin
                $display("Basic program FAIL: x26=0x%x, x27=0x%x", x26, x27);
                $display("fail testnum = %2d", x3);
                for (r = 0; r < 32; r = r + 1) begin
                    $display("x%2d = 0x%x", r, tinyriscv_soc_top_0.u_tinyriscv.u_regs.regs[r]);
                end
                fail_and_finish("Basic program x27 indicates failure.");
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
        basic_pass = 0;

        if (!$value$plusargs("FW_DATA=%s", fw_file)) begin
            fw_file = "E://learn/thu/digital_work/tinyriscv_2026/inst/Baisc_Inst_Example/inst_xori.data";
        end

        $display("UART download basic test running...");
        load_firmware_data();

        #200;
        rst = `RstDisable;
        repeat (200) @(posedge clk);
        uart_debug_pin = 1'b1;
        repeat (200) @(posedge clk);

        run_download();

        uart_debug_pin = 1'b0;

        $display("ROM CHECK PASS: downloaded ROM matches FW_DATA.");
        
        repeat (20) @(posedge clk);
        rst = `RstEnable;
        repeat (20) @(posedge clk);
        rst = `RstDisable;
        repeat (20) @(posedge clk);

        for (i = 0; i < fw_word_count; i = i + 1) begin
            if (u_fpga_mem_bridge.rom[i] !== fw_words[i]) begin
                $display("ROM MISMATCH at word[%0d]: rom=0x%08x expected=0x%08x",
                        i, u_fpga_mem_bridge.rom[i], fw_words[i]);
                fail_and_finish("Downloaded ROM content mismatch.");
            end
        end

        $display("ROM CHECK PASS: downloaded ROM matches FW_DATA.");

        check_basic_program();

        if (download_pass == 1 && basic_pass == 1) begin
            $display("~~~~~~~~~~~~~~~~~~~ UART DOWNLOAD BASIC TEST_PASS ~~~~~~~~~~~~~~~~~~~");
        end else begin
            $display("~~~~~~~~~~~~~~~~~~~ UART DOWNLOAD BASIC TEST_FAIL ~~~~~~~~~~~~~~~~~~~");
        end

        $finish;
    end

    initial begin
        #2000000000;
        $display("~~~~~~~~~~~~~~~~~~~ UART DOWNLOAD BASIC TEST_FAIL ~~~~~~~~~~~~~~~~~~~");
        $display("Global timeout.");
        $finish;
    end

    // initial begin
    //     $dumpfile("tinyriscv_soc_uart_download_tb.vcd");
    //     $dumpvars(0, tinyriscv_soc_uart_download_tb);
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
