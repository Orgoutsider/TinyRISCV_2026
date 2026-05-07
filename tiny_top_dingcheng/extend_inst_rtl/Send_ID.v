//`include "defines.v"
`include "../../../../Reference/tinyriscv-master/rtl/core/defines.v"

module Send_ID
(
    input wire clk,
    input wire rst,

    input wire start,
    output wire ready,

    input wire[`MemBus] mem_rdata_i,        // 内存输入数据

    output reg[`MemBus] mem_wdata_o,        // 写内存数据
    output reg[`MemAddrBus] mem_raddr_o,    // 读内存地址
    output reg[`MemAddrBus] mem_waddr_o,    // 写内存地址
    output reg mem_we_o,                   // 是否要写内存
    output reg mem_req_o                  // 请求访问内存标志
);

localparam [`MemAddrBus] UART0_STATE_ADDR  = 'h3000_0000+'h4;
localparam [`MemAddrBus] UART0_TXDATA_ADDR = 'h3000_0000+'hc;

localparam [1:0] STATE_IDLE         = 2'd0;
localparam [1:0] STATE_READ_STATE   = 2'd1;
localparam [1:0] STATE_CHECK_READY  = 2'd2;


reg [1:0] state;
reg [3:0] count;

assign ready=(state==STATE_IDLE);

always @(posedge clk) begin
    if (rst == `RstEnable) begin
        state<=STATE_IDLE;
        count<=4'd0;  
    end
    else begin
        case(state)
        STATE_IDLE:begin
            if(start == `True) begin
                state<=STATE_CHECK_READY;
                count<=4'd0;
                mem_wdata_o<=`ZeroWord;
                mem_raddr_o<=UART0_STATE_ADDR;
                mem_waddr_o<=`ZeroWord;
                mem_we_o   <=`WriteDisable;
                mem_req_o<=`RIB_REQ;
            end
            else begin
                state<=STATE_IDLE;
                count<=4'd0;
                mem_wdata_o<=`ZeroWord;
                mem_raddr_o<=`ZeroWord;
                mem_waddr_o<=`ZeroWord;
                mem_we_o   <=`WriteDisable;
                mem_req_o  <=`RIB_NREQ;
            end
        end
        STATE_READ_STATE:begin
            state<=STATE_CHECK_READY;
            count<=count;
            mem_wdata_o<=`ZeroWord;
            mem_raddr_o<=UART0_STATE_ADDR;
            mem_waddr_o<=`ZeroWord;
            mem_we_o   <=`WriteDisable;
            mem_req_o<=`RIB_REQ;
        end
        STATE_CHECK_READY:begin
            if( mem_rdata_i[0] != 1 )begin
                if(count<4'd10) begin
                    state<=STATE_READ_STATE;
                    count<=count+4'd1;
                    mem_wdata_o<=return_id(count);
                    mem_raddr_o<=`ZeroWord;
                    mem_waddr_o<=UART0_TXDATA_ADDR;
                    mem_we_o<=`WriteEnable;
                    mem_req_o<=`RIB_REQ;             
                end
                else begin
                    count<=count;
                    state<=STATE_IDLE;
                    mem_wdata_o<=`ZeroWord;
                    mem_raddr_o<=`ZeroWord;
                    mem_waddr_o<=`ZeroWord;
                    mem_we_o   <=`WriteDisable;
                    mem_req_o  <=`RIB_NREQ;
                end
            end
            else begin
                count<=count;
                state<=state;
                mem_wdata_o<=`ZeroWord;
                mem_raddr_o<=UART0_STATE_ADDR;
                mem_waddr_o<=`ZeroWord;
                mem_we_o   <=`WriteDisable;
                mem_req_o<=`RIB_REQ;
            end
        end
        default:begin
            count<=4'd0;
            state<=STATE_IDLE;
            mem_wdata_o<=`ZeroWord;
            mem_raddr_o<=`ZeroWord;
            mem_waddr_o<=`ZeroWord;
            mem_we_o   <=`WriteDisable;
            mem_req_o  <=`RIB_NREQ;         
        end
        endcase
    end
end


function [`MemBus] return_id(input [3:0] index);
    case(index)
    4'd0:return_id=48+2;
    4'd1:return_id=48+0;
    4'd2:return_id=48+2;
    4'd3:return_id=48+4;
    4'd4:return_id=48+3;
    4'd5:return_id=48+1;
    4'd6:return_id=48+0;
    4'd7:return_id=48+7;
    4'd8:return_id=48+7;
    4'd9:return_id=48+5;
    default:return_id=0;
    endcase
endfunction


endmodule
