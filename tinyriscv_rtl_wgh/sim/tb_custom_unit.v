`timescale 1ns/1ps
`include "defines.v"

module tb_custom_unit;
    reg clk;
    reg rst;
    reg start;
    reg[2:0] funct3;
    reg[11:0] imm;
    reg[31:0] rs1_data;
    reg[31:0] x31_data;
    reg[4:0] rd;
    reg uart_ready;
    reg i2c_valid;
    reg[7:0] i2c_data;
    reg i2c_busy;

    wire busy;
    wire ready;
    wire reg_we;
    wire[4:0] reg_waddr;
    wire[31:0] reg_wdata;
    wire uart_valid;
    wire[7:0] uart_data;
    wire i2c_req;

    integer sid_count;

    custom_unit dut(
        .clk(clk),
        .rst(rst),
        .start_i(start),
        .funct3_i(funct3),
        .imm_i(imm),
        .rs1_data_i(rs1_data),
        .x31_data_i(x31_data),
        .rd_i(rd),
        .busy_o(busy),
        .ready_o(ready),
        .reg_we_o(reg_we),
        .reg_waddr_o(reg_waddr),
        .reg_wdata_o(reg_wdata),
        .uart_tx_valid_o(uart_valid),
        .uart_tx_data_o(uart_data),
        .uart_tx_ready_i(uart_ready),
        .i2c_temp_req_o(i2c_req),
        .i2c_temp_valid_i(i2c_valid),
        .i2c_temp_data_i(i2c_data),
        .i2c_busy_i(i2c_busy)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task pulse_start;
        input[2:0] op;
        begin
            @(negedge clk);
            funct3 = op;
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
        end
    endtask

    initial begin
        rst = `RstEnable;
        start = 1'b0;
        funct3 = `INST_SID;
        imm = 12'h0;
        rs1_data = 32'h00000041;
        x31_data = 32'h0;
        rd = 5'd5;
        uart_ready = 1'b1;
        i2c_valid = 1'b0;
        i2c_data = 8'h5c;
        i2c_busy = 1'b0;
        sid_count = 0;

        repeat (3) @(negedge clk);
        rst = `RstDisable;

        pulse_start(`INST_SID);
        wait (ready);
        if (sid_count != 10) begin
            $display("FAIL: sID sent %0d bytes", sid_count);
            $finish;
        end

        pulse_start(`INST_RT);
        wait (i2c_req);
        @(negedge clk);
        i2c_valid = 1'b1;
        @(negedge clk);
        i2c_valid = 1'b0;
        wait (reg_we);
        if (reg_we != `WriteEnable || reg_waddr != 5'd5 || reg_wdata != 32'h0000005c) begin
            $display("FAIL: rT writeback we=%b rd=%0d data=%h", reg_we, reg_waddr, reg_wdata);
            $finish;
        end

        pulse_start(`INST_IFIRE);
        wait (reg_we);
        if (reg_we != `WriteEnable || reg_waddr != 5'd5 || reg_wdata != 32'h0) begin
            $display("FAIL: if writeback");
            $finish;
        end

        $display("PASS: tb_custom_unit");
        $finish;
    end

    always @(posedge clk) begin
        if (uart_valid && uart_ready) begin
            sid_count <= sid_count + 1;
            uart_ready <= 1'b0;
        end else begin
            uart_ready <= 1'b1;
        end
    end
endmodule
