`include "defines.v"

module i2c_ctrl(
    input clk,
    input rst,
    
    input i2c_start,
    
    output reg[`MemBus] i2c_wdata,
    output reg[`MemAddrBus] i2c_waddr,

    output reg i2c_busy 
    );

    //// Parameters
    // States
    localparam STATE_IDLE = 0;
    localparam STATE_SLAVE_ADDR = 1;
    localparam STATE_DATA = 2;
    localparam STATE_RESET = 3;
    
    // Write address
    localparam I2C_ADDR = 4'h7; // I2C addr: addr[31:28]
    localparam SLAVE_ADDR_ADDR = 4'h1; // addr[7:0]
    localparam OUT_DATA_ADDR = 4'h2;
    localparam IN_DATA_ADDR = 4'h3;

    // LM75 address
    localparam LM75_ADDR = 7'b1001000; // 1 0 0 1 A2(0) A1(0) A0(0)

    /// Regs
    reg[1:0] state;

    /// Logic
    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
            state <= STATE_IDLE;
            i2c_wdata <= 0;
            i2c_waddr <= 0;
            i2c_busy <= 0;
        end else begin
            case (state)
                STATE_IDLE: begin // Idle state
                    i2c_wdata <= 0;
                    i2c_waddr <= 0;
                    if (i2c_start) begin
                        i2c_busy <= 1'b1;
                        state <= STATE_SLAVE_ADDR;
                    end
                end
                STATE_SLAVE_ADDR: begin // Send slave address
                    i2c_wdata <= {{25'd0}, {LM75_ADDR}};
                    i2c_waddr <= {{I2C_ADDR}, {8'd0}, {SLAVE_ADDR_ADDR}, {16'd0}};
                    state <= STATE_DATA;
                end
                STATE_DATA: begin  // Send start sign
                    i2c_wdata <= {{31'd0}, {1'b1}};
                    i2c_waddr <= {{I2C_ADDR}, {8'd0}, {IN_DATA_ADDR}, {16'd0}};
                    state <= STATE_RESET;
                end
                STATE_RESET: begin // Reset start sign, avoid triggering again
                    i2c_wdata <= 32'd0;
                    i2c_waddr <= {{I2C_ADDR}, {8'd0}, {IN_DATA_ADDR}, {16'd0}};
                    state <= STATE_IDLE;
                end
            endcase
        end 
    end




endmodule