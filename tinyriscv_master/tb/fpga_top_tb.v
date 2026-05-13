`timescale 1 ns / 1 ps

`include "defines.v"

// FPGA top-level PWM validation testbench.
// This testbench keeps the PWM checking behavior/timing from tinyriscv_soc_pwm_tb.v
// while instantiating fpga_top instead of tinyriscv_soc_top + fpga_mem_bridge directly.
module fpga_top_tb;

    reg clk;
    reg rst;

    wire succ;
    wire uart_tx_pin;
    wire[2:0] PWM_o;
    wire io_scl;
    tri1 io_sda;

    wire uart_rx_pin;
    reg uart_debug_pin;

    reg[1023:0] inst_file;

    integer pwm_pass;
    integer wait_cycles;
    integer ch0_pass;
    integer ch1_pass;
    integer ch2_pass;
    integer ch3_pass;

    assign uart_rx_pin = 1'b1;  // UART idle level

    always #10 clk = ~clk;     // 50MHz

    // Keep exactly the same 4-channel PWM observation model as tinyriscv_soc_pwm_tb.v.
    // fpga_top only exports PWM_o[2:0], so channel 3 is observed from the internal
    // fpga_top.pwm_o[3] net to avoid changing the original PWM test semantics.
    function pwm_sample;
        input integer ch;
        begin
            case (ch)
                0: pwm_sample = fpga_top_0.pwm_o[0];
                1: pwm_sample = fpga_top_0.pwm_o[1];
                2: pwm_sample = fpga_top_0.pwm_o[2];
                3: pwm_sample = fpga_top_0.pwm_o[3];
                default: pwm_sample = 1'b0;
            endcase
        end
    endfunction

    task print_pwm_regs;
        begin
            $display("PWM regs:");
            $display("  period[0]    = %0d", fpga_top_0.u_tinyriscv_soc_top.u_pwm.period[0]);
            $display("  high_time[0] = %0d", fpga_top_0.u_tinyriscv_soc_top.u_pwm.high_time[0]);
            $display("  period[1]    = %0d", fpga_top_0.u_tinyriscv_soc_top.u_pwm.period[1]);
            $display("  high_time[1] = %0d", fpga_top_0.u_tinyriscv_soc_top.u_pwm.high_time[1]);
            $display("  period[2]    = %0d", fpga_top_0.u_tinyriscv_soc_top.u_pwm.period[2]);
            $display("  high_time[2] = %0d", fpga_top_0.u_tinyriscv_soc_top.u_pwm.high_time[2]);
            $display("  period[3]    = %0d", fpga_top_0.u_tinyriscv_soc_top.u_pwm.period[3]);
            $display("  high_time[3] = %0d", fpga_top_0.u_tinyriscv_soc_top.u_pwm.high_time[3]);
            $display("  enable       = 0x%0h", fpga_top_0.u_tinyriscv_soc_top.u_pwm.enable);
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
                    if (fpga_top_0.u_tinyriscv_soc_top.u_pwm.period[0] !== expected_period) pass = 0;
                    if (fpga_top_0.u_tinyriscv_soc_top.u_pwm.high_time[0] !== expected_high) pass = 0;
                end
                1: begin
                    if (fpga_top_0.u_tinyriscv_soc_top.u_pwm.period[1] !== expected_period) pass = 0;
                    if (fpga_top_0.u_tinyriscv_soc_top.u_pwm.high_time[1] !== expected_high) pass = 0;
                end
                2: begin
                    if (fpga_top_0.u_tinyriscv_soc_top.u_pwm.period[2] !== expected_period) pass = 0;
                    if (fpga_top_0.u_tinyriscv_soc_top.u_pwm.high_time[2] !== expected_high) pass = 0;
                end
                3: begin
                    if (fpga_top_0.u_tinyriscv_soc_top.u_pwm.period[3] !== expected_period) pass = 0;
                    if (fpga_top_0.u_tinyriscv_soc_top.u_pwm.high_time[3] !== expected_high) pass = 0;
                end
                default: pass = 0;
            endcase

            if (pass == 0) begin
                $display("PWM channel %0d register mismatch: expected period=%0d high=%0d",
                         ch, expected_period, expected_high);
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
                $display("  expected period=%0d high=%0d, measured period=timeout high=timeout",
                         expected_period, expected_high);
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
                    $display("  expected period=%0d high=%0d, measured period=%0d high=%0d",
                             expected_period, expected_high, period_count, high_count);
                end else if (((period_count >= expected_period - 1) && (period_count <= expected_period + 1)) &&
                             ((high_count >= expected_high - 1) && (high_count <= expected_high + 1))) begin
                    pass = 1;
                    $display("PWM channel %0d ok: expected period=%0d high=%0d, measured period=%0d high=%0d",
                             ch, expected_period, expected_high, period_count, high_count);
                end else begin
                    $display("PWM channel %0d failed: expected period=%0d high=%0d, measured period=%0d high=%0d",
                             ch, expected_period, expected_high, period_count, high_count);
                end
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = `RstEnable;
        uart_debug_pin = 1'b1;  // raw key unpressed; fpga_top inverts debounced debug key internally

        // fpga_top contains 20ms key debounce logic. The original PWM testbench applies
        // reset for only 40ns. To keep the original PWM test timing and behavior unchanged,
        // force the debounced internal key outputs to the same values the original SoC-level
        // testbench provided directly.
        force fpga_top_0.rst_key_up = rst;
        force fpga_top_0.debug_key_up = 1'b1;  // makes uart_debug_pin into SoC = 1'b0

        $display("FPGA top PWM test running...");
        #40
        rst = `RstDisable;
    end

    initial begin
        pwm_pass = 1;
        ch0_pass = 0;
        ch1_pass = 0;
        ch2_pass = 0;
        ch3_pass = 0;

        wait(rst == `RstDisable);

        wait_cycles = 0;
        while (fpga_top_0.u_tinyriscv_soc_top.u_pwm.enable !== 4'hF && wait_cycles < 50000) begin
            @(posedge clk);
            wait_cycles = wait_cycles + 1;
        end

        if (fpga_top_0.u_tinyriscv_soc_top.u_pwm.enable !== 4'hF) begin
            $display("~~~~~~~~~~~~~~~~~~~ FPGA TOP PWM TEST_FAIL ~~~~~~~~~~~~~~~~~~~");
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

        if (fpga_top_0.u_tinyriscv_soc_top.u_pwm.enable !== 4'hF) begin
            pwm_pass = 0;
            $display("PWM enable mismatch: expected 0xF, actual 0x%0h",
                     fpga_top_0.u_tinyriscv_soc_top.u_pwm.enable);
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
            $display("~~~~~~~~~~~~~~~~~~~ FPGA TOP PWM TEST_PASS ~~~~~~~~~~~~~~~~~~~");
        end else begin
            $display("~~~~~~~~~~~~~~~~~~~ FPGA TOP PWM TEST_FAIL ~~~~~~~~~~~~~~~~~~~");
            print_pwm_regs();
        end

        $finish;
    end

    initial begin
        #2000000
        $display("~~~~~~~~~~~~~~~~~~~ FPGA TOP PWM TEST_FAIL ~~~~~~~~~~~~~~~~~~~");
        $display("Time Out.");
        print_pwm_regs();
        $finish;
    end

    // Current ROM/RAM live on the FPGA side inside fpga_top.u_fpga_mem_bridge.
    // If your simulator runs from another directory, pass +INST=path/to/PWM_inst_fast.data.
    initial begin
        if (!$value$plusargs("INST=%s", inst_file)) begin
            inst_file = "E://learn/thu/digital_work/tinyriscv_2026/inst/Other_Example/PWM/PWM_inst_fast.data";
        end
        $display("load inst file: %0s", inst_file);
        $readmemh(inst_file, fpga_top_0.u_fpga_mem_bridge.rom);
    end

    // generate wave file, used by gtkwave
    initial begin
        $dumpfile("fpga_top_tb.vcd");
        $dumpvars(0, fpga_top_tb);
    end

    fpga_top fpga_top_0(
        .clk(clk),
        .rst(rst),
        .succ(succ),
        .uart_debug_pin(uart_debug_pin),
        .uart_tx_pin(uart_tx_pin),
        .uart_rx_pin(uart_rx_pin),
        .PWM_o(PWM_o),
        .io_scl(io_scl),
        .io_sda(io_sda)
    );

endmodule
