`include "defines.v"

module uart_ctrl(
    input wire clk,
    input wire rst,

    input wire uart_start,
    input wire[`MemAddrBus] data,
    // input wire[`MemBus] rib_rdata,

    output reg[`MemBus] uart_wdata,
    output reg[`MemAddrBus] uart_waddr,
    // output reg[`MemAddrBus] uart_raddr,
    // output reg uart_we,
    output reg uart_busy
    );

    //// Parameters
    // States
    localparam STATE_IDLE = 0;
    localparam STATE_CTRL = 1;
    localparam STATE_RESET_CTRL = 2;
    localparam STATE_TXDATA = 3;
 //   localparam STATE_READ_UART = 4;

    // Write address
    localparam UART_ADDR = 4'h3; // Uart addr: addr[31:28]
    localparam CTRL_ADDR = 8'h0; // addr[7:0]
    localparam STATUS_ADDR = 8'h4;
    localparam TXDATA_ADDR = 8'hc;

    //// Regs
    reg[1:0] state;// Every send needs at least 2 stages

    //// Logic
    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
            state <= STATE_IDLE;
            uart_wdata <= 0;
            uart_waddr <= 0;
            // uart_raddr <= 0;
            uart_busy <= 0;
            // uart_we <= 0;
        end else begin
            case (state)    
                STATE_IDLE: begin // Idle state
                    uart_wdata <= 0;
                    uart_waddr <= 0;
                    // uart_raddr <= 0;
                    if (uart_start) begin
                        uart_busy <= 1'b1;
                        // uart_we <= 1'b1;
                        state <= STATE_CTRL;
                    end
                end
                STATE_CTRL: begin // Set UART control
                    uart_wdata <= {{31'd0}, {1'b1}};
                    uart_waddr <= {{UART_ADDR}, {20'd0}, {CTRL_ADDR}};
                    state <= STATE_TXDATA;
                end
                STATE_TXDATA: begin // Set UART TX data
                    uart_wdata <= data;
                    uart_waddr <= {{UART_ADDR}, {20'd0}, {TXDATA_ADDR}};
                    state <= STATE_RESET_CTRL;
                end
                STATE_RESET_CTRL: begin // Reset UART control
                    uart_wdata <= 0;
                    uart_waddr <= {{UART_ADDR}, {20'd0}, {CTRL_ADDR}};
                    state <= STATE_IDLE;
                    // uart_raddr = {{4'h3}, {20'd0}, {8'h4}}; // Read UART status
                    // uart_we <= 1'b0;
                end
                // STATE_READ_UART: begin // read uart status
                //     if (rib_rdata[0] == 1'b0) begin // uart finishes sending data
                //         uart_busy <= 1'b0;
                //         state <= STATE_IDLE;
                //     end
                // end
            endcase
        end
    end



endmodule