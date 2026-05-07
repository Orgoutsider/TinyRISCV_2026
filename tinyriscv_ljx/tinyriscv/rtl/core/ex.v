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

`include "defines.v"

// 执行模块
// 纯组合�?�辑电路
module ex(
    input wire clk,
    input wire rst,

    // from id
    input wire[`InstBus] inst_i,            // 指令内容
    input wire[`InstAddrBus] inst_addr_i,   // 指令地址
    input wire reg_we_i,                    // 是否写�?�用寄存�???
    input wire[`RegAddrBus] reg_waddr_i,    // 写�?�用寄存器地�???
    input wire[`RegBus] reg1_rdata_i,       // 通用寄存�???1输入数据
    input wire[`RegBus] reg2_rdata_i,       // 通用寄存�???2输入数据
    input wire csr_we_i,                    // 是否写CSR寄存�???
    input wire[`MemAddrBus] csr_waddr_i,    // 写CSR寄存器地�???
    input wire[`RegBus] csr_rdata_i,        // CSR寄存器输入数�???
    input wire int_assert_i,                // 中断发生标志
    input wire[`InstAddrBus] int_addr_i,    // 中断跳转地址
    input wire[`MemAddrBus] op1_i,
    input wire[`MemAddrBus] op2_i,
    input wire[`MemAddrBus] op1_jump_i,
    input wire[`MemAddrBus] op2_jump_i,

    // from mem
    input wire[`MemBus] mem_rdata_i,        // 内存输入数据

    // from div
    input wire div_ready_i,                 // 除法运算完成标志
    input wire[`RegBus] div_result_i,       // 除法运算结果
    input wire div_busy_i,                  // 除法运算忙标�???
    input wire[`RegAddrBus] div_reg_waddr_i,// 除法运算结束后要写的寄存器地�???

    // from send_id
    input wire[`MemBus] si_wdata_i,
    input wire[`MemAddrBus] si_waddr_i,
    input wire[`MemAddrBus] si_raddr_i,
    input wire si_we_i,
    input wire si_req_i,
    input wire si_hold_flag_i,

    // from regs
    input wire[`RegBus] reg_rdata,

    // from iaf
    input wire iaf_we_i,
    input wire iaf_req_i,
    input wire iaf_hold_flag_i,
    input wire[`MemAddrBus] iaf_raddr_i,
    input wire[`MemAddrBus] iaf_waddr_i,
    input wire[`MemBus] iaf_wdata_i,

    input wire iaf_reg_we_i,
    input wire iaf_reg_re_i,
    input wire[`RegBus] iaf_reg_wdata_i,
    input wire[`RegAddrBus] iaf_reg_waddr_i,
    input wire[`RegAddrBus] iaf_reg_raddr_i,

    // from rt
    input wire rt_we_i,
    input wire rt_req_i,
    input wire rt_hold_flag_i,
    input wire[`MemAddrBus] rt_raddr_i,
    input wire[`MemAddrBus] rt_waddr_i,
    input wire[`MemBus] rt_wdata_i,

    input wire rt_reg_we_i,
    input wire[`RegBus] rt_reg_wdata_i,
    input wire[`RegAddrBus] rt_reg_waddr_i,

    // to mem
    output wire[`MemBus] mem_wdata_o,        // 写内存数�???
    output wire[`MemAddrBus] mem_raddr_o,    // 读内存地�???
    output wire[`MemAddrBus] mem_waddr_o,    // 写内存地�???
    output wire mem_we_o,                   // 是否要写内存
    output wire mem_req_o,                  // 请求访问内存标志

    // to regs
    output wire[`RegBus] reg_wdata_o,       // 写寄存器数据
    output wire reg_we_o,                   // 是否要写通用寄存�???
    output wire[`RegAddrBus] reg_waddr_o,   // 写�?�用寄存器地�???
    output wire reg_re_o,
    output wire[`RegAddrBus] reg_raddr_o,

    // to csr reg
    output reg[`RegBus] csr_wdata_o,        // 写CSR寄存器数�???
    output wire csr_we_o,                   // 是否要写CSR寄存�???
    output wire[`MemAddrBus] csr_waddr_o,   // 写CSR寄存器地�???

    // to div
    output wire div_start_o,                // �???始除法运算标�???
    output reg[`RegBus] div_dividend_o,     // 被除�???
    output reg[`RegBus] div_divisor_o,      // 除数
    output reg[2:0] div_op_o,               // 具体是哪�???条除法指�???
    output reg[`RegAddrBus] div_reg_waddr_o,// 除法运算结束后要写的寄存器地�???

    // to ctrl
    output wire hold_flag_o,                // 是否暂停标志
    output wire jump_flag_o,                // 是否跳转标志
    output wire[`InstAddrBus] jump_addr_o,  // 跳转目的地址

    // to send_id
    output reg si_start_o,
    output wire si_uart_read_o,

    // to iaf
    output reg iaf_start_o,
    output reg[`MemAddrBus] iaf_imm_o,
    output reg[`MemAddrBus] iaf_xrs1_o,
    output reg[`RegAddrBus] iaf_rd_o,
    output reg[`MemAddrBus] iaf_op1_add_op2_res_o,
    output wire[`RegBus] iaf_reg_rdata_o,
    output wire iaf_uart_read_o,

    //to rt
    output reg rt_start_o,
    output reg[`RegAddrBus] rt_rd_o,
    output wire[`MemBus] rt_i2c_out_o
    );

    wire[1:0] mem_raddr_index;
    wire[1:0] mem_waddr_index;
    wire[`DoubleRegBus] mul_temp;
    wire[`DoubleRegBus] mul_temp_invert;
    wire[31:0] sr_shift;
    wire[31:0] sri_shift;
    wire[31:0] sr_shift_mask;
    wire[31:0] sri_shift_mask;
    wire[31:0] op1_add_op2_res;
    wire[31:0] op1_jump_add_op2_jump_res;
    wire[31:0] reg1_data_invert;
    wire[31:0] reg2_data_invert;
    wire op1_ge_op2_signed;
    wire op1_ge_op2_unsigned;
    wire op1_eq_op2;
    reg[`RegBus] mul_op1;
    reg[`RegBus] mul_op2;
    wire[6:0] opcode;
    wire[2:0] funct3;
    wire[6:0] funct7;
    wire[4:0] rd;
    wire[4:0] uimm;
    reg[`RegBus] reg_wdata;
    reg reg_we;
    reg[`RegAddrBus] reg_waddr;
    reg[`RegBus] div_wdata;
    reg div_we;
    reg[`RegAddrBus] div_waddr;
    reg div_hold_flag;
    reg div_jump_flag;
    reg[`InstAddrBus] div_jump_addr;
    reg hold_flag;
    reg jump_flag;
    reg[`InstAddrBus] jump_addr;
    reg mem_we;
    reg mem_req;
    reg div_start;

    reg[`MemBus] mem_wdata;
    reg[`MemAddrBus] mem_waddr;
    reg[`MemAddrBus] mem_raddr;

    // For send ID instruction
    reg si_jump_flag;
    reg[`MemAddrBus] si_jump_addr;

    // For read temperature instruction
    // Interact with RIB
    // reg rt_we;
    // reg rt_req;
    // reg rt_hold_flag;
    reg rt_jump_flag;
    reg[`MemAddrBus] rt_jump_addr;
    // reg[`MemAddrBus] rt_raddr;
    // // Interact with regs
    // reg rt_reg_we;
    // reg[`RegBus] rt_reg_wdata;
    // reg[`RegAddrBus] rt_reg_waddr;
    // // state
    // reg rt_is_busy;
    // // store temperature data
    // reg[`MemBus] rt_temp;


    // For Integrate&Fire instruction
    reg iaf_jump_flag;
    reg[`MemAddrBus] iaf_jump_addr;

    // Wiring
    assign opcode = inst_i[6:0];
    assign funct3 = inst_i[14:12];
    assign funct7 = inst_i[31:25];
    assign rd = inst_i[11:7];
    assign uimm = inst_i[19:15];

    assign sr_shift = reg1_rdata_i >> reg2_rdata_i[4:0];
    assign sri_shift = reg1_rdata_i >> inst_i[24:20];
    assign sr_shift_mask = 32'hffffffff >> reg2_rdata_i[4:0];
    assign sri_shift_mask = 32'hffffffff >> inst_i[24:20];

    assign op1_add_op2_res = op1_i + op2_i;
    assign op1_jump_add_op2_jump_res = op1_jump_i + op2_jump_i;

    assign reg1_data_invert = ~reg1_rdata_i + 1;
    assign reg2_data_invert = ~reg2_rdata_i + 1;

    // 有符号数比较
    assign op1_ge_op2_signed = $signed(op1_i) >= $signed(op2_i);
    // 无符号数比较
    assign op1_ge_op2_unsigned = op1_i >= op2_i;
    assign op1_eq_op2 = (op1_i == op2_i);

    assign mul_temp = mul_op1 * mul_op2;
    assign mul_temp_invert = ~mul_temp + 1;

    assign mem_raddr_index = (reg1_rdata_i + {{20{inst_i[31]}}, inst_i[31:20]}) & 2'b11;
    assign mem_waddr_index = (reg1_rdata_i + {{20{inst_i[31]}}, inst_i[31:25], inst_i[11:7]}) & 2'b11;

    assign div_start_o = (int_assert_i == `INT_ASSERT)? `DivStop: div_start;

    // Add logic
    assign si_uart_read_o = mem_rdata_i[0];

    assign iaf_reg_rdata_o = reg_rdata;
    assign iaf_uart_read_o = mem_rdata_i[0];

    assign rt_i2c_out_o = mem_rdata_i;

    // Reg logic
    assign reg_wdata_o = reg_wdata | div_wdata | rt_reg_wdata_i | iaf_reg_wdata_i;
    assign reg_we_o = (int_assert_i == `INT_ASSERT)? `WriteDisable: (reg_we || div_we || rt_reg_we_i || iaf_reg_we_i);
    assign reg_waddr_o = reg_waddr | div_waddr | rt_reg_waddr_i | iaf_reg_waddr_i;
    assign reg_re_o = (int_assert_i == `INT_ASSERT)? `WriteDisable: iaf_reg_re_i;
    assign reg_raddr_o = iaf_reg_raddr_i;

    // RIB control logic
    assign mem_we_o = (int_assert_i == `INT_ASSERT)? `WriteDisable: (mem_we || si_we_i || rt_we_i || iaf_we_i);

    assign mem_req_o = (int_assert_i == `INT_ASSERT)? `RIB_NREQ: (mem_req || si_req_i || rt_req_i || iaf_req_i);
    
    assign mem_raddr_o = (mem_raddr | si_raddr_i | rt_raddr_i | iaf_raddr_i);
    assign mem_waddr_o = (mem_waddr | si_waddr_i | rt_waddr_i | iaf_waddr_i);
    assign mem_wdata_o = (mem_wdata | si_wdata_i | rt_wdata_i | iaf_wdata_i);

    assign hold_flag_o = hold_flag || div_hold_flag || si_hold_flag_i || rt_hold_flag_i || iaf_hold_flag_i;
    assign jump_flag_o = jump_flag || div_jump_flag || si_jump_flag || rt_jump_flag || iaf_jump_flag || ((int_assert_i == `INT_ASSERT)? `JumpEnable: `JumpDisable);
    assign jump_addr_o = (int_assert_i == `INT_ASSERT)? int_addr_i: (jump_addr | div_jump_addr | si_jump_addr | rt_jump_addr | iaf_jump_addr);

    // 响应中断时不写CSR寄存�???
    assign csr_we_o = (int_assert_i == `INT_ASSERT)? `WriteDisable: csr_we_i;
    assign csr_waddr_o = csr_waddr_i;


    // 处理乘法指令
    always @ (*) begin
        if ((opcode == `INST_TYPE_R_M) && (funct7 == 7'b0000001)) begin
            case (funct3)
                `INST_MUL, `INST_MULHU: begin
                    mul_op1 = reg1_rdata_i;
                    mul_op2 = reg2_rdata_i;
                end
                `INST_MULHSU: begin
                    mul_op1 = (reg1_rdata_i[31] == 1'b1)? (reg1_data_invert): reg1_rdata_i;
                    mul_op2 = reg2_rdata_i;
                end
                `INST_MULH: begin
                    mul_op1 = (reg1_rdata_i[31] == 1'b1)? (reg1_data_invert): reg1_rdata_i;
                    mul_op2 = (reg2_rdata_i[31] == 1'b1)? (reg2_data_invert): reg2_rdata_i;
                end
                default: begin
                    mul_op1 = reg1_rdata_i;
                    mul_op2 = reg2_rdata_i;
                end
            endcase
        end else begin
            mul_op1 = reg1_rdata_i;
            mul_op2 = reg2_rdata_i;
        end
    end

    // 处理除法指令
    always @ (*) begin
        div_dividend_o = reg1_rdata_i;
        div_divisor_o = reg2_rdata_i;
        div_op_o = funct3;
        div_reg_waddr_o = reg_waddr_i;
        if ((opcode == `INST_TYPE_R_M) && (funct7 == 7'b0000001)) begin
            div_we = `WriteDisable;
            div_wdata = `ZeroWord;
            div_waddr = `ZeroWord;
            case (funct3)
                `INST_DIV, `INST_DIVU, `INST_REM, `INST_REMU: begin
                    div_start = `DivStart;
                    div_jump_flag = `JumpEnable;
                    div_hold_flag = `HoldEnable;
                    div_jump_addr = op1_jump_add_op2_jump_res;
                end
                default: begin
                    div_start = `DivStop;
                    div_jump_flag = `JumpDisable;
                    div_hold_flag = `HoldDisable;
                    div_jump_addr = `ZeroWord;
                end
            endcase
        end else begin
            div_jump_flag = `JumpDisable;
            div_jump_addr = `ZeroWord;
            if (div_busy_i == `True) begin
                div_start = `DivStart;
                div_we = `WriteDisable;
                div_wdata = `ZeroWord;
                div_waddr = `ZeroWord;
                div_hold_flag = `HoldEnable;
            end else begin
                div_start = `DivStop;
                div_hold_flag = `HoldDisable;
                if (div_ready_i == `DivResultReady) begin
                    div_wdata = div_result_i;
                    div_waddr = div_reg_waddr_i;
                    div_we = `WriteEnable;
                end else begin
                    div_we = `WriteDisable;
                    div_wdata = `ZeroWord;
                    div_waddr = `ZeroWord;
                end
            end
        end
    end

    // 处理send ID指令
    always @ (*) begin
        if ((opcode == `INST_TYPE_ADD) && (funct3 == `INST_SID)) begin // Get inst send_id
            si_jump_flag = `JumpEnable;
            si_jump_addr = op1_jump_add_op2_jump_res;
            si_start_o = 1'b1;
        end else begin
            si_jump_flag = `JumpDisable;
            si_jump_addr = `ZeroWord;
            si_start_o = 1'b0;
        end
    end

    // 处理Read Temperature指令
    // always @ (*) begin
    //     if ((opcode == `INST_TYPE_ADD) && (funct3 == `INST_RT)) begin // Get inst read_temperature
    //         rt_we = `WriteEnable;
    //         rt_req = `RIB_REQ;
    //         rt_hold_flag = `HoldEnable;
    //         rt_jump_flag = `JumpEnable;
    //         rt_jump_addr = op1_jump_add_op2_jump_res;
    //         rt_raddr = `ZeroWord;
            

    //         rt_reg_we = `WriteDisable;
    //         rt_reg_wdata = `ZeroWord;
    //         rt_reg_waddr = reg_waddr_i;

    //         rt_is_busy = 1'b1;

    //         rt_temp = `ZeroWord;

    //         i2c_start_o = 1'b1;
    //     end else begin
    //         if (rt_is_busy) begin
    //             rt_jump_flag = `JumpDisable;
    //             rt_jump_addr = `ZeroWord;
    //             i2c_start_o = 1'b0;
    //             if (i2c_busy_i == 1'b0) begin // i2c_ctrl finishes setting regs; read reg and write to reg x[rd]
    //                 rt_we = `WriteDisable;
    //                 rt_raddr = {{4'h7}, {8'd0}, {4'h2}, {16'd0}}; // 0x7002_0000

    //                 if (mem_rdata_i[8] == 1'b1) begin // data valid
    //                     rt_reg_we = `WriteEnable;
    //                     rt_reg_wdata = mem_rdata_i[7:0];

    //                     rt_temp = mem_rdata_i[7:0];

    //                     rt_is_busy = 1'b0; // Finish inst rt

    //                     rt_req = `RIB_NREQ;
    //                     rt_hold_flag = `HoldDisable;
    //                 end
    //             end
    //         end else begin // Other instructions
    //             rt_we = `WriteDisable;
    //             rt_req = `RIB_NREQ;
    //             rt_hold_flag = `HoldDisable;
    //             rt_jump_flag = `JumpDisable;
    //             rt_jump_addr = `ZeroWord;
    //             rt_raddr = `ZeroWord;
                

    //             rt_reg_we = 1'b0;
    //             rt_reg_wdata = `ZeroWord;
    //             rt_reg_waddr = `ZeroReg;

    //             rt_is_busy = 1'b0;

    //             rt_temp = `ZeroWord;

    //             i2c_start_o = 1'b0;
    //         end
    //     end
    // end

    always @ (*) begin
        if ((opcode == `INST_TYPE_ADD) && (funct3 == `INST_RT)) begin // Get inst read_temperature
            rt_rd_o = reg_waddr_i;

            rt_start_o <= 1'b1;
            
            rt_jump_flag = `JumpEnable;
            rt_jump_addr = op1_jump_add_op2_jump_res;
        end else begin
            rt_start_o <= 1'b0;
            
            rt_jump_flag = `JumpDisable;
            rt_jump_addr = `ZeroWord;
        end
    end

    // 处理Integrate&Fire指令
    always @ (*) begin
        if ((opcode == `INST_TYPE_ADD) && (funct3 == `INST_IAF)) begin // Get inst integrate&fire
            iaf_imm_o = op2_i;
            iaf_xrs1_o = op1_i;
            iaf_rd_o = reg_waddr_i;
            iaf_op1_add_op2_res_o = op1_add_op2_res;

            iaf_start_o = 1'b1;

            iaf_jump_flag = `JumpEnable;
            iaf_jump_addr = op1_jump_add_op2_jump_res;   
        end else begin
            iaf_start_o = 1'b0;
            
            iaf_jump_flag = `JumpDisable;
            iaf_jump_addr = `ZeroWord;
        end
    end


    // 执行
    always @ (*) begin
        reg_we = reg_we_i;
        reg_waddr = reg_waddr_i;
        mem_req = `RIB_NREQ;
        csr_wdata_o = `ZeroWord;

        case (opcode)
            `INST_TYPE_I: begin
                case (funct3)
                    `INST_ADDI: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata = `ZeroWord;
                        mem_raddr = `ZeroWord;
                        mem_waddr = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = op1_add_op2_res;
                    end
                    `INST_SLTI: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata = `ZeroWord;
                        mem_raddr = `ZeroWord;
                        mem_waddr = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = {32{(~op1_ge_op2_signed)}} & 32'h1;
                    end
                    `INST_SLTIU: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata = `ZeroWord;
                        mem_raddr = `ZeroWord;
                        mem_waddr = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = {32{(~op1_ge_op2_unsigned)}} & 32'h1;
                    end
                    `INST_XORI: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata = `ZeroWord;
                        mem_raddr = `ZeroWord;
                        mem_waddr = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = op1_i ^ op2_i;
                    end
                    `INST_ORI: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata = `ZeroWord;
                        mem_raddr = `ZeroWord;
                        mem_waddr = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = op1_i | op2_i;
                    end
                    `INST_ANDI: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata = `ZeroWord;
                        mem_raddr = `ZeroWord;
                        mem_waddr = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = op1_i & op2_i;
                    end
                    `INST_SLLI: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata = `ZeroWord;
                        mem_raddr = `ZeroWord;
                        mem_waddr = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = reg1_rdata_i << inst_i[24:20];
                    end
                    `INST_SRI: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata = `ZeroWord;
                        mem_raddr = `ZeroWord;
                        mem_waddr = `ZeroWord;
                        mem_we = `WriteDisable;
                        if (inst_i[30] == 1'b1) begin
                            reg_wdata = (sri_shift & sri_shift_mask) | ({32{reg1_rdata_i[31]}} & (~sri_shift_mask));
                        end else begin
                            reg_wdata = reg1_rdata_i >> inst_i[24:20];
                        end
                    end
                    default: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata = `ZeroWord;
                        mem_raddr = `ZeroWord;
                        mem_waddr = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = `ZeroWord;
                    end
                endcase
            end
            `INST_TYPE_R_M: begin
                if ((funct7 == 7'b0000000) || (funct7 == 7'b0100000)) begin
                    case (funct3)
                        `INST_ADD_SUB: begin
                            jump_flag = `JumpDisable;
                            hold_flag = `HoldDisable;
                            jump_addr = `ZeroWord;
                            mem_wdata = `ZeroWord;
                            mem_raddr = `ZeroWord;
                            mem_waddr = `ZeroWord;
                            mem_we = `WriteDisable;
                            if (inst_i[30] == 1'b0) begin
                                reg_wdata = op1_add_op2_res;
                            end else begin
                                reg_wdata = op1_i - op2_i;
                            end
                        end
                        `INST_SLL: begin
                            jump_flag = `JumpDisable;
                            hold_flag = `HoldDisable;
                            jump_addr = `ZeroWord;
                            mem_wdata = `ZeroWord;
                            mem_raddr = `ZeroWord;
                            mem_waddr = `ZeroWord;
                            mem_we = `WriteDisable;
                            reg_wdata = op1_i << op2_i[4:0];
                        end
                        `INST_SLT: begin
                            jump_flag = `JumpDisable;
                            hold_flag = `HoldDisable;
                            jump_addr = `ZeroWord;
                            mem_wdata = `ZeroWord;
                            mem_raddr = `ZeroWord;
                            mem_waddr = `ZeroWord;
                            mem_we = `WriteDisable;
                            reg_wdata = {32{(~op1_ge_op2_signed)}} & 32'h1;
                        end
                        `INST_SLTU: begin
                            jump_flag = `JumpDisable;
                            hold_flag = `HoldDisable;
                            jump_addr = `ZeroWord;
                            mem_wdata = `ZeroWord;
                            mem_raddr = `ZeroWord;
                            mem_waddr = `ZeroWord;
                            mem_we = `WriteDisable;
                            reg_wdata = {32{(~op1_ge_op2_unsigned)}} & 32'h1;
                        end
                        `INST_XOR: begin
                            jump_flag = `JumpDisable;
                            hold_flag = `HoldDisable;
                            jump_addr = `ZeroWord;
                            mem_wdata = `ZeroWord;
                            mem_raddr = `ZeroWord;
                            mem_waddr = `ZeroWord;
                            mem_we = `WriteDisable;
                            reg_wdata = op1_i ^ op2_i;
                        end
                        `INST_SR: begin
                            jump_flag = `JumpDisable;
                            hold_flag = `HoldDisable;
                            jump_addr = `ZeroWord;
                            mem_wdata = `ZeroWord;
                            mem_raddr = `ZeroWord;
                            mem_waddr = `ZeroWord;
                            mem_we = `WriteDisable;
                            if (inst_i[30] == 1'b1) begin
                                reg_wdata = (sr_shift & sr_shift_mask) | ({32{reg1_rdata_i[31]}} & (~sr_shift_mask));
                            end else begin
                                reg_wdata = reg1_rdata_i >> reg2_rdata_i[4:0];
                            end
                        end
                        `INST_OR: begin
                            jump_flag = `JumpDisable;
                            hold_flag = `HoldDisable;
                            jump_addr = `ZeroWord;
                            mem_wdata = `ZeroWord;
                            mem_raddr = `ZeroWord;
                            mem_waddr = `ZeroWord;
                            mem_we = `WriteDisable;
                            reg_wdata = op1_i | op2_i;
                        end
                        `INST_AND: begin
                            jump_flag = `JumpDisable;
                            hold_flag = `HoldDisable;
                            jump_addr = `ZeroWord;
                            mem_wdata = `ZeroWord;
                            mem_raddr = `ZeroWord;
                            mem_waddr = `ZeroWord;
                            mem_we = `WriteDisable;
                            reg_wdata = op1_i & op2_i;
                        end
                        default: begin
                            jump_flag = `JumpDisable;
                            hold_flag = `HoldDisable;
                            jump_addr = `ZeroWord;
                            mem_wdata = `ZeroWord;
                            mem_raddr = `ZeroWord;
                            mem_waddr = `ZeroWord;
                            mem_we = `WriteDisable;
                            reg_wdata = `ZeroWord;
                        end
                    endcase
                end else if (funct7 == 7'b0000001) begin
                    case (funct3)
                        `INST_MUL: begin
                            jump_flag = `JumpDisable;
                            hold_flag = `HoldDisable;
                            jump_addr = `ZeroWord;
                            mem_wdata = `ZeroWord;
                            mem_raddr = `ZeroWord;
                            mem_waddr = `ZeroWord;
                            mem_we = `WriteDisable;
                            reg_wdata = mul_temp[31:0];
                        end
                        `INST_MULHU: begin
                            jump_flag = `JumpDisable;
                            hold_flag = `HoldDisable;
                            jump_addr = `ZeroWord;
                            mem_wdata = `ZeroWord;
                            mem_raddr = `ZeroWord;
                            mem_waddr = `ZeroWord;
                            mem_we = `WriteDisable;
                            reg_wdata = mul_temp[63:32];
                        end
                        `INST_MULH: begin
                            jump_flag = `JumpDisable;
                            hold_flag = `HoldDisable;
                            jump_addr = `ZeroWord;
                            mem_wdata = `ZeroWord;
                            mem_raddr = `ZeroWord;
                            mem_waddr = `ZeroWord;
                            mem_we = `WriteDisable;
                            case ({reg1_rdata_i[31], reg2_rdata_i[31]})
                                2'b00: begin
                                    reg_wdata = mul_temp[63:32];
                                end
                                2'b11: begin
                                    reg_wdata = mul_temp[63:32];
                                end
                                2'b10: begin
                                    reg_wdata = mul_temp_invert[63:32];
                                end
                                default: begin
                                    reg_wdata = mul_temp_invert[63:32];
                                end
                            endcase
                        end
                        `INST_MULHSU: begin
                            jump_flag = `JumpDisable;
                            hold_flag = `HoldDisable;
                            jump_addr = `ZeroWord;
                            mem_wdata = `ZeroWord;
                            mem_raddr = `ZeroWord;
                            mem_waddr = `ZeroWord;
                            mem_we = `WriteDisable;
                            if (reg1_rdata_i[31] == 1'b1) begin
                                reg_wdata = mul_temp_invert[63:32];
                            end else begin
                                reg_wdata = mul_temp[63:32];
                            end
                        end
                        default: begin
                            jump_flag = `JumpDisable;
                            hold_flag = `HoldDisable;
                            jump_addr = `ZeroWord;
                            mem_wdata = `ZeroWord;
                            mem_raddr = `ZeroWord;
                            mem_waddr = `ZeroWord;
                            mem_we = `WriteDisable;
                            reg_wdata = `ZeroWord;
                        end
                    endcase
                end else begin
                    jump_flag = `JumpDisable;
                    hold_flag = `HoldDisable;
                    jump_addr = `ZeroWord;
                    mem_wdata = `ZeroWord;
                    mem_raddr = `ZeroWord;
                    mem_waddr = `ZeroWord;
                    mem_we = `WriteDisable;
                    reg_wdata = `ZeroWord;
                end
            end
            `INST_TYPE_L: begin
                case (funct3)
                    `INST_LB: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata = `ZeroWord;
                        mem_waddr = `ZeroWord;
                        mem_we = `WriteDisable;
                        mem_req = `RIB_REQ;
                        mem_raddr = op1_add_op2_res;
                        case (mem_raddr_index)
                            2'b00: begin
                                reg_wdata = {{24{mem_rdata_i[7]}}, mem_rdata_i[7:0]};
                            end
                            2'b01: begin
                                reg_wdata = {{24{mem_rdata_i[15]}}, mem_rdata_i[15:8]};
                            end
                            2'b10: begin
                                reg_wdata = {{24{mem_rdata_i[23]}}, mem_rdata_i[23:16]};
                            end
                            default: begin
                                reg_wdata = {{24{mem_rdata_i[31]}}, mem_rdata_i[31:24]};
                            end
                        endcase
                    end
                    `INST_LH: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata = `ZeroWord;
                        mem_waddr = `ZeroWord;
                        mem_we = `WriteDisable;
                        mem_req = `RIB_REQ;
                        mem_raddr = op1_add_op2_res;
                        if (mem_raddr_index == 2'b0) begin
                            reg_wdata = {{16{mem_rdata_i[15]}}, mem_rdata_i[15:0]};
                        end else begin
                            reg_wdata = {{16{mem_rdata_i[31]}}, mem_rdata_i[31:16]};
                        end
                    end
                    `INST_LW: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata = `ZeroWord;
                        mem_waddr = `ZeroWord;
                        mem_we = `WriteDisable;
                        mem_req = `RIB_REQ;
                        mem_raddr = op1_add_op2_res;
                        reg_wdata = mem_rdata_i;
                    end
                    `INST_LBU: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata = `ZeroWord;
                        mem_waddr = `ZeroWord;
                        mem_we = `WriteDisable;
                        mem_req = `RIB_REQ;
                        mem_raddr = op1_add_op2_res;
                        case (mem_raddr_index)
                            2'b00: begin
                                reg_wdata = {24'h0, mem_rdata_i[7:0]};
                            end
                            2'b01: begin
                                reg_wdata = {24'h0, mem_rdata_i[15:8]};
                            end
                            2'b10: begin
                                reg_wdata = {24'h0, mem_rdata_i[23:16]};
                            end
                            default: begin
                                reg_wdata = {24'h0, mem_rdata_i[31:24]};
                            end
                        endcase
                    end
                    `INST_LHU: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata = `ZeroWord;
                        mem_waddr = `ZeroWord;
                        mem_we = `WriteDisable;
                        mem_req = `RIB_REQ;
                        mem_raddr = op1_add_op2_res;
                        if (mem_raddr_index == 2'b0) begin
                            reg_wdata = {16'h0, mem_rdata_i[15:0]};
                        end else begin
                            reg_wdata = {16'h0, mem_rdata_i[31:16]};
                        end
                    end
                    default: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata = `ZeroWord;
                        mem_raddr = `ZeroWord;
                        mem_waddr = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = `ZeroWord;
                    end
                endcase
            end
            `INST_TYPE_S: begin
                case (funct3)
                    `INST_SB: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        reg_wdata = `ZeroWord;
                        mem_we = `WriteEnable;
                        mem_req = `RIB_REQ;
                        mem_waddr = op1_add_op2_res;
                        mem_raddr = op1_add_op2_res;
                        case (mem_waddr_index)
                            2'b00: begin
                                mem_wdata = {mem_rdata_i[31:8], reg2_rdata_i[7:0]};
                            end
                            2'b01: begin
                                mem_wdata = {mem_rdata_i[31:16], reg2_rdata_i[7:0], mem_rdata_i[7:0]};
                            end
                            2'b10: begin
                                mem_wdata = {mem_rdata_i[31:24], reg2_rdata_i[7:0], mem_rdata_i[15:0]};
                            end
                            default: begin
                                mem_wdata = {reg2_rdata_i[7:0], mem_rdata_i[23:0]};
                            end
                        endcase
                    end
                    `INST_SH: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        reg_wdata = `ZeroWord;
                        mem_we = `WriteEnable;
                        mem_req = `RIB_REQ;
                        mem_waddr = op1_add_op2_res;
                        mem_raddr = op1_add_op2_res;
                        if (mem_waddr_index == 2'b00) begin
                            mem_wdata = {mem_rdata_i[31:16], reg2_rdata_i[15:0]};
                        end else begin
                            mem_wdata = {reg2_rdata_i[15:0], mem_rdata_i[15:0]};
                        end
                    end
                    `INST_SW: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        reg_wdata = `ZeroWord;
                        mem_we = `WriteEnable;
                        mem_req = `RIB_REQ;
                        mem_waddr = op1_add_op2_res;
                        mem_raddr = op1_add_op2_res;
                        mem_wdata = reg2_rdata_i;
                    end
                    default: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata = `ZeroWord;
                        mem_raddr = `ZeroWord;
                        mem_waddr = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = `ZeroWord;
                    end
                endcase
            end
            `INST_TYPE_B: begin
                case (funct3)
                    `INST_BEQ: begin
                        hold_flag = `HoldDisable;
                        mem_wdata = `ZeroWord;
                        mem_raddr = `ZeroWord;
                        mem_waddr = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = `ZeroWord;
                        jump_flag = op1_eq_op2 & `JumpEnable;
                        jump_addr = {32{op1_eq_op2}} & op1_jump_add_op2_jump_res;
                    end
                    `INST_BNE: begin
                        hold_flag = `HoldDisable;
                        mem_wdata = `ZeroWord;
                        mem_raddr = `ZeroWord;
                        mem_waddr = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = `ZeroWord;
                        jump_flag = (~op1_eq_op2) & `JumpEnable;
                        jump_addr = {32{(~op1_eq_op2)}} & op1_jump_add_op2_jump_res;
                    end
                    `INST_BLT: begin
                        hold_flag = `HoldDisable;
                        mem_wdata = `ZeroWord;
                        mem_raddr = `ZeroWord;
                        mem_waddr = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = `ZeroWord;
                        jump_flag = (~op1_ge_op2_signed) & `JumpEnable;
                        jump_addr = {32{(~op1_ge_op2_signed)}} & op1_jump_add_op2_jump_res;
                    end
                    `INST_BGE: begin
                        hold_flag = `HoldDisable;
                        mem_wdata = `ZeroWord;
                        mem_raddr = `ZeroWord;
                        mem_waddr = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = `ZeroWord;
                        jump_flag = (op1_ge_op2_signed) & `JumpEnable;
                        jump_addr = {32{(op1_ge_op2_signed)}} & op1_jump_add_op2_jump_res;
                    end
                    `INST_BLTU: begin
                        hold_flag = `HoldDisable;
                        mem_wdata = `ZeroWord;
                        mem_raddr = `ZeroWord;
                        mem_waddr = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = `ZeroWord;
                        jump_flag = (~op1_ge_op2_unsigned) & `JumpEnable;
                        jump_addr = {32{(~op1_ge_op2_unsigned)}} & op1_jump_add_op2_jump_res;
                    end
                    `INST_BGEU: begin
                        hold_flag = `HoldDisable;
                        mem_wdata = `ZeroWord;
                        mem_raddr = `ZeroWord;
                        mem_waddr = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = `ZeroWord;
                        jump_flag = (op1_ge_op2_unsigned) & `JumpEnable;
                        jump_addr = {32{(op1_ge_op2_unsigned)}} & op1_jump_add_op2_jump_res;
                    end
                    default: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata = `ZeroWord;
                        mem_raddr = `ZeroWord;
                        mem_waddr = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = `ZeroWord;
                    end
                endcase
            end
            `INST_JAL, `INST_JALR: begin
                hold_flag = `HoldDisable;
                mem_wdata = `ZeroWord;
                mem_raddr = `ZeroWord;
                mem_waddr = `ZeroWord;
                mem_we = `WriteDisable;
                jump_flag = `JumpEnable;
                jump_addr = op1_jump_add_op2_jump_res;
                reg_wdata = op1_add_op2_res;
            end
            `INST_LUI, `INST_AUIPC: begin
                hold_flag = `HoldDisable;
                mem_wdata = `ZeroWord;
                mem_raddr = `ZeroWord;
                mem_waddr = `ZeroWord;
                mem_we = `WriteDisable;
                jump_addr = `ZeroWord;
                jump_flag = `JumpDisable;
                reg_wdata = op1_add_op2_res;
            end
            `INST_NOP_OP: begin
                jump_flag = `JumpDisable;
                hold_flag = `HoldDisable;
                jump_addr = `ZeroWord;
                mem_wdata = `ZeroWord;
                mem_raddr = `ZeroWord;
                mem_waddr = `ZeroWord;
                mem_we = `WriteDisable;
                reg_wdata = `ZeroWord;
            end
            `INST_FENCE: begin
                hold_flag = `HoldDisable;
                mem_wdata = `ZeroWord;
                mem_raddr = `ZeroWord;
                mem_waddr = `ZeroWord;
                mem_we = `WriteDisable;
                reg_wdata = `ZeroWord;
                jump_flag = `JumpEnable;
                jump_addr = op1_jump_add_op2_jump_res;
            end
            `INST_CSR: begin
                jump_flag = `JumpDisable;
                hold_flag = `HoldDisable;
                jump_addr = `ZeroWord;
                mem_wdata = `ZeroWord;
                mem_raddr = `ZeroWord;
                mem_waddr = `ZeroWord;
                mem_we = `WriteDisable;
                case (funct3)
                    `INST_CSRRW: begin
                        csr_wdata_o = reg1_rdata_i;
                        reg_wdata = csr_rdata_i;
                    end
                    `INST_CSRRS: begin
                        csr_wdata_o = reg1_rdata_i | csr_rdata_i;
                        reg_wdata = csr_rdata_i;
                    end
                    `INST_CSRRC: begin
                        csr_wdata_o = csr_rdata_i & (~reg1_rdata_i);
                        reg_wdata = csr_rdata_i;
                    end
                    `INST_CSRRWI: begin
                        csr_wdata_o = {27'h0, uimm};
                        reg_wdata = csr_rdata_i;
                    end
                    `INST_CSRRSI: begin
                        csr_wdata_o = {27'h0, uimm} | csr_rdata_i;
                        reg_wdata = csr_rdata_i;
                    end
                    `INST_CSRRCI: begin
                        csr_wdata_o = (~{27'h0, uimm}) & csr_rdata_i;
                        reg_wdata = csr_rdata_i;
                    end
                    default: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata = `ZeroWord;
                        mem_raddr = `ZeroWord;
                        mem_waddr = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = `ZeroWord;
                    end
                endcase
            end
            default: begin
                jump_flag = `JumpDisable;
                hold_flag = `HoldDisable;
                jump_addr = `ZeroWord;
                mem_wdata = `ZeroWord;
                mem_raddr = `ZeroWord;
                mem_waddr = `ZeroWord;
                mem_we = `WriteDisable;
                reg_wdata = `ZeroWord;
            end
        endcase
    end

endmodule
