//`include "../core/defines.v"
//`include "defines.v"

`define     SCL_POS          (cnt==3'd0)      
`define     SCL_HIG          (cnt==3'd1)
`define     SCL_NEG          (cnt==3'd2)     
`define     SCL_LOW          (cnt==3'd3) 

module i2c(
    input wire clk,
    input wire rst,
    
    input wire we_i, //RIB interface
    input wire[31:0] addr_i, //RIB interface
    input wire[31:0] data_i, //RIB interface

    output reg[31:0] data_o, //RIB interface

    inout wire io_sda, // I2C wire for data
    output wire io_scl // I2C wire for clk sync
);

    localparam SLAVE_ADDR_ADDR = 4'h1; // 0x7001_0000
    localparam I2C_OUT_ADDR = 4'h2; // 0x7002_0000
    localparam I2C_IN_ADDR = 4'h3; // 0x7003_0000
    
    localparam LM75_ADDR = 7'b1001000; // 1 0 0 1 A2(0) A1(0) A0(0)

    // parametrers for states
    localparam STATE_IDLE = 0;
    localparam STATE_START = 1;
    localparam STATE_ADDR = 2;
    localparam STATE_ACK_ADDR = 3;
    localparam STATE_MSB = 4;
    localparam STATE_ACK_MSB = 5;
    localparam STATE_LSB = 6;
    localparam STATE_NACK_LSB = 7;
    localparam STATE_STOP = 8;


    // Regs interacting with RIB
    reg[31:0] slave_addr; // I2C slave
    reg[31:0] i2c_in; // bit_0: If read starts
    reg[31:0] i2c_out; // bit_8: If data is valid, bit_0-7: Temperataure data

    // Regs for I2C logic
    reg[7:0] cnt_delay;
    reg[2:0] cnt;
    reg[15:0] temp;

    reg[3:0] state;
    reg[7:0] bit_cnt;
    reg sda_out_en;
    reg sda_out_val;
    reg scl;
    reg[7:0] shift_reg;

    wire start_read;
     

    // Write regs
    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
            slave_addr <= 0;
            i2c_in <= 0;            
        end else begin
            if (we_i == `WriteEnable) begin
                case (addr_i[19:16])
                    SLAVE_ADDR_ADDR: begin
                        slave_addr <= data_i;
                    end
                    I2C_IN_ADDR: begin // TODO: reset i2c_in
                        i2c_in <= data_i; // Give read start sign
                    end 
                endcase
            end
        end
    end

    // Read regs
    always @ (*) begin
        if (rst == `RstEnable) begin
            data_o = `ZeroWord;
        end else begin
            case (addr_i[19:16])
                I2C_OUT_ADDR: begin
                    data_o = i2c_out;
                end
            endcase
        end
    end

    // generate I2C clk
    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
            cnt_delay <= 8'd0;
        end else begin
            if(cnt_delay == 8'd199)
                cnt_delay <= 8'd0;
            else cnt_delay <= cnt_delay+1'b1;
        end
    end

    // set cnt
    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
            cnt <= 3'd5;
        end else begin
            case (cnt_delay)
                9'd49:     cnt <= 3'd1;
                9'd99:     cnt <= 3'd2; 
                9'd149:    cnt <= 3'd3;  
                9'd199:    cnt <= 3'd0; 
                default:   cnt <= 3'd5;
            endcase
        end
    end

    // set scl
    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
            scl <= 1'b0;
        end else if (cnt==3'd0) begin
            scl <= 1'b1;
        end else if (cnt==3'd2) begin
            scl <= 1'b0;
        end
    end


    // Wiring
    assign start_read = i2c_in[0];
    assign io_sda = sda_out_en ? sda_out_val : 1'bz; // adapt to bidirectional data flow
    assign io_scl = scl;

    // Read temperataure data logic
    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
            sda_out_en <= 0;
            sda_out_val <= 1; // Initial SDA state: high
            i2c_out <= 0; // data valid sign
            state <= STATE_IDLE;
            bit_cnt <= 0;
            shift_reg <= 0;
            temp <= 0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    i2c_out <= 0;
                    sda_out_en <= 1;
                    sda_out_val <= 1; // stay high

                    if (start_read) begin // Start sign from RIB (master)
                        state <= STATE_START;
                        shift_reg <= {{slave_addr[6:0]}, {1'b1}};
                    end else begin
                        state <= STATE_IDLE;
                        shift_reg <= 0;
                        temp <= 0;
                    end
                end
                STATE_START: begin
                    if(`SCL_HIG) begin
                        sda_out_en <= 1'b1;  
                        sda_out_val <= 1'b0;        
                        state <= STATE_ADDR;
                        bit_cnt <= 0;
                    end else state <= STATE_START;
                end
                STATE_ADDR: begin
                    if(`SCL_LOW) begin
                        if (bit_cnt == 8) begin
                            bit_cnt <= 0;
                            sda_out_val <= 1'b1;
                            sda_out_en <= 1'b0;
                            state <= STATE_ACK_ADDR;
                        end else begin
                            state <= STATE_ADDR;
                            bit_cnt <= bit_cnt + 1'b1;
                            case (bit_cnt)
                                0: sda_out_val <= shift_reg[7];
                                1: sda_out_val <= shift_reg[6];
                                2: sda_out_val <= shift_reg[5];
                                3: sda_out_val <= shift_reg[4];
                                4: sda_out_val <= shift_reg[3];
                                5: sda_out_val <= shift_reg[2];
                                6: sda_out_val <= shift_reg[1];
                                7: sda_out_val <= shift_reg[0];
                                default: ;
                            endcase
                        end     
                    end else state <= STATE_ADDR;
                end
                STATE_ACK_ADDR: begin
                    if (!sda_out_val && (`SCL_HIG)) state <= STATE_MSB;
                    else if (`SCL_NEG) state <= STATE_MSB;
                    else state <= STATE_ACK_ADDR;
                end
                STATE_MSB: begin
                    if (`SCL_HIG) begin
                        bit_cnt <= bit_cnt + 1'b1;
                        case (bit_cnt)
                            0: temp[15] <= io_sda;
                            1: temp[14] <= io_sda;
                            2: temp[13] <= io_sda;
                            3: temp[12] <= io_sda;
                            4: temp[11] <= io_sda;
                            5: temp[10] <= io_sda;
                            6: temp[9] <= io_sda;
                            7: temp[8] <= io_sda;
                            default: ;
                        endcase
                    end else if ((`SCL_NEG) && (bit_cnt == 8)) begin
                        bit_cnt <= 0;
                        sda_out_en <= 1'b1;
                        sda_out_val <= 1'b1;
                        state <= STATE_ACK_MSB;
                    end else state <= STATE_MSB;
                end
                STATE_ACK_MSB: begin
                    if (`SCL_LOW) sda_out_val <= 1'b0;
                    else if (`SCL_NEG) begin
                        state <= STATE_LSB;
                        sda_out_en <= 1'b0;
                        sda_out_val <= 1'b1;
                    end else state <= STATE_ACK_MSB;
                end
                STATE_LSB: begin
                    if (`SCL_HIG) begin
                        bit_cnt <= bit_cnt + 1'b1;
                        case (bit_cnt)
                            0: temp[7] <= io_sda;
                            1: temp[6] <= io_sda;
                            2: temp[5] <= io_sda;
                            3: temp[4] <= io_sda;
                            4: temp[3] <= io_sda;
                            5: temp[2] <= io_sda;
                            6: temp[1] <= io_sda;
                            7: temp[0] <= io_sda;
                            default: ;
                        endcase
                    end else if ((`SCL_LOW) && (bit_cnt == 8)) begin
                        bit_cnt <= 0;
                        sda_out_en <= 1'b1;
                        sda_out_val <= 1'b1;
                        state <= STATE_NACK_LSB;

                        //data is valid
                        i2c_out <= {{23'd0}, {1'b1}, {temp[14:7]}};
                    end else state <= STATE_LSB;
                end
                STATE_NACK_LSB: begin
                    if (`SCL_LOW) begin
                        sda_out_val <= 1'b0;
                        state <= STATE_STOP;
                    end else state <= STATE_NACK_LSB;
                end
                STATE_STOP: begin
                    if (`SCL_HIG) begin
                        sda_out_val <= 1'b1;
                        state <= STATE_IDLE;
                    end else state <= STATE_STOP;
                end
                default: state <= STATE_IDLE;           
            endcase
        end
    end




endmodule