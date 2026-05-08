/*
 * Minimal I2C master/peripheral wrapper for LM75 temperature read.
 *
 * MMIO map after RIB removes high nibble:
 *   0x0000_0000 CTRL/STATUS: bit0 start read when written 1, bit1 busy, bit2 done
 *   0x0001_0000 SLAVE_ADDR : 7-bit LM75 address, default 0x48
 *   0x0002_0000 TX_DATA    : reserved/output data register
 *   0x0003_0000 RX_DATA    : {24'h0, temperature_msb}
 *
 * custom_temp_req_i starts the same LM75 read used by the rT instruction.
 */
`include "defines.v"

module i2c_lm75 #(
    parameter CLK_DIV = 16'd250       // 50MHz/(4*250) ~= 50kHz SCL in this simple engine
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       we_i,
    input  wire[31:0] addr_i,
    input  wire[31:0] data_i,
    output reg [31:0] data_o,

    input  wire       custom_temp_req_i,
    output reg        custom_temp_valid_o,
    output reg [7:0]  custom_temp_data_o,
    output wire       busy_o,

    output reg        i2c_scl,
    inout  wire       i2c_sda
);

    localparam REG_CTRL  = 8'h00;
    localparam REG_ADDR  = 8'h01;
    localparam REG_TX    = 8'h02;
    localparam REG_RX    = 8'h03;

    localparam ST_IDLE       = 5'd0;
    localparam ST_START_A    = 5'd1;
    localparam ST_START_B    = 5'd2;
    localparam ST_SEND       = 5'd3;
    localparam ST_SEND_HIGH  = 5'd4;
    localparam ST_ACK_LOW    = 5'd5;
    localparam ST_ACK_HIGH   = 5'd6;
    localparam ST_READ_LOW   = 5'd7;
    localparam ST_READ_HIGH  = 5'd8;
    localparam ST_NACK_LOW   = 5'd9;
    localparam ST_NACK_HIGH  = 5'd10;
    localparam ST_STOP_A     = 5'd11;
    localparam ST_STOP_B     = 5'd12;
    localparam ST_DONE       = 5'd13;

    reg[4:0] state;
    reg[15:0] div_cnt;
    wire tick = (div_cnt == CLK_DIV);

    reg[6:0] slave_addr;
    reg[31:0] tx_reg;
    reg[7:0] rx_reg;
    reg[7:0] shifter;
    reg[3:0] bit_cnt;
    reg sda_oe_low;
    reg start_pending;
    reg busy;
    reg done;

    assign i2c_sda = sda_oe_low ? 1'b0 : 1'bz;
    wire sda_in = i2c_sda;
    assign busy_o = busy;

    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            div_cnt <= 16'd0;
        end else if (busy) begin
            if (tick) begin
                div_cnt <= 16'd0;
            end else begin
                div_cnt <= div_cnt + 1'b1;
            end
        end else begin
            div_cnt <= 16'd0;
        end
    end

    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            slave_addr <= 7'h48;
            tx_reg <= 32'h0;
            start_pending <= 1'b0;
        end else begin
            if (we_i == `WriteEnable) begin
                case (addr_i[23:16])
                    REG_CTRL: begin
                        if (data_i[0]) start_pending <= 1'b1;
                    end
                    REG_ADDR: slave_addr <= data_i[6:0];
                    REG_TX:   tx_reg <= data_i;
                    default: begin end
                endcase
            end
            if (custom_temp_req_i) begin
                start_pending <= 1'b1;
            end
            if (state == ST_START_A && tick) begin
                start_pending <= 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            state <= ST_IDLE;
            i2c_scl <= 1'b1;
            sda_oe_low <= 1'b0;
            busy <= 1'b0;
            done <= 1'b0;
            custom_temp_valid_o <= 1'b0;
            custom_temp_data_o <= 8'h00;
            rx_reg <= 8'h00;
            shifter <= 8'h00;
            bit_cnt <= 4'd0;
        end else begin
            custom_temp_valid_o <= 1'b0;

            case (state)
                ST_IDLE: begin
                    busy <= 1'b0;
                    i2c_scl <= 1'b1;
                    sda_oe_low <= 1'b0;
                    if (start_pending) begin
                        busy <= 1'b1;
                        done <= 1'b0;
                        shifter <= {slave_addr, 1'b1};  // LM75 read
                        bit_cnt <= 4'd7;
                        state <= ST_START_A;
                    end
                end
                ST_START_A: begin
                    if (tick) begin
                        i2c_scl <= 1'b1;
                        sda_oe_low <= 1'b1;              // SDA falls while SCL high
                        state <= ST_START_B;
                    end
                end
                ST_START_B: begin
                    if (tick) begin
                        i2c_scl <= 1'b0;
                        state <= ST_SEND;
                    end
                end
                ST_SEND: begin
                    if (tick) begin
                        sda_oe_low <= ~shifter[bit_cnt]; // release for 1, pull low for 0
                        i2c_scl <= 1'b0;
                        state <= ST_SEND_HIGH;
                    end
                end
                ST_SEND_HIGH: begin
                    if (tick) begin
                        i2c_scl <= 1'b1;
                        if (bit_cnt == 4'd0) begin
                            state <= ST_ACK_LOW;
                        end else begin
                            bit_cnt <= bit_cnt - 1'b1;
                            state <= ST_SEND;
                        end
                    end
                end
                ST_ACK_LOW: begin
                    if (tick) begin
                        i2c_scl <= 1'b0;
                        sda_oe_low <= 1'b0;              // release for ACK
                        bit_cnt <= 4'd7;
                        rx_reg <= 8'h00;
                        state <= ST_ACK_HIGH;
                    end
                end
                ST_ACK_HIGH: begin
                    if (tick) begin
                        i2c_scl <= 1'b1;                 // sample ACK but do not fail on NACK
                        state <= ST_READ_LOW;
                    end
                end
                ST_READ_LOW: begin
                    if (tick) begin
                        i2c_scl <= 1'b0;
                        sda_oe_low <= 1'b0;
                        state <= ST_READ_HIGH;
                    end
                end
                ST_READ_HIGH: begin
                    if (tick) begin
                        i2c_scl <= 1'b1;
                        rx_reg[bit_cnt] <= sda_in;
                        if (bit_cnt == 4'd0) begin
                            state <= ST_NACK_LOW;
                        end else begin
                            bit_cnt <= bit_cnt - 1'b1;
                            state <= ST_READ_LOW;
                        end
                    end
                end
                ST_NACK_LOW: begin
                    if (tick) begin
                        i2c_scl <= 1'b0;
                        sda_oe_low <= 1'b0;              // NACK = release SDA
                        state <= ST_NACK_HIGH;
                    end
                end
                ST_NACK_HIGH: begin
                    if (tick) begin
                        i2c_scl <= 1'b1;
                        state <= ST_STOP_A;
                    end
                end
                ST_STOP_A: begin
                    if (tick) begin
                        sda_oe_low <= 1'b1;
                        i2c_scl <= 1'b1;
                        state <= ST_STOP_B;
                    end
                end
                ST_STOP_B: begin
                    if (tick) begin
                        sda_oe_low <= 1'b0;              // SDA rises while SCL high
                        state <= ST_DONE;
                    end
                end
                ST_DONE: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    custom_temp_data_o <= rx_reg;
                    custom_temp_valid_o <= 1'b1;
                    state <= ST_IDLE;
                end
                default: state <= ST_IDLE;
            endcase
        end
    end

    always @(*) begin
        data_o = `ZeroWord;
        case (addr_i[23:16])
            REG_CTRL: data_o = {29'h0, done, busy, 1'b0};
            REG_ADDR: data_o = {25'h0, slave_addr};
            REG_TX:   data_o = tx_reg;
            REG_RX:   data_o = {24'h0, rx_reg};
            default:  data_o = `ZeroWord;
        endcase
    end

endmodule
