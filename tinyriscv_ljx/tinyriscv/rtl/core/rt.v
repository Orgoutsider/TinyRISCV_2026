`include "defines.v"

module rt(
    input wire clk,
    input wire rst,

    input wire rt_start,
    input wire[`RegAddrBus] rd,
    input wire[`MemBus] i2c_out,

    // Interact with RIB
    output reg rt_we,
    output reg rt_req,
    output reg rt_hold_flag,
    output reg[`MemAddrBus] rt_raddr,
    output reg[`MemAddrBus] rt_waddr,
    output reg[`MemBus] rt_wdata,

    // Interact with regs
    output reg rt_reg_we,
    output reg[`RegBus] rt_reg_wdata,
    output reg[`RegAddrBus] rt_reg_waddr
);

    //// Parameters
    // States
    localparam STATE_IDLE = 0;
    localparam STATE_START_I2C = 1;
    localparam STATE_RESET_I2C = 2;
    localparam STATE_READ_I2C = 3;
    localparam STATE_WB = 4;


    // Write address
    localparam I2C_ADDR = 4'h7; // I2C addr: addr[31:28]
    localparam SLAVE_ADDR_ADDR = 4'h1; // addr[7:0]
    localparam OUT_DATA_ADDR = 4'h2;
    localparam IN_DATA_ADDR = 4'h3;

    // LM75 address
    localparam LM75_ADDR = 7'b1001000; // 1 0 0 1 A2(0) A1(0) A0(0)

    //// Regs
    reg[2:0] state;

    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
            state <= STATE_IDLE;

            rt_we <= `WriteDisable;
            rt_req <= `RIB_NREQ;
            rt_hold_flag <= `HoldDisable;
            rt_raddr <= `ZeroWord;
            rt_waddr <= `ZeroWord;
            rt_wdata <= `ZeroWord;

            rt_reg_we <= 1'b0;
            rt_reg_wdata <= `ZeroWord;
            rt_reg_waddr <= `ZeroReg;
        end else begin
            case (state)
                STATE_IDLE: begin
                    if (rt_start == 1'b1) begin
                        state <= STATE_START_I2C;

                        rt_we <= `WriteEnable; // Send I2C slave address
                        rt_req <= `RIB_REQ;
                        rt_hold_flag <= `HoldEnable;
                        rt_raddr <= `ZeroWord;
                        rt_waddr <= {{I2C_ADDR}, {8'd0}, {SLAVE_ADDR_ADDR}, {16'd0}};
                        rt_wdata <= {{25'd0}, {LM75_ADDR}};

                        rt_reg_we <= 1'b0;
                        rt_reg_wdata <= `ZeroWord;
                        rt_reg_waddr <= `ZeroReg;
                    end else begin
                        state <= STATE_IDLE;

                        rt_we <= `WriteDisable;
                        rt_req <= `RIB_NREQ;
                        rt_hold_flag <= `HoldDisable;
                        rt_raddr <= `ZeroWord;
                        rt_waddr <= `ZeroWord;
                        rt_wdata <= `ZeroWord;

                        rt_reg_we <= 1'b0;
                        rt_reg_wdata <= `ZeroWord;
                        rt_reg_waddr <= `ZeroReg;
                    end
                end
                STATE_START_I2C: begin
                    state <= STATE_RESET_I2C;

                    rt_we <= `WriteEnable; // Send I2C start sign
                    rt_req <= `RIB_REQ;
                    rt_hold_flag <= `HoldEnable;
                    rt_raddr <= `ZeroWord;
                    rt_waddr <= {{I2C_ADDR}, {8'd0}, {IN_DATA_ADDR}, {16'd0}};
                    rt_wdata <= {{31'd0}, {1'b1}};

                    rt_reg_we <= 1'b0;
                    rt_reg_wdata <= `ZeroWord;
                    rt_reg_waddr <= `ZeroReg;
                end
                STATE_RESET_I2C: begin
                    state <= STATE_READ_I2C;

                    rt_we <= `WriteEnable; // Reset start sign, avoid triggering again
                    rt_req <= `RIB_REQ;
                    rt_hold_flag <= `HoldEnable;
                    rt_raddr <= `ZeroWord;
                    rt_waddr <= {{I2C_ADDR}, {8'd0}, {IN_DATA_ADDR}, {16'd0}};
                    rt_wdata <= 32'd0;

                    rt_reg_we <= 1'b0;
                    rt_reg_wdata <= `ZeroWord;
                    rt_reg_waddr <= `ZeroReg;
                end
                STATE_READ_I2C: begin
                    state <= STATE_WB;

                    rt_we <= `WriteDisable;
                    rt_req <= `RIB_REQ;
                    rt_hold_flag <= `HoldEnable;
                    rt_raddr <= {{I2C_ADDR}, {8'd0}, {OUT_DATA_ADDR}, {16'd0}}; // read I2C status
                    rt_waddr <= `ZeroWord;
                    rt_wdata <= `ZeroWord;

                    rt_reg_we <= 1'b0;
                    rt_reg_wdata <= `ZeroWord;
                    rt_reg_waddr <= `ZeroReg;
                end
                STATE_WB: begin
                    if (i2c_out[8] == 1'b1) begin
                        state <= STATE_IDLE;

                        rt_we <= `WriteDisable;
                        rt_req <= `RIB_NREQ;
                        rt_hold_flag <= `HoldDisable;
                        rt_raddr <= `ZeroWord;
                        rt_waddr <= `ZeroWord;
                        rt_wdata <= `ZeroWord;

                        rt_reg_we <= 1'b1;
                        rt_reg_wdata <= {{24'd0},{i2c_out[7:0]}};
                        rt_reg_waddr <= rd;
                    end
                end
            endcase
        end     
    end


endmodule