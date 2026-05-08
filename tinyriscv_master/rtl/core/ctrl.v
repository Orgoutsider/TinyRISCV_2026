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

// 控制模块
// 发出跳转、暂停流水线信号
module ctrl( // 模块声明

    input wire rst, // 复位信号

    // from ex
    input wire jump_flag_i, // EX跳转标志
    input wire[`InstAddrBus] jump_addr_i, // EX跳转地址
    input wire hold_flag_ex_i, // EX暂停标志

    // from rib
    input wire hold_flag_rib_i, // RIB暂停标志
    input wire hold_flag_rib_full_i, // RIB全暂停标志

    // from jtag
    input wire jtag_halt_flag_i, // JTAG暂停标志

    // from clint
    input wire hold_flag_clint_i, // CLINT暂停标志

    output reg[`Hold_Flag_Bus] hold_flag_o, // 控制输出暂停标志

    // to pc_reg
    output reg jump_flag_o, // 输出跳转标志
    output reg[`InstAddrBus] jump_addr_o // 输出跳转地址

    ); // 端口列表结束


    always @ (*) begin // 组合控制逻辑
        jump_addr_o = jump_addr_i; // 直通跳转地址
        jump_flag_o = jump_flag_i; // 直通跳转标志
        // 默认不暂停
        hold_flag_o = `Hold_None; // 默认无暂停
        // 按优先级处理不同模块的请求
        if (jump_flag_i == `JumpEnable || hold_flag_ex_i == `HoldEnable || hold_flag_clint_i == `HoldEnable) begin
            // 暂停整条流水线
            hold_flag_o = `Hold_Id; // 暂停到ID阶段
        end else if (hold_flag_rib_full_i == `HoldEnable) begin
            // Multi-cycle non-fetch accesses must stop younger instructions too.
            hold_flag_o = `Hold_Id; // 多周期访问全暂停
        end else if (hold_flag_rib_i == `HoldEnable) begin
            hold_flag_o = `Hold_Pc; // 只暂停PC
        end else if (jtag_halt_flag_i == `HoldEnable) begin
            // 暂停整条流水线
            hold_flag_o = `Hold_Id; // JTAG暂停
        end else begin
            hold_flag_o = `Hold_None; // 无暂停
        end
    end // always结束

endmodule // 模块结束
