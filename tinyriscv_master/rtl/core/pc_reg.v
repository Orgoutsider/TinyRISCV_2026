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

// PC寄存器模块
module pc_reg( // 模块声明

    input wire clk, // 时钟信号
    input wire rst, // 复位信号

    input wire jump_flag_i,                 // 跳转标志
    input wire[`InstAddrBus] jump_addr_i,   // 跳转地址
    input wire[`Hold_Flag_Bus] hold_flag_i, // 流水线暂停标志
    input wire jtag_reset_flag_i,           // 复位标志

    output reg[`InstAddrBus] pc_o           // PC指针

    ); // 端口列表结束


    always @ (posedge clk) begin // 时钟驱动PC更新
        // 复位
        if (rst == `RstEnable || jtag_reset_flag_i == 1'b1) begin // 复位条件
            pc_o <= `CpuResetAddr; // 复位地址
        // 跳转
        end else if (jump_flag_i == `JumpEnable) begin // 跳转条件
            pc_o <= jump_addr_i; // 更新为跳转地址
        // 暂停
        end else if (hold_flag_i >= `Hold_Pc) begin // 流水线暂停
            pc_o <= pc_o; // 保持PC不变
        // 地址加4
        end else begin // 正常顺序执行
            pc_o <= pc_o + 4'h4; // PC加4
        end // if结束
    end // always结束

endmodule // 模块结束
