 /*                                                                      
 Copyright 2020 Blue Liang, liangkangnan@163.com
                                                                         
 Licensed under the Apache License, Version 2.0 (the "License");         
 you may not use this file except in compliance with the License.        
 You may obtain a copy of the License at                                 
                                                                         
     http://www.apache.org/licenses/LICENSE-2.0                          
                                                                         
 Unless required by applicable law or agreed to in writing, software    
 distributed under the License is distributed on an "AS IS" BASIS,       
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and     
 limitations under the License.                                          
 */

`include "defines.v" // 全局宏定义

// 将译码结果向执行模块传递
module id_ex( // 模块声明

    input wire clk, // 时钟信号
    input wire rst, // 复位信号

    input wire[`InstBus] inst_i,            // 指令内容
    input wire[`InstAddrBus] inst_addr_i,   // 指令地址
    input wire reg_we_i,                    // 写通用寄存器标志
    input wire[`RegAddrBus] reg_waddr_i,    // 写通用寄存器地址
    input wire[`RegBus] reg1_rdata_i,       // 通用寄存器1读数据
    input wire[`RegBus] reg2_rdata_i,       // 通用寄存器2读数据
    input wire csr_we_i,                    // 写CSR寄存器标志
    input wire[`MemAddrBus] csr_waddr_i,    // 写CSR寄存器地址
    input wire[`RegBus] csr_rdata_i,        // CSR寄存器读数据
    input wire[`MemAddrBus] op1_i,          // 操作数1
    input wire[`MemAddrBus] op2_i,          // 操作数2
    input wire[`MemAddrBus] op1_jump_i,     // 跳转操作数1
    input wire[`MemAddrBus] op2_jump_i,     // 跳转操作数2

    input wire[`Hold_Flag_Bus] hold_flag_i, // 流水线暂停标志

    output wire[`MemAddrBus] op1_o,         // 输出操作数1
    output wire[`MemAddrBus] op2_o,         // 输出操作数2
    output wire[`MemAddrBus] op1_jump_o,    // 输出跳转操作数1
    output wire[`MemAddrBus] op2_jump_o,    // 输出跳转操作数2
    output wire[`InstBus] inst_o,            // 指令内容
    output wire[`InstAddrBus] inst_addr_o,   // 指令地址
    output wire reg_we_o,                    // 写通用寄存器标志
    output wire[`RegAddrBus] reg_waddr_o,    // 写通用寄存器地址
    output wire[`RegBus] reg1_rdata_o,       // 通用寄存器1读数据
    output wire[`RegBus] reg2_rdata_o,       // 通用寄存器2读数据
    output wire csr_we_o,                    // 写CSR寄存器标志
    output wire[`MemAddrBus] csr_waddr_o,    // 写CSR寄存器地址
    output wire[`RegBus] csr_rdata_o         // CSR寄存器读数据

    ); // 端口列表结束

    wire hold_en = (hold_flag_i >= `Hold_Id); // ID/EX暂停条件

    wire[`InstBus] inst; // 指令寄存
    gen_pipe_dff #(32) inst_ff(clk, rst, hold_en, `INST_NOP, inst_i, inst); // 指令流水寄存
    assign inst_o = inst; // 输出指令

    wire[`InstAddrBus] inst_addr; // 指令地址寄存
    gen_pipe_dff #(32) inst_addr_ff(clk, rst, hold_en, `ZeroWord, inst_addr_i, inst_addr); // 地址流水寄存
    assign inst_addr_o = inst_addr; // 输出指令地址

    wire reg_we; // 写使能寄存
    gen_pipe_dff #(1) reg_we_ff(clk, rst, hold_en, `WriteDisable, reg_we_i, reg_we); // 写使能流水寄存
    assign reg_we_o = reg_we; // 输出写使能

    wire[`RegAddrBus] reg_waddr; // 写地址寄存
    gen_pipe_dff #(5) reg_waddr_ff(clk, rst, hold_en, `ZeroReg, reg_waddr_i, reg_waddr); // 写地址流水寄存
    assign reg_waddr_o = reg_waddr; // 输出写地址

    wire[`RegBus] reg1_rdata; // 寄存器1读数寄存
    gen_pipe_dff #(32) reg1_rdata_ff(clk, rst, hold_en, `ZeroWord, reg1_rdata_i, reg1_rdata); // 读数流水寄存
    assign reg1_rdata_o = reg1_rdata; // 输出寄存器1读数

    wire[`RegBus] reg2_rdata; // 寄存器2读数寄存
    gen_pipe_dff #(32) reg2_rdata_ff(clk, rst, hold_en, `ZeroWord, reg2_rdata_i, reg2_rdata); // 读数流水寄存
    assign reg2_rdata_o = reg2_rdata; // 输出寄存器2读数

    wire csr_we; // CSR写使能寄存
    gen_pipe_dff #(1) csr_we_ff(clk, rst, hold_en, `WriteDisable, csr_we_i, csr_we); // CSR写使能流水寄存
    assign csr_we_o = csr_we; // 输出CSR写使能

    wire[`MemAddrBus] csr_waddr; // CSR写地址寄存
    gen_pipe_dff #(32) csr_waddr_ff(clk, rst, hold_en, `ZeroWord, csr_waddr_i, csr_waddr); // CSR写地址寄存
    assign csr_waddr_o = csr_waddr; // 输出CSR写地址

    wire[`RegBus] csr_rdata; // CSR读数据寄存
    gen_pipe_dff #(32) csr_rdata_ff(clk, rst, hold_en, `ZeroWord, csr_rdata_i, csr_rdata); // CSR读数寄存
    assign csr_rdata_o = csr_rdata; // 输出CSR读数

    wire[`MemAddrBus] op1; // 操作数1寄存
    gen_pipe_dff #(32) op1_ff(clk, rst, hold_en, `ZeroWord, op1_i, op1); // 操作数1寄存
    assign op1_o = op1; // 输出操作数1

    wire[`MemAddrBus] op2; // 操作数2寄存
    gen_pipe_dff #(32) op2_ff(clk, rst, hold_en, `ZeroWord, op2_i, op2); // 操作数2寄存
    assign op2_o = op2; // 输出操作数2

    wire[`MemAddrBus] op1_jump; // 跳转操作数1寄存
    gen_pipe_dff #(32) op1_jump_ff(clk, rst, hold_en, `ZeroWord, op1_jump_i, op1_jump); // 跳转操作数1寄存
    assign op1_jump_o = op1_jump; // 输出跳转操作数1

    wire[`MemAddrBus] op2_jump; // 跳转操作数2寄存
    gen_pipe_dff #(32) op2_jump_ff(clk, rst, hold_en, `ZeroWord, op2_jump_i, op2_jump); // 跳转操作数2寄存
    assign op2_jump_o = op2_jump; // 输出跳转操作数2

endmodule // 模块结束
