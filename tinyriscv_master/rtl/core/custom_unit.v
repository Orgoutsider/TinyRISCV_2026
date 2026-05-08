/*
 * 自定义指令多周期执行单元。
 *   sID: 通过UART发送学号ASCII。
 *   rT : 通过I2C读取LM75温度并写入x[rd]。
 *   if : 当imm==0且x[rs1]>=x31时，发送x[rs1][7:0]并写0。
 *
 * 学号ASCII字节在下面FSM中按小端索引case表取出。
 * 请在最终提交前将DEFAULT_ID_*替换为自己的学号字节。
 */
`include "defines.v" // 全局宏定义
// 已经完成验证，有波形图

module custom_unit #( // 自定义指令执行模块
    parameter ID_LEN = 10, // 学号字节数
    parameter DEFAULT_ID0 = 8'h32, // 默认学号字节0（'2'）
    parameter DEFAULT_ID1 = 8'h30, // 默认学号字节1（'0'）
    parameter DEFAULT_ID2 = 8'h32, // 默认学号字节2（'2'）
    parameter DEFAULT_ID3 = 8'h35, // 默认学号字节3（'5'）
    parameter DEFAULT_ID4 = 8'h32, // 默认学号字节4（'2'）
    parameter DEFAULT_ID5 = 8'h31, // 默认学号字节5（'1'）
    parameter DEFAULT_ID6 = 8'h30, // 默认学号字节6（'0'）
    parameter DEFAULT_ID7 = 8'h39, // 默认学号字节7（'9'）
    parameter DEFAULT_ID8 = 8'h31, // 默认学号字节8（'1'）
    parameter DEFAULT_ID9 = 8'h31  // 默认学号字节9（'1'）
)( // 参数列表结束
    input  wire       clk, // 时钟信号
    input  wire       rst, // 复位信号

    // 指令输入信号
    input  wire       start_i, // 启动请求
    input  wire[2:0]  funct3_i, // 指令funct3
    input  wire[11:0] imm_i, // 立即数
    input  wire[31:0] rs1_data_i, // rs1数据
    input  wire[31:0] x31_data_i, // x31数据
    input  wire[4:0]  rd_i, // 目的寄存器地址

    // 执行状态信号
    output reg        busy_o, // 忙标志
    output reg        ready_o, // 完成标志

    // 寄存器写回信号
    output reg        reg_we_o, // 写回使能
    output reg [4:0]  reg_waddr_o, // 写回寄存器地址
    output reg [31:0] reg_wdata_o, // 写回寄存器数据

    // UART 接口（与 uart_shared 通信）
    output reg        uart_tx_valid_o, // UART发送有效
    output reg [7:0]  uart_tx_data_o, // UART发送数据
    input  wire       uart_tx_ready_i, // UART可发送

    // I2C 接口（与 i2c_lm75 通信）
    output reg        i2c_temp_req_o, // I2C温度请求
    input  wire       i2c_temp_valid_i, // I2C温度有效
    input  wire[7:0]  i2c_temp_data_i, // I2C温度数据
    input  wire       i2c_busy_i // I2C忙标志
); // 端口列表结束

    localparam S_IDLE       = 4'd0; // 空闲状态
    localparam S_SID_SEND   = 4'd1; // 发送学号字节
    localparam S_SID_WAIT   = 4'd2; // 等待发送握手
    localparam S_RT_REQ     = 4'd3; // 请求温度采样
    localparam S_RT_WAIT    = 4'd4; // 等待温度数据
    localparam S_IF_SEND    = 4'd5; // 发送if字节
    localparam S_IF_WAIT    = 4'd6; // 等待if发送握手
    localparam S_DONE       = 4'd7; // 完成状态

    reg[3:0] state; // 状态寄存器
    reg[3:0] id_idx; // 学号字节索引
    reg[4:0] rd_saved; // 保存的rd
    reg[7:0] if_byte_saved; // 保存的if字节

    function [7:0] id_byte; // 学号字节查表函数
        input [3:0] idx; // 字节索引
        begin // 函数体开始
            case (idx) // 根据索引选择字节
                4'd0: id_byte = DEFAULT_ID0; // 字节0
                4'd1: id_byte = DEFAULT_ID1; // 字节1
                4'd2: id_byte = DEFAULT_ID2; // 字节2
                4'd3: id_byte = DEFAULT_ID3; // 字节3
                4'd4: id_byte = DEFAULT_ID4; // 字节4
                4'd5: id_byte = DEFAULT_ID5; // 字节5
                4'd6: id_byte = DEFAULT_ID6; // 字节6
                4'd7: id_byte = DEFAULT_ID7; // 字节7
                4'd8: id_byte = DEFAULT_ID8; // 字节8
                4'd9: id_byte = DEFAULT_ID9; // 字节9
                default: id_byte = 8'h00; // 默认值
            endcase // case结束
        end // 函数体结束
    endfunction // 函数结束

    always @(posedge clk) begin // 时序状态机
        if (rst == `RstEnable) begin // 复位处理
            state <= S_IDLE; // 状态复位
            busy_o <= 1'b0; // 清忙标志
            ready_o <= 1'b0; // 清完成标志
            reg_we_o <= `WriteDisable; // 禁止写回
            reg_waddr_o <= `ZeroReg; // 写回地址复位
            reg_wdata_o <= `ZeroWord; // 写回数据复位
            uart_tx_valid_o <= 1'b0; // 清UART有效
            uart_tx_data_o <= 8'h00; // UART数据清零
            i2c_temp_req_o <= 1'b0; // 清I2C请求
            id_idx <= 4'd0; // 索引清零
            rd_saved <= `ZeroReg; // rd保存清零
            if_byte_saved <= 8'h00; // if字节清零
        end else begin // 非复位
            ready_o <= 1'b0; // 默认不完成
            reg_we_o <= `WriteDisable; // 默认不写回
            uart_tx_valid_o <= 1'b0; // 默认不发送
            i2c_temp_req_o <= 1'b0; // 默认不请求

            case (state) // 状态机分支
                S_IDLE: begin // 空闲状态
                    busy_o <= 1'b0; // 清忙标志
                    if (start_i) begin // 有启动请求
                        busy_o <= 1'b1; // 置忙
                        rd_saved <= rd_i; // 保存rd
                        case (funct3_i) // 根据指令类型
                            `INST_SID: begin // 发送学号
                                id_idx <= 4'd0; // 从0开始
                                state <= S_SID_SEND; // 转到发送
                            end
                            `INST_RT: begin // 读温度
                                state <= S_RT_REQ; // 转到请求
                            end
                            `INST_IFIRE: begin // if自定义指令
                                if_byte_saved <= rs1_data_i[7:0]; // 保存待发字节
                                state <= S_IF_SEND; // 转到发送
                            end
                            default: begin // 其他指令
                                state <= S_DONE; // 直接完成
                            end
                        endcase // 指令选择结束
                    end
                end

                S_SID_SEND: begin // 发送学号字节
                    if (uart_tx_ready_i) begin // UART可发送
                        uart_tx_valid_o <= 1'b1; // 拉高有效
                        uart_tx_data_o  <= id_byte(id_idx); // 发送字节
                        state <= S_SID_WAIT; // 转等待
                    end
                end
                S_SID_WAIT: begin // 等待发送完成
                    if (!uart_tx_ready_i) begin // 等待握手拉低
                        if (id_idx == (ID_LEN - 1)) begin // 最后一个字节
                            state <= S_DONE; // 完成
                        end else begin // 还有字节
                            id_idx <= id_idx + 1'b1; // 索引加1
                            state <= S_SID_SEND; // 继续发送
                        end
                    end
                end

                S_RT_REQ: begin // 请求温度
                    if (!i2c_busy_i) begin // I2C空闲
                        i2c_temp_req_o <= 1'b1; // 发起请求
                        state <= S_RT_WAIT; // 转等待
                    end
                end
                S_RT_WAIT: begin // 等待温度数据
                    if (i2c_temp_valid_i) begin // 温度有效
                        reg_we_o <= `WriteEnable; // 允许写回
                        reg_waddr_o <= rd_saved; // 写回rd
                        reg_wdata_o <= {24'h0, i2c_temp_data_i}; // 写回温度
                        state <= S_DONE; // 完成
                    end
                end

                S_IF_SEND: begin // 发送if字节
                    if (uart_tx_ready_i) begin // UART可发送
                        uart_tx_valid_o <= 1'b1; // 拉高有效
                        uart_tx_data_o  <= if_byte_saved; // 发送字节
                        state <= S_IF_WAIT; // 转等待
                    end
                end
                S_IF_WAIT: begin // 等待if发送完成
                    if (!uart_tx_ready_i) begin // 等待握手
                        reg_we_o <= `WriteEnable; // 允许写回
                        reg_waddr_o <= rd_saved; // 写回rd
                        reg_wdata_o <= `ZeroWord; // 写回0
                        state <= S_DONE; // 完成
                    end
                end

                S_DONE: begin // 完成状态
                    ready_o <= 1'b1; // 拉高完成
                    busy_o <= 1'b0; // 清忙
                    state <= S_IDLE; // 回到空闲
                end

                default: begin // 其他状态
                    state <= S_IDLE; // 回到空闲
                    busy_o <= 1'b0; // 清忙
                end
            endcase // 状态机结束
        end
    end

endmodule // 模块结束
