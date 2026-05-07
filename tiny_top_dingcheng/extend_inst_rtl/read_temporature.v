`include "../../../../Reference/tinyriscv-master/rtl/core/defines.v"

module read_temperature
(
    input wire clk,
    input wire rst,

    input wire start,
    output wire ready,

    input wire[`RegAddrBus] reg_waddr_i, // 运算结束后需要写的寄存器

    input wire[`MemBus] mem_rdata_i,        // 内存输入数据

    output reg[`MemBus] mem_wdata_o,        // 写内存数�???
    output reg[`MemAddrBus] mem_raddr_o,    // 读内存地�???
    output reg[`MemAddrBus] mem_waddr_o,    // 写内存地�???
    output reg mem_we_o,                    // 是否要写内存
    output reg mem_req_o,                    // 请求访问内存标志
    output reg reg_we_o,
    output reg[`RegBus] reg_wdata_o,
    output reg[`RegAddrBus] reg_waddr_o
);

//MODIFY ADD UART
localparam [`MemAddrBus] UART0_STATE_ADDR  = 'h30000000+'h4;
localparam [`MemAddrBus] UART0_TXDATA_ADDR = 'h30000000+'hc;

localparam [`MemAddrBus] IIC_STATE_ADDR  = 'h7000_0000;
localparam [`MemAddrBus] DEVICE_ADDR     = 'h7001_0000;
localparam [`MemAddrBus] DATA_OUT_ADDR   = 'h7002_0000;
localparam [`MemAddrBus] DATA_IN_ADDR    = 'h7003_0000;

localparam [3:0] STATE_IDLE           =3'd0;
localparam [3:0] STATE_WRITE_REG_ADDR =3'd1;
localparam [3:0] STATE_WAIT_WRITE     =3'd2;
localparam [3:0] STATE_READ_BACK      =3'd3;
localparam [3:0] STATE_WAIT_READ      =3'd4;
localparam [3:0] STATE_GET_DATA       =3'd5;
localparam [3:0] STATE_FINISH         =3'd6;
localparam [3:0] STATE_READ_STATE     =3'd7;
localparam [3:0] STATE_CHECK_READY    =3'd8;

reg [2:0] state;
reg[`RegAddrBus] reg_waddr_store;

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

        reg_waddr_store<=`ZeroWord;
    end
    else begin
        case(state)
        STATE_IDLE:begin
            if(start==`True) begin  
                mem_wdata_o<=8'b1001_0000;      //写入写寄存器的设备地�???
                mem_raddr_o<=`ZeroWord;
                mem_waddr_o<=DEVICE_ADDR;
                mem_we_o<=`WriteEnable;
                mem_req_o<=`RIB_REQ;
                reg_we_o   <=`WriteDisable;
                reg_wdata_o<=`ZeroWord;
                reg_waddr_o<=`ZeroWord;
//                state<=STATE_WRITE_REG_ADDR;
                state<=STATE_READ_BACK;
                reg_waddr_store<=reg_waddr_i;
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
                reg_waddr_store<=`ZeroWord;
            end
        end
        STATE_WRITE_REG_ADDR:begin
            mem_wdata_o<='h00;      //写入温度传感器寄存器地址
            mem_raddr_o<=`ZeroWord;
            mem_waddr_o<=DATA_OUT_ADDR;
            mem_we_o<=`WriteEnable;
            mem_req_o<=`RIB_REQ;

            state<=STATE_WAIT_WRITE;
        end
        STATE_WAIT_WRITE:begin
            mem_wdata_o<=`ZeroWord;      //读会I2C状�?�寄存器，判断是否发送完�???
            mem_raddr_o<=IIC_STATE_ADDR;
            mem_waddr_o<=`ZeroWord;
            mem_we_o<=`WriteDisable;
            mem_req_o<=`RIB_REQ;

            state<=STATE_READ_BACK;
        end
        STATE_READ_BACK:begin
            if(mem_rdata_i==`IIC_IDLE) begin
                mem_wdata_o<=`ZeroWord;  //通知I2C读寄存器，开始读回数�???
                mem_raddr_o<=`ZeroWord;
                mem_waddr_o<=DATA_IN_ADDR;
                mem_we_o<=`WriteEnable;
                mem_req_o<=`RIB_REQ;

                state<=STATE_WAIT_READ;
            end
            else begin
                mem_wdata_o<=`ZeroWord;      
                mem_raddr_o<=IIC_STATE_ADDR;
                mem_waddr_o<=`ZeroWord;
                mem_we_o<=`WriteDisable;
                mem_req_o<=`RIB_REQ;
            end
        end
        STATE_WAIT_READ:begin
            mem_wdata_o<=`ZeroWord;      //读回I2C状�?�寄存器，判断是否发送完�???
            mem_raddr_o<=IIC_STATE_ADDR;
            mem_waddr_o<=`ZeroWord;
            mem_we_o<=`WriteDisable;
            mem_req_o<=`RIB_REQ;

            state<=STATE_GET_DATA;
        end
        STATE_GET_DATA:begin
            if(mem_rdata_i==`IIC_IDLE) begin
                mem_wdata_o<=`ZeroWord;  //从I2C输入寄存器中读回数据    
                mem_raddr_o<=DATA_IN_ADDR;
                mem_waddr_o<=`ZeroWord;
                mem_we_o<=`WriteDisable;
                mem_req_o<=`RIB_REQ;

                state<=STATE_FINISH;
            end
            else begin
                mem_wdata_o<=`ZeroWord;      
                mem_raddr_o<=IIC_STATE_ADDR;
                mem_waddr_o<=`ZeroWord;
                mem_we_o<=`WriteDisable;
                mem_req_o<=`RIB_REQ;
            end
        end
        STATE_FINISH:begin
            state<=STATE_CHECK_READY;
            mem_wdata_o<=`ZeroWord;
            mem_raddr_o<=`ZeroWord;
            mem_waddr_o<=`ZeroWord;
            mem_we_o   <=`WriteDisable;
            mem_req_o  <=`RIB_NREQ;
            reg_we_o   <=`WriteEnable;
//            reg_wdata_o<=mem_rdata_i>>7;
            reg_wdata_o<=mem_rdata_i[14:7];//modify
            reg_waddr_o<=reg_waddr_store;
            reg_waddr_store<=`ZeroWord;
        end
        
        //MODIFY followed
        STATE_READ_STATE:begin
            mem_raddr_o<=UART0_STATE_ADDR;
            mem_req_o<=`RIB_REQ;
            state<=STATE_CHECK_READY;
        end
        STATE_CHECK_READY:begin
            if(mem_rdata_i[0] != 1)begin
                mem_wdata_o<=reg_wdata_o;
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
        //MODIFY aboved
        
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
            reg_waddr_store<=`ZeroWord;
        end
        endcase
    end
end


endmodule
