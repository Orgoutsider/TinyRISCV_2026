`include "defines.v"

module iaf(
    input wire clk,
    input wire rst,

    input wire iaf_start,
    input wire[`MemAddrBus] imm,
    input wire[`MemAddrBus] xrs1,
    input wire[`RegAddrBus] rd,
    input wire[`MemAddrBus] op1_add_op2_res,
    input wire[`RegBus] reg_rdata,
    input wire uart_read,

    // Interact with RIB
    output reg iaf_we,
    output reg iaf_req,
    output reg iaf_hold_flag,
    output reg[`MemAddrBus] iaf_raddr,
    output reg[`MemAddrBus] iaf_waddr,
    output reg[`MemBus] iaf_wdata,

    //Interact with regs
    output reg iaf_reg_we,
    output reg iaf_reg_re,
    output reg[`RegBus] iaf_reg_wdata,
    output reg[`RegAddrBus] iaf_reg_waddr,
    output reg[`RegAddrBus] iaf_reg_raddr
);

    //// Parameters
    // States
    localparam STATE_IDLE = 0;
    localparam STATE_IMM_NZ = 1;
    localparam STATE_UART_TX = 2;
    localparam STATE_UART_READ_STATUS = 3;
    localparam STATE_UART_JUDGE = 4;

    // Write address
    localparam UART_ADDR = 4'h3; // Uart addr: addr[31:28]
    localparam CTRL_ADDR = 8'h0; // addr[7:0]
    localparam STATUS_ADDR = 8'h4;
    localparam TXDATA_ADDR = 8'hc;

    //// Regs
    reg[2:0] state;

    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
            state <= STATE_IDLE;
            
            iaf_we <= `WriteDisable;
            iaf_req <= `RIB_NREQ;
            iaf_hold_flag <= `HoldDisable;
            iaf_raddr <= `ZeroWord;
            iaf_waddr <= `ZeroWord;
            iaf_wdata <= `ZeroWord;

            iaf_reg_we <= 1'b0;
            iaf_reg_re <= 1'b0;
            iaf_reg_wdata <= `ZeroWord;
            iaf_reg_waddr <= `ZeroReg;
            iaf_reg_raddr <= `ZeroReg;            
        end else begin
            case (state)
                STATE_IDLE: begin
                    if (iaf_start == 1'b1) begin
                        if (imm != `ZeroWord) begin // write x[rs1]+imm
                            iaf_we <= `WriteDisable;
                            iaf_req <= `RIB_NREQ;
                            iaf_hold_flag <= `HoldEnable;
                            iaf_raddr <= `ZeroWord;
                            iaf_waddr <= `ZeroWord;
                            iaf_wdata <= `ZeroWord;

                            iaf_reg_we <= 1'b1;
                            iaf_reg_re <= 1'b0;
                            iaf_reg_wdata <= op1_add_op2_res;
                            iaf_reg_waddr <= rd;
                            iaf_reg_raddr <= `ZeroReg;
                        end else begin // imm != 0
                            state <= STATE_IMM_NZ;

                            iaf_we <= `WriteDisable;
                            iaf_req <= `RIB_NREQ;
                            iaf_hold_flag <= `HoldEnable;
                            iaf_raddr <= `ZeroWord;
                            iaf_waddr <= `ZeroWord;
                            iaf_wdata <= `ZeroWord;

                            iaf_reg_we <= 1'b0; // Read reg x31
                            iaf_reg_re <= 1'b1;
                            iaf_reg_wdata <= `ZeroWord;
                            iaf_reg_waddr <= `ZeroReg;
                            iaf_reg_raddr <= 5'd31;
                        end
                    end else begin // do not start           
                        iaf_we <= `WriteDisable;
                        iaf_req <= `RIB_NREQ;
                        iaf_hold_flag <= `HoldDisable;
                        iaf_raddr <= `ZeroWord;
                        iaf_waddr <= `ZeroWord;
                        iaf_wdata <= `ZeroWord;

                        iaf_reg_we <= 1'b0;
                        iaf_reg_re <= 1'b0;
                        iaf_reg_wdata <= `ZeroWord;
                        iaf_reg_waddr <= `ZeroReg;
                        iaf_reg_raddr <= `ZeroReg; 
                    end
                end
                STATE_IMM_NZ: begin
                    if (xrs1 < reg_rdata) begin // Write x[rs1] to x[rd]
                        state <= STATE_IDLE;

                        iaf_we <= `WriteDisable;
                        iaf_req <= `RIB_NREQ;
                        iaf_hold_flag <= `HoldEnable;
                        iaf_raddr <= `ZeroWord;
                        iaf_waddr <= `ZeroWord;
                        iaf_wdata <= `ZeroWord;

                        iaf_reg_we <= 1'b1;
                        iaf_reg_re <= 1'b0;
                        iaf_reg_wdata <= xrs1;
                        iaf_reg_waddr <= rd;
                        iaf_reg_raddr <= `ZeroReg;
                    end else begin // need to use uart
                        state <= STATE_UART_TX;

                        iaf_we <= `WriteEnable;
                        iaf_req <= `RIB_REQ;
                        iaf_hold_flag <= `HoldEnable;
                        iaf_raddr <= `ZeroWord;
                        iaf_waddr <= {{UART_ADDR}, {20'd0}, {CTRL_ADDR}}; // set uart_ctrl
                        iaf_wdata <= {{31'd0}, {1'b1}};

                        iaf_reg_we <= 1'b0;
                        iaf_reg_re <= 1'b0;
                        iaf_reg_wdata <= `ZeroWord;
                        iaf_reg_waddr <= `ZeroReg;
                        iaf_reg_raddr <= `ZeroReg;
                    end
                end
                STATE_UART_TX: begin
                    state <= STATE_UART_READ_STATUS;

                    iaf_we <= `WriteEnable;
                    iaf_req <= `RIB_REQ;
                    iaf_hold_flag <= `HoldEnable;
                    iaf_raddr <= `ZeroWord;
                    iaf_waddr <= {{UART_ADDR}, {20'd0}, {TXDATA_ADDR}}; // set uart_ctxdata
                    iaf_wdata <= xrs1[7:0];

                    iaf_reg_we <= 1'b0;
                    iaf_reg_re <= 1'b0;
                    iaf_reg_wdata <= `ZeroWord;
                    iaf_reg_waddr <= `ZeroReg;
                    iaf_reg_raddr <= `ZeroReg;
                end
                STATE_UART_READ_STATUS: begin
                    state <= STATE_UART_JUDGE;

                    iaf_we <= `WriteDisable;
                    iaf_req <= `RIB_REQ;
                    iaf_hold_flag <= `HoldEnable;
                    iaf_raddr <= {{UART_ADDR}, {20'd0}, {STATUS_ADDR}}; // set read address
                    iaf_waddr <= `ZeroWord;
                    iaf_wdata <= xrs1;

                    iaf_reg_we <= 1'b0;
                    iaf_reg_re <= 1'b0;
                    iaf_reg_wdata <= `ZeroWord;
                    iaf_reg_waddr <= `ZeroReg;
                    iaf_reg_raddr <= `ZeroReg;
                end
                STATE_UART_JUDGE: begin
                    if (uart_read == 1'b0) begin // uart is not busy
                        state <= STATE_IDLE;

                        iaf_we <= `WriteDisable;
                        iaf_req <= `RIB_NREQ;
                        iaf_hold_flag <= `HoldEnable;
                        iaf_raddr <= `ZeroWord;
                        iaf_waddr <= `ZeroWord;
                        iaf_wdata <= `ZeroWord;

                        iaf_reg_we <= 1'b1; // x[rd] = 0
                        iaf_reg_re <= 1'b0;
                        iaf_reg_wdata <= `ZeroWord;
                        iaf_reg_waddr <= rd;
                        iaf_reg_raddr <= `ZeroReg;
                    end
                end 
            endcase
        end
    end



endmodule