 /*                                                                      
 Copyright 2019 Blue Liang, liangkangnan@163.com
                                                                         
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

// 将指令向译码模块传递
module if_id( // 模块声明

    input wire clk, // 时钟信号
    input wire rst, // 复位信号

    input wire[`InstBus] inst_i,            // 指令内容
    input wire[`InstAddrBus] inst_addr_i,   // 指令地址

    input wire[`Hold_Flag_Bus] hold_flag_i, // 流水线暂停标志

    input wire[`INT_BUS] int_flag_i,        // 外设中断输入信号
    output wire[`INT_BUS] int_flag_o,       // 译码级中断输出

    output wire[`InstBus] inst_o,           // 指令内容
    output wire[`InstAddrBus] inst_addr_o   // 指令地址

    ); // 端口列表结束

    wire hold_en = (hold_flag_i >= `Hold_If); // IF/ID暂停条件

    wire[`InstBus] inst; // IF/ID寄存指令
    gen_pipe_dff #(32) inst_ff(clk, rst, hold_en, `INST_NOP, inst_i, inst); // 指令流水寄存
    assign inst_o = inst; // 输出指令

    wire[`InstAddrBus] inst_addr; // IF/ID寄存指令地址
    gen_pipe_dff #(32) inst_addr_ff(clk, rst, hold_en, `ZeroWord, inst_addr_i, inst_addr); // 地址流水寄存
    assign inst_addr_o = inst_addr; // 输出指令地址

    wire[`INT_BUS] int_flag; // IF/ID寄存中断标志
    gen_pipe_dff #(8) int_ff(clk, rst, hold_en, `INT_NONE, int_flag_i, int_flag); // 中断流水寄存
    assign int_flag_o = int_flag; // 输出中断标志

endmodule // 模块结束
