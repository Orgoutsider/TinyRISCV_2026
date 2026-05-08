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

// CSR寄存器模块
module csr_reg( // 模块声明

    input wire clk, // 时钟信号
    input wire rst, // 复位信号

    // form ex
    input wire we_i,                        // ex模块写寄存器标志
    input wire[`MemAddrBus] raddr_i,        // ex模块读寄存器地址
    input wire[`MemAddrBus] waddr_i,        // ex模块写寄存器地址
    input wire[`RegBus] data_i,             // ex模块写寄存器数据

    // from clint
    input wire clint_we_i,                  // clint模块写寄存器标志
    input wire[`MemAddrBus] clint_raddr_i,  // clint模块读寄存器地址
    input wire[`MemAddrBus] clint_waddr_i,  // clint模块写寄存器地址
    input wire[`RegBus] clint_data_i,       // clint模块写寄存器数据

    output wire global_int_en_o,            // 全局中断使能标志

    // to clint
    output reg[`RegBus] clint_data_o,       // clint模块读寄存器数据
    output wire[`RegBus] clint_csr_mtvec,   // mtvec
    output wire[`RegBus] clint_csr_mepc,    // mepc
    output wire[`RegBus] clint_csr_mstatus, // mstatus

    // to ex
    output reg[`RegBus] data_o              // ex模块读寄存器数据

    ); // 端口列表结束

    reg[`DoubleRegBus] cycle; // cycle计数器
    reg[`RegBus] mtvec; // mtvec寄存器
    reg[`RegBus] mcause; // mcause寄存器
    reg[`RegBus] mepc; // mepc寄存器
    reg[`RegBus] mie; // mie寄存器
    reg[`RegBus] mstatus; // mstatus寄存器
    reg[`RegBus] mscratch; // mscratch寄存器

    assign global_int_en_o = (mstatus[3] == 1'b1)? `True: `False; // 全局中断使能

    assign clint_csr_mtvec = mtvec; // 输出mtvec
    assign clint_csr_mepc = mepc; // 输出mepc
    assign clint_csr_mstatus = mstatus; // 输出mstatus

    // cycle counter
    // 复位撤销后就一直计数
    always @ (posedge clk) begin // cycle计数
        if (rst == `RstEnable) begin // 复位
            cycle <= {`ZeroWord, `ZeroWord}; // 清零
        end else begin // 正常计数
            cycle <= cycle + 1'b1; // 自增
        end // if结束
    end // always结束

    // write reg
    // 写寄存器操作
    always @ (posedge clk) begin // 写寄存器时序逻辑
        if (rst == `RstEnable) begin // 复位
            mtvec <= `ZeroWord; // 清mtvec
            mcause <= `ZeroWord; // 清mcause
            mepc <= `ZeroWord; // 清mepc
            mie <= `ZeroWord; // 清mie
            mstatus <= `ZeroWord; // 清mstatus
            mscratch <= `ZeroWord; // 清mscratch
        end else begin // 正常写入
            // 优先响应ex模块的写操作
            if (we_i == `WriteEnable) begin // EX写CSR
                case (waddr_i[11:0]) // 地址选择
                    `CSR_MTVEC: begin
                        mtvec <= data_i; // 写mtvec
                    end
                    `CSR_MCAUSE: begin
                        mcause <= data_i; // 写mcause
                    end
                    `CSR_MEPC: begin
                        mepc <= data_i; // 写mepc
                    end
                    `CSR_MIE: begin
                        mie <= data_i; // 写mie
                    end
                    `CSR_MSTATUS: begin
                        mstatus <= data_i; // 写mstatus
                    end
                    `CSR_MSCRATCH: begin
                        mscratch <= data_i; // 写mscratch
                    end
                    default: begin

                    end
                endcase // case结束
            // clint模块写操作
            end else if (clint_we_i == `WriteEnable) begin // CLINT写CSR
                case (clint_waddr_i[11:0]) // 地址选择
                    `CSR_MTVEC: begin
                        mtvec <= clint_data_i; // 写mtvec
                    end
                    `CSR_MCAUSE: begin
                        mcause <= clint_data_i; // 写mcause
                    end
                    `CSR_MEPC: begin
                        mepc <= clint_data_i; // 写mepc
                    end
                    `CSR_MIE: begin
                        mie <= clint_data_i; // 写mie
                    end
                    `CSR_MSTATUS: begin
                        mstatus <= clint_data_i; // 写mstatus
                    end
                    `CSR_MSCRATCH: begin
                        mscratch <= clint_data_i; // 写mscratch
                    end
                    default: begin

                    end
                endcase // case结束
            end
        end
    end // always结束

    // read reg
    // ex模块读CSR寄存器
    always @ (*) begin // EX读CSR组合逻辑
        if ((waddr_i[11:0] == raddr_i[11:0]) && (we_i == `WriteEnable)) begin // 旁路写数据
            data_o = data_i; // 直接返回写数据
        end else begin // 正常读
            case (raddr_i[11:0]) // 地址选择
                `CSR_CYCLE: begin
                    data_o = cycle[31:0]; // 读cycle低32位
                end
                `CSR_CYCLEH: begin
                    data_o = cycle[63:32]; // 读cycle高32位
                end
                `CSR_MTVEC: begin
                    data_o = mtvec; // 读mtvec
                end
                `CSR_MCAUSE: begin
                    data_o = mcause; // 读mcause
                end
                `CSR_MEPC: begin
                    data_o = mepc; // 读mepc
                end
                `CSR_MIE: begin
                    data_o = mie; // 读mie
                end
                `CSR_MSTATUS: begin
                    data_o = mstatus; // 读mstatus
                end
                `CSR_MSCRATCH: begin
                    data_o = mscratch; // 读mscratch
                end
                default: begin
                    data_o = `ZeroWord; // 默认返回0
                end
            endcase // case结束
        end
    end // always结束

    // read reg
    // clint模块读CSR寄存器
    always @ (*) begin // CLINT读CSR组合逻辑
        if ((clint_waddr_i[11:0] == clint_raddr_i[11:0]) && (clint_we_i == `WriteEnable)) begin // 旁路写数据
            clint_data_o = clint_data_i; // 直接返回写数据
        end else begin // 正常读
            case (clint_raddr_i[11:0]) // 地址选择
                `CSR_CYCLE: begin
                    clint_data_o = cycle[31:0]; // 读cycle低32位
                end
                `CSR_CYCLEH: begin
                    clint_data_o = cycle[63:32]; // 读cycle高32位
                end
                `CSR_MTVEC: begin
                    clint_data_o = mtvec; // 读mtvec
                end
                `CSR_MCAUSE: begin
                    clint_data_o = mcause; // 读mcause
                end
                `CSR_MEPC: begin
                    clint_data_o = mepc; // 读mepc
                end
                `CSR_MIE: begin
                    clint_data_o = mie; // 读mie
                end
                `CSR_MSTATUS: begin
                    clint_data_o = mstatus; // 读mstatus
                end
                `CSR_MSCRATCH: begin
                    clint_data_o = mscratch; // 读mscratch
                end
                default: begin
                    clint_data_o = `ZeroWord; // 默认返回0
                end
            endcase // case结束
        end
    end // always结束

endmodule // 模块结束
