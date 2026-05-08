/*
 * Area-reduced UART firmware download helper.
 *
 * Project modification: packet size is reduced from 131 bytes to 35 bytes and
 * the internal RX buffer is exactly 35 x 8-bit.
 *
 * Protocol:
 *   byte 0      : packet header/control byte, received but not written
 *   byte 1..32  : payload, 32 bytes, written as 8 little-endian 32-bit words
 *   byte 33..34 : CRC16, low byte first; compare with {rx_data[34], rx_data[33]}
 *
 * CRC16 uses the original tinyriscV UART debug settings: initial value 16'hffff
 * and polynomial 16'ha001. The CRC covers byte 1..32 only. The first packet
 * carries fw_file_size and is not written to memory. Remaining packets are
 * written sequentially from ROM_START_ADDR, 8 words per packet.
 */
`include "defines.v"

`define UART_BAUD_115200        32'h0000_01B8
`define UART_CTRL_REG           32'h3000_0000
`define UART_STATUS_REG         32'h3000_0004
`define UART_BAUD_REG           32'h3000_0008
`define UART_TX_REG             32'h3000_000c
`define UART_RX_REG             32'h3000_0010
`define UART_TX_BUSY_FLAG       32'h0000_0001
`define UART_RX_OVER_FLAG       32'h0000_0002
`define UART_RESP_ACK           32'h0000_0006
`define UART_RESP_NAK           32'h0000_0015

`define ROM_START_ADDR          32'h0000_0000

