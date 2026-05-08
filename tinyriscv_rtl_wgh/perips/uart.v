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


// 串口模块(默认: 115200, 8 N 1)
module uart( // UART模块

    input wire clk, // 时钟信号
    input wire rst, // 复位信号(低有效)

    input wire we_i, // 写使能
    input wire[31:0] addr_i, // 地址
    input wire[31:0] data_i, // 写数据

    output reg[31:0] data_o, // 读数据
    output wire tx_pin, // TX引脚
    input wire rx_pin // RX引脚

    ); // 端口列表结束


    // 50MHz时钟，波特率115200bps对应的分频系数
    localparam BAUD_115200 = 32'h1B8; // 默认波特率分频

    localparam S_IDLE       = 4'b0001; // 空闲状态
    localparam S_START      = 4'b0010; // 起始位状态
    localparam S_SEND_BYTE  = 4'b0100; // 发送数据状态
    localparam S_STOP       = 4'b1000; // 停止位状态

    reg tx_data_valid; // 发送有效
    reg tx_data_ready; // 发送完成

    reg[3:0] state; // 发送状态
    reg[15:0] cycle_cnt; // 发送计数
    reg[3:0] bit_cnt; // 发送位计数
    reg[7:0] tx_data; // 发送数据
    reg tx_reg; // TX寄存器

    reg rx_q0; // RX同步寄存器0
    reg rx_q1; // RX同步寄存器1
    wire rx_negedge; // RX下降沿
    reg rx_start; // RX使能
    reg[3:0] rx_clk_edge_cnt; // clk时钟沿的个数
    reg rx_clk_edge_level; // clk沿电平
    reg rx_done; // 接收完成
    reg[15:0] rx_clk_cnt; // 接收时钟计数
    reg[15:0] rx_div_cnt; // 接收分频计数
    reg[7:0] rx_data; // 接收数据
    reg rx_over; // 接收溢出

    localparam UART_CTRL = 8'h0; // 控制寄存器地址
    localparam UART_STATUS = 8'h4; // 状态寄存器地址
    localparam UART_BAUD = 8'h8; // 波特率寄存器地址
    localparam UART_TXDATA = 8'hc; // 发送数据寄存器地址
    localparam UART_RXDATA = 8'h10; // 接收数据寄存器地址

    // addr: 0x00
    // rw. bit[0]: tx enable, 1 = enable, 0 = disable
    // rw. bit[1]: rx enable, 1 = enable, 0 = disable
    reg[31:0] uart_ctrl; // 控制寄存器

    // addr: 0x04
    // ro. bit[0]: tx busy, 1 = busy, 0 = idle
    // rw. bit[1]: rx over, 1 = over, 0 = receiving
    // must check this bit before tx data
    reg[31:0] uart_status; // 状态寄存器

    // addr: 0x08
    // rw. clk div
    reg[31:0] uart_baud; // 波特率寄存器

    // addr: 0x10
    // ro. rx data
    reg[31:0] uart_rx; // 接收寄存器

    assign tx_pin = tx_reg; // TX引脚输出


    // 写寄存器
    always @ (posedge clk) begin // 写控制
        if (rst == 1'b0) begin // 复位
            uart_ctrl <= 32'h0; // 控制清零
            uart_status <= 32'h0; // 状态清零
            uart_rx <= 32'h0; // 接收清零
            uart_baud <= BAUD_115200; // 默认波特率
            tx_data_valid <= 1'b0; // 清发送有效
        end else begin // 非复位
            if (we_i == 1'b1) begin // MMIO写
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
                        if (uart_ctrl[0] == 1'b1 && uart_status[0] == 1'b0) begin // 允许发送
                            tx_data <= data_i[7:0]; // 载入数据
                            uart_status[0] <= 1'b1; // 置忙
                            tx_data_valid <= 1'b1; // 触发发送
                        end // if结束
                    end // 分支结束
                endcase // case结束
            end else begin // 无写操作
                tx_data_valid <= 1'b0; // 默认不发送
                if (tx_data_ready == 1'b1) begin // 发送完成
                    uart_status[0] <= 1'b0; // 清忙
                end // if结束
                if (uart_ctrl[1] == 1'b1) begin // RX使能
                    if (rx_over == 1'b1) begin // 接收完成
                        uart_status[1] <= 1'b1; // 置接收溢出
                        uart_rx <= {24'h0, rx_data}; // 写接收数据
                    end // if结束
                end // if结束
            end // if结束
        end // if结束
    end // always结束

    // 读寄存器
    always @ (*) begin // 读控制
        if (rst == 1'b0) begin // 复位
            data_o = 32'h0; // 读数据清零
        end else begin // 非复位
            case (addr_i[7:0]) // 地址译码
                UART_CTRL: begin // 控制寄存器
                    data_o = uart_ctrl; // 读控制
                end // 分支结束
                UART_STATUS: begin // 状态寄存器
                    data_o = uart_status; // 读状态
                end // 分支结束
                UART_BAUD: begin // 波特率寄存器
                    data_o = uart_baud; // 读波特率
                end // 分支结束
                UART_RXDATA: begin // 接收数据寄存器
                    data_o = uart_rx; // 读接收
                end // 分支结束
                default: begin // 默认
                    data_o = 32'h0; // 清零
                end // 分支结束
            endcase // case结束
        end // if结束
    end // always结束

    // *************************** TX发送 ****************************

    always @ (posedge clk) begin // 发送状态机
        if (rst == 1'b0) begin // 复位
            state <= S_IDLE; // 状态空闲
            cycle_cnt <= 16'd0; // 计数清零
            tx_reg <= 1'b0; // TX清零
            bit_cnt <= 4'd0; // 位计数清零
            tx_data_ready <= 1'b0; // 清完成
        end else begin // 非复位
            if (state == S_IDLE) begin // 空闲状态
                tx_reg <= 1'b1; // TX拉高
                tx_data_ready <= 1'b0; // 清完成
                if (tx_data_valid == 1'b1) begin // 有发送
                    state <= S_START; // 转起始位
                    cycle_cnt <= 16'd0; // 清计数
                    bit_cnt <= 4'd0; // 清位计数
                    tx_reg <= 1'b0; // 拉低起始位
                end // if结束
            end else begin // 非空闲
                cycle_cnt <= cycle_cnt + 16'd1; // 计数加1
                if (cycle_cnt == uart_baud[15:0]) begin // 达到分频
                    cycle_cnt <= 16'd0; // 清计数
                    case (state) // 状态分支
                        S_START: begin // 起始位
                            tx_reg <= tx_data[bit_cnt]; // 发送第1位
                            state <= S_SEND_BYTE; // 转发送数据
                            bit_cnt <= bit_cnt + 4'd1; // 位计数加1
                        end // 分支结束
                        S_SEND_BYTE: begin // 发送数据
                            bit_cnt <= bit_cnt + 4'd1; // 位计数加1
                            if (bit_cnt == 4'd8) begin // 数据结束
                                state <= S_STOP; // 转停止位
                                tx_reg <= 1'b1; // 拉高停止位
                            end else begin // 数据未完
                                tx_reg <= tx_data[bit_cnt]; // 发送当前位
                            end // if结束
                        end // 分支结束
                        S_STOP: begin // 停止位
                            tx_reg <= 1'b1; // 保持高
                            state <= S_IDLE; // 回空闲
                            tx_data_ready <= 1'b1; // 发送完成
                        end // 分支结束
                    endcase // case结束
                end // if结束
            end // if结束
        end // if结束
    end // always结束

    // *************************** RX接收 ****************************

    // 下降沿检测(检测起始信号)
    assign rx_negedge = rx_q1 && ~rx_q0; // RX下降沿


    always @ (posedge clk) begin // RX同步
        if (rst == 1'b0) begin // 复位
            rx_q0 <= 1'b0; // 同步寄存器清零
            rx_q1 <= 1'b0; // 同步寄存器清零
        end else begin // 非复位
            rx_q0 <= rx_pin; // 采样RX
            rx_q1 <= rx_q0; // 延迟一拍
        end // if结束
    end // always结束

    // 开始接收数据信号，接收期间一直有效
    always @ (posedge clk) begin // 接收启动
        if (rst == 1'b0) begin // 复位
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

    always @ (posedge clk) begin // 接收分频
        if (rst == 1'b0) begin // 复位
            rx_div_cnt <= 16'h0; // 清分频计数
        end else begin // 非复位
            // 第一个时钟沿只需波特率分频系数的一半
            if (rx_start == 1'b1 && rx_clk_edge_cnt == 4'h0) begin // 起始半周期
                rx_div_cnt <= {1'b0, uart_baud[15:1]}; // 半分频
            end else begin // 正常分频
                rx_div_cnt <= uart_baud[15:0]; // 全分频
            end // if结束
        end // if结束
    end // always结束

    // 对时钟进行计数
    always @ (posedge clk) begin // 接收时钟计数
        if (rst == 1'b0) begin // 复位
            rx_clk_cnt <= 16'h0; // 清计数
        end else if (rx_start == 1'b1) begin // 接收进行中
            // 计数达到分频值
            if (rx_clk_cnt == rx_div_cnt) begin // 达到分频
                rx_clk_cnt <= 16'h0; // 清计数
            end else begin // 未达到
                rx_clk_cnt <= rx_clk_cnt + 1'b1; // 计数加1
            end // if结束
        end else begin // 未接收
            rx_clk_cnt <= 16'h0; // 清计数
        end // if结束
    end // always结束

    // 每当时钟计数达到分频值时产生一个上升沿脉冲
    always @ (posedge clk) begin // 产生采样边沿
        if (rst == 1'b0) begin // 复位
            rx_clk_edge_cnt <= 4'h0; // 边沿计数清零
            rx_clk_edge_level <= 1'b0; // 边沿电平清零
        end else if (rx_start == 1'b1) begin // 接收进行中
            // 计数达到分频值
            if (rx_clk_cnt == rx_div_cnt) begin // 达到分频
                // 时钟沿个数达到最大值
                if (rx_clk_edge_cnt == 4'd9) begin // 达到最大
                    rx_clk_edge_cnt <= 4'h0; // 清边沿计数
                    rx_clk_edge_level <= 1'b0; // 清边沿电平
                end else begin // 未达到最大
                    // 时钟沿个数加1
                    rx_clk_edge_cnt <= rx_clk_edge_cnt + 1'b1; // 边沿计数加1
                    // 产生上升沿脉冲
                    rx_clk_edge_level <= 1'b1; // 置边沿脉冲
                end // if结束
            end else begin // 未达到分频
                rx_clk_edge_level <= 1'b0; // 清边沿电平
            end // if结束
        end else begin // 未接收
            rx_clk_edge_cnt <= 4'h0; // 清边沿计数
            rx_clk_edge_level <= 1'b0; // 清边沿电平
        end // if结束
    end // always结束

    // bit序列
    always @ (posedge clk) begin // 接收数据
        if (rst == 1'b0) begin // 复位
            rx_data <= 8'h0; // 清接收数据
            rx_over <= 1'b0; // 清完成标志
        end else begin // 非复位
            if (rx_start == 1'b1) begin // 接收进行中
                // 上升沿
                if (rx_clk_edge_level == 1'b1) begin // 采样边沿
                    case (rx_clk_edge_cnt) // 位采样
                        // 起始位
                        1: begin // 起始位

                        end // 分支结束
                        // 数据位
                        2, 3, 4, 5, 6, 7, 8, 9: begin // 数据位
                            rx_data <= rx_data | (rx_pin << (rx_clk_edge_cnt - 2)); // 拼接数据
                            // 最后一位接收完成，置位接收完成标志
                            if (rx_clk_edge_cnt == 4'h9) begin // 最后一位
                                rx_over <= 1'b1; // 置完成
                            end // if结束
                        end // 分支结束
                    endcase // case结束
                end // if结束
            end else begin // 未接收
                rx_data <= 8'h0; // 清接收数据
                rx_over <= 1'b0; // 清完成标志
            end // if结束
        end // if结束
    end // always结束

endmodule // 模块结束
