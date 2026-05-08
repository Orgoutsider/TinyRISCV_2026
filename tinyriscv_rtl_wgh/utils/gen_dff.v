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

// 带默认值和控制信号的流水线触发器
module gen_pipe_dff #( // 模块声明
    parameter DW = 32)( // 数据位宽

    input wire clk, // 时钟信号
    input wire rst, // 复位信号
    input wire hold_en, // 保持使能

    input wire[DW-1:0] def_val, // 默认输出值
    input wire[DW-1:0] din, // 输入数据
    output wire[DW-1:0] qout // 输出数据

    ); // 端口列表结束

    reg[DW-1:0] qout_r; // 输出寄存器

    always @ (posedge clk) begin // 时钟上升沿触发
        if (!rst | hold_en) begin // 复位或保持时输出默认值
            qout_r <= def_val; // 加载默认值
        end else begin // 正常工作
            qout_r <= din; // 锁存输入
        end // if结束
    end // always结束

    assign qout = qout_r; // 输出寄存器值

endmodule // 模块结束

// 复位后输出为0的触发器
module gen_rst_0_dff #( // 模块声明
    parameter DW = 32)( // 数据位宽

    input wire clk, // 时钟信号
    input wire rst, // 复位信号

    input wire[DW-1:0] din, // 输入数据
    output wire[DW-1:0] qout // 输出数据

    ); // 端口列表结束

    reg[DW-1:0] qout_r; // 输出寄存器

    always @ (posedge clk) begin // 时钟上升沿触发
        if (!rst) begin // 复位有效
            qout_r <= {DW{1'b0}}; // 输出清零
        end else begin                  
            qout_r <= din; // 锁存输入
        end // if结束
    end // always结束

    assign qout = qout_r; // 输出寄存器值

endmodule // 模块结束

// 复位后输出为1的触发器
module gen_rst_1_dff #( // 模块声明
    parameter DW = 32)( // 数据位宽

    input wire clk, // 时钟信号
    input wire rst, // 复位信号

    input wire[DW-1:0] din, // 输入数据
    output wire[DW-1:0] qout // 输出数据

    ); // 端口列表结束

    reg[DW-1:0] qout_r; // 输出寄存器

    always @ (posedge clk) begin // 时钟上升沿触发
        if (!rst) begin // 复位有效
            qout_r <= {DW{1'b1}}; // 输出置1
        end else begin                  
            qout_r <= din; // 锁存输入
        end // if结束
    end // always结束

    assign qout = qout_r; // 输出寄存器值

endmodule // 模块结束

// 复位后输出为默认值的触发器
module gen_rst_def_dff #( // 模块声明
    parameter DW = 32)( // 数据位宽

    input wire clk, // 时钟信号
    input wire rst, // 复位信号
    input wire[DW-1:0] def_val, // 默认输出值

    input wire[DW-1:0] din, // 输入数据
    output wire[DW-1:0] qout // 输出数据

    ); // 端口列表结束

    reg[DW-1:0] qout_r; // 输出寄存器

    always @ (posedge clk) begin // 时钟上升沿触发
        if (!rst) begin // 复位有效
            qout_r <= def_val; // 输出默认值
        end else begin                  
            qout_r <= din; // 锁存输入
        end // if结束
    end // always结束

    assign qout = qout_r; // 输出寄存器值

endmodule // 模块结束

// 带使能端、复位后输出为0的触发器
module gen_en_dff #( // 模块声明
    parameter DW = 32)( // 数据位宽

    input wire clk, // 时钟信号
    input wire rst, // 复位信号

    input wire en, // 使能信号
    input wire[DW-1:0] din, // 输入数据
    output wire[DW-1:0] qout // 输出数据

    ); // 端口列表结束

    reg[DW-1:0] qout_r; // 输出寄存器

    always @ (posedge clk) begin // 时钟上升沿触发
        if (!rst) begin // 复位有效
            qout_r <= {DW{1'b0}}; // 输出清零
        end else if (en == 1'b1) begin // 使能有效
            qout_r <= din; // 锁存输入
        end // 条件结束
    end // always结束

    assign qout = qout_r; // 输出寄存器值

endmodule // 模块结束