module uart_debug(
    input  wire       clk,
    input  wire       rst,
    input  wire       debug_en_i,
    output wire       req_o,
    output reg        mem_we_o,
    output reg [31:0] mem_addr_o,
    output reg [31:0] mem_wdata_o,
    input  wire[31:0] mem_rdata_i
);

    localparam S_IDLE                    = 5'd0;
    localparam S_INIT_UART_CTRL          = 5'd1;
    localparam S_INIT_UART_BAUD          = 5'd2;
    localparam S_REC_FIRST_PACKET        = 5'd3;
    localparam S_REC_REMAIN_PACKET       = 5'd4;
    localparam S_CLEAR_UART_RX_OVER_FLAG = 5'd5;
    localparam S_WAIT_BYTE               = 5'd6;
    localparam S_WAIT_BYTE2              = 5'd7;
    localparam S_GET_BYTE                = 5'd8;
    localparam S_GET_BYTE2               = 5'd9;
    localparam S_CRC_START               = 5'd10;
    localparam S_CRC_CALC                = 5'd11;
    localparam S_CRC_END                 = 5'd12;
    localparam S_WRITE_MEM               = 5'd13;
    localparam S_WAIT_TX_IDLE            = 5'd14;
    localparam S_WAIT_TX_IDLE2           = 5'd15;
    localparam S_SEND_ACK                = 5'd16;
    localparam S_SEND_NAK                = 5'd17;

    localparam PACKET_FIRST              = 1'b0;
    localparam PACKET_REMAIN             = 1'b1;
    localparam RESP_ACK                  = 1'b0;
    localparam RESP_NAK                  = 1'b1;

    reg [4:0]  state;
    reg [7:0] rx_data [0:34];
    reg [5:0]  rx_index;
    reg        packet_type;
    reg        response_type;

    reg [31:0] fw_file_size;
    reg [31:0] remain_packet_count;
    reg [31:0] write_mem_addr;
    reg [2:0]  write_word_cnt;

    reg [15:0] crc16;
    reg [7:0]  crc_byte;
    reg [5:0]  crc_byte_index;
    reg [2:0]  crc_bit_index;

    assign req_o = (rst == 1'b1 && debug_en_i == 1'b1) ? 1'b1 : 1'b0;

    always @(posedge clk) begin
        if (rst == `RstEnable || debug_en_i == 1'b0) begin
            state <= S_IDLE;
            mem_we_o <= `WriteDisable;
            mem_addr_o <= `ZeroWord;
            mem_wdata_o <= `ZeroWord;
            rx_index <= 6'd0;
            packet_type <= PACKET_FIRST;
            response_type <= RESP_ACK;
            fw_file_size <= `ZeroWord;
            remain_packet_count <= `ZeroWord;
            write_mem_addr <= `ROM_START_ADDR;
            write_word_cnt <= 3'd0;
            crc16 <= 16'hffff;
            crc_byte <= 8'h00;
            crc_byte_index <= 6'd0;
            crc_bit_index <= 3'd0;
        end else begin
            mem_we_o <= `WriteDisable;
            mem_addr_o <= `ZeroWord;
            mem_wdata_o <= `ZeroWord;

            case (state)
                S_IDLE: begin
                    rx_index <= 6'd0;
                    packet_type <= PACKET_FIRST;
                    response_type <= RESP_ACK;
                    write_mem_addr <= `ROM_START_ADDR;
                    mem_addr_o <= `UART_CTRL_REG;
                    mem_wdata_o <= 32'h0000_0003;
                    mem_we_o <= `WriteEnable;
                    state <= S_INIT_UART_CTRL;
                end

                S_INIT_UART_CTRL: begin
                    mem_addr_o <= `UART_BAUD_REG;
                    mem_wdata_o <= `UART_BAUD_115200;
                    mem_we_o <= `WriteEnable;
                    state <= S_INIT_UART_BAUD;
                end

                S_INIT_UART_BAUD: begin
                    state <= S_REC_FIRST_PACKET;
                end

                S_REC_FIRST_PACKET: begin
                    rx_index <= 6'd0;
                    packet_type <= PACKET_FIRST;
                    state <= S_CLEAR_UART_RX_OVER_FLAG;
                end

                S_REC_REMAIN_PACKET: begin
                    rx_index <= 6'd0;
                    packet_type <= PACKET_REMAIN;
                    state <= S_CLEAR_UART_RX_OVER_FLAG;
                end

                S_CLEAR_UART_RX_OVER_FLAG: begin
                    mem_addr_o <= `UART_STATUS_REG;
                    mem_wdata_o <= 32'h0000_0000;
                    mem_we_o <= `WriteEnable;
                    state <= S_WAIT_BYTE;
                end

                S_WAIT_BYTE: begin
                    mem_addr_o <= `UART_STATUS_REG;
                    state <= S_WAIT_BYTE2;
                end

                S_WAIT_BYTE2: begin
                    mem_addr_o <= `UART_STATUS_REG;
                    if ((mem_rdata_i & `UART_RX_OVER_FLAG) == `UART_RX_OVER_FLAG) begin
                        state <= S_GET_BYTE;
                    end else begin
                        state <= S_WAIT_BYTE;
                    end
                end

                S_GET_BYTE: begin
                    mem_addr_o <= `UART_RX_REG;
                    state <= S_GET_BYTE2;
                end

                S_GET_BYTE2: begin
                    mem_addr_o <= `UART_RX_REG;
                    rx_data[rx_index] <= mem_rdata_i[7:0];
                    if (rx_index == 6'd34) begin
                        state <= S_CRC_START;
                    end else begin
                        rx_index <= rx_index + 1'b1;
                        state <= S_CLEAR_UART_RX_OVER_FLAG;
                    end
                end

                S_CRC_START: begin
                    crc16 <= 16'hffff;
                    crc_byte <= rx_data[1];
                    crc_byte_index <= 6'd1;
                    crc_bit_index <= 3'd0;
                    state <= S_CRC_CALC;
                end

                S_CRC_CALC: begin
                    if ((crc16[0] ^ crc_byte[0]) == 1'b1) begin
                        crc16 <= (crc16 >> 1) ^ 16'ha001;
                    end else begin
                        crc16 <= (crc16 >> 1);
                    end
                    crc_byte <= {1'b0, crc_byte[7:1]};

                    if (crc_bit_index == 3'd7) begin
                        crc_bit_index <= 3'd0;
                        if (crc_byte_index == 6'd32) begin
                            state <= S_CRC_END;
                        end else begin
                            crc_byte_index <= crc_byte_index + 1'b1;
                            crc_byte <= rx_data[crc_byte_index + 1'b1];
                        end
                    end else begin
                        crc_bit_index <= crc_bit_index + 1'b1;
                    end
                end

                S_CRC_END: begin
                    if (crc16 == {rx_data[34], rx_data[33]}) begin
                        response_type <= RESP_ACK;
                        if (packet_type == PACKET_FIRST) begin
                            // fw_file_size <= {rx_data[17], rx_data[18], rx_data[19], rx_data[20]};
                            fw_file_size <= {rx_data[25], rx_data[26], rx_data[27], rx_data[28]};
                            // match FILE_SIZE_INDEX = 25
                            write_mem_addr <= `ROM_START_ADDR;
                            // if ({rx_data[17], rx_data[18], rx_data[19], rx_data[20]} == 32'h0000_0000) begin
                            //     remain_packet_count <= 32'h0000_0000;
                            // end else begin
                            //     remain_packet_count <= ({rx_data[17], rx_data[18], rx_data[19], rx_data[20]} + 32'd31) >> 5;
                            // end
                            if ({rx_data[25], rx_data[26], rx_data[27], rx_data[28]} == 32'h0000_0000) begin
                                remain_packet_count <= 32'h0000_0000;
                            end else begin
                                remain_packet_count <= ({rx_data[25], rx_data[26], rx_data[27], rx_data[28]} + 32'd31) >> 5;
                            end
                            state <= S_WAIT_TX_IDLE;
                        end else begin
                            if (remain_packet_count != 32'h0000_0000) begin
                                write_word_cnt <= 3'd0;
                                state <= S_WRITE_MEM;
                            end else begin
                                state <= S_WAIT_TX_IDLE;
                            end
                        end
                    end else begin
                        response_type <= RESP_NAK;
                        state <= S_WAIT_TX_IDLE;
                    end
                end

                S_WRITE_MEM: begin
                    mem_we_o <= `WriteEnable;
                    mem_addr_o <= write_mem_addr + {27'h0, write_word_cnt, 2'b00};
                    case (write_word_cnt)
                        3'd0: mem_wdata_o <= {rx_data[4],  rx_data[3],  rx_data[2],  rx_data[1]};
                        3'd1: mem_wdata_o <= {rx_data[8],  rx_data[7],  rx_data[6],  rx_data[5]};
                        3'd2: mem_wdata_o <= {rx_data[12], rx_data[11], rx_data[10], rx_data[9]};
                        3'd3: mem_wdata_o <= {rx_data[16], rx_data[15], rx_data[14], rx_data[13]};
                        3'd4: mem_wdata_o <= {rx_data[20], rx_data[19], rx_data[18], rx_data[17]};
                        3'd5: mem_wdata_o <= {rx_data[24], rx_data[23], rx_data[22], rx_data[21]};
                        3'd6: mem_wdata_o <= {rx_data[28], rx_data[27], rx_data[26], rx_data[25]};
                        default: mem_wdata_o <= {rx_data[32], rx_data[31], rx_data[30], rx_data[29]};
                    endcase

                    if (write_word_cnt == 3'd7) begin
                        write_word_cnt <= 3'd0;
                        write_mem_addr <= write_mem_addr + 32'd32;
                        remain_packet_count <= remain_packet_count - 1'b1;
                        state <= S_WAIT_TX_IDLE;
                    end else begin
                        write_word_cnt <= write_word_cnt + 1'b1;
                    end
                end

                S_WAIT_TX_IDLE: begin
                    mem_addr_o <= `UART_STATUS_REG;
                    state <= S_WAIT_TX_IDLE2;
                end

                S_WAIT_TX_IDLE2: begin
                    mem_addr_o <= `UART_STATUS_REG;
                    if ((mem_rdata_i & `UART_TX_BUSY_FLAG) == 32'h0000_0000) begin
                        if (response_type == RESP_ACK) begin
                            state <= S_SEND_ACK;
                        end else begin
                            state <= S_SEND_NAK;
                        end
                    end else begin
                        state <= S_WAIT_TX_IDLE;
                    end
                end

                S_SEND_ACK: begin
                    mem_addr_o <= `UART_TX_REG;
                    mem_wdata_o <= `UART_RESP_ACK;
                    mem_we_o <= `WriteEnable;
                    if (packet_type == PACKET_FIRST) begin
                        if (remain_packet_count == 32'h0000_0000) begin
                            state <= S_REC_FIRST_PACKET;
                        end else begin
                            state <= S_REC_REMAIN_PACKET;
                        end
                    end else begin
                        if (remain_packet_count == 32'h0000_0000) begin
                            state <= S_REC_FIRST_PACKET;
                        end else begin
                            state <= S_REC_REMAIN_PACKET;
                        end
                    end
                end

                S_SEND_NAK: begin
                    mem_addr_o <= `UART_TX_REG;
                    mem_wdata_o <= `UART_RESP_NAK;
                    mem_we_o <= `WriteEnable;
                    if (packet_type == PACKET_FIRST) begin
                        state <= S_REC_FIRST_PACKET;
                    end else begin
                        state <= S_REC_REMAIN_PACKET;
                    end
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
