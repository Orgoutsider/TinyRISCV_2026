`include "../../../../Reference/tinyriscv-master/rtl/core/defines.v"

module extend_inst
(
    input wire clk,
    input wire rst,

    // frome ex
    input wire [6:0] opcode,
    input wire [2:0] funct3,
    input wire[`RegBus] rs1_i,
    input wire[`RegBus] rx31_i,
    input wire[11:0] imm_i,
    input wire[`RegAddrBus] reg_waddr_i,    //运算结束后需要写的寄存器
    input wire[`MemBus] mem_rdata_i,        //内存输入数据
    input wire[`MemAddrBus] jump_addr_i,    //下一条指令地址

    // to ex
    output reg hold_flag_o,
    output reg jump_flag_o,
    output reg[`MemAddrBus] jump_addr_o,
    output wire[`MemBus] mem_wdata_o,        // 写内存数据
    output wire[`MemAddrBus] mem_raddr_o,    // 读内存地址
    output wire[`MemAddrBus] mem_waddr_o,    // 写内存地址
    output wire  mem_we_o,                   // 是否要写内存
    output wire  mem_req_o,                  // 请求访问内存标志
    output wire  reg_we_o,
    output wire[`RegBus] reg_wdata_o,
    output wire[`RegAddrBus] reg_waddr_o
);

reg RT_start;
wire RT_ready;
wire [`RegAddrBus] RT_reg_waddr_i;
wire [`MemBus] RT_mem_rdata_i;
wire [`MemBus] RT_mem_wdata_o;        
wire [`MemAddrBus] RT_mem_raddr_o;    
wire [`MemAddrBus] RT_mem_waddr_o;    
wire RT_mem_we_o;       
wire RT_mem_req_o;          
wire RT_reg_we_o;
wire [`RegBus] RT_reg_wdata_o;
wire [`RegAddrBus] RT_reg_waddr_o;

reg SEND_start;
wire SEND_ready;
wire [`MemBus] SEND_mem_rdata_i;
wire [`MemBus] SEND_mem_wdata_o;        
wire [`MemAddrBus] SEND_mem_raddr_o;    
wire [`MemAddrBus] SEND_mem_waddr_o;    
wire SEND_mem_we_o;       
wire SEND_mem_req_o;          


reg IF_start;
wire IF_ready;
wire [`RegAddrBus] IF_reg_waddr_i;
wire [`MemBus] IF_mem_rdata_i;
wire [`MemBus] IF_mem_wdata_o;        
wire [`MemAddrBus] IF_mem_raddr_o;    
wire [`MemAddrBus] IF_mem_waddr_o;    
wire IF_mem_we_o;       
wire IF_mem_req_o;          
wire IF_reg_we_o;
wire [`RegBus] IF_reg_wdata_o;
wire [`RegAddrBus] IF_reg_waddr_o;

assign SEND_mem_rdata_i=mem_rdata_i;
assign IF_mem_rdata_i=mem_rdata_i;
assign RT_mem_rdata_i=mem_rdata_i;
assign RT_reg_waddr_i=reg_waddr_i;
assign IF_reg_waddr_i=reg_waddr_i;

assign mem_wdata_o  =RT_mem_wdata_o | SEND_mem_wdata_o | IF_mem_wdata_o ; 
assign mem_raddr_o  =RT_mem_raddr_o | SEND_mem_raddr_o | IF_mem_raddr_o ;
assign mem_waddr_o  =RT_mem_waddr_o | SEND_mem_waddr_o | IF_mem_waddr_o ;
assign mem_we_o     =RT_mem_we_o    | SEND_mem_we_o    | IF_mem_we_o    ;
assign mem_req_o    =RT_mem_req_o   | SEND_mem_req_o   | IF_mem_req_o   ;
assign reg_we_o     =RT_reg_we_o    | IF_reg_we_o    ;
assign reg_wdata_o  =RT_reg_wdata_o | IF_reg_wdata_o ;
assign reg_waddr_o  =RT_reg_waddr_o | IF_reg_waddr_o ;

