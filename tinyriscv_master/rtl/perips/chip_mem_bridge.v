/*
 * Chip-side ROM/RAM bridge using an 8-bit output bus and an 8-bit input bus.
 *
 * Protocol, one byte per clock on chip_data_o, response one byte per clock on
 * chip_data_i. No extra valid/ready pins are used; fixed preambles delimit frames.
 * Request frame from chip to FPGA:
 *   0: 8'hA5
 *   1: {we, is_ram, 6'b0}
 *   2: word_addr[7:0]
 *   3: wdata[7:0]
 *   4: wdata[15:8]
 *   5: wdata[23:16]
 *   6: wdata[31:24]
 * Read response from FPGA to chip:
 *   0: 8'h5A
 *   1: rdata[7:0]
 *   2: rdata[15:8]
 *   3: rdata[23:16]
 *   4: rdata[31:24]
 * Write response uses 8'h5A then four zero bytes.
 */
`include "../core/defines.v"

module chip_mem_bridge(
    input  wire       clk,
    input  wire       rst,

    input  wire       req_i,
    input  wire       we_i,
    input  wire       is_ram_i,
    input  wire[31:0] addr_i,
    input  wire[31:0] wdata_i,
    output reg [31:0] rdata_o,
    output wire       busy_o,

    output reg [7:0]  chip_data_o,
    input  wire[7:0]  chip_data_i
);

    localparam S_IDLE  = 4'd0;
    localparam S_TX0   = 4'd1;
    localparam S_TX1   = 4'd2;
    localparam S_TX2   = 4'd3;
    localparam S_TX3   = 4'd4;
    localparam S_TX4   = 4'd5;
    localparam S_TX5   = 4'd6;
    localparam S_TX6   = 4'd7;
    localparam S_RX0   = 4'd8;
    localparam S_RX1   = 4'd9;
    localparam S_RX2   = 4'd10;
    localparam S_RX3   = 4'd11;
    localparam S_RX4   = 4'd12;
    localparam S_DONE  = 4'd13;

    reg[3:0] state;
    reg[31:0] addr_q;
    reg[31:0] wdata_q;
    reg we_q;
    reg is_ram_q;
    reg busy;

    assign busy_o = busy;

    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            state <= S_IDLE;
            chip_data_o <= 8'h00;
            rdata_o <= `ZeroWord;
            busy <= 1'b0;
            addr_q <= `ZeroWord;
            wdata_q <= `ZeroWord;
            we_q <= 1'b0;
            is_ram_q <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    chip_data_o <= 8'h00;
                    if (req_i) begin
                        busy <= 1'b1;
                        addr_q <= addr_i;
                        wdata_q <= wdata_i;
                        we_q <= we_i;
                        is_ram_q <= is_ram_i;
                        state <= S_TX0;
                    end
                end
                S_TX0: begin chip_data_o <= 8'hA5; state <= S_TX1; end
                S_TX1: begin chip_data_o <= {we_q, is_ram_q, 6'b0}; state <= S_TX2; end
                S_TX2: begin chip_data_o <= addr_q[9:2]; state <= S_TX3; end
                S_TX3: begin chip_data_o <= wdata_q[7:0]; state <= S_TX4; end
                S_TX4: begin chip_data_o <= wdata_q[15:8]; state <= S_TX5; end
                S_TX5: begin chip_data_o <= wdata_q[23:16]; state <= S_TX6; end
                S_TX6: begin chip_data_o <= wdata_q[31:24]; state <= S_RX0; end
                S_RX0: begin
                    chip_data_o <= 8'h00;
                    if (chip_data_i == 8'h5A) begin
                        state <= S_RX1;
                    end
                end
                S_RX1: begin rdata_o[7:0]   <= chip_data_i; state <= S_RX2; end
                S_RX2: begin rdata_o[15:8]  <= chip_data_i; state <= S_RX3; end
                S_RX3: begin rdata_o[23:16] <= chip_data_i; state <= S_RX4; end
                S_RX4: begin rdata_o[31:24] <= chip_data_i; state <= S_DONE; end
                S_DONE: begin busy <= 1'b0; state <= S_IDLE; end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
