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


// CLINT本地中断控制模块
module clint( // 模块声明

    input wire clk, // 时钟信号
    input wire rst, // 复位信号

    // from core
    input wire[`INT_BUS] int_flag_i,         // 中断输入信号

    // from id
    input wire[`InstBus] inst_i,             // 指令内容
    input wire[`InstAddrBus] inst_addr_i,    // 指令地址

    // from ex
    input wire jump_flag_i, // 跳转标志
    input wire[`InstAddrBus] jump_addr_i, // 跳转地址
    input wire div_started_i, // 除法启动标志

    // from ctrl
    input wire[`Hold_Flag_Bus] hold_flag_i,  // 流水线暂停标志

    // from csr_reg
    input wire[`RegBus] data_i,              // CSR读数据
    input wire[`RegBus] csr_mtvec,           // mtvec寄存器
    input wire[`RegBus] csr_mepc,            // mepc寄存器
    input wire[`RegBus] csr_mstatus,         // mstatus寄存器

    input wire global_int_en_i,              // 全局中断使能

    // to ctrl
    output wire hold_flag_o,                 // 流水线暂停标志

    // to csr_reg
    output reg we_o,                         // 写CSR寄存器使能
    output reg[`MemAddrBus] waddr_o,         // 写CSR地址
    output reg[`MemAddrBus] raddr_o,         // 读CSR地址
    output reg[`RegBus] data_o,              // 写CSR数据

    // to ex
    output reg[`InstAddrBus] int_addr_o,     // 中断入口地址
    output reg int_assert_o                  // 中断有效标志

    ); // 端口列表结束


    // 中断状态机编码
    localparam S_INT_IDLE            = 4'b0001; // 空闲
    localparam S_INT_SYNC_ASSERT     = 4'b0010; // 同步异常
    localparam S_INT_ASYNC_ASSERT    = 4'b0100; // 异步中断
    localparam S_INT_MRET            = 4'b1000; // MRET返回

    // CSR写状态机编码
    localparam S_CSR_IDLE            = 5'b00001; // 空闲
    localparam S_CSR_MSTATUS         = 5'b00010; // 写mstatus
    localparam S_CSR_MEPC            = 5'b00100; // 写mepc
    localparam S_CSR_MSTATUS_MRET    = 5'b01000; // MRET写mstatus
    localparam S_CSR_MCAUSE          = 5'b10000; // 写mcause

    reg[3:0] int_state; // 中断状态
    reg[4:0] csr_state; // CSR写状态
    reg[`InstAddrBus] inst_addr; // 保存指令地址
    reg[31:0] cause; // 异常原因


    assign hold_flag_o = ((int_state != S_INT_IDLE) | (csr_state != S_CSR_IDLE))? `HoldEnable: `HoldDisable; // 中断期间暂停流水线


    // 中断状态判断逻辑
    always @ (*) begin // 组合逻辑
        if (rst == `RstEnable) begin // 复位
            int_state = S_INT_IDLE; // 进入空闲
        end else begin // 非复位
            if (inst_i == `INST_ECALL || inst_i == `INST_EBREAK) begin // 同步异常指令
                // 执行阶段遇到同步异常，若除法未启动则触发
                if (div_started_i == `DivStop) begin // 无除法阻塞
                    int_state = S_INT_SYNC_ASSERT; // 同步异常
                end else begin // 除法进行中
                    int_state = S_INT_IDLE; // 保持空闲
                end
            end else if (int_flag_i != `INT_NONE && global_int_en_i == `True) begin // 外部中断
                int_state = S_INT_ASYNC_ASSERT; // 异步中断
            end else if (inst_i == `INST_MRET) begin // MRET返回
                int_state = S_INT_MRET; // 返回状态
            end else begin // 其他情况
                int_state = S_INT_IDLE; // 空闲
            end
        end
    end

    // CSR写状态机
    always @ (posedge clk) begin // 时序逻辑
        if (rst == `RstEnable) begin // 复位
            csr_state <= S_CSR_IDLE; // 状态清零
            cause <= `ZeroWord; // 原因清零
            inst_addr <= `ZeroWord; // 地址清零
        end else begin // 非复位
            case (csr_state) // 状态机跳转
                S_CSR_IDLE: begin // 空闲
                    // 同步异常
                    if (int_state == S_INT_SYNC_ASSERT) begin
                        csr_state <= S_CSR_MEPC; // 先写mepc
                        // 同步异常时若发生跳转，返回地址需要减4
                        if (jump_flag_i == `JumpEnable) begin // 已跳转
                            inst_addr <= jump_addr_i - 4'h4; // 保存返回地址
                        end else begin // 未跳转
                            inst_addr <= inst_addr_i; // 保存当前地址
                        end
                        case (inst_i) // 设置cause
                            `INST_ECALL: begin
                                cause <= 32'd11; // ECALL原因
                            end
                            `INST_EBREAK: begin
                                cause <= 32'd3; // EBREAK原因
                            end
                            default: begin
                                cause <= 32'd10; // 其他同步异常
                            end
                        endcase
                    // 异步中断
                    end else if (int_state == S_INT_ASYNC_ASSERT) begin
                        // 定时器中断
                        cause <= 32'h80000004; // 异步中断原因
                        csr_state <= S_CSR_MEPC; // 先写mepc
                        if (jump_flag_i == `JumpEnable) begin // 已跳转
                            inst_addr <= jump_addr_i; // 保存跳转地址
                        // 异步中断可能打断除法执行，返回地址减4
                        end else if (div_started_i == `DivStart) begin // 除法启动
                            inst_addr <= inst_addr_i - 4'h4; // 保存返回地址
                        end else begin // 正常情况
                            inst_addr <= inst_addr_i; // 保存当前地址
                        end
                    // 中断返回
                    end else if (int_state == S_INT_MRET) begin
                        csr_state <= S_CSR_MSTATUS_MRET; // 恢复mstatus
                    end
                end
                S_CSR_MEPC: begin // 写完mepc
                    csr_state <= S_CSR_MSTATUS; // 转写mstatus
                end
                S_CSR_MSTATUS: begin // 写完mstatus
                    csr_state <= S_CSR_MCAUSE; // 转写mcause
                end
                S_CSR_MCAUSE: begin // 写完mcause
                    csr_state <= S_CSR_IDLE; // 回空闲
                end
                S_CSR_MSTATUS_MRET: begin // MRET写mstatus完成
                    csr_state <= S_CSR_IDLE; // 回空闲
                end
                default: begin // 默认分支
                    csr_state <= S_CSR_IDLE; // 回空闲
                end
            endcase
        end
    end

    // 中断处理过程中写CSR寄存器
    always @ (posedge clk) begin // 时序逻辑
        if (rst == `RstEnable) begin // 复位
            we_o <= `WriteDisable; // 禁止写CSR
            waddr_o <= `ZeroWord; // 写地址清零
            data_o <= `ZeroWord; // 写数据清零
        end else begin // 非复位
            case (csr_state) // 根据CSR状态写
                // 写mepc寄存器为返回地址
                S_CSR_MEPC: begin
                    we_o <= `WriteEnable; // 允许写
                    waddr_o <= {20'h0, `CSR_MEPC}; // mepc地址
                    data_o <= inst_addr; // 写入返回地址
                end
                // 写异常原因
                S_CSR_MCAUSE: begin
                    we_o <= `WriteEnable; // 允许写
                    waddr_o <= {20'h0, `CSR_MCAUSE}; // mcause地址
                    data_o <= cause; // 写入原因
                end
                // 关闭全局中断
                S_CSR_MSTATUS: begin
                    we_o <= `WriteEnable; // 允许写
                    waddr_o <= {20'h0, `CSR_MSTATUS}; // mstatus地址
                    data_o <= {csr_mstatus[31:4], 1'b0, csr_mstatus[2:0]}; // 清MIE
                end
                // 中断返回恢复全局中断
                S_CSR_MSTATUS_MRET: begin
                    we_o <= `WriteEnable; // 允许写
                    waddr_o <= {20'h0, `CSR_MSTATUS}; // mstatus地址
                    data_o <= {csr_mstatus[31:4], csr_mstatus[7], csr_mstatus[2:0]}; // 恢复MIE
                end
                default: begin
                    we_o <= `WriteDisable; // 默认不写
                    waddr_o <= `ZeroWord; // 地址清零
                    data_o <= `ZeroWord; // 数据清零
                end
            endcase
        end
    end

    // 向ex模块输出中断信号
    always @ (posedge clk) begin // 时序逻辑
        if (rst == `RstEnable) begin // 复位
            int_assert_o <= `INT_DEASSERT; // 清中断
            int_addr_o <= `ZeroWord; // 清入口
        end else begin // 非复位
            case (csr_state) // 根据CSR状态输出
                // 发出中断进入信号，写完mcause后生效
                S_CSR_MCAUSE: begin
                    int_assert_o <= `INT_ASSERT; // 置中断
                    int_addr_o <= csr_mtvec; // 跳转到mtvec
                end
                // 发出中断返回信号
                S_CSR_MSTATUS_MRET: begin
                    int_assert_o <= `INT_ASSERT; // 置中断
                    int_addr_o <= csr_mepc; // 跳转到mepc
                end
                default: begin
                    int_assert_o <= `INT_DEASSERT; // 默认不触发
                    int_addr_o <= `ZeroWord; // 默认地址
                end
            endcase
        end
    end

endmodule // 模块结束