always @(*) begin
    RT_start=`False;
    SEND_start=`False;
    IF_start=`False;
    hold_flag_o=`HoldDisable;
    jump_flag_o=`JumpDisable;
    jump_addr_o=`ZeroWord;
    
    if(opcode==`INST_TYPE_EXTEND) begin
        hold_flag_o=`HoldEnable;
        jump_flag_o=`JumpEnable;
        case(funct3)
        `INST_SEND_ID:begin 
            SEND_start=`True;
            IF_start=`False;
            RT_start=`False;
            jump_addr_o=jump_addr_i;
        end
        `INST_INTEGRATED_FIRE:begin 
            SEND_start=`False;
            IF_start=`True;
            RT_start=`False;
            jump_addr_o=jump_addr_i;
        end
        `INST_READ_TEMPERATURE:begin 
            SEND_start=`False;
            IF_start=`False;
            RT_start=`True;
            jump_addr_o=jump_addr_i;
        end
        default:begin
            RT_start=`False;
            SEND_start=`False;
            IF_start=`False;
            hold_flag_o=`HoldDisable;
            jump_flag_o=`JumpDisable;
            jump_addr_o=`ZeroWord;
        end
        endcase
    end
    else begin
        RT_start=`False;
        SEND_start=`False;
        IF_start=`False;
        jump_flag_o=`JumpDisable;
        jump_addr_o=`ZeroWord;
        if(RT_ready && SEND_ready && IF_ready) begin
            hold_flag_o=`HoldDisable;
        end
        else begin
            hold_flag_o=`HoldEnable;
        end
    end
end

read_temperature read_temperature_inst
(
    .clk(clk),
    .rst(rst),
    .start(RT_start),
    .ready(RT_ready),
    .reg_waddr_i(RT_reg_waddr_i),
    .mem_rdata_i(RT_mem_rdata_i),
    .mem_wdata_o(RT_mem_wdata_o),        
    .mem_raddr_o(RT_mem_raddr_o),    
    .mem_waddr_o(RT_mem_waddr_o),    
    .mem_we_o(RT_mem_we_o),                    
    .mem_req_o(RT_mem_req_o),                  
    .reg_we_o(RT_reg_we_o),
    .reg_wdata_o(RT_reg_wdata_o),
    .reg_waddr_o(RT_reg_waddr_o)
);

integrated_file integrated_file_inst
(
    .clk(clk),
    .rst(rst),
    .start(IF_start),
    .ready(IF_ready),
    .rs1_i(rs1_i),
    .rx31_i(rx31_i),
    .imm_i(imm_i),
    .reg_waddr_i(IF_reg_waddr_i),
    .mem_rdata_i(IF_mem_rdata_i),
    .mem_wdata_o(IF_mem_wdata_o),        
    .mem_raddr_o(IF_mem_raddr_o),    
    .mem_waddr_o(IF_mem_waddr_o),    
    .mem_we_o(IF_mem_we_o),                    
    .mem_req_o(IF_mem_req_o),                  
    .reg_we_o(IF_reg_we_o),
    .reg_wdata_o(IF_reg_wdata_o),
    .reg_waddr_o(IF_reg_waddr_o)
);

Send_ID Send_ID_inst
(
    .clk(clk),
    .rst(rst),
    .start(SEND_start),
    .ready(SEND_ready),
    .mem_rdata_i(SEND_mem_rdata_i),
    .mem_wdata_o(SEND_mem_wdata_o),        
    .mem_raddr_o(SEND_mem_raddr_o),    
    .mem_waddr_o(SEND_mem_waddr_o),    
    .mem_we_o(SEND_mem_we_o),                    
    .mem_req_o(SEND_mem_req_o)             
);


endmodule


