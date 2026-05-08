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

// 数据发送端模块
// 跨时钟域传输，全(四次)握手协议
// req_o = 1
// ack = 1
// req_o = 0
// ack = 0
module full_handshake_tx #( // 发送端模块声明
    parameter DW = 32)(             // TX要发送数据的位宽

    input wire clk,                 // TX端时钟信号
    input wire rst_n,               // TX端复位信号

    // from rx
    input wire ack_i,               // RX端应答信号

    // from tx
    input wire req_i,               // TX端请求信号，只需持续一个时钟
    input wire[DW-1:0] req_data_i,  // TX端要发送的数据，只需持续一个时钟

    // to tx
    output wire idle_o,             // TX端是否空闲信号，空闲才能发数据

    // to rx
    output wire req_o,              // TX端请求信号
    output wire[DW-1:0] req_data_o  // TX端要发送的数据

    ); // 端口列表结束

    localparam STATE_IDLE     = 3'b001; // 空闲状态
    localparam STATE_ASSERT   = 3'b010; // 请求保持状态
    localparam STATE_DEASSERT = 3'b100; // 撤销请求状态

    reg[2:0] state; // 当前状态
    reg[2:0] state_next; // 下一状态

    always @ (posedge clk or negedge rst_n) begin // 状态寄存器
        if (!rst_n) begin // 复位有效
            state <= STATE_IDLE; // 进入空闲
        end else begin // 正常时钟
            state <= state_next; // 更新状态
        end // if结束
    end // always结束

    always @ (*) begin // 状态转移组合逻辑
        case (state) // 状态选择
            STATE_IDLE: begin // 空闲态
                if (req_i == 1'b1) begin // 有请求
                    state_next = STATE_ASSERT; // 进入请求态
                end else begin // 无请求
                    state_next = STATE_IDLE; // 保持空闲
                end // if结束
            end
            // 等待ack=1
            STATE_ASSERT: begin // 请求保持态
                if (!ack) begin // 未收到应答
                    state_next = STATE_ASSERT; // 继续等待
                end else begin // 收到应答
                    state_next = STATE_DEASSERT; // 进入撤销态
                end // if结束
            end
            // 等待ack=0
            STATE_DEASSERT: begin // 撤销态
                if (!ack) begin // 应答撤销
                    state_next = STATE_IDLE; // 回到空闲
                end else begin // 应答仍在
                    state_next = STATE_DEASSERT; // 继续等待
                end // if结束
            end
            default: begin // 默认分支
                state_next = STATE_IDLE; // 回到空闲
            end
        endcase // case结束
    end // always结束

    reg ack_d; // 应答打一拍
    reg ack; // 同步后应答

    // 将应答信号打两拍进行同步
    always @ (posedge clk or negedge rst_n) begin // 应答同步
        if (!rst_n) begin // 复位有效
            ack_d <= 1'b0; // 清零
            ack <= 1'b0; // 清零
        end else begin // 正常时钟
            ack_d <= ack_i; // 第一级同步
            ack <= ack_d; // 第二级同步
        end // if结束
    end // always结束

    reg req; // 输出请求寄存器
    reg[DW-1:0] req_data; // 输出数据寄存器
    reg idle; // 空闲标志寄存器

    always @ (posedge clk or negedge rst_n) begin // 输出寄存器控制
        if (!rst_n) begin // 复位有效
            idle <= 1'b1; // 标记空闲
            req <= 1'b0; // 清请求
            req_data <= {(DW){1'b0}}; // 清数据
        end else begin // 正常时钟
            case (state) // 状态处理
                // 锁存TX请求数据，在收到ack之前一直保持有效
                STATE_IDLE: begin // 空闲态
                    if (req_i == 1'b1) begin // 有新请求
                        idle <= 1'b0; // 退出空闲
                        req <= req_i; // 置请求
                        req_data <= req_data_i; // 锁存数据
                    end else begin // 无请求
                        idle <= 1'b1; // 保持空闲
                        req <= 1'b0; // 保持无请求
                    end // if结束
                end
                // 收到RX的ack之后撤销TX请求
                STATE_ASSERT: begin // 请求保持态
                    if (ack == 1'b1) begin // 收到应答
                        req <= 1'b0; // 撤销请求
                        req_data <= {(DW){1'b0}}; // 清空数据
                    end // if结束
                end
                STATE_DEASSERT: begin // 撤销态
                    if (!ack) begin // 应答撤销
                        idle <= 1'b1; // 回到空闲
                    end // if结束
                end
            endcase // case结束
        end // if结束
    end // always结束

    assign idle_o = idle; // 输出空闲标志
    assign req_o = req; // 输出请求信号
    assign req_data_o = req_data; // 输出数据

endmodule // 模块结束
