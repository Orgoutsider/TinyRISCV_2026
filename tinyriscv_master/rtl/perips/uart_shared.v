/*
 * 带自定义指令发送注入口的存储器映射UART。
 * MMIO接口与原 tinyriscv UART 兼容：
 *   +0x00 CTRL   bit0 TX使能，bit1 RX使能
 *   +0x04 STATUS bit0 TX忙，bit1 RX溢出
 *   +0x08 BAUD
 *   +0x0c TXDATA
 *   +0x10 RXDATA
 */
`include "defines.v" // 全局宏定义

module uart_shared( // UART共享模块
    input  wire        clk, // 时钟信号
    input  wire        rst, // 复位信号
    input  wire        we_i, // 写使能
    input  wire[31:0]  addr_i, // 地址
    input  wire[31:0]  data_i, // 写数据
    output reg [31:0]  data_o, // 读数据
    output wire        tx_pin, // TX引脚
    input  wire        rx_pin, // RX引脚

    input  wire        custom_tx_valid_i, // 自定义发送有效
    input  wire[7:0]   custom_tx_data_i, // 自定义发送数据
    output wire        custom_tx_ready_o // 自定义发送就绪
);

    localparam BAUD_115200 = 32'h0000_01B8; // 默认波特率分频

    localparam UART_CTRL   = 8'h00; // 控制寄存器地址
    localparam UART_STATUS = 8'h04; // 状态寄存器地址
    localparam UART_BAUD   = 8'h08; // 波特率寄存器地址
    localparam UART_TXDATA = 8'h0c; // 发送数据寄存器地址
    localparam UART_RXDATA = 8'h10; // 接收数据寄存器地址

    localparam S_IDLE      = 4'b0001; // 空闲状态
    localparam S_START     = 4'b0010; // 起始位状态
    localparam S_SEND_BYTE = 4'b0100; // 发送数据状态
    localparam S_STOP      = 4'b1000; // 停止位状态

    reg[31:0] uart_ctrl; // 控制寄存器
    reg[31:0] uart_status; // 状态寄存器
    reg[31:0] uart_baud; // 波特率寄存器
    reg[31:0] uart_rx; // 接收寄存器

    reg       tx_data_valid; // 发送有效
    reg       tx_data_ready; // 发送完成
    reg[7:0]  tx_data; // 发送数据
    reg[3:0]  tx_state; // 发送状态
    reg[15:0] tx_cycle_cnt; // 发送计数
    reg[3:0]  tx_bit_cnt; // 发送位计数
    reg       tx_reg; // TX寄存器

    reg rx_q0; // RX同步寄存器0
    reg rx_q1; // RX同步寄存器1
    wire rx_negedge; // RX下降沿
    reg rx_start; // 接收启动
    reg[3:0] rx_clk_edge_cnt; // 接收时钟沿计数
    reg rx_clk_edge_level; // 接收时钟沿电平
    reg rx_done; // 接收完成
    reg[15:0] rx_clk_cnt; // 接收时钟计数
    reg[15:0] rx_div_cnt; // 接收分频计数
    reg[7:0] rx_data; // 接收数据
    reg rx_over; // 接收溢出

    wire mmio_tx_req = (we_i == `WriteEnable) && // MMIO写请求
                       (addr_i[7:0] == UART_TXDATA) && // 写TXDATA
                       (uart_ctrl[0] == 1'b1) && // TX使能
                       (uart_status[0] == 1'b0); // TX空闲

    assign custom_tx_ready_o = (uart_status[0] == 1'b0); // 自定义发送就绪条件
    assign tx_pin = tx_reg; // 输出TX引脚

    always @(posedge clk) begin // 寄存器写控制
        if (rst == `RstEnable) begin // 复位
            uart_ctrl      <= 32'h0000_0003; // 默认开TX/RX
            uart_status    <= 32'h0; // 状态清零
            uart_rx        <= 32'h0; // 接收清零
            uart_baud      <= BAUD_115200; // 默认波特率
            tx_data_valid  <= 1'b0; // 清发送有效
            tx_data        <= 8'h00; // 清发送数据
        end else begin // 非复位
            tx_data_valid <= 1'b0; // 默认不发送

            if (we_i == `WriteEnable) begin // MMIO写
                case (addr_i[7:0]) // 地址译码
                    UART_CTRL: begin // 控制寄存器
                        uart_ctrl <= data_i; // 写控制
                    end // 分支结束
                    UART_BAUD: begin // 波特率寄存器
                        uart_baud <= data_i; // 写波特率
                    end // 分支结束
                    UART_STATUS: begin // 状态寄存器
                        uart_status[1] <= data_i[1]; // 清接收溢出
                    end // 分支结束
                    UART_TXDATA: begin // 发送数据寄存器
                        if (mmio_tx_req) begin // 允许发送
                            tx_data       <= data_i[7:0]; // 载入数据
                            uart_status[0] <= 1'b1; // 置忙
                            tx_data_valid <= 1'b1; // 触发发送
                        end // if结束
                    end // 分支结束
                    default: begin // 默认分支
                    end // 分支结束
                endcase // case结束
            end else if (custom_tx_valid_i && custom_tx_ready_o) begin // 自定义发送
                tx_data         <= custom_tx_data_i; // 载入自定义数据
                uart_status[0]  <= 1'b1; // 置忙
                tx_data_valid   <= 1'b1; // 触发发送
            end else begin // 无写操作
                if (tx_data_ready == 1'b1) begin // 发送完成
                    uart_status[0] <= 1'b0; // 清忙
                end // if结束
                if (uart_ctrl[1] == 1'b1 && rx_over == 1'b1) begin // 接收完成
                    uart_status[1] <= 1'b1; // 置接收溢出
                    uart_rx <= {24'h0, rx_data}; // 写接收数据
                end // if结束
            end // if结束
        end // if结束
    end // always结束

    always @(*) begin // 读寄存器
        if (rst == `RstEnable) begin // 复位
            data_o = `ZeroWord; // 读数据清零
        end else begin // 非复位
            case (addr_i[7:0]) // 地址译码
                UART_CTRL:   data_o = uart_ctrl; // 读控制
                UART_STATUS: data_o = uart_status; // 读状态
                UART_BAUD:   data_o = uart_baud; // 读波特率
                UART_RXDATA: data_o = uart_rx; // 读接收
                default:     data_o = `ZeroWord; // 默认清零
            endcase // case结束
        end // if结束
    end // always结束

    // TX engine
    always @(posedge clk) begin // 发送状态机
        if (rst == `RstEnable) begin // 复位
            tx_state      <= S_IDLE; // 状态空闲
            tx_cycle_cnt  <= 16'd0; // 计数清零
            tx_reg        <= 1'b1; // TX空闲高
            tx_bit_cnt    <= 4'd0; // 位计数清零
            tx_data_ready <= 1'b0; // 清发送完成
        end else begin // 非复位
            if (tx_state == S_IDLE) begin // 空闲状态
                tx_reg <= 1'b1; // TX拉高
                tx_data_ready <= 1'b0; // 清完成标志
                if (tx_data_valid == 1'b1) begin // 有发送请求
                    tx_state <= S_START; // 转起始位
                    tx_cycle_cnt <= 16'd0; // 清计数
                    tx_bit_cnt <= 4'd0; // 清位计数
                    tx_reg <= 1'b0; // 拉低起始位
                end // if结束
            end else begin // 非空闲
                tx_cycle_cnt <= tx_cycle_cnt + 1'b1; // 计数加1
                if (tx_cycle_cnt == uart_baud[15:0]) begin // 达到分频
                    tx_cycle_cnt <= 16'd0; // 计数清零
                    case (tx_state) // 状态分支
                        S_START: begin // 起始位
                            tx_reg <= tx_data[tx_bit_cnt]; // 发送第1位
                            tx_state <= S_SEND_BYTE; // 转发送数据
                            tx_bit_cnt <= tx_bit_cnt + 1'b1; // 位计数加1
                        end // 分支结束
                        S_SEND_BYTE: begin // 发送数据
                            tx_bit_cnt <= tx_bit_cnt + 1'b1; // 位计数加1
                            if (tx_bit_cnt == 4'd8) begin // 数据结束
                                tx_state <= S_STOP; // 转停止位
                                tx_reg <= 1'b1; // 拉高停止位
                            end else begin // 数据未完
                                tx_reg <= tx_data[tx_bit_cnt]; // 发送当前位
                            end // if结束
                        end // 分支结束
                        S_STOP: begin // 停止位
                            tx_reg <= 1'b1; // 保持高
                            tx_state <= S_IDLE; // 回空闲
                            tx_data_ready <= 1'b1; // 发送完成
                        end // 分支结束
                        default: tx_state <= S_IDLE; // 默认回空闲
                    endcase // case结束
                end // if结束
            end // if结束
        end // if结束
    end // always结束

    assign rx_negedge = rx_q1 && ~rx_q0; // RX下降沿检测

    always @(posedge clk) begin // RX同步
        if (rst == `RstEnable) begin // 复位
            rx_q0 <= 1'b1; // 同步寄存器清零
            rx_q1 <= 1'b1; // 同步寄存器清零
        end else begin // 非复位
            rx_q0 <= rx_pin; // 采样RX
            rx_q1 <= rx_q0; // 延迟一拍
        end // if结束
    end // always结束

    always @(posedge clk) begin // 接收启动控制
        if (rst == `RstEnable) begin // 复位
            rx_start <= 1'b0; // 清启动
        end else begin // 非复位
            if (uart_ctrl[1]) begin // RX使能
                if (rx_negedge) begin // 检测起始位
                    rx_start <= 1'b1; // 开始接收
                end else if (rx_clk_edge_cnt == 4'd9) begin // 接收结束
                    rx_start <= 1'b0; // 停止接收
                end // if结束
            end else begin // RX关闭
                rx_start <= 1'b0; // 清启动
            end // if结束
        end // if结束
    end // always结束

    always @(posedge clk) begin // 接收分频计数
        if (rst == `RstEnable) begin // 复位
            rx_div_cnt <= 16'd0; // 清分频计数
        end else if (rx_start) begin // 接收进行中
            if (rx_div_cnt == uart_baud[15:0]) begin // 达到分频
                rx_div_cnt <= 16'd0; // 清计数
            end else begin // 未达到
                rx_div_cnt <= rx_div_cnt + 1'b1; // 计数加1
            end // if结束
        end else begin // 未接收
            rx_div_cnt <= 16'd0; // 清计数
        end // if结束
    end // always结束

    always @(posedge clk) begin // 采样时钟边沿计数
        if (rst == `RstEnable) begin // 复位
            rx_clk_cnt <= 16'd0; // 计数清零
            rx_clk_edge_cnt <= 4'd0; // 边沿计数清零
            rx_clk_edge_level <= 1'b0; // 边沿电平清零
        end else if (rx_start) begin // 接收进行中
            if (rx_div_cnt == uart_baud[15:0]) begin // 达到分频
                rx_clk_cnt <= rx_clk_cnt + 1'b1; // 时钟计数加1
                rx_clk_edge_level <= 1'b1; // 产生边沿脉冲
                rx_clk_edge_cnt <= rx_clk_edge_cnt + 1'b1; // 边沿计数加1
            end else begin // 未达到
                rx_clk_edge_level <= 1'b0; // 边沿电平清零
            end // if结束
        end else begin // 未接收
            rx_clk_cnt <= 16'd0; // 计数清零
            rx_clk_edge_cnt <= 4'd0; // 边沿计数清零
            rx_clk_edge_level <= 1'b0; // 边沿电平清零
        end // if结束
    end // always结束

    always @(posedge clk) begin // 接收数据采样
        if (rst == `RstEnable) begin // 复位
            rx_data <= 8'h00; // 清接收数据
            rx_done <= 1'b0; // 清完成标志
        end else if (rx_start && rx_clk_edge_level) begin // 采样边沿
            rx_done <= 1'b0; // 默认未完成
            case (rx_clk_edge_cnt) // 按位采样
                4'd1: rx_data[0] <= rx_pin; // bit0
                4'd2: rx_data[1] <= rx_pin; // bit1
                4'd3: rx_data[2] <= rx_pin; // bit2
                4'd4: rx_data[3] <= rx_pin; // bit3
                4'd5: rx_data[4] <= rx_pin; // bit4
                4'd6: rx_data[5] <= rx_pin; // bit5
                4'd7: rx_data[6] <= rx_pin; // bit6
                4'd8: rx_data[7] <= rx_pin; // bit7
                4'd9: rx_done <= 1'b1; // 完成标志
                default: begin // 默认分支
                end // 分支结束
            endcase // case结束
        end else begin // 非采样
            rx_done <= 1'b0; // 清完成标志
        end // if结束
    end // always结束

    always @(posedge clk) begin // 接收完成锁存
        if (rst == `RstEnable) begin // 复位
            rx_over <= 1'b0; // 清接收完成
        end else begin // 非复位
            rx_over <= rx_done; // 锁存完成
        end // if结束
    end // always结束

endmodule // 模块结束
