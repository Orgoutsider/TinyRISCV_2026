`include "defines.v"

module send_id(
    input wire clk,
    input wire rst,

    input wire send_start,
    input wire uart_read,

    output reg[`MemBus] si_wdata,
    output reg[`MemAddrBus] si_waddr,
    output reg[`MemAddrBus] si_raddr,
    output reg si_we,
    output reg si_req,
    output reg si_hold_flag
//    output reg si_busy // 1 - busy
    );

    //// Parameters
    // States
    localparam STATE_IDLE = 0;
    localparam STATE_TXDATA = 1;
    localparam STATE_READ_STATUS = 2;
    localparam STATE_JUDGE = 3;

    // Write address
    localparam UART_ADDR = 4'h3; // Uart addr: addr[31:28]
    localparam CTRL_ADDR = 8'h0; // addr[7:0]
    localparam STATUS_ADDR = 8'h4;
    localparam TXDATA_ADDR = 8'hc;

    // Write data (ID)
    localparam ONE = 8'd50; // '2' 
    localparam TWO = 8'd48; // '0'
    localparam THREE = 8'd50; // '2'
    localparam FOUR = 8'd52; // '4'
    localparam FIVE = 8'd50; // '2'
    localparam SIX = 8'd49; // '1'
    localparam SEVEN = 8'd48; // '0'
    localparam EIGHT = 8'd57; // '9'
    localparam NINE = 8'd56; // '8'
    localparam TEN = 8'd56; // '8' 


    //// Regs
    reg[1:0] state; // Every send needs at least 2 stages
    reg[3:0] cnt; // Send 10 times


    //// Logic
    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
            state <= STATE_IDLE;
            cnt <= 0;
            si_wdata <= 0;
            si_waddr <= 0;
            si_raddr <= 0;
            si_we <= 0;
            si_req <= 0;
            si_hold_flag <= 0;
 //           si_busy <= 0;
        end else begin
            case (state)
                STATE_IDLE: begin // Idle state
                    si_wdata <= 0;
                    si_waddr <= 0;
                    si_raddr <= 0;
                    si_we <= 0;
                    si_req <= 0;
                    si_hold_flag <= 0;
                    if (send_start) begin
                        state <= STATE_TXDATA;
                    end
                end
                // STATE_CTRL: begin // Set UART control
                //     si_wdata <= {{31'd0}, {1'b1}};
                //     si_waddr <= {{UART_ADDR}, {20'd0}, {CTRL_ADDR}};
                //     state <= STATE_TXDATA;
                // end
                STATE_TXDATA: begin // Set UART TX data
                    si_we <= 1;
                    si_req <= 1;
                    si_hold_flag <= 1;
                    case (cnt)
                        0: si_wdata <= {{24'd0}, {ONE}};
                        1: si_wdata <= {{24'd0}, {TWO}};
                        2: si_wdata <= {{24'd0}, {THREE}};
                        3: si_wdata <= {{24'd0}, {FOUR}};
                        4: si_wdata <= {{24'd0}, {FIVE}};
                        5: si_wdata <= {{24'd0}, {SIX}};
                        6: si_wdata <= {{24'd0}, {SEVEN}};
                        7: si_wdata <= {{24'd0}, {EIGHT}};
                        8: si_wdata <= {{24'd0}, {NINE}};
                        9: si_wdata <= {{24'd0}, {TEN}}; 
                    endcase
                    si_waddr <= {{UART_ADDR}, {20'd0}, {TXDATA_ADDR}};
                    state <= STATE_READ_STATUS;
                end
                // STATE_RESET_CTRL: begin // Reset UART control
                //     si_wdata <= 0;
                //     si_waddr <= {{UART_ADDR}, {20'd0}, {CTRL_ADDR}};
                //     si_raddr <= {{UART_ADDR}, {20'd0}, {STATUS_ADDR}};
                //     si_we <= 0;
                //     state <= STATE_READ_STATUS;
                // end
                STATE_READ_STATUS: begin
                    si_raddr <= {{UART_ADDR}, {20'd0}, {STATUS_ADDR}};
                    si_we <= 0;
                    si_req <= 1;
                    si_hold_flag <= 1;
                    state <= STATE_JUDGE;
                end
                STATE_JUDGE: begin
                    if (uart_read == 1'b0) begin // uart is not busy
                        if (cnt == 9) begin // Finish
                            cnt <= 0;
//                            si_busy <= 0;
                            // si_req <= 0;
                            // si_we <= 0;
                            // si_hold_flag <= 0;
                            state <= STATE_IDLE;
                        end else begin
                            cnt <= cnt + 1;
                            state <= STATE_TXDATA;
                        end
                    end
                end
            endcase
        end
    end



endmodule