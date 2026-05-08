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

// 译码模块
// 纯组合逻辑电路
module id( // 模块声明

	input wire rst, // 复位信号

    // from if_id
    input wire[`InstBus] inst_i,             // 指令内容
    input wire[`InstAddrBus] inst_addr_i,    // 指令地址

    // from regs
    input wire[`RegBus] reg1_rdata_i,        // 通用寄存器1输入数据
    input wire[`RegBus] reg2_rdata_i,        // 通用寄存器2输入数据

    // from csr reg
    input wire[`RegBus] csr_rdata_i,         // CSR寄存器输入数据

    // from ex
    input wire ex_jump_flag_i,               // 跳转标志

    // to regs
    output reg[`RegAddrBus] reg1_raddr_o,    // 读通用寄存器1地址
    output reg[`RegAddrBus] reg2_raddr_o,    // 读通用寄存器2地址

    // to csr reg
    output reg[`MemAddrBus] csr_raddr_o,     // 读CSR寄存器地址

    // to ex
    output reg[`MemAddrBus] op1_o,           // 运算操作数1
    output reg[`MemAddrBus] op2_o,           // 运算操作数2
    output reg[`MemAddrBus] op1_jump_o,      // 跳转操作数1
    output reg[`MemAddrBus] op2_jump_o,      // 跳转操作数2
    output reg[`InstBus] inst_o,             // 指令内容
    output reg[`InstAddrBus] inst_addr_o,    // 指令地址
    output reg[`RegBus] reg1_rdata_o,        // 通用寄存器1数据
    output reg[`RegBus] reg2_rdata_o,        // 通用寄存器2数据
    output reg reg_we_o,                     // 写通用寄存器标志
    output reg[`RegAddrBus] reg_waddr_o,     // 写通用寄存器地址
    output reg csr_we_o,                     // 写CSR寄存器标志
    output reg[`RegBus] csr_rdata_o,         // CSR寄存器数据
    output reg[`MemAddrBus] csr_waddr_o      // 写CSR寄存器地址

    ); // 端口列表结束

    wire[6:0] opcode = inst_i[6:0]; // 操作码
    wire[2:0] funct3 = inst_i[14:12]; // funct3
    wire[6:0] funct7 = inst_i[31:25]; // funct7
    wire[4:0] rd = inst_i[11:7]; // 目的寄存器
    wire[4:0] rs1 = inst_i[19:15]; // 源寄存器1
    wire[4:0] rs2 = inst_i[24:20]; // 源寄存器2


    always @ (*) begin // 译码组合逻辑
        inst_o = inst_i; // 默认直通指令
        inst_addr_o = inst_addr_i; // 默认直通地址
        reg1_rdata_o = reg1_rdata_i; // 默认直通reg1数据
        reg2_rdata_o = reg2_rdata_i; // 默认直通reg2数据
        csr_rdata_o = csr_rdata_i; // 默认直通CSR读数
        csr_raddr_o = `ZeroWord; // 默认CSR读地址清零
        csr_waddr_o = `ZeroWord; // 默认CSR写地址清零
        csr_we_o = `WriteDisable; // 默认不写CSR
        op1_o = `ZeroWord; // 默认操作数1清零
        op2_o = `ZeroWord; // 默认操作数2清零
        op1_jump_o = `ZeroWord; // 默认跳转操作数1清零
        op2_jump_o = `ZeroWord; // 默认跳转操作数2清零
        reg_we_o = `WriteDisable; // 默认不写通用寄存器
        reg_waddr_o = `ZeroReg; // 默认写地址为x0
        reg1_raddr_o = `ZeroReg; // 默认读寄存器1为x0
        reg2_raddr_o = `ZeroReg; // 默认读寄存器2为x0

        case (opcode) // 按操作码译码
            `INST_TYPE_I: begin // I类指令
                case (funct3) // 按funct3选择
                    `INST_ADDI, `INST_SLTI, `INST_SLTIU, `INST_XORI, `INST_ORI, `INST_ANDI, `INST_SLLI, `INST_SRI: begin // I类运算
                        reg_we_o = `WriteEnable; // 写寄存器
                        reg_waddr_o = rd; // 目的寄存器
                        reg1_raddr_o = rs1; // 源寄存器1
                        reg2_raddr_o = `ZeroReg; // 源寄存器2不用
                        op1_o = reg1_rdata_i; // 操作数1
                        op2_o = {{20{inst_i[31]}}, inst_i[31:20]}; // 立即数
                    end
                    default: begin // 不支持的funct3
                        reg_we_o = `WriteDisable; // 禁止写寄存器
                        reg_waddr_o = `ZeroReg; // 写地址清零
                        reg1_raddr_o = `ZeroReg; // 读地址清零
                        reg2_raddr_o = `ZeroReg; // 读地址清零
                    end
                endcase // funct3 endcase
            end
            `INST_TYPE_R_M: begin // R/M类指令
                if ((funct7 == 7'b0000000) || (funct7 == 7'b0100000)) begin // 普通R类
                    case (funct3) // 按funct3选择
                        `INST_ADD_SUB, `INST_SLL, `INST_SLT, `INST_SLTU, `INST_XOR, `INST_SR, `INST_OR, `INST_AND: begin // R类运算
                            reg_we_o = `WriteEnable; // 写寄存器
                            reg_waddr_o = rd; // 目的寄存器
                            reg1_raddr_o = rs1; // 源寄存器1
                            reg2_raddr_o = rs2; // 源寄存器2
                            op1_o = reg1_rdata_i; // 操作数1
                            op2_o = reg2_rdata_i; // 操作数2
                        end
                        default: begin // 不支持的funct3
                            reg_we_o = `WriteDisable; // 禁止写寄存器
                            reg_waddr_o = `ZeroReg; // 写地址清零
                            reg1_raddr_o = `ZeroReg; // 读地址清零
                            reg2_raddr_o = `ZeroReg; // 读地址清零
                        end
                    endcase // funct3 endcase
                end else if (funct7 == 7'b0000001) begin // M类指令
                    case (funct3) // 按funct3选择
                        `INST_MUL, `INST_MULHU, `INST_MULH, `INST_MULHSU: begin // 乘法类
                            reg_we_o = `WriteEnable; // 写寄存器
                            reg_waddr_o = rd; // 目的寄存器
                            reg1_raddr_o = rs1; // 源寄存器1
                            reg2_raddr_o = rs2; // 源寄存器2
                            op1_o = reg1_rdata_i; // 操作数1
                            op2_o = reg2_rdata_i; // 操作数2
                        end
                        `INST_DIV, `INST_DIVU, `INST_REM, `INST_REMU: begin // 除法类
                            reg_we_o = `WriteDisable; // 延迟写回
                            reg_waddr_o = rd; // 目的寄存器
                            reg1_raddr_o = rs1; // 源寄存器1
                            reg2_raddr_o = rs2; // 源寄存器2
                            op1_o = reg1_rdata_i; // 操作数1
                            op2_o = reg2_rdata_i; // 操作数2
                            op1_jump_o = inst_addr_i; // 记录PC
                            op2_jump_o = 32'h4; // 记录步进
                        end
                        default: begin // 不支持的funct3
                            reg_we_o = `WriteDisable; // 禁止写寄存器
                            reg_waddr_o = `ZeroReg; // 写地址清零
                            reg1_raddr_o = `ZeroReg; // 读地址清零
                            reg2_raddr_o = `ZeroReg; // 读地址清零
                        end
                    endcase // funct3 endcase
                end else begin // 其他funct7
                    reg_we_o = `WriteDisable; // 禁止写寄存器
                    reg_waddr_o = `ZeroReg; // 写地址清零
                    reg1_raddr_o = `ZeroReg; // 读地址清零
                    reg2_raddr_o = `ZeroReg; // 读地址清零
                end
            end
            `INST_TYPE_L: begin // L类指令
                case (funct3) // 按funct3选择
                    `INST_LB, `INST_LH, `INST_LW, `INST_LBU, `INST_LHU: begin // Load类
                        reg1_raddr_o = rs1; // 源寄存器1
                        reg2_raddr_o = `ZeroReg; // 源寄存器2不用
                        reg_we_o = `WriteEnable; // 写寄存器
                        reg_waddr_o = rd; // 目的寄存器
                        op1_o = reg1_rdata_i; // 操作数1
                        op2_o = {{20{inst_i[31]}}, inst_i[31:20]}; // 立即数
                    end
                    default: begin // 不支持的funct3
                        reg1_raddr_o = `ZeroReg; // 读地址清零
                        reg2_raddr_o = `ZeroReg; // 读地址清零
                        reg_we_o = `WriteDisable; // 禁止写寄存器
                        reg_waddr_o = `ZeroReg; // 写地址清零
                    end
                endcase // funct3 endcase
            end
            `INST_TYPE_S: begin // S类指令
                case (funct3) // 按funct3选择
                    `INST_SB, `INST_SW, `INST_SH: begin // Store类
                        reg1_raddr_o = rs1; // 源寄存器1
                        reg2_raddr_o = rs2; // 源寄存器2
                        reg_we_o = `WriteDisable; // 不写寄存器
                        reg_waddr_o = `ZeroReg; // 写地址清零
                        op1_o = reg1_rdata_i; // 操作数1
                        op2_o = {{20{inst_i[31]}}, inst_i[31:25], inst_i[11:7]}; // 立即数
                    end
                    default: begin // 不支持的funct3
                        reg1_raddr_o = `ZeroReg; // 读地址清零
                        reg2_raddr_o = `ZeroReg; // 读地址清零
                        reg_we_o = `WriteDisable; // 禁止写寄存器
                        reg_waddr_o = `ZeroReg; // 写地址清零
                    end
                endcase // funct3 endcase
            end
            `INST_TYPE_B: begin // B类指令
                case (funct3) // 按funct3选择
                    `INST_BEQ, `INST_BNE, `INST_BLT, `INST_BGE, `INST_BLTU, `INST_BGEU: begin // 分支类
                        reg1_raddr_o = rs1; // 源寄存器1
                        reg2_raddr_o = rs2; // 源寄存器2
                        reg_we_o = `WriteDisable; // 不写寄存器
                        reg_waddr_o = `ZeroReg; // 写地址清零
                        op1_o = reg1_rdata_i; // 操作数1
                        op2_o = reg2_rdata_i; // 操作数2
                        op1_jump_o = inst_addr_i; // 跳转基址
                        op2_jump_o = {{20{inst_i[31]}}, inst_i[7], inst_i[30:25], inst_i[11:8], 1'b0}; // 分支偏移
                    end
                    default: begin // 不支持的funct3
                        reg1_raddr_o = `ZeroReg; // 读地址清零
                        reg2_raddr_o = `ZeroReg; // 读地址清零
                        reg_we_o = `WriteDisable; // 禁止写寄存器
                        reg_waddr_o = `ZeroReg; // 写地址清零
                    end
                endcase // funct3 endcase
            end
            `INST_JAL: begin // JAL指令
                reg_we_o = `WriteEnable; // 写寄存器
                reg_waddr_o = rd; // 目的寄存器
                reg1_raddr_o = `ZeroReg; // 源寄存器1不用
                reg2_raddr_o = `ZeroReg; // 源寄存器2不用
                op1_o = inst_addr_i; // 返回地址基址
                op2_o = 32'h4; // 返回地址步进
                op1_jump_o = inst_addr_i; // 跳转基址
                op2_jump_o = {{12{inst_i[31]}}, inst_i[19:12], inst_i[20], inst_i[30:21], 1'b0}; // 跳转偏移
            end
            `INST_JALR: begin // JALR指令
                reg_we_o = `WriteEnable; // 写寄存器
                reg1_raddr_o = rs1; // 源寄存器1
                reg2_raddr_o = `ZeroReg; // 源寄存器2不用
                reg_waddr_o = rd; // 目的寄存器
                op1_o = inst_addr_i; // 返回地址基址
                op2_o = 32'h4; // 返回地址步进
                op1_jump_o = reg1_rdata_i; // 跳转基址
                op2_jump_o = {{20{inst_i[31]}}, inst_i[31:20]}; // 跳转偏移
            end
            `INST_LUI: begin // LUI指令
                reg_we_o = `WriteEnable; // 写寄存器
                reg_waddr_o = rd; // 目的寄存器
                reg1_raddr_o = `ZeroReg; // 源寄存器1不用
                reg2_raddr_o = `ZeroReg; // 源寄存器2不用
                op1_o = {inst_i[31:12], 12'b0}; // 立即数上位
                op2_o = `ZeroWord; // 操作数2清零
            end
            `INST_AUIPC: begin // AUIPC指令
                reg_we_o = `WriteEnable; // 写寄存器
                reg_waddr_o = rd; // 目的寄存器
                reg1_raddr_o = `ZeroReg; // 源寄存器1不用
                reg2_raddr_o = `ZeroReg; // 源寄存器2不用
                op1_o = inst_addr_i; // PC基址
                op2_o = {inst_i[31:12], 12'b0}; // 立即数上位
            end
            `INST_NOP_OP: begin // NOP指令
                reg_we_o = `WriteDisable; // 不写寄存器
                reg_waddr_o = `ZeroReg; // 写地址清零
                reg1_raddr_o = `ZeroReg; // 读地址清零
                reg2_raddr_o = `ZeroReg; // 读地址清零
            end
            `INST_FENCE: begin // FENCE指令
                reg_we_o = `WriteDisable; // 不写寄存器
                reg_waddr_o = `ZeroReg; // 写地址清零
                reg1_raddr_o = `ZeroReg; // 读地址清零
                reg2_raddr_o = `ZeroReg; // 读地址清零
                op1_jump_o = inst_addr_i; // 记录PC
                op2_jump_o = 32'h4; // 记录步进
            end
            `INST_CSR: begin // CSR指令
                reg_we_o = `WriteDisable; // 默认不写寄存器
                reg_waddr_o = `ZeroReg; // 写地址清零
                reg1_raddr_o = `ZeroReg; // 读地址清零
                reg2_raddr_o = `ZeroReg; // 读地址清零
                csr_raddr_o = {20'h0, inst_i[31:20]}; // CSR读地址
                csr_waddr_o = {20'h0, inst_i[31:20]}; // CSR写地址
                case (funct3) // CSR功能选择
                    `INST_CSRRW, `INST_CSRRS, `INST_CSRRC: begin // CSR寄存器源于rs1
                        reg1_raddr_o = rs1; // 源寄存器1
                        reg2_raddr_o = `ZeroReg; // 源寄存器2不用
                        reg_we_o = `WriteEnable; // 写通用寄存器
                        reg_waddr_o = rd; // 目的寄存器
                        csr_we_o = `WriteEnable; // 写CSR
                    end
                    `INST_CSRRWI, `INST_CSRRSI, `INST_CSRRCI: begin // CSR立即数
                        reg1_raddr_o = `ZeroReg; // 源寄存器1不用
                        reg2_raddr_o = `ZeroReg; // 源寄存器2不用
                        reg_we_o = `WriteEnable; // 写通用寄存器
                        reg_waddr_o = rd; // 目的寄存器
                        csr_we_o = `WriteEnable; // 写CSR
                    end
                    default: begin // 不支持的funct3
                        reg_we_o = `WriteDisable; // 禁止写寄存器
                        reg_waddr_o = `ZeroReg; // 写地址清零
                        reg1_raddr_o = `ZeroReg; // 读地址清零
                        reg2_raddr_o = `ZeroReg; // 读地址清零
                        csr_we_o = `WriteDisable; // 禁止写CSR
                    end
                endcase // CSR funct3 endcase
            end
            `INST_CUSTOM: begin // 自定义指令
                case (funct3) // 按funct3选择
                    `INST_SID: begin // sID指令
                        reg_we_o = `WriteDisable; // 不写寄存器
                        reg_waddr_o = `ZeroReg; // 写地址清零
                        reg1_raddr_o = `ZeroReg; // 读地址清零
                        reg2_raddr_o = `ZeroReg; // 读地址清零
                        op1_jump_o = inst_addr_i; // 记录PC
                        op2_jump_o = 32'h4; // 记录步进
                    end
                    `INST_RT: begin // rT指令
                        reg_we_o = `WriteDisable; // 延迟写回
                        reg_waddr_o = rd; // 目的寄存器
                        reg1_raddr_o = `ZeroReg; // 读地址清零
                        reg2_raddr_o = `ZeroReg; // 读地址清零
                        op1_jump_o = inst_addr_i; // 记录PC
                        op2_jump_o = 32'h4; // 记录步进
                    end
                    `INST_IFIRE: begin // if指令
                        reg_we_o = `WriteEnable; // 写寄存器
                        reg_waddr_o = rd; // 目的寄存器
                        reg1_raddr_o = rs1; // 源寄存器1
                        reg2_raddr_o = 5'd31; // 源寄存器2=x31
                        op1_o = reg1_rdata_i; // 操作数1
                        op2_o = {{20{inst_i[31]}}, inst_i[31:20]}; // 立即数
                        op1_jump_o = inst_addr_i; // 记录PC
                        op2_jump_o = 32'h4; // 记录步进
                    end
                    default: begin // 不支持的funct3
                        reg_we_o = `WriteDisable; // 禁止写寄存器
                        reg_waddr_o = `ZeroReg; // 写地址清零
                        reg1_raddr_o = `ZeroReg; // 读地址清零
                        reg2_raddr_o = `ZeroReg; // 读地址清零
                    end
                endcase // custom funct3 endcase
            end
            default: begin // 未识别操作码
                reg_we_o = `WriteDisable; // 禁止写寄存器
                reg_waddr_o = `ZeroReg; // 写地址清零
                reg1_raddr_o = `ZeroReg; // 读地址清零
                reg2_raddr_o = `ZeroReg; // 读地址清零
            end
        endcase // opcode endcase
    end

endmodule
