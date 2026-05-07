`include "../../../../Reference/tinyriscv-master/rtl/core/defines.v"

module integrated_file
(
    input wire clk,
    input wire rst,

    input wire start,
    output wire ready,

    input wire[`RegBus] rs1_i,
    input wire[`RegBus] rx31_i,
    input wire[11:0] imm_i,
    input wire[`RegAddrBus] reg_waddr_i, // 运算结束后需要写的寄存器

    input wire[`MemBus] mem_rdata_i,        // 内存输入数据

    output reg[`MemBus] mem_wdata_o,        // 写内存数据
    output reg[`MemAddrBus] mem_raddr_o,    // 读内存地址
    output reg[`MemAddrBus] mem_waddr_o,    // 写内存地址
    output reg mem_we_o,                   // 是否要写内存
    output reg mem_req_o,                  // 请求访问内存标志

    output reg reg_we_o,
    output reg[`RegBus] reg_wdata_o,
    output reg[`RegAddrBus] reg_waddr_o
);


localparam [`MemAddrBus] UART0_STATE_ADDR  = 'h30000000+'h4;
localparam [`MemAddrBus] UART0_TXDATA_ADDR = 'h30000000+'hc;

localparam [1:0] STATE_IDLE        = 2'd0;
localparam [1:0] STATE_READ_STATE  = 2'd1;
localparam [1:0] STATE_CHECK_READY = 2'd2;

reg [1:0] state;
reg [`RegBus] rs1_data;

assign ready=(state==STATE_IDLE);

always @(posedge clk) begin
    if (rst == `RstEnable) begin
        state<=STATE_IDLE;
        mem_wdata_o<=`ZeroWord;
        mem_raddr_o<=`ZeroWord;
        mem_waddr_o<=`ZeroWord;
        mem_we_o   <=`WriteDisable;
        mem_req_o  <=`RIB_NREQ;
        reg_we_o   <=`WriteDisable;
        reg_wdata_o<=`ZeroWord;
        reg_waddr_o<=`ZeroWord;
        rs1_data<=`ZeroWord;
    end
    else begin
        case(state)
        STATE_IDLE:begin
            if(start==`True) begin
                if(imm_i==12'd0) begin
                    if(rs1_i>=rx31_i) begin         
                        state<=STATE_READ_STATE;
                        reg_we_o   <=`WriteDisable;
                        reg_wdata_o<=`ZeroWord;
                        reg_waddr_o<=`ZeroWord;
                        rs1_data<=rs1_i;
                    end
                    else begin
                        reg_we_o<=`WriteEnable;
                        reg_wdata_o<=rs1_i;
                        reg_waddr_o<=reg_waddr_i;
                    end
                end
                else begin
                    reg_we_o<=`WriteEnable;
                    reg_wdata_o<=rs1_i+$signed(imm_i[11:0]);
                    reg_waddr_o<=reg_waddr_i;
                end
            end
            else begin
                mem_wdata_o<=`ZeroWord;
                mem_raddr_o<=`ZeroWord;
                mem_waddr_o<=`ZeroWord;
                mem_we_o   <=`WriteDisable;
                mem_req_o  <=`RIB_NREQ;
                reg_we_o   <=`WriteDisable;
                reg_wdata_o<=`ZeroWord;
                reg_waddr_o<=`ZeroWord;
            end
        end
        STATE_READ_STATE:begin
            mem_raddr_o<=UART0_STATE_ADDR;
            mem_req_o<=`RIB_REQ;
            state<=STATE_CHECK_READY;
        end
        STATE_CHECK_READY:begin
            if(mem_rdata_i[0] != 1)begin
                mem_wdata_o<=rs1_data;
                mem_raddr_o<=`ZeroWord;
                mem_waddr_o<=UART0_TXDATA_ADDR;
                mem_we_o<=`WriteEnable;
                mem_req_o<=`RIB_REQ;

                reg_we_o<=`WriteEnable;
                reg_wdata_o<=0;
                reg_waddr_o<=reg_waddr_i;
                state<=STATE_IDLE;
            end
            else begin
                mem_raddr_o<=UART0_STATE_ADDR;
                mem_req_o<=`RIB_REQ;
            end
        end
        default:begin
            state<=STATE_IDLE;
            mem_wdata_o<=`ZeroWord;
            mem_raddr_o<=`ZeroWord;
            mem_waddr_o<=`ZeroWord;
            mem_we_o   <=`WriteDisable;
            mem_req_o  <=`RIB_NREQ;
            reg_we_o   <=`WriteDisable;
            reg_wdata_o<=`ZeroWord;
            reg_waddr_o<=`ZeroWord;
        end
        endcase
    end
end




endmodule

