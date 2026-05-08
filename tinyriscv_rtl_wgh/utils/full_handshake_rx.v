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

// 数据接收端模块
// 跨时钟域传输，全(四次)握手协议
// req = 1
// ack_o = 1
// req = 0
// ack_o = 0
module full_handshake_rx #( // 接收端模块声明
    parameter DW = 32)(             // RX要接收数据的位宽

    input wire clk,                 // RX端时钟信号
    input wire rst_n,               // RX端复位信号

    // from tx
    input wire req_i,               // TX端请求信号
    input wire[DW-1:0] req_data_i,  // TX端输入数据

    // to tx
    output wire ack_o,              // RX端应答TX端信号

    // to rx
    output wire[DW-1:0] recv_data_o,// RX端接收到的数据
    output wire recv_rdy_o          // RX端是否接收到数据信号

    ); // 端口列表结束

    localparam STATE_IDLE     = 2'b01; // 空闲状态
    localparam STATE_DEASSERT = 2'b10; // 撤销应答状态

    reg[1:0] state; // 当前状态
    reg[1:0] state_next; // 下一状态

    always @ (posedge clk or negedge rst_n) begin // 状态寄存器
        if (!rst_n) begin // 复位有效
            state <= STATE_IDLE; // 进入空闲
        end else begin // 正常时钟
            state <= state_next; // 更新状态
        end // if结束
    end // always结束

    always @ (*) begin // 状态转移组合逻辑
        case (state) // 状态选择
            // 等待TX请求信号req=1
            STATE_IDLE: begin // 空闲态
                if (req == 1'b1) begin // 收到请求
                    state_next = STATE_DEASSERT; // 进入撤销态
                end else begin // 无请求
                    state_next = STATE_IDLE; // 保持空闲
                end // if结束
            end
            // 等待req=0
            STATE_DEASSERT: begin // 撤销态
                if (req) begin // 请求仍在
                    state_next = STATE_DEASSERT; // 继续等待
                end else begin // 请求撤销
                    state_next = STATE_IDLE; // 回到空闲
                end // if结束
            end
            default: begin // 默认分支
                state_next = STATE_IDLE; // 回到空闲
            end
        endcase // case结束
    end // always结束

    reg req_d; // 请求打一拍
    reg req; // 同步后请求

    // 将请求信号打两拍进行同步
    always @ (posedge clk or negedge rst_n) begin // 请求同步
        if (!rst_n) begin // 复位有效
            req_d <= 1'b0; // 清零
            req <= 1'b0; // 清零
        end else begin // 正常时钟
            req_d <= req_i; // 第一级同步
            req <= req_d; // 第二级同步
        end // if结束
    end // always结束

    reg[DW-1:0] recv_data; // 接收数据寄存器
    reg recv_rdy; // 接收就绪寄存器
    reg ack; // 应答寄存器

    always @ (posedge clk or negedge rst_n) begin // 输出寄存器控制
        if (!rst_n) begin // 复位有效
            ack <= 1'b0; // 清应答
            recv_rdy <= 1'b0; // 清就绪
            recv_data <= {(DW){1'b0}}; // 清数据
        end else begin // 正常时钟
            case (state) // 状态处理
                STATE_IDLE: begin // 空闲态
                    if (req == 1'b1) begin // 收到请求
                        ack <= 1'b1; // 置应答
                        recv_rdy <= 1'b1;           // 这个信号只会持续一个时钟
                        recv_data <= req_data_i;    // 这个信号只会持续一个时钟
                    end // if结束
                end
                STATE_DEASSERT: begin // 撤销态
                    recv_rdy <= 1'b0; // 清就绪
                    recv_data <= {(DW){1'b0}}; // 清数据
                    // req撤销后ack也撤销
                    if (req == 1'b0) begin // 请求撤销
                        ack <= 1'b0; // 撤销应答
                    end // if结束
                end
            endcase // case结束
        end // if结束
    end // always结束

    assign ack_o = ack; // 输出应答
    assign recv_rdy_o = recv_rdy; // 输出就绪
    assign recv_data_o = recv_data; // 输出数据

endmodule // 模块结束
