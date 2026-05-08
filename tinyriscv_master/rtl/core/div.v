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

// 除法模块
// 试商法实现32位整数除法
// 每次除法运算至少需要33个时钟周期才能完成
module div( // 模块声明

    input wire clk, // 时钟信号
    input wire rst, // 复位信号

    // from ex
    input wire[`RegBus] dividend_i,      // 被除数
    input wire[`RegBus] divisor_i,       // 除数
    input wire start_i,                  // 开始信号，运算期间这个信号需要一直保持有效
    input wire[2:0] op_i,                // 具体是哪一条指令
    input wire[`RegAddrBus] reg_waddr_i, // 运算结束后需要写的寄存器

    // to ex
    output reg[`RegBus] result_o,        // 除法结果，高32位是余数，低32位是商
    output reg ready_o,                  // 运算结束信号
    output reg busy_o,                  // 正在运算信号
    output reg[`RegAddrBus] reg_waddr_o  // 运算结束后需要写的寄存器

    ); // 端口列表结束

    // 状态定义
    localparam STATE_IDLE  = 4'b0001; // 空闲状态
    localparam STATE_START = 4'b0010; // 启动状态
    localparam STATE_CALC  = 4'b0100; // 计算状态
    localparam STATE_END   = 4'b1000; // 结束状态

    reg[`RegBus] dividend_r; // 被除数寄存
    reg[`RegBus] divisor_r; // 除数寄存
    reg[2:0] op_r; // 运算类型寄存
    reg[3:0] state; // 当前状态
    reg[31:0] count; // 计数器
    reg[`RegBus] div_result; // 商寄存
    reg[`RegBus] div_remain; // 余数寄存
    reg[`RegBus] minuend; // 当前被减数
    reg invert_result; // 是否取补码标志

    wire op_div = (op_r == `INST_DIV); // 有符号除法
    wire op_divu = (op_r == `INST_DIVU); // 无符号除法
    wire op_rem = (op_r == `INST_REM); // 有符号取余
    wire op_remu = (op_r == `INST_REMU); // 无符号取余

    wire[31:0] dividend_invert = (-dividend_r); // 被除数补码
    wire[31:0] divisor_invert = (-divisor_r); // 除数补码
    wire minuend_ge_divisor = minuend >= divisor_r; // 比较大小
    wire[31:0] minuend_sub_res = minuend - divisor_r; // 减法结果
    wire[31:0] div_result_tmp = minuend_ge_divisor? ({div_result[30:0], 1'b1}): ({div_result[30:0], 1'b0}); // 更新商
    wire[31:0] minuend_tmp = minuend_ge_divisor? minuend_sub_res[30:0]: minuend[30:0]; // 更新被减数

    // 状态机实现
    always @ (posedge clk) begin // 时钟驱动状态机
        if (rst == `RstEnable) begin // 复位
            state <= STATE_IDLE; // 状态清零
            ready_o <= `DivResultNotReady; // 未完成
            result_o <= `ZeroWord; // 结果清零
            div_result <= `ZeroWord; // 商清零
            div_remain <= `ZeroWord; // 余数清零
            op_r <= 3'h0; // 操作清零
            reg_waddr_o <= `ZeroWord; // 写地址清零
            dividend_r <= `ZeroWord; // 被除数清零
            divisor_r <= `ZeroWord; // 除数清零
            minuend <= `ZeroWord; // 被减数清零
            invert_result <= 1'b0; // 清补码标志
            busy_o <= `False; // 不忙
            count <= `ZeroWord; // 计数清零
        end else begin // 正常时钟
            case (state) // 状态机
                STATE_IDLE: begin // 空闲状态
                    if (start_i == `DivStart) begin // 启动除法
                        op_r <= op_i; // 锁存操作类型
                        dividend_r <= dividend_i; // 锁存被除数
                        divisor_r <= divisor_i; // 锁存除数
                        reg_waddr_o <= reg_waddr_i; // 锁存写地址
                        state <= STATE_START; // 进入启动态
                        busy_o <= `True; // 标记忙
                    end else begin // 未启动
                        op_r <= 3'h0; // 清操作
                        reg_waddr_o <= `ZeroWord; // 清写地址
                        dividend_r <= `ZeroWord; // 清被除数
                        divisor_r <= `ZeroWord; // 清除数
                        ready_o <= `DivResultNotReady; // 未完成
                        result_o <= `ZeroWord; // 结果清零
                        busy_o <= `False; // 不忙
                    end
                end

                STATE_START: begin // 启动状态
                    if (start_i == `DivStart) begin // 保持启动
                        // 除数为0
                        if (divisor_r == `ZeroWord) begin // 除数为0
                            if (op_div | op_divu) begin // 除法
                                result_o <= 32'hffffffff; // 返回全1
                            end else begin // 取余
                                result_o <= dividend_r; // 返回被除数
                            end
                            ready_o <= `DivResultReady; // 完成
                            state <= STATE_IDLE; // 回空闲
                            busy_o <= `False; // 不忙
                        // 除数不为0
                        end else begin // 除数非0
                            busy_o <= `True; // 标记忙
                            count <= 32'h40000000; // 初始化计数
                            state <= STATE_CALC; // 进入计算态
                            div_result <= `ZeroWord; // 商清零
                            div_remain <= `ZeroWord; // 余数清零

                            // DIV和REM这两条指令是有符号数运算指令
                            if (op_div | op_rem) begin // 有符号运算
                                // 被除数求补码
                                if (dividend_r[31] == 1'b1) begin // 被除数为负
                                    dividend_r <= dividend_invert; // 转为正
                                    minuend <= dividend_invert[31]; // 初始化被减数
                                end else begin // 被除数为正
                                    minuend <= dividend_r[31]; // 初始化被减数
                                end
                                // 除数求补码
                                if (divisor_r[31] == 1'b1) begin // 除数为负
                                    divisor_r <= divisor_invert; // 转为正
                                end
                            end else begin // 无符号运算
                                minuend <= dividend_r[31]; // 初始化被减数
                            end

                            // 运算结束后是否要对结果取补码
                            if ((op_div && (dividend_r[31] ^ divisor_r[31] == 1'b1))
                                || (op_rem && (dividend_r[31] == 1'b1))) begin // 需要取补码
                                invert_result <= 1'b1; // 置补码标志
                            end else begin // 不需要补码
                                invert_result <= 1'b0; // 清补码标志
                            end
                        end
                    end else begin // 启动撤销
                        state <= STATE_IDLE; // 回空闲
                        result_o <= `ZeroWord; // 清结果
                        ready_o <= `DivResultNotReady; // 未完成
                        busy_o <= `False; // 不忙
                    end
                end

                STATE_CALC: begin // 计算状态
                    if (start_i == `DivStart) begin // 保持启动
                        dividend_r <= {dividend_r[30:0], 1'b0}; // 左移被除数
                        div_result <= div_result_tmp; // 更新商
                        count <= {1'b0, count[31:1]}; // 计数右移
                        if (|count) begin // 计数未结束
                            minuend <= {minuend_tmp[30:0], dividend_r[30]}; // 更新被减数
                        end else begin // 计数结束
                            state <= STATE_END; // 进入结束态
                            if (minuend_ge_divisor) begin // 可减
                                div_remain <= minuend_sub_res; // 余数更新
                            end else begin // 不可减
                                div_remain <= minuend; // 余数保持
                            end
                        end
                    end else begin // 启动撤销
                        state <= STATE_IDLE; // 回空闲
                        result_o <= `ZeroWord; // 清结果
                        ready_o <= `DivResultNotReady; // 未完成
                        busy_o <= `False; // 不忙
                    end
                end

                STATE_END: begin // 结束状态
                    if (start_i == `DivStart) begin // 保持启动
                        ready_o <= `DivResultReady; // 标记完成
                        state <= STATE_IDLE; // 回空闲
                        busy_o <= `False; // 不忙
                        if (op_div | op_divu) begin // 除法结果
                            if (invert_result) begin // 取补码
                                result_o <= (-div_result); // 输出负商
                            end else begin // 不取补码
                                result_o <= div_result; // 输出正商
                            end
                        end else begin // 余数结果
                            if (invert_result) begin // 取补码
                                result_o <= (-div_remain); // 输出负余数
                            end else begin // 不取补码
                                result_o <= div_remain; // 输出正余数
                            end
                        end
                    end else begin // 启动撤销
                        state <= STATE_IDLE; // 回空闲
                        result_o <= `ZeroWord; // 清结果
                        ready_o <= `DivResultNotReady; // 未完成
                        busy_o <= `False; // 不忙
                    end
                end

            endcase // case结束
        end // if结束
    end // always结束

endmodule // 模块结束
