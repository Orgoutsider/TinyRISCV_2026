`timescale 1ns/1ps

module tb_mem_bridge;
    reg clk;
    reg rst;
    reg req;
    reg we;
    reg is_ram;
    reg[31:0] addr;
    reg[31:0] wdata;
    wire[31:0] rdata;
    wire busy;
    wire[7:0] chip_to_fpga;
    wire[7:0] fpga_to_chip;
    reg timeout_req;
    wire[31:0] timeout_rdata;
    wire timeout_busy;
    wire[7:0] timeout_chip_to_fpga;

    chip_mem_bridge chip(
        .clk(clk),
        .rst(rst),
        .req_i(req),
        .we_i(we),
        .is_ram_i(is_ram),
        .addr_i(addr),
        .wdata_i(wdata),
        .rdata_o(rdata),
        .busy_o(busy),
        .chip_data_o(chip_to_fpga),
        .chip_data_i(fpga_to_chip)
    );

    chip_mem_bridge #(.RX_SYNC_TIMEOUT(16'd4)) chip_timeout(
        .clk(clk),
        .rst(rst),
        .req_i(timeout_req),
        .we_i(1'b0),
        .is_ram_i(1'b0),
        .addr_i(32'h0),
        .wdata_i(32'h0),
        .rdata_o(timeout_rdata),
        .busy_o(timeout_busy),
        .chip_data_o(timeout_chip_to_fpga),
        .chip_data_i(8'h00)
    );

    fpga_mem_bridge fpga(
        .clk(clk),
        .rst(rst),
        .chip_data_i(chip_to_fpga),
        .chip_data_o(fpga_to_chip)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task access;
        input wr;
        input ram;
        input[31:0] a;
        input[31:0] d;
        begin
            @(negedge clk);
            we = wr;
            is_ram = ram;
            addr = a;
            wdata = d;
            req = 1'b1;
            @(negedge clk);
            req = 1'b0;
            wait (busy == 1'b1);
            wait (busy == 1'b0);
            @(negedge clk);
        end
    endtask

    initial begin
        rst = 1'b0;
        req = 1'b0;
        we = 1'b0;
        is_ram = 1'b0;
        addr = 32'h0;
        wdata = 32'h0;
        timeout_req = 1'b0;
        repeat (3) @(negedge clk);
        rst = 1'b1;

        access(1'b1, 1'b1, 32'h0000_0008, 32'h12345678);
        access(1'b0, 1'b1, 32'h0000_0008, 32'h0);
        if (rdata != 32'h12345678) begin
            $display("FAIL: ram bridge readback %h", rdata);
            $finish;
        end

        access(1'b0, 1'b0, 32'h0000_0000, 32'h0);
        if (rdata != 32'h00000013) begin
            $display("FAIL: rom bridge default %h", rdata);
            $finish;
        end

        @(negedge clk);
        timeout_req = 1'b1;
        @(negedge clk);
        timeout_req = 1'b0;
        wait (timeout_busy == 1'b1);
        repeat (32) @(negedge clk);
        if (timeout_busy != 1'b0 || timeout_rdata != 32'h00000000) begin
            $display("FAIL: bridge timeout busy=%b rdata=%h", timeout_busy, timeout_rdata);
            $finish;
        end

        $display("PASS: tb_mem_bridge");
        $finish;
    end
endmodule
