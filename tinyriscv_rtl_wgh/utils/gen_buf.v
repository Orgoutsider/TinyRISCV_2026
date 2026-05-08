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

// 将输入打DP拍后输出
module gen_ticks_sync #( // DP级同步模块
    parameter DP = 2, // 同步级数
    parameter DW = 32)( // 数据位宽

    input wire rst, // 复位信号
    input wire clk, // 时钟信号

    input wire[DW-1:0] din, // 输入数据
    output wire[DW-1:0] dout // 输出数据

    ); // 端口列表结束

    wire[DW-1:0] sync_dat[DP-1:0]; // 同步数据链

    genvar i; // 生成变量

    generate // 生成块开始
        for (i = 0; i < DP; i = i + 1) begin: dp_width // 生成DP级触发器
            if (i == 0) begin: dp_is_0 // 第0级直接采样输入
                gen_rst_0_dff #(DW) rst_0_dff(clk, rst, din, sync_dat[0]); // 第0级触发器实例
            end else begin: dp_is_not_0 // 后续级采样前一级
                gen_rst_0_dff #(DW) rst_0_dff(clk, rst, sync_dat[i-1], sync_dat[i]); // 后续级触发器实例
            end // 条件分支结束
        end // for生成结束
    endgenerate // 生成块结束

    assign dout = sync_dat[DP-1]; // 输出最后一级
  
endmodule // 模块结束
