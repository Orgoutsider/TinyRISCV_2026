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

// 执行模块
// 纯组合逻辑电路
module ex( // 执行模块声明

    input wire rst, // 复位信号

    // from id
    input wire[`InstBus] inst_i,            // 指令内容
    input wire[`InstAddrBus] inst_addr_i,   // 指令地址
    input wire reg_we_i,                    // 是否写通用寄存器
    input wire[`RegAddrBus] reg_waddr_i,    // 写通用寄存器地址
    input wire[`RegBus] reg1_rdata_i,       // 通用寄存器1输入数据
    input wire[`RegBus] reg2_rdata_i,       // 通用寄存器2输入数据
    input wire csr_we_i,                    // 是否写CSR寄存器
    input wire[`MemAddrBus] csr_waddr_i,    // 写CSR寄存器地址
    input wire[`RegBus] csr_rdata_i,        // CSR寄存器输入数据
    input wire int_assert_i,                // 中断发生标志
    input wire[`InstAddrBus] int_addr_i,    // 中断跳转地址
    input wire[`MemAddrBus] op1_i, // 操作数1
    input wire[`MemAddrBus] op2_i, // 操作数2
    input wire[`MemAddrBus] op1_jump_i, // 跳转操作数1
    input wire[`MemAddrBus] op2_jump_i, // 跳转操作数2

    // from mem
    input wire[`MemBus] mem_rdata_i,        // 内存输入数据

    // from div
    input wire div_ready_i,                 // 除法运算完成标志
    input wire[`RegBus] div_result_i,       // 除法运算结果
    input wire div_busy_i,                  // 除法运算忙标志
    input wire[`RegAddrBus] div_reg_waddr_i,// 除法运算结束后要写的寄存器地址

    // from custom instruction unit
    input wire custom_ready_i,            // 自定义指令完成标志
    input wire custom_busy_i,             // 自定义指令忙标志
    input wire custom_reg_we_i,           // 自定义写回使能
    input wire[`RegAddrBus] custom_reg_waddr_i, // 自定义写回地址
    input wire[`RegBus] custom_reg_wdata_i,     // 自定义写回数据

    // to mem
    output reg[`MemBus] mem_wdata_o,        // 写内存数据
    output reg[`MemAddrBus] mem_raddr_o,    // 读内存地址
    output reg[`MemAddrBus] mem_waddr_o,    // 写内存地址
    output wire mem_we_o,                   // 是否要写内存
    output wire mem_req_o,                  // 请求访问内存标志

    // to regs
    output wire[`RegBus] reg_wdata_o,       // 写寄存器数据
    output wire reg_we_o,                   // 是否要写通用寄存器
    output wire[`RegAddrBus] reg_waddr_o,   // 写通用寄存器地址

    // to csr reg
    output reg[`RegBus] csr_wdata_o,        // 写CSR寄存器数据
    output wire csr_we_o,                   // 是否要写CSR寄存器
    output wire[`MemAddrBus] csr_waddr_o,   // 写CSR寄存器地址

    // to div
    output wire div_start_o,                // 开始除法运算标志
    output reg[`RegBus] div_dividend_o,     // 被除数
    output reg[`RegBus] div_divisor_o,      // 除数
    output reg[2:0] div_op_o,               // 具体是哪一条除法指令
    output reg[`RegAddrBus] div_reg_waddr_o,// 除法运算结束后要写的寄存器地址

    // to custom instruction unit
    output reg custom_start_o,            // 自定义指令启动
    output reg[2:0] custom_funct3_o,      // 自定义funct3
    output reg[11:0] custom_imm_o,        // 自定义立即数
    output reg[`RegBus] custom_rs1_data_o,// 自定义rs1数据
    output reg[`RegBus] custom_x31_data_o,// 自定义x31数据
    output reg[`RegAddrBus] custom_rd_o,  // 自定义rd

    // to ctrl
    output wire hold_flag_o,                // 是否暂停标志
    output wire jump_flag_o,                // 是否跳转标志
    output wire[`InstAddrBus] jump_addr_o   // 跳转目的地址

    ); // 端口列表结束

    wire[1:0] mem_raddr_index; // 读内存地址低两位
    wire[1:0] mem_waddr_index; // 写内存地址低两位
    wire[`DoubleRegBus] mul_temp; // 乘法结果
    wire[`DoubleRegBus] mul_temp_invert; // 乘法结果取补
    wire[31:0] sr_shift; // 可变右移结果
    wire[31:0] sri_shift; // 立即数右移结果
    wire[31:0] sr_shift_mask; // 右移掩码
    wire[31:0] sri_shift_mask; // 立即数右移掩码
    wire[31:0] op1_add_op2_res; // op1+op2
    wire[31:0] op1_jump_add_op2_jump_res; // 跳转目标计算
    wire[31:0] reg1_data_invert; // reg1取补
    wire[31:0] reg2_data_invert; // reg2取补
    wire op1_ge_op2_signed; // 有符号比较结果
    wire op1_ge_op2_unsigned; // 无符号比较结果
    wire op1_eq_op2; // 相等比较结果
    reg[`RegBus] mul_op1; // 乘法操作数1
    reg[`RegBus] mul_op2; // 乘法操作数2
    wire[6:0] opcode; // 操作码
    wire[2:0] funct3; // funct3
    wire[6:0] funct7; // funct7
    wire[4:0] rd; // 目的寄存器
    wire[4:0] uimm; // CSR立即数
    reg[`RegBus] reg_wdata; // 写回数据
    reg reg_we; // 写回使能
    reg[`RegAddrBus] reg_waddr; // 写回地址
    reg[`RegBus] div_wdata; // 除法写回数据
    reg div_we; // 除法写回使能
    reg[`RegAddrBus] div_waddr; // 除法写回地址
    reg div_hold_flag; // 除法暂停标志
    reg div_jump_flag; // 除法跳转标志
    reg[`InstAddrBus] div_jump_addr; // 除法跳转地址
    reg hold_flag; // 暂停标志
    reg jump_flag; // 跳转标志
    reg[`InstAddrBus] jump_addr; // 跳转地址
    reg mem_we; // 内存写使能
    reg mem_req; // 内存请求
    reg div_start; // 除法启动
    reg custom_inflight; // custom_unit is busy with the current EX custom instruction
    wire is_custom_inst;
    wire is_sid_inst;
    wire is_rt_inst;
    wire is_ifire_inst;
    wire ifire_need_custom;
    wire custom_need_start;
    wire custom_start_pulse;
    wire custom_hold_req;
    wire[31:0] ifire_sign_ext_imm;

    wire wb_from_custom; // 写回来自自定义单元
    wire wb_from_div; // 写回来自除法单元

    assign opcode = inst_i[6:0]; // 提取操作码
    assign funct3 = inst_i[14:12]; // 提取funct3
    assign funct7 = inst_i[31:25]; // 提取funct7
    assign rd = inst_i[11:7]; // 提取rd
    assign uimm = inst_i[19:15]; // 提取uimm

    assign sr_shift = reg1_rdata_i >> reg2_rdata_i[4:0]; // 变量右移
    assign sri_shift = reg1_rdata_i >> inst_i[24:20]; // 立即数右移
    assign sr_shift_mask = 32'hffffffff >> reg2_rdata_i[4:0]; // 变量右移掩码
    assign sri_shift_mask = 32'hffffffff >> inst_i[24:20]; // 立即数右移掩码

    assign op1_add_op2_res = op1_i + op2_i; // 加法结果
    assign op1_jump_add_op2_jump_res = op1_jump_i + op2_jump_i; // 跳转目标

    assign reg1_data_invert = ~reg1_rdata_i + 1; // reg1取补
    assign reg2_data_invert = ~reg2_rdata_i + 1; // reg2取补

    // 有符号数比较
    assign op1_ge_op2_signed = $signed(op1_i) >= $signed(op2_i); // 有符号比较
    // 无符号数比较
    assign op1_ge_op2_unsigned = op1_i >= op2_i; // 无符号比较
    assign op1_eq_op2 = (op1_i == op2_i); // 相等比较

    assign mul_temp = mul_op1 * mul_op2; // 乘法结果
    assign mul_temp_invert = ~mul_temp + 1; // 乘法结果取补

    assign mem_raddr_index = (reg1_rdata_i + {{20{inst_i[31]}}, inst_i[31:20]}) & 2'b11; // 读地址低两位
    assign mem_waddr_index = (reg1_rdata_i + {{20{inst_i[31]}}, inst_i[31:25], inst_i[11:7]}) & 2'b11; // 写地址低两位

    assign div_start_o = (int_assert_i == `INT_ASSERT)? `DivStop: div_start; // 中断时禁用除法启动

    assign wb_from_custom = custom_reg_we_i; // 写回来自自定义
    assign is_custom_inst = (opcode == `INST_CUSTOM);
    assign is_sid_inst = is_custom_inst && (funct3 == `INST_SID);
    assign is_rt_inst = is_custom_inst && (funct3 == `INST_RT);
    assign is_ifire_inst = is_custom_inst && (funct3 == `INST_IFIRE);
    assign ifire_need_custom = is_ifire_inst && (inst_i[31:20] == 12'h000) &&
                               ($signed(reg1_rdata_i) >= $signed(reg2_rdata_i));
    assign custom_need_start = is_sid_inst || is_rt_inst || ifire_need_custom;
    assign custom_start_pulse = (rst == `RstDisable) && (int_assert_i != `INT_ASSERT) &&
                                custom_need_start && (custom_inflight == 1'b0) &&
                                (custom_busy_i == 1'b0) && (custom_ready_i == 1'b0);
    assign custom_hold_req = custom_need_start && (custom_ready_i == 1'b0);
    assign ifire_sign_ext_imm = {{20{inst_i[31]}}, inst_i[31:20]};
    assign wb_from_div = div_we; // 写回来自除法

    assign reg_wdata_o = wb_from_custom ? custom_reg_wdata_i : // 写回数据优先自定义
                         (wb_from_div ? div_wdata : reg_wdata); // 其次除法否则普通
    // 响应中断时不写通用寄存器
    assign reg_we_o = (int_assert_i == `INT_ASSERT)? `WriteDisable: // 中断禁止写回
                      (reg_we || div_we || custom_reg_we_i); // 正常写使能
    assign reg_waddr_o = wb_from_custom ? custom_reg_waddr_i : // 写回地址优先自定义
                         (wb_from_div ? div_waddr : reg_waddr); // 其次除法否则普通

    // 响应中断时不写内存
    assign mem_we_o = (int_assert_i == `INT_ASSERT)? `WriteDisable: mem_we; // 内存写使能选择

    // 响应中断时不向总线请求访问内存
    assign mem_req_o = (int_assert_i == `INT_ASSERT)? `RIB_NREQ: mem_req; // 内存请求选择

    assign hold_flag_o = hold_flag || div_hold_flag || custom_hold_req; // 暂停条件
    assign jump_flag_o = jump_flag || div_jump_flag || ((int_assert_i == `INT_ASSERT)? `JumpEnable: `JumpDisable); // 跳转标志选择
    assign jump_addr_o = (int_assert_i == `INT_ASSERT)? int_addr_i: (div_jump_flag ? div_jump_addr : jump_addr); // 跳转地址选择

    // 响应中断时不写CSR寄存器
    assign csr_we_o = (int_assert_i == `INT_ASSERT)? `WriteDisable: csr_we_i; // CSR写使能选择
    assign csr_waddr_o = csr_waddr_i; // CSR写地址直通


    // 处理乘法指令
    always @ (*) begin // 乘法操作数选择
        if ((opcode == `INST_TYPE_R_M) && (funct7 == 7'b0000001)) begin // 乘法类指令
            case (funct3) // 根据funct3选择
                `INST_MUL, `INST_MULHU: begin // 无符号乘法
                    mul_op1 = reg1_rdata_i; // op1取rs1
                    mul_op2 = reg2_rdata_i; // op2取rs2
                end // 分支结束
                `INST_MULHSU: begin // 有符号/无符号混合
                    mul_op1 = (reg1_rdata_i[31] == 1'b1)? (reg1_data_invert): reg1_rdata_i; // op1取绝对值
                    mul_op2 = reg2_rdata_i; // op2取rs2
                end // 分支结束
                `INST_MULH: begin // 有符号乘法高位
                    mul_op1 = (reg1_rdata_i[31] == 1'b1)? (reg1_data_invert): reg1_rdata_i; // op1取绝对值
                    mul_op2 = (reg2_rdata_i[31] == 1'b1)? (reg2_data_invert): reg2_rdata_i; // op2取绝对值
                end // 分支结束
                default: begin // 默认情况
                    mul_op1 = reg1_rdata_i; // op1默认rs1
                    mul_op2 = reg2_rdata_i; // op2默认rs2
                end // 分支结束
            endcase // case结束
        end else begin // 非乘法指令
            mul_op1 = reg1_rdata_i; // op1默认rs1
            mul_op2 = reg2_rdata_i; // op2默认rs2
        end // if结束
    end // always结束

    // 处理除法指令
    always @ (*) begin // 除法控制与写回
        div_dividend_o = reg1_rdata_i; // 被除数
        div_divisor_o = reg2_rdata_i; // 除数
        div_op_o = funct3; // 除法操作码
        div_reg_waddr_o = reg_waddr_i; // 写回地址
        if ((opcode == `INST_TYPE_R_M) && (funct7 == 7'b0000001)) begin // 除法类指令
            div_we = `WriteDisable; // 默认不写回
            div_wdata = `ZeroWord; // 默认写回数据
            div_waddr = `ZeroWord; // 默认写回地址
            case (funct3) // 根据funct3
                `INST_DIV, `INST_DIVU, `INST_REM, `INST_REMU: begin // 除法/取余
                    div_start = `DivStart; // 启动除法
                    div_jump_flag = `JumpEnable; // 发起跳转
                    div_hold_flag = `HoldEnable; // 暂停流水
                    div_jump_addr = op1_jump_add_op2_jump_res; // 跳转地址
                end // 分支结束
                default: begin // 非法funct3
                    div_start = `DivStop; // 不启动
                    div_jump_flag = `JumpDisable; // 不跳转
                    div_hold_flag = `HoldDisable; // 不暂停
                    div_jump_addr = `ZeroWord; // 地址清零
                end // 分支结束
            endcase // case结束
        end else begin // 非除法指令
            div_jump_flag = `JumpDisable; // 不跳转
            div_jump_addr = `ZeroWord; // 地址清零
            if (div_busy_i == `True) begin // 除法单元忙
                div_start = `DivStart; // 保持启动
                div_we = `WriteDisable; // 不写回
                div_wdata = `ZeroWord; // 数据清零
                div_waddr = `ZeroWord; // 地址清零
                div_hold_flag = `HoldEnable; // 暂停流水
            end else begin // 除法单元不忙
                div_start = `DivStop; // 停止启动
                div_hold_flag = `HoldDisable; // 解除暂停
                if (div_ready_i == `DivResultReady) begin // 结果就绪
                    div_wdata = div_result_i; // 写回结果
                    div_waddr = div_reg_waddr_i; // 写回地址
                    div_we = `WriteEnable; // 允许写回
                end else begin // 结果未就绪
                    div_we = `WriteDisable; // 不写回
                    div_wdata = `ZeroWord; // 数据清零
                    div_waddr = `ZeroWord; // 地址清零
                end // if结束
            end // else结束
        end // if结束
    end // always结束

    // 执行
    always @ (*) begin // 执行主组合逻辑
        reg_we = reg_we_i; // 默认写使能
        reg_waddr = reg_waddr_i; // 默认写地址
        mem_req = `RIB_NREQ; // 默认不请求内存
        csr_wdata_o = `ZeroWord; // 默认CSR写数据
        custom_inflight = (rst == `RstEnable || int_assert_i == `INT_ASSERT) ? 1'b0 :
                          (custom_busy_i && (custom_ready_i == 1'b0)); // block re-start while custom_unit is active
        custom_start_o = 1'b0; // 默认不启动自定义
        custom_funct3_o = funct3; // 默认funct3
        custom_imm_o = inst_i[31:20]; // 默认立即数
        custom_rs1_data_o = reg1_rdata_i; // 默认rs1数据
        custom_x31_data_o = reg2_rdata_i; // 默认x31数据
        custom_rd_o = rd; // 默认rd

        case (opcode) // 操作码译码
            `INST_TYPE_I: begin // I型运算
                case (funct3) // I型子操作
                    `INST_ADDI: begin // ADDI
                        jump_flag = `JumpDisable; // 不跳转
                        hold_flag = `HoldDisable; // 不暂停
                        jump_addr = `ZeroWord; // 跳转地址清零
                        mem_wdata_o = `ZeroWord; // 写数据清零
                        mem_raddr_o = `ZeroWord; // 读地址清零
                        mem_waddr_o = `ZeroWord; // 写地址清零
                        mem_we = `WriteDisable; // 禁止写内存
                        reg_wdata = op1_add_op2_res; // 写回加法结果
                    end
                    `INST_SLTI: begin // SLTI
                        jump_flag = `JumpDisable; // 不跳转
                        hold_flag = `HoldDisable; // 不暂停
                        jump_addr = `ZeroWord; // 跳转地址清零
                        mem_wdata_o = `ZeroWord; // 写数据清零
                        mem_raddr_o = `ZeroWord; // 读地址清零
                        mem_waddr_o = `ZeroWord; // 写地址清零
                        mem_we = `WriteDisable; // 禁止写内存
                        reg_wdata = {32{(~op1_ge_op2_signed)}} & 32'h1; // 有符号比较
                    end
                    `INST_SLTIU: begin // SLTIU
                        jump_flag = `JumpDisable; // 不跳转
                        hold_flag = `HoldDisable; // 不暂停
                        jump_addr = `ZeroWord; // 跳转地址清零
                        mem_wdata_o = `ZeroWord; // 写数据清零
                        mem_raddr_o = `ZeroWord; // 读地址清零
                        mem_waddr_o = `ZeroWord; // 写地址清零
                        mem_we = `WriteDisable; // 禁止写内存
                        reg_wdata = {32{(~op1_ge_op2_unsigned)}} & 32'h1; // 无符号比较
                    end
                    `INST_XORI: begin // XORI
                        jump_flag = `JumpDisable; // 不跳转
                        hold_flag = `HoldDisable; // 不暂停
                        jump_addr = `ZeroWord; // 跳转地址清零
                        mem_wdata_o = `ZeroWord; // 写数据清零
                        mem_raddr_o = `ZeroWord; // 读地址清零
                        mem_waddr_o = `ZeroWord; // 写地址清零
                        mem_we = `WriteDisable; // 禁止写内存
                        reg_wdata = op1_i ^ op2_i; // 异或结果
                    end
                    `INST_ORI: begin // ORI
                        jump_flag = `JumpDisable; // 不跳转
                        hold_flag = `HoldDisable; // 不暂停
                        jump_addr = `ZeroWord; // 跳转地址清零
                        mem_wdata_o = `ZeroWord; // 写数据清零
                        mem_raddr_o = `ZeroWord; // 读地址清零
                        mem_waddr_o = `ZeroWord; // 写地址清零
                        mem_we = `WriteDisable; // 禁止写内存
                        reg_wdata = op1_i | op2_i; // 或结果
                    end
                    `INST_ANDI: begin // ANDI
                        jump_flag = `JumpDisable; // 不跳转
                        hold_flag = `HoldDisable; // 不暂停
                        jump_addr = `ZeroWord; // 跳转地址清零
                        mem_wdata_o = `ZeroWord; // 写数据清零
                        mem_raddr_o = `ZeroWord; // 读地址清零
                        mem_waddr_o = `ZeroWord; // 写地址清零
                        mem_we = `WriteDisable; // 禁止写内存
                        reg_wdata = op1_i & op2_i; // 与结果
                    end
                    `INST_SLLI: begin // SLLI
                        jump_flag = `JumpDisable; // 不跳转
                        hold_flag = `HoldDisable; // 不暂停
                        jump_addr = `ZeroWord; // 跳转地址清零
                        mem_wdata_o = `ZeroWord; // 写数据清零
                        mem_raddr_o = `ZeroWord; // 读地址清零
                        mem_waddr_o = `ZeroWord; // 写地址清零
                        mem_we = `WriteDisable; // 禁止写内存
                        reg_wdata = reg1_rdata_i << inst_i[24:20]; // 逻辑左移
                    end
                    `INST_SRI: begin // SRLI/SRAI
                        jump_flag = `JumpDisable; // 不跳转
                        hold_flag = `HoldDisable; // 不暂停
                        jump_addr = `ZeroWord; // 跳转地址清零
                        mem_wdata_o = `ZeroWord; // 写数据清零
                        mem_raddr_o = `ZeroWord; // 读地址清零
                        mem_waddr_o = `ZeroWord; // 写地址清零
                        mem_we = `WriteDisable; // 禁止写内存
                        if (inst_i[30] == 1'b1) begin // SRAI
                            reg_wdata = (sri_shift & sri_shift_mask) | ({32{reg1_rdata_i[31]}} & (~sri_shift_mask)); // 算术右移
                        end else begin // SRLI
                            reg_wdata = reg1_rdata_i >> inst_i[24:20]; // 逻辑右移
                        end
                    end
                    default: begin // 默认
                        jump_flag = `JumpDisable; // 不跳转
                        hold_flag = `HoldDisable; // 不暂停
                        jump_addr = `ZeroWord; // 跳转地址清零
                        mem_wdata_o = `ZeroWord; // 写数据清零
                        mem_raddr_o = `ZeroWord; // 读地址清零
                        mem_waddr_o = `ZeroWord; // 写地址清零
                        mem_we = `WriteDisable; // 禁止写内存
                        reg_wdata = `ZeroWord; // 写回清零
                    end
                endcase // I型子操作结束
            end
            `INST_TYPE_R_M: begin // R型/乘除
                if ((funct7 == 7'b0000000) || (funct7 == 7'b0100000)) begin // 普通R型
                    case (funct3) // R型子操作
                        `INST_ADD_SUB: begin // ADD/SUB
                            jump_flag = `JumpDisable; // 不跳转
                            hold_flag = `HoldDisable; // 不暂停
                            jump_addr = `ZeroWord; // 跳转地址清零
                            mem_wdata_o = `ZeroWord; // 写数据清零
                            mem_raddr_o = `ZeroWord; // 读地址清零
                            mem_waddr_o = `ZeroWord; // 写地址清零
                            mem_we = `WriteDisable; // 禁止写内存
                            if (inst_i[30] == 1'b0) begin // ADD
                                reg_wdata = op1_add_op2_res; // 加法结果
                            end else begin // SUB
                                reg_wdata = op1_i - op2_i; // 减法结果
                            end
                        end
                        `INST_SLL: begin // SLL
                            jump_flag = `JumpDisable; // 不跳转
                            hold_flag = `HoldDisable; // 不暂停
                            jump_addr = `ZeroWord; // 跳转地址清零
                            mem_wdata_o = `ZeroWord; // 写数据清零
                            mem_raddr_o = `ZeroWord; // 读地址清零
                            mem_waddr_o = `ZeroWord; // 写地址清零
                            mem_we = `WriteDisable; // 禁止写内存
                            reg_wdata = op1_i << op2_i[4:0]; // 逻辑左移
                        end
                        `INST_SLT: begin // SLT
                            jump_flag = `JumpDisable; // 不跳转
                            hold_flag = `HoldDisable; // 不暂停
                            jump_addr = `ZeroWord; // 跳转地址清零
                            mem_wdata_o = `ZeroWord; // 写数据清零
                            mem_raddr_o = `ZeroWord; // 读地址清零
                            mem_waddr_o = `ZeroWord; // 写地址清零
                            mem_we = `WriteDisable; // 禁止写内存
                            reg_wdata = {32{(~op1_ge_op2_signed)}} & 32'h1; // 有符号比较
                        end
                        `INST_SLTU: begin // SLTU
                            jump_flag = `JumpDisable; // 不跳转
                            hold_flag = `HoldDisable; // 不暂停
                            jump_addr = `ZeroWord; // 跳转地址清零
                            mem_wdata_o = `ZeroWord; // 写数据清零
                            mem_raddr_o = `ZeroWord; // 读地址清零
                            mem_waddr_o = `ZeroWord; // 写地址清零
                            mem_we = `WriteDisable; // 禁止写内存
                            reg_wdata = {32{(~op1_ge_op2_unsigned)}} & 32'h1; // 无符号比较
                        end
                        `INST_XOR: begin // XOR
                            jump_flag = `JumpDisable; // 不跳转
                            hold_flag = `HoldDisable; // 不暂停
                            jump_addr = `ZeroWord; // 跳转地址清零
                            mem_wdata_o = `ZeroWord; // 写数据清零
                            mem_raddr_o = `ZeroWord; // 读地址清零
                            mem_waddr_o = `ZeroWord; // 写地址清零
                            mem_we = `WriteDisable; // 禁止写内存
                            reg_wdata = op1_i ^ op2_i; // 异或结果
                        end
                        `INST_SR: begin // SRL/SRA
                            jump_flag = `JumpDisable; // 不跳转
                            hold_flag = `HoldDisable; // 不暂停
                            jump_addr = `ZeroWord; // 跳转地址清零
                            mem_wdata_o = `ZeroWord; // 写数据清零
                            mem_raddr_o = `ZeroWord; // 读地址清零
                            mem_waddr_o = `ZeroWord; // 写地址清零
                            mem_we = `WriteDisable; // 禁止写内存
                            if (inst_i[30] == 1'b1) begin // SRA
                                reg_wdata = (sr_shift & sr_shift_mask) | ({32{reg1_rdata_i[31]}} & (~sr_shift_mask)); // 算术右移
                            end else begin // SRL
                                reg_wdata = reg1_rdata_i >> reg2_rdata_i[4:0]; // 逻辑右移
                            end
                        end
                        `INST_OR: begin // OR
                            jump_flag = `JumpDisable; // 不跳转
                            hold_flag = `HoldDisable; // 不暂停
                            jump_addr = `ZeroWord; // 跳转地址清零
                            mem_wdata_o = `ZeroWord; // 写数据清零
                            mem_raddr_o = `ZeroWord; // 读地址清零
                            mem_waddr_o = `ZeroWord; // 写地址清零
                            mem_we = `WriteDisable; // 禁止写内存
                            reg_wdata = op1_i | op2_i; // 或结果
                        end
                        `INST_AND: begin // AND
                            jump_flag = `JumpDisable; // 不跳转
                            hold_flag = `HoldDisable; // 不暂停
                            jump_addr = `ZeroWord; // 跳转地址清零
                            mem_wdata_o = `ZeroWord; // 写数据清零
                            mem_raddr_o = `ZeroWord; // 读地址清零
                            mem_waddr_o = `ZeroWord; // 写地址清零
                            mem_we = `WriteDisable; // 禁止写内存
                            reg_wdata = op1_i & op2_i; // 与结果
                        end
                        default: begin // 默认
                            jump_flag = `JumpDisable; // 不跳转
                            hold_flag = `HoldDisable; // 不暂停
                            jump_addr = `ZeroWord; // 跳转地址清零
                            mem_wdata_o = `ZeroWord; // 写数据清零
                            mem_raddr_o = `ZeroWord; // 读地址清零
                            mem_waddr_o = `ZeroWord; // 写地址清零
                            mem_we = `WriteDisable; // 禁止写内存
                            reg_wdata = `ZeroWord; // 写回清零
                        end
                    endcase // R型子操作结束
                end else if (funct7 == 7'b0000001) begin // 乘法指令
                    case (funct3) // 乘法子操作
                        `INST_MUL: begin // MUL
                            jump_flag = `JumpDisable; // 不跳转
                            hold_flag = `HoldDisable; // 不暂停
                            jump_addr = `ZeroWord; // 跳转地址清零
                            mem_wdata_o = `ZeroWord; // 写数据清零
                            mem_raddr_o = `ZeroWord; // 读地址清零
                            mem_waddr_o = `ZeroWord; // 写地址清零
                            mem_we = `WriteDisable; // 禁止写内存
                            reg_wdata = mul_temp[31:0]; // 低32位结果
                        end
                        `INST_MULHU: begin // MULHU
                            jump_flag = `JumpDisable; // 不跳转
                            hold_flag = `HoldDisable; // 不暂停
                            jump_addr = `ZeroWord; // 跳转地址清零
                            mem_wdata_o = `ZeroWord; // 写数据清零
                            mem_raddr_o = `ZeroWord; // 读地址清零
                            mem_waddr_o = `ZeroWord; // 写地址清零
                            mem_we = `WriteDisable; // 禁止写内存
                            reg_wdata = mul_temp[63:32]; // 高32位结果
                        end
                        `INST_MULH: begin // MULH
                            jump_flag = `JumpDisable; // 不跳转
                            hold_flag = `HoldDisable; // 不暂停
                            jump_addr = `ZeroWord; // 跳转地址清零
                            mem_wdata_o = `ZeroWord; // 写数据清零
                            mem_raddr_o = `ZeroWord; // 读地址清零
                            mem_waddr_o = `ZeroWord; // 写地址清零
                            mem_we = `WriteDisable; // 禁止写内存
                            case ({reg1_rdata_i[31], reg2_rdata_i[31]}) // 符号组合
                                2'b00: begin // 正正
                                    reg_wdata = mul_temp[63:32]; // 取高位
                                end
                                2'b11: begin // 负负
                                    reg_wdata = mul_temp[63:32]; // 取高位
                                end
                                2'b10: begin // 负正
                                    reg_wdata = mul_temp_invert[63:32]; // 取补
                                end
                                default: begin // 正负
                                    reg_wdata = mul_temp_invert[63:32]; // 取补
                                end
                            endcase // 符号组合结束
                        end
                        `INST_MULHSU: begin // MULHSU
                            jump_flag = `JumpDisable; // 不跳转
                            hold_flag = `HoldDisable; // 不暂停
                            jump_addr = `ZeroWord; // 跳转地址清零
                            mem_wdata_o = `ZeroWord; // 写数据清零
                            mem_raddr_o = `ZeroWord; // 读地址清零
                            mem_waddr_o = `ZeroWord; // 写地址清零
                            mem_we = `WriteDisable; // 禁止写内存
                            if (reg1_rdata_i[31] == 1'b1) begin // rs1为负
                                reg_wdata = mul_temp_invert[63:32]; // 取补高位
                            end else begin // rs1为正
                                reg_wdata = mul_temp[63:32]; // 取高位
                            end
                        end
                        default: begin // 默认
                            jump_flag = `JumpDisable; // 不跳转
                            hold_flag = `HoldDisable; // 不暂停
                            jump_addr = `ZeroWord; // 跳转地址清零
                            mem_wdata_o = `ZeroWord; // 写数据清零
                            mem_raddr_o = `ZeroWord; // 读地址清零
                            mem_waddr_o = `ZeroWord; // 写地址清零
                            mem_we = `WriteDisable; // 禁止写内存
                            reg_wdata = `ZeroWord; // 写回清零
                        end
                    endcase // 乘法子操作结束
                end else begin // 其他funct7
                    jump_flag = `JumpDisable; // 不跳转
                    hold_flag = `HoldDisable; // 不暂停
                    jump_addr = `ZeroWord; // 跳转地址清零
                    mem_wdata_o = `ZeroWord; // 写数据清零
                    mem_raddr_o = `ZeroWord; // 读地址清零
                    mem_waddr_o = `ZeroWord; // 写地址清零
                    mem_we = `WriteDisable; // 禁止写内存
                    reg_wdata = `ZeroWord; // 写回清零
                end
            end
            `INST_TYPE_L: begin // Load指令
                case (funct3) // Load子操作
                    `INST_LB: begin // LB
                        jump_flag = `JumpDisable; // 不跳转
                        hold_flag = `HoldDisable; // 不暂停
                        jump_addr = `ZeroWord; // 跳转地址清零
                        mem_wdata_o = `ZeroWord; // 写数据清零
                        mem_waddr_o = `ZeroWord; // 写地址清零
                        mem_we = `WriteDisable; // 禁止写内存
                        mem_req = `RIB_REQ; // 请求内存
                        mem_raddr_o = op1_add_op2_res; // 读地址
                        case (mem_raddr_index) // 字节选择
                            2'b00: begin // 字节0
                                reg_wdata = {{24{mem_rdata_i[7]}}, mem_rdata_i[7:0]}; // 符号扩展
                            end
                            2'b01: begin // 字节1
                                reg_wdata = {{24{mem_rdata_i[15]}}, mem_rdata_i[15:8]}; // 符号扩展
                            end
                            2'b10: begin // 字节2
                                reg_wdata = {{24{mem_rdata_i[23]}}, mem_rdata_i[23:16]}; // 符号扩展
                            end
                            default: begin // 字节3
                                reg_wdata = {{24{mem_rdata_i[31]}}, mem_rdata_i[31:24]}; // 符号扩展
                            end
                        endcase // 字节选择结束
                    end
                    `INST_LH: begin // LH
                        jump_flag = `JumpDisable; // 不跳转
                        hold_flag = `HoldDisable; // 不暂停
                        jump_addr = `ZeroWord; // 跳转地址清零
                        mem_wdata_o = `ZeroWord; // 写数据清零
                        mem_waddr_o = `ZeroWord; // 写地址清零
                        mem_we = `WriteDisable; // 禁止写内存
                        mem_req = `RIB_REQ; // 请求内存
                        mem_raddr_o = op1_add_op2_res; // 读地址
                        if (mem_raddr_index == 2'b0) begin // 低半字
                            reg_wdata = {{16{mem_rdata_i[15]}}, mem_rdata_i[15:0]}; // 符号扩展
                        end else begin // 高半字
                            reg_wdata = {{16{mem_rdata_i[31]}}, mem_rdata_i[31:16]}; // 符号扩展
                        end
                    end
                    `INST_LW: begin // LW
                        jump_flag = `JumpDisable; // 不跳转
                        hold_flag = `HoldDisable; // 不暂停
                        jump_addr = `ZeroWord; // 跳转地址清零
                        mem_wdata_o = `ZeroWord; // 写数据清零
                        mem_waddr_o = `ZeroWord; // 写地址清零
                        mem_we = `WriteDisable; // 禁止写内存
                        mem_req = `RIB_REQ; // 请求内存
                        mem_raddr_o = op1_add_op2_res; // 读地址
                        reg_wdata = mem_rdata_i; // 写回整字
                    end
                    `INST_LBU: begin // LBU
                        jump_flag = `JumpDisable; // 不跳转
                        hold_flag = `HoldDisable; // 不暂停
                        jump_addr = `ZeroWord; // 跳转地址清零
                        mem_wdata_o = `ZeroWord; // 写数据清零
                        mem_waddr_o = `ZeroWord; // 写地址清零
                        mem_we = `WriteDisable; // 禁止写内存
                        mem_req = `RIB_REQ; // 请求内存
                        mem_raddr_o = op1_add_op2_res; // 读地址
                        case (mem_raddr_index) // 字节选择
                            2'b00: begin // 字节0
                                reg_wdata = {24'h0, mem_rdata_i[7:0]}; // 零扩展
                            end
                            2'b01: begin // 字节1
                                reg_wdata = {24'h0, mem_rdata_i[15:8]}; // 零扩展
                            end
                            2'b10: begin // 字节2
                                reg_wdata = {24'h0, mem_rdata_i[23:16]}; // 零扩展
                            end
                            default: begin // 字节3
                                reg_wdata = {24'h0, mem_rdata_i[31:24]}; // 零扩展
                            end
                        endcase // 字节选择结束
                    end
                    `INST_LHU: begin // LHU
                        jump_flag = `JumpDisable; // 不跳转
                        hold_flag = `HoldDisable; // 不暂停
                        jump_addr = `ZeroWord; // 跳转地址清零
                        mem_wdata_o = `ZeroWord; // 写数据清零
                        mem_waddr_o = `ZeroWord; // 写地址清零
                        mem_we = `WriteDisable; // 禁止写内存
                        mem_req = `RIB_REQ; // 请求内存
                        mem_raddr_o = op1_add_op2_res; // 读地址
                        if (mem_raddr_index == 2'b0) begin // 低半字
                            reg_wdata = {16'h0, mem_rdata_i[15:0]}; // 零扩展
                        end else begin // 高半字
                            reg_wdata = {16'h0, mem_rdata_i[31:16]}; // 零扩展
                        end
                    end
                    default: begin // 默认
                        jump_flag = `JumpDisable; // 不跳转
                        hold_flag = `HoldDisable; // 不暂停
                        jump_addr = `ZeroWord; // 跳转地址清零
                        mem_wdata_o = `ZeroWord; // 写数据清零
                        mem_raddr_o = `ZeroWord; // 读地址清零
                        mem_waddr_o = `ZeroWord; // 写地址清零
                        mem_we = `WriteDisable; // 禁止写内存
                        reg_wdata = `ZeroWord; // 写回清零
                    end
                endcase // Load子操作结束
            end
            `INST_TYPE_S: begin // Store指令
                case (funct3) // Store子操作
                    `INST_SB: begin // SB
                        jump_flag = `JumpDisable; // 不跳转
                        hold_flag = `HoldDisable; // 不暂停
                        jump_addr = `ZeroWord; // 跳转地址清零
                        reg_wdata = `ZeroWord; // 写回清零
                        mem_we = `WriteEnable; // 允许写内存
                        mem_req = `RIB_REQ; // 请求内存
                        mem_waddr_o = op1_add_op2_res; // 写地址
                        mem_raddr_o = op1_add_op2_res; // 读地址
                        case (mem_waddr_index) // 字节选择
                            2'b00: begin // 字节0
                                mem_wdata_o = {mem_rdata_i[31:8], reg2_rdata_i[7:0]}; // 写入低字节
                            end
                            2'b01: begin // 字节1
                                mem_wdata_o = {mem_rdata_i[31:16], reg2_rdata_i[7:0], mem_rdata_i[7:0]}; // 写入字节1
                            end
                            2'b10: begin // 字节2
                                mem_wdata_o = {mem_rdata_i[31:24], reg2_rdata_i[7:0], mem_rdata_i[15:0]}; // 写入字节2
                            end
                            default: begin // 字节3
                                mem_wdata_o = {reg2_rdata_i[7:0], mem_rdata_i[23:0]}; // 写入高字节
                            end
                        endcase // 字节选择结束
                    end
                    `INST_SH: begin // SH
                        jump_flag = `JumpDisable; // 不跳转
                        hold_flag = `HoldDisable; // 不暂停
                        jump_addr = `ZeroWord; // 跳转地址清零
                        reg_wdata = `ZeroWord; // 写回清零
                        mem_we = `WriteEnable; // 允许写内存
                        mem_req = `RIB_REQ; // 请求内存
                        mem_waddr_o = op1_add_op2_res; // 写地址
                        mem_raddr_o = op1_add_op2_res; // 读地址
                        if (mem_waddr_index == 2'b00) begin // 低半字
                            mem_wdata_o = {mem_rdata_i[31:16], reg2_rdata_i[15:0]}; // 写低半字
                        end else begin // 高半字
                            mem_wdata_o = {reg2_rdata_i[15:0], mem_rdata_i[15:0]}; // 写高半字
                        end
                    end
                    `INST_SW: begin // SW
                        jump_flag = `JumpDisable; // 不跳转
                        hold_flag = `HoldDisable; // 不暂停
                        jump_addr = `ZeroWord; // 跳转地址清零
                        reg_wdata = `ZeroWord; // 写回清零
                        mem_we = `WriteEnable; // 允许写内存
                        mem_req = `RIB_REQ; // 请求内存
                        mem_waddr_o = op1_add_op2_res; // 写地址
                        mem_raddr_o = op1_add_op2_res; // 读地址
                        mem_wdata_o = reg2_rdata_i; // 写数据
                    end
                    default: begin // 默认
                        jump_flag = `JumpDisable; // 不跳转
                        hold_flag = `HoldDisable; // 不暂停
                        jump_addr = `ZeroWord; // 跳转地址清零
                        mem_wdata_o = `ZeroWord; // 写数据清零
                        mem_raddr_o = `ZeroWord; // 读地址清零
                        mem_waddr_o = `ZeroWord; // 写地址清零
                        mem_we = `WriteDisable; // 禁止写内存
                        reg_wdata = `ZeroWord; // 写回清零
                    end
                endcase // Store子操作结束
            end
            `INST_TYPE_B: begin // 分支指令
                case (funct3) // 分支子操作
                    `INST_BEQ: begin // BEQ
                        hold_flag = `HoldDisable; // 不暂停
                        mem_wdata_o = `ZeroWord; // 写数据清零
                        mem_raddr_o = `ZeroWord; // 读地址清零
                        mem_waddr_o = `ZeroWord; // 写地址清零
                        mem_we = `WriteDisable; // 禁止写内存
                        reg_wdata = `ZeroWord; // 写回清零
                        jump_flag = op1_eq_op2 & `JumpEnable; // 相等则跳
                        jump_addr = {32{op1_eq_op2}} & op1_jump_add_op2_jump_res; // 跳转目标
                    end
                    `INST_BNE: begin // BNE
                        hold_flag = `HoldDisable; // 不暂停
                        mem_wdata_o = `ZeroWord; // 写数据清零
                        mem_raddr_o = `ZeroWord; // 读地址清零
                        mem_waddr_o = `ZeroWord; // 写地址清零
                        mem_we = `WriteDisable; // 禁止写内存
                        reg_wdata = `ZeroWord; // 写回清零
                        jump_flag = (~op1_eq_op2) & `JumpEnable; // 不等则跳
                        jump_addr = {32{(~op1_eq_op2)}} & op1_jump_add_op2_jump_res; // 跳转目标
                    end
                    `INST_BLT: begin // BLT
                        hold_flag = `HoldDisable; // 不暂停
                        mem_wdata_o = `ZeroWord; // 写数据清零
                        mem_raddr_o = `ZeroWord; // 读地址清零
                        mem_waddr_o = `ZeroWord; // 写地址清零
                        mem_we = `WriteDisable; // 禁止写内存
                        reg_wdata = `ZeroWord; // 写回清零
                        jump_flag = (~op1_ge_op2_signed) & `JumpEnable; // 小于则跳
                        jump_addr = {32{(~op1_ge_op2_signed)}} & op1_jump_add_op2_jump_res; // 跳转目标
                    end
                    `INST_BGE: begin // BGE
                        hold_flag = `HoldDisable; // 不暂停
                        mem_wdata_o = `ZeroWord; // 写数据清零
                        mem_raddr_o = `ZeroWord; // 读地址清零
                        mem_waddr_o = `ZeroWord; // 写地址清零
                        mem_we = `WriteDisable; // 禁止写内存
                        reg_wdata = `ZeroWord; // 写回清零
                        jump_flag = (op1_ge_op2_signed) & `JumpEnable; // 大于等于则跳
                        jump_addr = {32{(op1_ge_op2_signed)}} & op1_jump_add_op2_jump_res; // 跳转目标
                    end
                    `INST_BLTU: begin // BLTU
                        hold_flag = `HoldDisable; // 不暂停
                        mem_wdata_o = `ZeroWord; // 写数据清零
                        mem_raddr_o = `ZeroWord; // 读地址清零
                        mem_waddr_o = `ZeroWord; // 写地址清零
                        mem_we = `WriteDisable; // 禁止写内存
                        reg_wdata = `ZeroWord; // 写回清零
                        jump_flag = (~op1_ge_op2_unsigned) & `JumpEnable; // 无符号小于则跳
                        jump_addr = {32{(~op1_ge_op2_unsigned)}} & op1_jump_add_op2_jump_res; // 跳转目标
                    end
                    `INST_BGEU: begin // BGEU
                        hold_flag = `HoldDisable; // 不暂停
                        mem_wdata_o = `ZeroWord; // 写数据清零
                        mem_raddr_o = `ZeroWord; // 读地址清零
                        mem_waddr_o = `ZeroWord; // 写地址清零
                        mem_we = `WriteDisable; // 禁止写内存
                        reg_wdata = `ZeroWord; // 写回清零
                        jump_flag = (op1_ge_op2_unsigned) & `JumpEnable; // 无符号大于等于则跳
                        jump_addr = {32{(op1_ge_op2_unsigned)}} & op1_jump_add_op2_jump_res; // 跳转目标
                    end
                    default: begin // 默认
                        jump_flag = `JumpDisable; // 不跳转
                        hold_flag = `HoldDisable; // 不暂停
                        jump_addr = `ZeroWord; // 跳转地址清零
                        mem_wdata_o = `ZeroWord; // 写数据清零
                        mem_raddr_o = `ZeroWord; // 读地址清零
                        mem_waddr_o = `ZeroWord; // 写地址清零
                        mem_we = `WriteDisable; // 禁止写内存
                        reg_wdata = `ZeroWord; // 写回清零
                    end
                endcase // 分支子操作结束
            end
            `INST_JAL, `INST_JALR: begin // JAL/JALR
                hold_flag = `HoldDisable; // 不暂停
                mem_wdata_o = `ZeroWord; // 写数据清零
                mem_raddr_o = `ZeroWord; // 读地址清零
                mem_waddr_o = `ZeroWord; // 写地址清零
                mem_we = `WriteDisable; // 禁止写内存
                jump_flag = `JumpEnable; // 使能跳转
                jump_addr = op1_jump_add_op2_jump_res; // 跳转目标
                reg_wdata = op1_add_op2_res; // 写回返回地址
            end
            `INST_LUI, `INST_AUIPC: begin // LUI/AUIPC
                hold_flag = `HoldDisable; // 不暂停
                mem_wdata_o = `ZeroWord; // 写数据清零
                mem_raddr_o = `ZeroWord; // 读地址清零
                mem_waddr_o = `ZeroWord; // 写地址清零
                mem_we = `WriteDisable; // 禁止写内存
                jump_addr = `ZeroWord; // 跳转地址清零
                jump_flag = `JumpDisable; // 不跳转
                reg_wdata = op1_add_op2_res; // 写回结果
            end
            `INST_NOP_OP: begin // NOP
                jump_flag = `JumpDisable; // 不跳转
                hold_flag = `HoldDisable; // 不暂停
                jump_addr = `ZeroWord; // 跳转地址清零
                mem_wdata_o = `ZeroWord; // 写数据清零
                mem_raddr_o = `ZeroWord; // 读地址清零
                mem_waddr_o = `ZeroWord; // 写地址清零
                mem_we = `WriteDisable; // 禁止写内存
                reg_wdata = `ZeroWord; // 写回清零
            end
            `INST_FENCE: begin // FENCE
                hold_flag = `HoldDisable; // 不暂停
                mem_wdata_o = `ZeroWord; // 写数据清零
                mem_raddr_o = `ZeroWord; // 读地址清零
                mem_waddr_o = `ZeroWord; // 写地址清零
                mem_we = `WriteDisable; // 禁止写内存
                reg_wdata = `ZeroWord; // 写回清零
                jump_flag = `JumpEnable; // 强制跳转
                jump_addr = op1_jump_add_op2_jump_res; // 跳转目标
            end
            `INST_CSR: begin // CSR指令
                jump_flag = `JumpDisable; // 不跳转
                hold_flag = `HoldDisable; // 不暂停
                jump_addr = `ZeroWord; // 跳转地址清零
                mem_wdata_o = `ZeroWord; // 写数据清零
                mem_raddr_o = `ZeroWord; // 读地址清零
                mem_waddr_o = `ZeroWord; // 写地址清零
                mem_we = `WriteDisable; // 禁止写内存
                case (funct3) // CSR子操作
                    `INST_CSRRW: begin // CSRRW
                        csr_wdata_o = reg1_rdata_i; // 写CSR
                        reg_wdata = csr_rdata_i; // 读CSR
                    end
                    `INST_CSRRS: begin // CSRRS
                        csr_wdata_o = reg1_rdata_i | csr_rdata_i; // 置位
                        reg_wdata = csr_rdata_i; // 读CSR
                    end
                    `INST_CSRRC: begin // CSRRC
                        csr_wdata_o = csr_rdata_i & (~reg1_rdata_i); // 清位
                        reg_wdata = csr_rdata_i; // 读CSR
                    end
                    `INST_CSRRWI: begin // CSRRWI
                        csr_wdata_o = {27'h0, uimm}; // 立即数写CSR
                        reg_wdata = csr_rdata_i; // 读CSR
                    end
                    `INST_CSRRSI: begin // CSRRSI
                        csr_wdata_o = {27'h0, uimm} | csr_rdata_i; // 立即数置位
                        reg_wdata = csr_rdata_i; // 读CSR
                    end
                    `INST_CSRRCI: begin // CSRRCI
                        csr_wdata_o = (~{27'h0, uimm}) & csr_rdata_i; // 立即数清位
                        reg_wdata = csr_rdata_i; // 读CSR
                    end
                    default: begin // 默认
                        jump_flag = `JumpDisable; // 不跳转
                        hold_flag = `HoldDisable; // 不暂停
                        jump_addr = `ZeroWord; // 跳转地址清零
                        mem_wdata_o = `ZeroWord; // 写数据清零
                        mem_raddr_o = `ZeroWord; // 读地址清零
                        mem_waddr_o = `ZeroWord; // 写地址清零
                        mem_we = `WriteDisable; // 禁止写内存
                        reg_wdata = `ZeroWord; // 写回清零
                    end
                endcase // CSR子操作结束
            end
            `INST_CUSTOM: begin // 自定义指令
                jump_flag = `JumpDisable; // 不跳转
                hold_flag = `HoldDisable; // 不暂停
                jump_addr = `ZeroWord; // 跳转地址清零
                mem_wdata_o = `ZeroWord; // 写数据清零
                mem_raddr_o = `ZeroWord; // 读地址清零
                mem_waddr_o = `ZeroWord; // 写地址清零
                mem_we = `WriteDisable; // 禁止写内存
                reg_wdata = `ZeroWord; // 写回清零
                reg_waddr = reg_waddr_i; // 写回地址直通

                case (funct3) // 自定义子操作
                    `INST_SID: begin // 发送学号
                        reg_we = `WriteDisable; // 不写通用寄存器
                        custom_start_o = custom_start_pulse; // single-cycle start pulse
                        custom_funct3_o = funct3; // 传递funct3
                        custom_imm_o = inst_i[31:20]; // 传递立即数
                        custom_rs1_data_o = reg1_rdata_i; // 传递rs1
                        custom_x31_data_o = reg2_rdata_i; // 传递x31
                        custom_rd_o = rd; // 传递rd
                        hold_flag = (custom_ready_i == 1'b1) ? `HoldDisable : `HoldEnable; // wait for custom done
                        jump_flag = `JumpDisable; // no PC redirect; release hold to execute next instruction
                        jump_addr = `ZeroWord; // 跳转地址
                    end
                    `INST_RT: begin // 读取温度
                        reg_we = `WriteDisable; // 不写通用寄存器
                        custom_start_o = custom_start_pulse; // single-cycle start pulse
                        custom_funct3_o = funct3; // 传递funct3
                        custom_imm_o = inst_i[31:20]; // 传递立即数
                        // TODO: check id.v if it is correct
                        custom_rs1_data_o = reg1_rdata_i; // 传递rs1
                        custom_x31_data_o = reg2_rdata_i; // 传递x31
                        custom_rd_o = rd; // 传递rd
                        hold_flag = (custom_ready_i == 1'b1) ? `HoldDisable : `HoldEnable; // wait for custom done
                        jump_flag = `JumpDisable; // no PC redirect; release hold to execute next instruction
                        jump_addr = `ZeroWord; // 跳转地址
                    end
                    `INST_IFIRE: begin // IFIRE
                        if (inst_i[31:20] == 12'h000) begin // imm==0
                            if ($signed(reg1_rdata_i) >= $signed(reg2_rdata_i)) begin // rs1>=x31
                                reg_we = `WriteDisable; // 不写通用寄存器
                                custom_start_o = custom_start_pulse; // single-cycle start pulse
                                custom_funct3_o = funct3; // 传递funct3
                                custom_imm_o = inst_i[31:20]; // 传递立即数
                                custom_rs1_data_o = reg1_rdata_i; // 传递rs1
                                custom_x31_data_o = reg2_rdata_i; // 传递x31
                                custom_rd_o = rd; // 传递rd
                                hold_flag = (custom_ready_i == 1'b1) ? `HoldDisable : `HoldEnable; // wait for custom done
                                jump_flag = `JumpDisable; // no PC redirect; release hold to execute next instruction
                                jump_addr = `ZeroWord; // 跳转地址
                            end else begin // 条件不满足
                                reg_we = `WriteEnable; // 写回使能
                                reg_wdata = reg1_rdata_i; // 写回rs1
                            end
                        end else begin // imm!=0
                            reg_we = `WriteEnable; // 写回使能
                            reg_wdata = reg1_rdata_i + ifire_sign_ext_imm; // 加立即数
                        end
                    end
                    default: begin // 默认
                        reg_we = `WriteDisable; // 不写通用寄存器
                        reg_wdata = `ZeroWord; // 写回清零
                    end
                endcase // 自定义子操作结束
            end
            default: begin // 默认
                jump_flag = `JumpDisable; // 不跳转
                hold_flag = `HoldDisable; // 不暂停
                jump_addr = `ZeroWord; // 跳转地址清零
                mem_wdata_o = `ZeroWord; // 写数据清零
                mem_raddr_o = `ZeroWord; // 读地址清零
                mem_waddr_o = `ZeroWord; // 写地址清零
                mem_we = `WriteDisable; // 禁止写内存
                reg_wdata = `ZeroWord; // 写回清零
            end
        endcase // 操作码译码结束
    end // always结束

endmodule // 模块结束
