/*
 * FPGA-side memory bridge matching chip_mem_bridge.v.
 * External ROM: 256 x 32-bit, RAM: 16 x 32-bit.
 * ROM can optionally be preloaded from ROM_INIT_FILE for FPGA simulation/synthesis.
 */
module fpga_mem_bridge #(
    // TODO: may delete
    parameter ROM_INIT_FILE = ""
)(
    input  wire       clk,
    input  wire       rst,
    input  wire[7:0]  chip_data_i,
    output reg [7:0]  chip_data_o
);

    localparam S_IDLE = 4'd0;
    localparam S_CMD  = 4'd1;
    localparam S_ADDR = 4'd2;
    localparam S_D0   = 4'd3;
    localparam S_D1   = 4'd4;
    localparam S_D2   = 4'd5;
    localparam S_D3   = 4'd6;
    localparam S_RSP0 = 4'd7;
    localparam S_RSP1 = 4'd8;
    localparam S_RSP2 = 4'd9;
    localparam S_RSP3 = 4'd10;
    localparam S_RSP4 = 4'd11;

    reg[3:0] state;
    reg we_q;
    reg is_ram_q;
    reg[7:0] word_addr_q;
    reg[31:0] wdata_q;
    reg[31:0] rdata_q;

    // TODO: Use block RAMs and ROMs for FPGA implementation if necessary.
    reg[31:0] rom[0:255];
    reg[31:0] ram[0:15];

    integer i;
    initial begin
        for (i = 0; i < 256; i = i + 1) rom[i] = 32'h00000013; // ADDI x0,x0,0
        for (i = 0; i < 16; i = i + 1) ram[i] = 32'h00000000;
        if (ROM_INIT_FILE != "") begin
            $readmemh(ROM_INIT_FILE, rom);
        end
    end

    always @(posedge clk) begin
        if (rst == 1'b0) begin
            state <= S_IDLE;
            chip_data_o <= 8'h00;
            we_q <= 1'b0;
            is_ram_q <= 1'b0;
            word_addr_q <= 8'h00;
            wdata_q <= 32'h0;
            rdata_q <= 32'h0;
        end else begin
            case (state)
                S_IDLE: begin
                    chip_data_o <= 8'h00;
                    if (chip_data_i == 8'hA5) state <= S_CMD;
                end
                S_CMD: begin
                    we_q <= chip_data_i[7];
                    is_ram_q <= chip_data_i[6];
                    state <= S_ADDR;
                end
                S_ADDR: begin
                    word_addr_q <= chip_data_i;
                    state <= S_D0;
                end
                S_D0: begin wdata_q[7:0] <= chip_data_i; state <= S_D1; end
                S_D1: begin wdata_q[15:8] <= chip_data_i; state <= S_D2; end
                S_D2: begin wdata_q[23:16] <= chip_data_i; state <= S_D3; end
                S_D3: begin
                    wdata_q[31:24] <= chip_data_i;
                    if (we_q) begin
                        if (is_ram_q) begin
                            ram[word_addr_q[3:0]] <= {chip_data_i, wdata_q[23:0]};
                        end
                        // ROM writes are ignored intentionally.
                            rom[word_addr_q] <= {chip_data_i, wdata_q[23:0]};
                    end
                    if (is_ram_q) begin
                        rdata_q <= ram[word_addr_q[3:0]];
                    end else begin
                        rdata_q <= rom[word_addr_q];
                    end
                    state <= S_RSP0;
                end
                S_RSP0: begin chip_data_o <= 8'h5A; state <= S_RSP1; end
                S_RSP1: begin chip_data_o <= rdata_q[7:0]; state <= S_RSP2; end
                S_RSP2: begin chip_data_o <= rdata_q[15:8]; state <= S_RSP3; end
                S_RSP3: begin chip_data_o <= rdata_q[23:16]; state <= S_RSP4; end
                S_RSP4: begin chip_data_o <= rdata_q[31:24]; state <= S_IDLE; end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
