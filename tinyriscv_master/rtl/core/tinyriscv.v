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

// tinyriscv处理器核顶层模块
module tinyriscv( // 模块声明

    input wire clk, // 时钟信号
    input wire rst, // 复位信号

    output wire[`MemAddrBus] rib_ex_addr_o,    // 读写外设地址
    input wire[`MemBus] rib_ex_data_i,         // 从外设读取的数据
    output wire[`MemBus] rib_ex_data_o,        // 写入外设的数据
    output wire rib_ex_req_o,                  // 访问外设请求
    output wire rib_ex_we_o,                   // 写外设标志

    output wire[`MemAddrBus] rib_pc_addr_o,    // 取指地址
    input wire[`MemBus] rib_pc_data_i,         // 取到的指令内容

    input wire[`RegAddrBus] jtag_reg_addr_i,   // JTAG寄存器地址
    input wire[`RegBus] jtag_reg_data_i,       // JTAG写寄存器数据
    input wire jtag_reg_we_i,                  // JTAG写寄存器标志
    output wire[`RegBus] jtag_reg_data_o,      // JTAG读取寄存器数据

    input wire rib_hold_flag_i,                // 总线暂停标志
    input wire rib_hold_flag_full_i,           // 总线全暂停标志
    input wire jtag_halt_flag_i,               // JTAG暂停标志
    input wire jtag_reset_flag_i,              // JTAG复位PC标志

    input wire[`INT_BUS] int_i,                // 中断信号

    input wire[`MemBus] offchip_mem_rdata_i,   // 片外内存读数据

    // custom instruction sideband ports
    output wire custom_uart_tx_valid_o,        // 自定义UART发送有效
    output wire[7:0] custom_uart_tx_data_o,    // 自定义UART发送数据
    input  wire custom_uart_tx_ready_i,        // 自定义UART发送就绪

    output wire custom_i2c_temp_req_o,         // 自定义I2C温度请求
    input  wire custom_i2c_temp_valid_i,       // 自定义I2C温度有效
    input  wire[7:0] custom_i2c_temp_data_i,   // 自定义I2C温度数据
    input  wire custom_i2c_busy_i              // 自定义I2C忙标志

    ); // 端口列表结束

    // pc_reg模块输出信号
	wire[`InstAddrBus] pc_pc_o; // PC值

    // if_id模块输出信号
	wire[`InstBus] if_inst_o; // IF阶段指令
    wire[`InstAddrBus] if_inst_addr_o; // IF阶段指令地址
    wire[`INT_BUS] if_int_flag_o; // IF阶段中断标志

    // id模块输出信号
    wire[`RegAddrBus] id_reg1_raddr_o; // rs1读地址
    wire[`RegAddrBus] id_reg2_raddr_o; // rs2读地址
    wire[`InstBus] id_inst_o; // ID阶段指令
    wire[`InstAddrBus] id_inst_addr_o; // ID阶段指令地址
    wire[`RegBus] id_reg1_rdata_o; // rs1读数据
    wire[`RegBus] id_reg2_rdata_o; // rs2读数据
    wire id_reg_we_o; // 写回使能
    wire[`RegAddrBus] id_reg_waddr_o; // 写回地址
    wire[`MemAddrBus] id_csr_raddr_o; // CSR读地址
    wire id_csr_we_o; // CSR写使能
    wire[`RegBus] id_csr_rdata_o; // CSR读数据
    wire[`MemAddrBus] id_csr_waddr_o; // CSR写地址
    wire[`MemAddrBus] id_op1_o; // 操作数1
    wire[`MemAddrBus] id_op2_o; // 操作数2
    wire[`MemAddrBus] id_op1_jump_o; // 跳转操作数1
    wire[`MemAddrBus] id_op2_jump_o; // 跳转操作数2

    // id_ex模块输出信号
    wire[`InstBus] ie_inst_o; // EX阶段指令
    wire[`InstAddrBus] ie_inst_addr_o; // EX阶段指令地址
    wire ie_reg_we_o; // EX阶段写回使能
    wire[`RegAddrBus] ie_reg_waddr_o; // EX阶段写回地址
    wire[`RegBus] ie_reg1_rdata_o; // EX阶段rs1数据
    wire[`RegBus] ie_reg2_rdata_o; // EX阶段rs2数据
    wire ie_csr_we_o; // EX阶段CSR写使能
    wire[`MemAddrBus] ie_csr_waddr_o; // EX阶段CSR写地址
    wire[`RegBus] ie_csr_rdata_o; // EX阶段CSR读数据
    wire[`MemAddrBus] ie_op1_o; // EX阶段操作数1
    wire[`MemAddrBus] ie_op2_o; // EX阶段操作数2
    wire[`MemAddrBus] ie_op1_jump_o; // EX阶段跳转操作数1
    wire[`MemAddrBus] ie_op2_jump_o; // EX阶段跳转操作数2

    // ex模块输出信号
    wire[`MemBus] ex_mem_wdata_o; // 写内存数据
    wire[`MemAddrBus] ex_mem_raddr_o; // 读内存地址
    wire[`MemAddrBus] ex_mem_waddr_o; // 写内存地址
    wire ex_mem_we_o; // 写内存使能
    wire ex_mem_req_o; // 内存请求
    wire[`RegBus] ex_reg_wdata_o; // 写回数据
    wire ex_reg_we_o; // 写回使能
    wire[`RegAddrBus] ex_reg_waddr_o; // 写回地址
    wire ex_hold_flag_o; // 执行级暂停标志
    wire ex_jump_flag_o; // 执行级跳转标志
    wire[`InstAddrBus] ex_jump_addr_o; // 执行级跳转地址
    wire ex_div_start_o; // 除法启动
    wire[`RegBus] ex_div_dividend_o; // 被除数
    wire[`RegBus] ex_div_divisor_o; // 除数
    wire[2:0] ex_div_op_o; // 除法操作码
    wire[`RegAddrBus] ex_div_reg_waddr_o; // 除法写回地址
    wire[`RegBus] ex_csr_wdata_o; // CSR写数据
    wire ex_csr_we_o; // CSR写使能
    wire[`MemAddrBus] ex_csr_waddr_o; // CSR写地址

    // regs模块输出信号
    wire[`RegBus] regs_rdata1_o; // 寄存器1读数据
    wire[`RegBus] regs_rdata2_o; // 寄存器2读数据

    // csr_reg模块输出信号
    wire[`RegBus] csr_data_o; // CSR读数据
    wire[`RegBus] csr_clint_data_o; // CLINT读CSR数据
    wire csr_global_int_en_o; // 全局中断使能
    wire[`RegBus] csr_clint_csr_mtvec; // CLINT mtvec
    wire[`RegBus] csr_clint_csr_mepc; // CLINT mepc
    wire[`RegBus] csr_clint_csr_mstatus; // CLINT mstatus

    // ctrl模块输出信号
    wire[`Hold_Flag_Bus] ctrl_hold_flag_o; // 控制暂停标志
    wire ctrl_jump_flag_o; // 控制跳转标志
    wire[`InstAddrBus] ctrl_jump_addr_o; // 控制跳转地址

    // div模块输出信号
    wire[`RegBus] div_result_o; // 除法结果
	wire div_ready_o; // 除法完成
    wire div_busy_o; // 除法忙
    wire[`RegAddrBus] div_reg_waddr_o; // 除法写回地址

    // custom instruction unit wires
    wire custom_start; // 自定义指令启动
    wire[2:0] custom_funct3; // 自定义funct3
    wire[11:0] custom_imm; // 自定义立即数
    wire[`RegBus] custom_rs1_data; // 自定义rs1数据
    wire[`RegBus] custom_x31_data; // 自定义x31数据
    wire[`RegAddrBus] custom_rd; // 自定义rd
    wire custom_ready; // 自定义完成
    wire custom_busy; // 自定义忙
    wire custom_reg_we; // 自定义写回使能
    wire[`RegAddrBus] custom_reg_waddr; // 自定义写回地址
    wire[`RegBus] custom_reg_wdata; // 自定义写回数据

    // 片外多周期读回写控制
    wire ex_mem_addr_is_offchip; // 地址是否片外
    wire ex_load_from_offchip; // 是否片外load
    wire mem_load_finish; // 片外load完成
    reg mem_load_pending; // 片外load挂起
    reg mem_load_seen_busy; // 片外load看到busy
    reg s0_busy_d; // busy延迟拍
    reg[2:0] mem_load_funct3; // load类型
    reg[1:0] mem_load_addr_index; // 字节索引
    reg[`RegAddrBus] mem_load_rd; // load写回寄存器
    reg[`RegBus] mem_load_wdata; // load写回数据
    wire regs_we; // 寄存器写使能
    wire[`RegAddrBus] regs_waddr; // 寄存器写地址
    wire[`RegBus] regs_wdata; // 寄存器写数据

    // clint模块输出信号
    wire clint_we_o; // CLINT写使能
    wire[`MemAddrBus] clint_waddr_o; // CLINT写地址
    wire[`MemAddrBus] clint_raddr_o; // CLINT读地址
    wire[`RegBus] clint_data_o; // CLINT写数据
    wire[`InstAddrBus] clint_int_addr_o; // 中断入口
    wire clint_int_assert_o; // 中断有效
    wire clint_hold_flag_o; // CLINT暂停标志


    assign rib_ex_addr_o = (ex_mem_we_o == `WriteEnable)? ex_mem_waddr_o: ex_mem_raddr_o; // 选择读写地址
    assign rib_ex_data_o = ex_mem_wdata_o; // 外设写数据
    assign rib_ex_req_o = ex_mem_req_o; // 外设请求
    assign rib_ex_we_o = ex_mem_we_o; // 外设写使能

    assign rib_pc_addr_o = pc_pc_o; // 取指地址输出

    assign ex_mem_addr_is_offchip = (rib_ex_addr_o[31:28] == 4'h0) ||
                                    (rib_ex_addr_o[31:28] == 4'h1); // 判断片外地址
    assign ex_load_from_offchip = ex_mem_req_o &&
                                  (ex_mem_we_o == `WriteDisable) &&
                                  (ex_reg_we_o == `WriteEnable) &&
                                  ex_mem_addr_is_offchip; // 片外load判定
    assign mem_load_finish = mem_load_pending && mem_load_seen_busy &&
                             s0_busy_d && (rib_hold_flag_full_i == `HoldDisable); // 片外load完成判定
    assign regs_we = mem_load_finish ? `WriteEnable :
                     (ex_load_from_offchip ? `WriteDisable : ex_reg_we_o); // 写使能选择
    assign regs_waddr = mem_load_finish ? mem_load_rd : ex_reg_waddr_o; // 写地址选择
    assign regs_wdata = mem_load_finish ? mem_load_wdata : ex_reg_wdata_o; // 写数据选择

    always @(*) begin // 片外load数据对齐
        case (mem_load_funct3) // 根据load类型
            `INST_LB: begin // 有符号字节
                case (mem_load_addr_index) // 字节选择
                    2'b00: mem_load_wdata = {{24{offchip_mem_rdata_i[7]}}, offchip_mem_rdata_i[7:0]}; // 低字节
                    2'b01: mem_load_wdata = {{24{offchip_mem_rdata_i[15]}}, offchip_mem_rdata_i[15:8]}; // 次低字节
                    2'b10: mem_load_wdata = {{24{offchip_mem_rdata_i[23]}}, offchip_mem_rdata_i[23:16]}; // 次高字节
                    default: mem_load_wdata = {{24{offchip_mem_rdata_i[31]}}, offchip_mem_rdata_i[31:24]}; // 高字节
                endcase // 字节选择结束
            end
            `INST_LH: begin // 有符号半字
                if (mem_load_addr_index == 2'b00) begin // 低半字
                    mem_load_wdata = {{16{offchip_mem_rdata_i[15]}}, offchip_mem_rdata_i[15:0]}; // 低半字对齐
                end else begin // 高半字
                    mem_load_wdata = {{16{offchip_mem_rdata_i[31]}}, offchip_mem_rdata_i[31:16]}; // 高半字对齐
                end
            end
            `INST_LBU: begin // 无符号字节
                case (mem_load_addr_index) // 字节选择
                    2'b00: mem_load_wdata = {24'h0, offchip_mem_rdata_i[7:0]}; // 低字节
                    2'b01: mem_load_wdata = {24'h0, offchip_mem_rdata_i[15:8]}; // 次低字节
                    2'b10: mem_load_wdata = {24'h0, offchip_mem_rdata_i[23:16]}; // 次高字节
                    default: mem_load_wdata = {24'h0, offchip_mem_rdata_i[31:24]}; // 高字节
                endcase // 字节选择结束
            end
            `INST_LHU: begin // 无符号半字
                if (mem_load_addr_index == 2'b00) begin // 低半字
                    mem_load_wdata = {16'h0, offchip_mem_rdata_i[15:0]}; // 低半字对齐
                end else begin // 高半字
                    mem_load_wdata = {16'h0, offchip_mem_rdata_i[31:16]}; // 高半字对齐
                end
            end
            default: begin // 其他类型
                mem_load_wdata = offchip_mem_rdata_i; // 直接取整字
            end
        endcase // load对齐结束
    end

    always @(posedge clk) begin // 片外load状态机
        if (rst == `RstEnable) begin // 复位
            mem_load_pending <= 1'b0; // 清挂起
            mem_load_seen_busy <= 1'b0; // 清busy标志
            s0_busy_d <= 1'b0; // 清延迟busy
            mem_load_funct3 <= 3'b000; // 清类型
            mem_load_addr_index <= 2'b00; // 清索引
            mem_load_rd <= `ZeroReg; // 清rd
        end else begin // 非复位
            s0_busy_d <= rib_hold_flag_full_i; // 记录busy
            if (mem_load_finish) begin // load完成
                mem_load_pending <= 1'b0; // 清挂起
                mem_load_seen_busy <= 1'b0; // 清busy标志
            end else if (ex_load_from_offchip && (mem_load_pending == 1'b0)) begin // 新片外load
                mem_load_pending <= 1'b1; // 置挂起
                mem_load_seen_busy <= 1'b0; // 清busy标志
                mem_load_funct3 <= ie_inst_o[14:12]; // 记录类型
                mem_load_addr_index <= ex_mem_raddr_o[1:0]; // 记录字节索引
                mem_load_rd <= ex_reg_waddr_o; // 记录rd
            end else if (mem_load_pending && (rib_hold_flag_full_i == `HoldEnable)) begin // 见到busy
                mem_load_seen_busy <= 1'b1; // 置busy标志
            end
        end
    end


    // pc_reg模块例化
    pc_reg u_pc_reg( // PC寄存器
        .clk(clk), // 时钟
        .rst(rst), // 复位
        .jtag_reset_flag_i(jtag_reset_flag_i), // JTAG复位
        .pc_o(pc_pc_o), // PC输出
        .hold_flag_i(ctrl_hold_flag_o), // 暂停标志
        .jump_flag_i(ctrl_jump_flag_o), // 跳转标志
        .jump_addr_i(ctrl_jump_addr_o) // 跳转地址
    );

    // ctrl模块例化
    ctrl u_ctrl( // 控制模块
        .rst(rst), // 复位
        .jump_flag_i(ex_jump_flag_o), // 执行跳转标志
        .jump_addr_i(ex_jump_addr_o), // 执行跳转地址
        .hold_flag_ex_i(ex_hold_flag_o), // 执行暂停
        .hold_flag_rib_i(rib_hold_flag_i), // 总线暂停
        .hold_flag_rib_full_i(rib_hold_flag_full_i), // 总线全暂停
        .hold_flag_o(ctrl_hold_flag_o), // 输出暂停
        .hold_flag_clint_i(clint_hold_flag_o), // CLINT暂停
        .jump_flag_o(ctrl_jump_flag_o), // 输出跳转
        .jump_addr_o(ctrl_jump_addr_o), // 输出跳转地址
        .jtag_halt_flag_i(jtag_halt_flag_i) // JTAG暂停
    );

    // regs模块例化
    regs u_regs( // 通用寄存器堆
        .clk(clk), // 时钟
        .rst(rst), // 复位
        .we_i(regs_we), // 写使能
        .waddr_i(regs_waddr), // 写地址
        .wdata_i(regs_wdata), // 写数据
        .raddr1_i(id_reg1_raddr_o), // 读地址1
        .rdata1_o(regs_rdata1_o), // 读数据1
        .raddr2_i(id_reg2_raddr_o), // 读地址2
        .rdata2_o(regs_rdata2_o), // 读数据2
        .jtag_we_i(jtag_reg_we_i), // JTAG写使能
        .jtag_addr_i(jtag_reg_addr_i), // JTAG地址
        .jtag_data_i(jtag_reg_data_i), // JTAG写数据
        .jtag_data_o(jtag_reg_data_o) // JTAG读数据
    );

    // csr_reg模块例化
    csr_reg u_csr_reg( // CSR寄存器
        .clk(clk), // 时钟
        .rst(rst), // 复位
        .we_i(ex_csr_we_o), // EX写使能
        .raddr_i(id_csr_raddr_o), // 读地址
        .waddr_i(ex_csr_waddr_o), // 写地址
        .data_i(ex_csr_wdata_o), // 写数据
        .data_o(csr_data_o), // 读数据
        .global_int_en_o(csr_global_int_en_o), // 全局中断使能
        .clint_we_i(clint_we_o), // CLINT写使能
        .clint_raddr_i(clint_raddr_o), // CLINT读地址
        .clint_waddr_i(clint_waddr_o), // CLINT写地址
        .clint_data_i(clint_data_o), // CLINT写数据
        .clint_data_o(csr_clint_data_o), // CLINT读数据
        .clint_csr_mtvec(csr_clint_csr_mtvec), // CLINT mtvec
        .clint_csr_mepc(csr_clint_csr_mepc), // CLINT mepc
        .clint_csr_mstatus(csr_clint_csr_mstatus) // CLINT mstatus
    );

    // if_id模块例化
    if_id u_if_id( // IF/ID寄存器
        .clk(clk), // 时钟
        .rst(rst), // 复位
        .inst_i(rib_pc_data_i), // 取指数据
        .inst_addr_i(pc_pc_o), // 取指地址
        .int_flag_i(int_i), // 中断标志
        .int_flag_o(if_int_flag_o), // 中断输出
        .hold_flag_i(ctrl_hold_flag_o), // 暂停标志
        .inst_o(if_inst_o), // 指令输出
        .inst_addr_o(if_inst_addr_o) // 地址输出
    );

    // id模块例化
    id u_id( // 指令译码
        .rst(rst), // 复位
        .inst_i(if_inst_o), // 指令输入
        .inst_addr_i(if_inst_addr_o), // 指令地址
        .reg1_rdata_i(regs_rdata1_o), // rs1数据
        .reg2_rdata_i(regs_rdata2_o), // rs2数据
        .ex_jump_flag_i(ex_jump_flag_o), // 前递跳转标志
        .reg1_raddr_o(id_reg1_raddr_o), // rs1读地址
        .reg2_raddr_o(id_reg2_raddr_o), // rs2读地址
        .inst_o(id_inst_o), // 指令输出
        .inst_addr_o(id_inst_addr_o), // 地址输出
        .reg1_rdata_o(id_reg1_rdata_o), // rs1输出
        .reg2_rdata_o(id_reg2_rdata_o), // rs2输出
        .reg_we_o(id_reg_we_o), // 写使能输出
        .reg_waddr_o(id_reg_waddr_o), // 写地址输出
        .op1_o(id_op1_o), // 操作数1
        .op2_o(id_op2_o), // 操作数2
        .op1_jump_o(id_op1_jump_o), // 跳转操作数1
        .op2_jump_o(id_op2_jump_o), // 跳转操作数2
        .csr_rdata_i(csr_data_o), // CSR读数据
        .csr_raddr_o(id_csr_raddr_o), // CSR读地址
        .csr_we_o(id_csr_we_o), // CSR写使能
        .csr_rdata_o(id_csr_rdata_o), // CSR读数据输出
        .csr_waddr_o(id_csr_waddr_o) // CSR写地址
    );

    // id_ex模块例化
    id_ex u_id_ex( // ID/EX寄存器
        .clk(clk), // 时钟
        .rst(rst), // 复位
        .inst_i(id_inst_o), // 指令输入
        .inst_addr_i(id_inst_addr_o), // 指令地址
        .reg_we_i(id_reg_we_o), // 写使能
        .reg_waddr_i(id_reg_waddr_o), // 写地址
        .reg1_rdata_i(id_reg1_rdata_o), // rs1数据
        .reg2_rdata_i(id_reg2_rdata_o), // rs2数据
        .hold_flag_i(ctrl_hold_flag_o), // 暂停标志
        .inst_o(ie_inst_o), // 指令输出
        .inst_addr_o(ie_inst_addr_o), // 地址输出
        .reg_we_o(ie_reg_we_o), // 写使能输出
        .reg_waddr_o(ie_reg_waddr_o), // 写地址输出
        .reg1_rdata_o(ie_reg1_rdata_o), // rs1输出
        .reg2_rdata_o(ie_reg2_rdata_o), // rs2输出
        .op1_i(id_op1_o), // 操作数1输入
        .op2_i(id_op2_o), // 操作数2输入
        .op1_jump_i(id_op1_jump_o), // 跳转操作数1输入
        .op2_jump_i(id_op2_jump_o), // 跳转操作数2输入
        .op1_o(ie_op1_o), // 操作数1输出
        .op2_o(ie_op2_o), // 操作数2输出
        .op1_jump_o(ie_op1_jump_o), // 跳转操作数1输出
        .op2_jump_o(ie_op2_jump_o), // 跳转操作数2输出
        .csr_we_i(id_csr_we_o), // CSR写使能输入
        .csr_waddr_i(id_csr_waddr_o), // CSR写地址输入
        .csr_rdata_i(id_csr_rdata_o), // CSR读数据输入
        .csr_we_o(ie_csr_we_o), // CSR写使能输出
        .csr_waddr_o(ie_csr_waddr_o), // CSR写地址输出
        .csr_rdata_o(ie_csr_rdata_o) // CSR读数据输出
    );

    // ex模块例化
    ex u_ex( // 执行模块
        .rst(rst), // 复位
        .inst_i(ie_inst_o), // 指令输入
        .inst_addr_i(ie_inst_addr_o), // 指令地址
        .reg_we_i(ie_reg_we_o), // 写使能
        .reg_waddr_i(ie_reg_waddr_o), // 写地址
        .reg1_rdata_i(ie_reg1_rdata_o), // rs1数据
        .reg2_rdata_i(ie_reg2_rdata_o), // rs2数据
        .op1_i(ie_op1_o), // 操作数1
        .op2_i(ie_op2_o), // 操作数2
        .op1_jump_i(ie_op1_jump_o), // 跳转操作数1
        .op2_jump_i(ie_op2_jump_o), // 跳转操作数2
        .mem_rdata_i(rib_ex_data_i), // 外设读数据
        .mem_wdata_o(ex_mem_wdata_o), // 写外设数据
        .mem_raddr_o(ex_mem_raddr_o), // 读外设地址
        .mem_waddr_o(ex_mem_waddr_o), // 写外设地址
        .mem_we_o(ex_mem_we_o), // 写外设使能
        .mem_req_o(ex_mem_req_o), // 外设请求
        .reg_wdata_o(ex_reg_wdata_o), // 写回数据
        .reg_we_o(ex_reg_we_o), // 写回使能
        .reg_waddr_o(ex_reg_waddr_o), // 写回地址
        .hold_flag_o(ex_hold_flag_o), // 暂停标志
        .jump_flag_o(ex_jump_flag_o), // 跳转标志
        .jump_addr_o(ex_jump_addr_o), // 跳转地址
        .int_assert_i(clint_int_assert_o), // 中断有效
        .int_addr_i(clint_int_addr_o), // 中断入口
        .div_ready_i(div_ready_o), // 除法完成
        .div_result_i(div_result_o), // 除法结果
        .div_busy_i(div_busy_o), // 除法忙
        .div_reg_waddr_i(div_reg_waddr_o), // 除法写回地址
        .custom_ready_i(custom_ready), // 自定义完成
        .custom_busy_i(custom_busy), // 自定义忙
        .custom_reg_we_i(custom_reg_we), // 自定义写使能
        .custom_reg_waddr_i(custom_reg_waddr), // 自定义写地址
        .custom_reg_wdata_i(custom_reg_wdata), // 自定义写数据
        .div_start_o(ex_div_start_o), // 启动除法
        .div_dividend_o(ex_div_dividend_o), // 被除数
        .div_divisor_o(ex_div_divisor_o), // 除数
        .div_op_o(ex_div_op_o), // 除法操作码
        .div_reg_waddr_o(ex_div_reg_waddr_o), // 除法写回地址
        .custom_start_o(custom_start), // 自定义启动
        .custom_funct3_o(custom_funct3), // 自定义funct3
        .custom_imm_o(custom_imm), // 自定义立即数
        .custom_rs1_data_o(custom_rs1_data), // 自定义rs1数据
        .custom_x31_data_o(custom_x31_data), // 自定义x31数据
        .custom_rd_o(custom_rd), // 自定义rd
        .csr_we_i(ie_csr_we_o), // CSR写使能
        .csr_waddr_i(ie_csr_waddr_o), // CSR写地址
        .csr_rdata_i(ie_csr_rdata_o), // CSR读数据
        .csr_wdata_o(ex_csr_wdata_o), // CSR写数据
        .csr_we_o(ex_csr_we_o), // CSR写使能
        .csr_waddr_o(ex_csr_waddr_o) // CSR写地址
    );

    // div模块例化
    div u_div( // 除法器
        .clk(clk), // 时钟
        .rst(rst), // 复位
        .dividend_i(ex_div_dividend_o), // 被除数
        .divisor_i(ex_div_divisor_o), // 除数
        .start_i(ex_div_start_o), // 启动
        .op_i(ex_div_op_o), // 操作码
        .reg_waddr_i(ex_div_reg_waddr_o), // 写回地址
        .result_o(div_result_o), // 运算结果
        .ready_o(div_ready_o), // 完成标志
        .busy_o(div_busy_o), // 忙标志
        .reg_waddr_o(div_reg_waddr_o) // 写回地址
    );

    // custom instruction unit
    custom_unit u_custom_unit( // 自定义指令单元
        .clk(clk), // 时钟
        .rst(rst), // 复位
        .start_i(custom_start), // 启动
        .funct3_i(custom_funct3), // funct3
        .imm_i(custom_imm), // 立即数
        .rs1_data_i(custom_rs1_data), // rs1数据
        .x31_data_i(custom_x31_data), // x31数据
        .rd_i(custom_rd), // rd
        .busy_o(custom_busy), // 忙标志
        .ready_o(custom_ready), // 完成标志
        .reg_we_o(custom_reg_we), // 写回使能
        .reg_waddr_o(custom_reg_waddr), // 写回地址
        .reg_wdata_o(custom_reg_wdata), // 写回数据
        .uart_tx_valid_o(custom_uart_tx_valid_o), // UART发送有效
        .uart_tx_data_o(custom_uart_tx_data_o), // UART发送数据
        .uart_tx_ready_i(custom_uart_tx_ready_i), // UART发送就绪
        .i2c_temp_req_o(custom_i2c_temp_req_o), // I2C温度请求
        .i2c_temp_valid_i(custom_i2c_temp_valid_i), // I2C温度有效
        .i2c_temp_data_i(custom_i2c_temp_data_i), // I2C温度数据
        .i2c_busy_i(custom_i2c_busy_i) // I2C忙标志
    );

    // clint模块例化
    clint u_clint( // 本地中断控制
        .clk(clk), // 时钟
        .rst(rst), // 复位
        .int_flag_i(if_int_flag_o), // 中断标志
        .inst_i(id_inst_o), // 指令输入
        .inst_addr_i(id_inst_addr_o), // 指令地址
        .jump_flag_i(ex_jump_flag_o), // 跳转标志
        .jump_addr_i(ex_jump_addr_o), // 跳转地址
        .hold_flag_i(ctrl_hold_flag_o), // 暂停标志
        .div_started_i(ex_div_start_o), // 除法启动
        .data_i(csr_clint_data_o), // CSR读数据
        .csr_mtvec(csr_clint_csr_mtvec), // mtvec
        .csr_mepc(csr_clint_csr_mepc), // mepc
        .csr_mstatus(csr_clint_csr_mstatus), // mstatus
        .we_o(clint_we_o), // 写使能
        .waddr_o(clint_waddr_o), // 写地址
        .raddr_o(clint_raddr_o), // 读地址
        .data_o(clint_data_o), // 写数据
        .hold_flag_o(clint_hold_flag_o), // 暂停标志
        .global_int_en_i(csr_global_int_en_o), // 全局中断使能
        .int_addr_o(clint_int_addr_o), // 中断入口
        .int_assert_o(clint_int_assert_o) // 中断有效
    );

endmodule // 模块结束
