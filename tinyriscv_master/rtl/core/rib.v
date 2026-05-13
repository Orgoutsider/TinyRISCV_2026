/*
 * Reduced RIB for the project SoC.
 *
 * The original tinyriscV RIB assumes single-cycle slaves.  In this project the
 * ROM/RAM window is behind an 8-bit multi-cycle chip/FPGA bridge, so slave 0 is
 * handled as an explicit transaction:
 *   IDLE  : select and latch one off-chip request
 *   ISSUE : pulse s0_req_o for exactly one cycle
 *   WAIT  : wait for bridge busy to rise and then fall
 *   RESP  : present the returned data to the latched master for one cycle
 *
 * Non-off-chip peripherals remain single-cycle combinational MMIO.
 */
`include "defines.v" // 全局宏定义

module rib( // RIB仲裁与桥接模块
    input  wire       clk, // 时钟信号
    input  wire       rst, // 复位信号

    input  wire[`MemAddrBus] m0_addr_i, // 主机0地址
    input  wire[`MemBus]     m0_data_i, // 主机0写数据
    output reg [`MemBus]     m0_data_o, // 主机0读数据
    input  wire              m0_req_i, // 主机0请求
    input  wire              m0_we_i, // 主机0写使能

    input  wire[`MemAddrBus] m1_addr_i, // 主机1地址
    input  wire[`MemBus]     m1_data_i, // 主机1写数据
    output reg [`MemBus]     m1_data_o, // 主机1读数据
    input  wire              m1_req_i, // 主机1请求
    input  wire              m1_we_i, // 主机1写使能

    input  wire[`MemAddrBus] m2_addr_i, // 主机2地址
    input  wire[`MemBus]     m2_data_i, // 主机2写数据
    output reg [`MemBus]     m2_data_o, // 主机2读数据
    input  wire              m2_req_i, // 主机2请求
    input  wire              m2_we_i, // 主机2写使能

    input  wire[`MemAddrBus] m3_addr_i, // 主机3地址
    input  wire[`MemBus]     m3_data_i, // 主机3写数据
    output reg [`MemBus]     m3_data_o, // 主机3读数据
    input  wire              m3_req_i, // 主机3请求
    input  wire              m3_we_i, // 主机3写使能
    output reg               m3_ack_o, // 主机3回应

    output reg [`MemAddrBus] s0_addr_o, // 从设备0地址
    output reg [`MemBus]     s0_data_o, // 从设备0写数据
    input  wire[`MemBus]     s0_data_i, // 从设备0读数据
    output reg               s0_we_o, // 从设备0写使能
    output reg               s0_req_o, // 从设备0请求
    output reg               s0_is_ram_o, // 从设备0是否RAM区
    input  wire              s0_busy_i, // 从设备0忙信号

    output reg [`MemAddrBus] s1_addr_o, // 从设备1地址
    output reg [`MemBus]     s1_data_o, // 从设备1写数据
    input  wire[`MemBus]     s1_data_i, // 从设备1读数据
    output reg               s1_we_o, // 从设备1写使能

    output reg [`MemAddrBus] s2_addr_o, // 从设备2地址
    output reg [`MemBus]     s2_data_o, // 从设备2写数据
    input  wire[`MemBus]     s2_data_i, // 从设备2读数据
    output reg               s2_we_o, // 从设备2写使能

    output reg [`MemAddrBus] s3_addr_o, // 从设备3地址
    output reg [`MemBus]     s3_data_o, // 从设备3写数据
    input  wire[`MemBus]     s3_data_i, // 从设备3读数据
    output reg               s3_we_o, // 从设备3写使能

    output reg               hold_flag_o, // 总线暂停标志
    output reg               hold_flag_full_o // 全暂停标志
); // 端口列表结束

    localparam [1:0] GRANT0 = 2'd0; // 主机0优先级编码
    localparam [1:0] GRANT1 = 2'd1; // 主机1优先级编码
    localparam [1:0] GRANT2 = 2'd2; // 主机2优先级编码
    localparam [1:0] GRANT3 = 2'd3; // 主机3优先级编码

    localparam [1:0] ST_IDLE  = 2'd0; // 空闲状态
    localparam [1:0] ST_ISSUE = 2'd1; // 发起请求状态
    localparam [1:0] ST_WAIT  = 2'd2; // 等待完成状态
    localparam [1:0] ST_RESP  = 2'd3; // 响应返回状态

    reg[1:0] state; // 当前状态
    reg[1:0] owner; // 当前拥有者
    reg[`MemAddrBus] off_addr; // off-chip锁存地址
    reg[`MemBus]     off_wdata; // off-chip锁存写数据
    reg              off_we; // off-chip锁存写使能
    reg              off_is_ram; // off-chip是否RAM
    reg[`MemBus]     off_rdata; // off-chip返回读数据
    reg              off_seen_busy; // 是否见过busy拉高
    reg              defer_fetch; // 延迟IF取指标志

    reg[1:0] grant; // 当前仲裁结果
    reg[`MemAddrBus] g_addr; // 仲裁后的地址
    reg[`MemBus]     g_wdata; // 仲裁后的写数据
    reg              g_we; // 仲裁后的写使能
    reg              g_req; // 仲裁后的请求

    wire[3:0] req = {m3_req_i, m2_req_i, m1_req_i, m0_req_i}; // 请求向量
    wire g_is_offchip = (g_addr[31:28] == 4'h0) || (g_addr[31:28] == 4'h1); // off-chip地址判断
    wire start_offchip = (state == ST_IDLE) && (g_req == `RIB_REQ) &&
                         g_is_offchip && !(defer_fetch && (grant == GRANT1)); // 是否启动off-chip
    wire active_offchip = (state != ST_IDLE) || start_offchip; // off-chip事务活动标志
    wire active_full_hold = active_offchip &&
                            ((state == ST_IDLE) ? (grant != GRANT1) : (owner != GRANT1)); // 全暂停条件
    wire offchip_wait_hold = start_offchip ||
                             (state == ST_ISSUE) ||
                             (state == ST_WAIT) ||
                             ((state == ST_RESP) && (owner != GRANT1)); // off-chip等待暂停

    always @(*) begin // 仲裁优先级选择
        if (req[3]) begin // 主机3优先
            grant = GRANT3; // 选择主机3
        end else if (req[0]) begin // 主机0其次
            grant = GRANT0; // 选择主机0
        end else if (req[2]) begin // 主机2再次
            grant = GRANT2; // 选择主机2
        end else begin // 默认主机1
            grant = GRANT1; // 选择主机1
        end
    end

    always @(*) begin // 根据grant选通信号
        case (grant) // 按仲裁选择
            GRANT0: begin // 主机0
                g_addr = m0_addr_i; // 选地址
                g_wdata = m0_data_i; // 选写数据
                g_we = m0_we_i; // 选写使能
                g_req = m0_req_i; // 选请求
            end
            GRANT1: begin // 主机1
                g_addr = m1_addr_i; // 选地址
                g_wdata = m1_data_i; // 选写数据
                g_we = m1_we_i; // 选写使能
                g_req = m1_req_i; // 选请求
            end
            GRANT2: begin // 主机2
                g_addr = m2_addr_i; // 选地址
                g_wdata = m2_data_i; // 选写数据
                g_we = m2_we_i; // 选写使能
                g_req = m2_req_i; // 选请求
            end
            default: begin // 主机3
                g_addr = m3_addr_i; // 选地址
                g_wdata = m3_data_i; // 选写数据
                g_we = m3_we_i; // 选写使能
                g_req = m3_req_i; // 选请求
            end
        endcase // case结束
    end

    always @(posedge clk) begin // off-chip状态机
        if (rst == `RstEnable) begin // 复位
            state <= ST_IDLE; // 状态清零
            owner <= GRANT1; // 默认拥有者
            off_addr <= `ZeroWord; // 清地址
            off_wdata <= `ZeroWord; // 清数据
            off_we <= `WriteDisable; // 清写使能
            off_is_ram <= 1'b0; // 清RAM标志
            off_rdata <= `ZeroWord; // 清读数据
            off_seen_busy <= 1'b0; // 清busy标志
            defer_fetch <= 1'b0; // 清延迟取指
        end else begin // 正常时钟
            case (state) // 状态机
                ST_IDLE: begin // 空闲
                    off_seen_busy <= 1'b0; // 清busy跟踪
                    if (defer_fetch) begin // 有延迟取指
                        defer_fetch <= 1'b0; // 清除延迟
                    end
                    if (start_offchip) begin // 启动off-chip
                        owner <= grant; // 锁存拥有者
                        off_addr <= {4'h0, g_addr[27:0]}; // 锁存地址
                        off_wdata <= g_wdata; // 锁存写数据
                        off_we <= g_we; // 锁存写使能
                        off_is_ram <= (g_addr[31:28] == 4'h1); // 选择RAM/ROM
                        state <= ST_ISSUE; // 进入发起态
                    end
                end

                ST_ISSUE: begin // 发起请求
                    off_seen_busy <= 1'b0; // 清busy跟踪
                    state <= ST_WAIT; // 转等待态
                end

                ST_WAIT: begin // 等待返回
                    if (s0_busy_i == 1'b1) begin // bridge忙
                        off_seen_busy <= 1'b1; // 标记见过busy
                    end else if (off_seen_busy == 1'b1) begin // busy已结束
                        off_rdata <= s0_data_i; // 锁存读数据
                        state <= ST_RESP; // 转响应态
                    end
                end

                ST_RESP: begin // 响应返回
                    state <= ST_IDLE; // 回空闲态
                    off_seen_busy <= 1'b0; // 清busy跟踪
                    defer_fetch <= (owner == GRANT1); // 若为取指则延迟一次
                end

                default: begin // 默认
                    state <= ST_IDLE; // 回空闲
                    off_seen_busy <= 1'b0; // 清busy
                end
            endcase // case结束
        end // if结束
    end // always结束

    always @(*) begin // 组合输出
        m0_data_o = `ZeroWord; // 默认主机0读数据
        m1_data_o = `INST_NOP; // 默认主机1读数据
        m2_data_o = `ZeroWord; // 默认主机2读数据
        m3_data_o = `ZeroWord; // 默认主机3读数据

        m3_ack_o = 0; // 默认主机3回应

        s0_addr_o = off_addr; // off-chip地址输出
        s0_data_o = off_wdata; // off-chip写数据输出
        s0_we_o = off_we; // off-chip写使能输出
        s0_req_o = (state == ST_ISSUE) ? `RIB_REQ : `RIB_NREQ; // off-chip请求脉冲
        s0_is_ram_o = off_is_ram; // off-chip RAM标志

        s1_addr_o = `ZeroWord; // 默认UART地址
        s1_data_o = `ZeroWord; // 默认UART写数据
        s1_we_o = `WriteDisable; // 默认UART写禁止

        s2_addr_o = `ZeroWord; // 默认PWM地址
        s2_data_o = `ZeroWord; // 默认PWM写数据
        s2_we_o = `WriteDisable; // 默认PWM写禁止

        s3_addr_o = `ZeroWord; // 默认I2C地址
        s3_data_o = `ZeroWord; // 默认I2C写数据
        s3_we_o = `WriteDisable; // 默认I2C写禁止

        if (state == ST_IDLE && g_req == `RIB_REQ && !g_is_offchip) begin // on-chip访问
            case (g_addr[31:28]) // 外设片选
                4'h3: begin // UART
                    s1_we_o = g_we; // UART写使能
                    s1_addr_o = {4'h0, g_addr[27:0]}; // UART地址
                    s1_data_o = g_wdata; // UART写数据
                    case (grant) // 读返回路由
                        GRANT0: m0_data_o = s1_data_i; // 返回给主机0
                        GRANT1: m1_data_o = s1_data_i; // 返回给主机1
                        GRANT2: m2_data_o = s1_data_i; // 返回给主机2
                        // default: m3_data_o = s1_data_i; // 返回给主机3
                        default: begin
                            m3_data_o = s1_data_i;
                            m3_ack_o = 1'b1;
                        end
                    endcase
                end
                4'h6: begin // PWM
                    s2_we_o = g_we; // PWM写使能
                    s2_addr_o = {4'h0, g_addr[27:0]}; // PWM地址
                    s2_data_o = g_wdata; // PWM写数据
                    case (grant) // 读返回路由
                        GRANT0: m0_data_o = s2_data_i; // 返回给主机0
                        GRANT1: m1_data_o = s2_data_i; // 返回给主机1
                        GRANT2: m2_data_o = s2_data_i; // 返回给主机2
                        // default: m3_data_o = s2_data_i; // 返回给主机3
                        default: begin
                            m3_data_o = s2_data_i;
                            m3_ack_o = 1'b1;
                        end
                    endcase
                end
                4'h7: begin // I2C
                    s3_we_o = g_we; // I2C写使能
                    s3_addr_o = {4'h0, g_addr[27:0]}; // I2C地址
                    s3_data_o = g_wdata; // I2C写数据
                    case (grant) // 读返回路由
                        GRANT0: m0_data_o = s3_data_i; // 返回给主机0
                        GRANT1: m1_data_o = s3_data_i; // 返回给主机1
                        GRANT2: m2_data_o = s3_data_i; // 返回给主机2
                        // default: m3_data_o = s3_data_i; // 返回给主机3
                        default: begin
                            m3_data_o = s3_data_i;
                            m3_ack_o = 1'b1;
                        end
                    endcase
                end
                // default: begin end // 其他地址忽略
                default: begin
                    if (grant == GRANT3) begin
                        m3_ack_o = 1'b1;  // 可选：避免非法地址让 uart_debug 死等
                    end
                end                
            endcase
        end

        if (state == ST_RESP) begin // off-chip响应阶段
            m3_ack_o = 1'b0;
            case (owner) // 返回给拥有者
                GRANT0: m0_data_o = off_rdata; // 主机0返回
                GRANT1: m1_data_o = off_rdata; // 主机1返回
                GRANT2: m2_data_o = off_rdata; // 主机2返回
                // default: m3_data_o = off_rdata; // 主机3返回
                default: begin
                    m3_data_o = off_rdata;
                    m3_ack_o = 1'b1;
                end
            endcase
        end

        hold_flag_full_o = active_full_hold ? `HoldEnable : `HoldDisable; // 全暂停输出
        hold_flag_o = (offchip_wait_hold || defer_fetch || req[3] || req[0] || req[2]) ?
                      `HoldEnable : `HoldDisable; // 轻暂停输出
    end // always结束

endmodule // 模块结束
