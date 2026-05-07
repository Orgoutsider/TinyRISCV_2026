//`include "../core/defines.v"
//`include "defines.v"

module pwm(
    input wire clk,
    input wire rst,

    input wire we_i, //RIB interface
    input wire[31:0] addr_i, //RIB interface
    input wire[31:0] data_i, //RIB interface

    output reg[31:0] data_o, //RIB interface
    
    output wire[3:0] PWM_o

    );

    // addr[23:20]
    localparam AC_ADDR = 4'h0; // regs A/C address offset 
    localparam B_ADDR = 4'h1; // regs B address offset

    // addr[19:16]
    localparam A0_ADDR = 4'h0; // reg A0 address offset
    localparam A1_ADDR = 4'h1; // reg A1 address offset
    localparam A2_ADDR = 4'h2; // reg A2 address offset
    localparam A3_ADDR = 4'h3; // reg A3 address offset
    localparam C_ADDR = 4'h4; // reg C address offset
    localparam B0_ADDR = 4'h0; // reg B0 address offset
    localparam B1_ADDR = 4'h1; // reg B1 address offset
    localparam B2_ADDR = 4'h2; // reg B2 address offset
    localparam B3_ADDR = 4'h3; // reg B3 address offset

    localparam TIMER_WIDTH = 32; // width of reg A, B (same as width of input data)

    // regs for rib write/read
    // addr: 0x6000_0000 -> 0x6003_0000
    reg[TIMER_WIDTH - 1:0] A0;
    reg[TIMER_WIDTH - 1:0] A1;
    reg[TIMER_WIDTH - 1:0] A2;
    reg[TIMER_WIDTH - 1:0] A3;

    // addr: 0x6004_0000
    reg[31:0] C; // same width with width of input data, actual width is 4

    // addr: 0x6010_0000 -> 0x6013_0000
    reg[TIMER_WIDTH - 1:0] B0;
    reg[TIMER_WIDTH - 1:0] B1;
    reg[TIMER_WIDTH - 1:0] B2;
    reg[TIMER_WIDTH - 1:0] B3;

    // regs for PWM logic
    reg[TIMER_WIDTH - 1:0] counter[0:3];
    reg[3:0] out;

    
    // Write regs
    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
            A0 <= {(TIMER_WIDTH){1'b0}};
            A1 <= {(TIMER_WIDTH){1'b0}};
            A2 <= {(TIMER_WIDTH){1'b0}};
            A3 <= {(TIMER_WIDTH){1'b0}};
            C <= {(TIMER_WIDTH){1'b0}};
            B0 <= {(TIMER_WIDTH){1'b0}};
            B1 <= {(TIMER_WIDTH){1'b0}};
            B2 <= {(TIMER_WIDTH){1'b0}};
            B3 <= {(TIMER_WIDTH){1'b0}};
        end else begin
            if(we_i == `WriteEnable) begin
                case (addr_i[23:20])
                    AC_ADDR: begin
                        case (addr_i[19:16])
                            A0_ADDR: begin
                                A0 <= data_i;
                            end
                            A1_ADDR: begin
                                A1 <= data_i;
                            end
                            A2_ADDR: begin
                                A2 <= data_i;
                            end
                            A3_ADDR: begin
                                A3 <= data_i;
                            end
                            C_ADDR: begin
                                C <= data_i;
                            end
                        endcase
                    end 
                    B_ADDR: begin
                        case (addr_i[19:16])
                            B0_ADDR: begin
                                B0 <= data_i;
                            end
                            B1_ADDR: begin
                                B1 <= data_i;
                            end
                            B2_ADDR: begin
                                B2 <= data_i;
                            end
                            B3_ADDR: begin
                                B3 <= data_i;
                            end
                        endcase
                    end 
                endcase
            end else begin
                
            end
        end
    end

    // Read regs
    always @ (*) begin
        if (rst == `RstEnable) begin
            data_o = `ZeroWord;
        end else begin
            case (addr_i[23:20])
                AC_ADDR: begin
                    case (addr_i[19:16])
                        A0_ADDR: begin
                            data_o = A0;
                        end
                        A1_ADDR: begin
                            data_o = A1;
                        end
                        A2_ADDR: begin
                            data_o = A2;
                        end
                        A3_ADDR: begin
                            data_o = A3;
                        end
                        C_ADDR: begin
                            data_o = C;
                        end
                    endcase
                end 
                B_ADDR: begin
                    case (addr_i[19:16])
                        B0_ADDR: begin
                            data_o = B0;
                        end
                        B1_ADDR: begin
                            data_o = B1;
                        end
                        B2_ADDR: begin
                            data_o = B2;
                        end
                        B3_ADDR: begin
                            data_o = B3;
                        end
                    endcase
                end 
            endcase
        end
    end

    // PWM logic
    assign PWM_o = out;

    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
            counter[0] <= {(TIMER_WIDTH){1'b0}};
            counter[1] <= {(TIMER_WIDTH){1'b0}};
            counter[2] <= {(TIMER_WIDTH){1'b0}};
            counter[3] <= {(TIMER_WIDTH){1'b0}};
            out <= 4'd0;
        end else begin
            if (C[0]) begin // output0
                if (counter[0] < B0 - 1) begin
                    out[0] <= 1'b1;
                    counter[0] <= counter[0] + 1;
                end else if (counter[0] < A0 - 1) begin
                    out[0] <= 1'b0;
                    counter[0] <= counter[0] + 1;
                end else if (counter[0] == A0 - 1) begin
                    out[0] <= 1'b1;
                    counter[0] <= 0;
                end else begin //wrong case
                    out[0] <= 1'b0;
                    counter[0] <= 0;
                end
            end else begin
                out[0] <= 0;
            end
            if (C[1]) begin // output1
                if (counter[1] < B1 - 1) begin
                    out[1] <= 1'b1;
                    counter[1] <= counter[1] + 1;
                end else if (counter[1] < A1 - 1) begin
                    out[1] <= 1'b0;
                    counter[1] <= counter[1] + 1;
                end else if (counter[1] == A1 - 1) begin
                    out[1] <= 1'b1;
                    counter[1] <= 0;
                end else begin //wrong case
                    out[1] <= 1'b0;
                    counter[1] <= 0;
                end
            end else begin
                out[1] <= 0;
            end
            if (C[2]) begin // output2
                if (counter[2] < B2 - 1) begin
                    out[2] <= 1'b1;
                    counter[2] <= counter[2] + 1;
                end else if (counter[2] < A2 - 1) begin
                    out[2] <= 1'b0;
                    counter[2] <= counter[2] + 1;
                end else if (counter[2] == A2 - 1) begin
                    out[2] <= 1'b1;
                    counter[2] <= 0;
                end else begin //wrong case
                    out[2] <= 1'b0;
                    counter[2] <= 0;
                end
            end else begin
                out[2] <= 0;
            end
            if (C[3]) begin // output3
                if (counter[3] < B3 - 1) begin
                    out[3] <= 1'b1;
                    counter[3] <= counter[3] + 1;
                end else if (counter[3] < A3 - 1) begin
                    out[3] <= 1'b0;
                    counter[3] <= counter[3] + 1;
                end else if (counter[3] == A3 - 1) begin
                    out[3] <= 1'b1;
                    counter[3] <= 0;
                end else begin //wrong case
                    out[3] <= 1'b0;
                    counter[3] <= 0;
                end
            end else begin
                out[3] <= 0;
            end
        end
    end


endmodule