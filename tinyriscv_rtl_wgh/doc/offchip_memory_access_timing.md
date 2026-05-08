# Off-Chip 内存访问完整时序追踪

## 概述
本文档追踪一次 **Load（读取）** 和 **Store（写入）** off-chip ROM/RAM 的完整时序路径，展示关键信号在各阶段的状态。

---

## 场景 1: Load 指令（从 FPGA RAM 读数据）

### 示例指令
```
lw x1, 0x00000100  # 从地址 0x00000100 加载 32-bit 数据到 x1
# 地址高 4 位 = 0x0，说明是 off-chip ROM 区域
```

### 时序表（假设桥接需 8 个周期完成一次事务）

| 周期 | 模块 | 关键信号 | 值/状态 | 说明 |
|------|------|---------|--------|------|
| **T0** | **EX** | `ex_mem_req_o` | 1 | EX 阶段发起读请求 |
| | | `ex_mem_we_o` | `WriteDisable` | **读操作标志** |
| | | `ex_mem_raddr_o` | `0x00000100` | 访问地址 |
| | | `ex_reg_we_o` | 1 | 会写回寄存器（x1） |
| | **tinyriscv** | `ex_mem_addr_is_offchip` | 1 | 地址判断：高位 == 0x0 → off-chip |
| | | `ex_load_from_offchip` | 1 | **满足多周期条件** |
| | **RIB（RIB.v）** | `req[0]` | 1 | M0（EX）的请求被识别 |
| | | `grant` | `GRANT0` | 选中 M0 |
| | | `state` | `ST_IDLE` | RIB 处于空闲，准备启动事务 |
| | | `g_is_offchip` | 1 | 地址是 off-chip |
| | | `start_offchip` | 1 | **启动 off-chip 事务** |
| | | 下个状态 → `ST_ISSUE` | - | - |
| **T1** | **RIB** | `state` | `ST_ISSUE` | RIB 发起阶段 |
| | | `owner` | `GRANT0` | 锁定 M0 为拥有者 |
| | | `s0_req_o` | `RIB_REQ` (1) | **向桥发起请求** |
| | | `s0_addr_o` | `0x00000100` | 传递地址 |
| | | `s0_we_o` | `WriteDisable` | 读操作 |
| | | `s0_is_ram_o` | 0 | 地址 0x0 → ROM |
| | **chip_mem_bridge** | `req_i` | 1 | 接收 RIB 请求 |
| | | `busy_o` | 0 → 1 | **bridge 变忙，开始处理** |
| | | 内部 `state` | `S_IDLE` → `S_TX0` | 准备发送帧 |
| | **tinyriscv** | `mem_load_pending` | 0 → 1 | 标记有 pending 的 load |
| | | `mem_load_seen_busy` | 1 → 0 | 清除标志，准备捕捉 busy |
| | | `mem_load_funct3` | `INST_LW` (3'b010) | 保存 load 类型 |
| | | `mem_load_addr_index` | `0[1:0]` | 保存地址低 2 位 |
| | | `mem_load_rd` | `0x01` | 保存目标寄存器（x1） |
| | **控制** | `rib_hold_flag_full_i` | 0 | 还未置 1（初始） |
| **T2** | **RIB** | `state` | `ST_WAIT` | RIB 等待桥完成 |
| | | `s0_req_o` | `RIB_NREQ` (0) | **脉冲结束，请求信号拉低** |
| | **chip_mem_bridge** | `state` | `S_TX0...S_TX6` | 逐周期发送 8-bit 帧：前导码(0xA5)、控制字、地址、数据 |
| | | `chip_data_o[7:0]` | 依次输出 | 分时发送帧数据到 FPGA |
| | | `busy_o` | 1 | **持续忙信号** |
| | **tinyriscv** | `rib_hold_flag_full_i` | 0 | RIB 还未拉高（取决于 RIB 的 `active_full_hold` 逻辑） |
| | | `s0_busy_d` | 0 | 捕捉上周期的 `hold_flag_full_i` |
| **T3~T7** | **chip_mem_bridge** | - | 继续发送帧字节 | - |
| | | `chip_data_i[7:0]` | (等待 FPGA 应答) | - |
| | **RIB** | `state` | `ST_WAIT` | 等待 `s0_busy_i` 的上升和下降 |
| **T8** | **chip_mem_bridge** | `state` | `S_RX0...S_RX4` | 开始接收 FPGA 的应答帧 |
| | | `chip_data_i[7:0]` | FPGA 返回数据 | 前导码(0x5A)、读数据低字节... |
| | | `busy_o` | 1 → 0 | **bridge 接收完毕后拉低** |
| | **RIB** | `s0_busy_i` | 0（下降沿检测） | `off_seen_busy` 已为 1 |
| | | `off_rdata` ← `s0_data_i` | 32-bit 数据 | **锁存 FPGA 返回的数据** |
| | | `state` | `ST_WAIT` → `ST_RESP` | 进入响应阶段 |
| | | `hold_flag_full_o` | 计算中... | - |
| **T9** | **RIB** | `state` | `ST_RESP` | 响应阶段：向 M0 返回数据 |
| | | `m0_data_o` ← `off_rdata` | 32-bit 读数据 | **EX 可见读取数据** |
| | **tinyriscv** | `mem_load_seen_busy` | 0 → 1 | 捕捉到了 busy 信号变化 |
| | | `s0_busy_d` | 1（= 上周期的 `rib_hold_flag_full_i`） | - |
| | **EX/Pipeline** | `rib_ex_data_i` | 32-bit 数据 | EX 可以看到响应数据 |
| | | （但不立即写回寄存器，因为延迟处理） | - | - |
| **T10** | **RIB** | `state` | `ST_RESP` → `ST_IDLE` | 事务完成，RIB 回到空闲 |
| | | `hold_flag_full_o` | 0 | off-chip 事务结束 |
| | **tinyriscv** | `rib_hold_flag_full_i` | 0（本周期） | - |
| | | `s0_busy_d` ← `rib_hold_flag_full_i` | 0 | 采样 hold flag |
| | | `mem_load_finish` 逻辑： | - | - |
| | | `mem_load_finish = mem_load_pending && mem_load_seen_busy && s0_busy_d && (rib_hold_flag_full_i == HoldDisable)` | **1** | **所有条件满足** |
| | | `regs_we` | `WriteEnable` | 触发写回 |
| | | `regs_waddr` | `0x01` (x1) | 写入 x1 |
| | | `regs_wdata` ← 处理后的数据 | 32-bit | （若 LB/LH/LBU/LHU 需提取/符号扩展） |
| | **regs（寄存器堆）** | `we_i` | 1 | 写使能 |
| | | `regs[1]` | ← 最终数据 | **x1 被更新** ✓ |
| | **tinyriscv 内部** | `mem_load_pending` | 1 → 0 | 清除 pending 标志 |
| | | `mem_load_seen_busy` | 1 → 0 | 清除 busy 标志 |

---

## 场景 2: Store 指令（向 FPGA RAM 写数据）

### 示例指令
```
sw x5, 0x10000200  # 将 x5（值 0x12345678）写入地址 0x10000200
# 地址高 4 位 = 0x1，说明是 off-chip RAM 区域
```

### 时序表（假设桥接同样需 ~8 个周期）

| 周期 | 模块 | 关键信号 | 值/状态 | 说明 |
|------|------|---------|--------|------|
| **T0** | **EX** | `ex_mem_req_o` | 1 | EX 发起**写**请求 |
| | | `ex_mem_we_o` | `WriteEnable` | **写操作标志** ✓ |
| | | `ex_mem_waddr_o` | `0x10000200` | 写地址 |
| | | `ex_mem_wdata_o` | `0x12345678` | 写数据（x5 值） |
| | | `ex_reg_we_o` | 0 | **不会写回寄存器**（sw 不写寄存器） |
| | **tinyriscv** | `ex_mem_addr_is_offchip` | 1 | 高位 0x1 → off-chip |
| | | `ex_load_from_offchip` | **0** | **写操作不满足多周期条件**（`ex_mem_we_o != WriteDisable`） |
| | **RIB** | `grant` | `GRANT0` | M0 被仲裁 |
| | | `g_is_offchip` | 1 | 识别为 off-chip |
| | | `start_offchip` | 1 | **启动 off-chip 写事务** |
| **T1** | **RIB** | `state` | `ST_ISSUE` | 发起阶段 |
| | | `s0_req_o` | 1 | **向桥发起请求** |
| | | `s0_addr_o` | `0x10000200` | 写地址 |
| | | `s0_data_o` | `0x12345678` | 写数据 |
| | | `s0_we_o` | `WriteEnable` | **写使能** |
| | | `s0_is_ram_o` | 1 | 地址 0x1 → **RAM** |
| | **chip_mem_bridge** | `req_i` | 1 | 接收请求 |
| | | `we_i` | `WriteEnable` | 识别为写操作 |
| | | `busy_o` | 0 → 1 | bridge 开始处理 |
| **T2~T8** | **chip_mem_bridge** | `state` | `S_TX0...S_TX6` | 发送写请求帧给 FPGA：<br/>`[0xA5, {we=1,is_ram=1,xx}, addr_byte, data[7:0], data[15:8], data[23:16], data[31:24]]` |
| | | `chip_data_o[7:0]` | 依次输出帧 | - |
| | **FPGA 侧** | `fpga_data_o[7:0]` | 接收帧字节 | FPGA RAM 接收并执行写入 |
| **T9** | **chip_mem_bridge** | `state` | `S_RX0` | 等待 FPGA 写应答 |
| | | `chip_data_i[7:0]` | FPGA 返回 `0x5A` | 写确认帧的前导码 |
| **T10** | **chip_mem_bridge** | `state` | `S_RX1...S_RX4` | 接收应答帧（`0x5A` + 4 个零字节） |
| | | `busy_o` | 1 → 0 | **bridge 完成，拉低 busy** |
| | **RIB** | `state` | `ST_RESP` | 响应阶段 |
| **T11** | **RIB** | `state` | `ST_IDLE` | 事务完成，RIB 回到空闲 |
| | **tinyriscv** | 无特殊处理 | - | **写操作单周期完成**，无需延迟 |
| | | `regs[*]` | 无变化 | store 不修改 CPU 寄存器 |

---

## 关键设计点

### 为什么 Load 有延迟但 Store 没有？

1. **Load（读）**：
   - CPU **需要等待 FPGA 返回的数据** 才能继续执行后续依赖指令。
   - 使用 `mem_load_pending`/`mem_load_seen_busy` 等状态机，监测多周期事务完成后才写回寄存器。
   - 若直接写回，会写入过时或错误的数据。

2. **Store（写）**：
   - CPU **无需等待 FPGA 的确认数据**（write-through 语义）。
   - RIB 和 bridge 直接处理，write 命令发出后 CPU 流水线可继续执行。
   - 若后续有读操作，RIB 的仲裁和握手会自动保证顺序。

### 信号关系

```
tinyriscv.v:
  ex_load_from_offchip = ex_mem_req_o && (ex_mem_we_o == WriteDisable) 
                         && (ex_reg_we_o == WriteEnable) && ex_mem_addr_is_offchip

  mem_load_finish = mem_load_pending && mem_load_seen_busy 
                    && s0_busy_d && (rib_hold_flag_full_i == HoldDisable)

  regs_we = mem_load_finish ? WriteEnable :
            (ex_load_from_offchip ? WriteDisable : ex_reg_we_o)
```

- `ex_load_from_offchip`：只有 **load（读）** off-chip 时为 1。
- `mem_load_finish`：监测桥从忙转闲，触发最终写回。
- Store 不进入该延迟路径，直接由 RIB 仲裁处理。

### 多主机仲裁

RIB 优先级（见 rib.v L114-119）：
```
M3 (UART Debug) > M0 (Data) > M2 (JTAG) > M1 (IF)
```

若 UART Debug（uart_debug_pin）同时发起写内存，会抢占 M0 的 store 操作。

---

## 地址映射

| 地址高 4 位 | 目的地 | 读写 |
|-------------|-------|------|
| `0x0` | off-chip ROM | RO（只读） |
| `0x1` | off-chip RAM | RW（可读写） |
| `0x3` | UART（内部） | RW |
| `0x6` | PWM（内部） | RW |
| `0x7` | I2C（内部） | RW |

---

## 完整 off-chip 访问数据流图

```
CPU EX Stage (T0)
  │
  ├─ Load?  ex_mem_we_o=0, ex_reg_we_o=1  ───→ tinyriscv: mem_load_pending ← 1
  │                                              (延迟写回路径)
  │
  └─ Store? ex_mem_we_o=1  ────────────────────→ (直接通过 RIB)
  
    ↓ (both paths)
  
  RIB 仲裁 (T0-T1)
    ├─ 仲裁 4 个 Master
    ├─ 检查 off-chip 地址
    └─ 启动事务: state ← ST_ISSUE
  
    ↓
  
  chip_mem_bridge (T1-T10)
    ├─ 接收请求，转换为 8-bit 帧
    ├─ 发送帧到 FPGA: fpga_data_o[7:0]
    ├─ 接收 FPGA 应答: fpga_data_i[7:0]
    └─ 返回数据给 RIB: s0_data_i
  
    ↓
  
  RIB 响应 (T9-T10)
    └─ state ← ST_RESP
       m0_data_o ← off_rdata (for Load)
       state ← ST_IDLE
  
    ↓ (only for Load)
  
  tinyriscv 延迟写回 (T10+)
    ├─ 监测: rib_hold_flag_full_i: 1 → 0
    ├─ 计算: mem_load_finish ← 1
    └─ 触发: regs_we ← 1, regs[rd] ← 数据
```

---

## 总结

| 操作 | 周期数 | 关键延迟点 | 写回时机 |
|------|--------|-----------|---------|
| **Load off-chip** | ~11-12 | bridge 协议转换 | T10 `mem_load_finish` 时触发 |
| **Store off-chip** | ~11-12 | bridge 协议转换 | 无（store 不需写回） |
| **Load/Store on-chip（UART/PWM）** | 1 | MMIO 组合逻辑 | 同周期 |

**答案**：tinyriscv **完全支持写入 FPGA RAM**。Store 指令通过相同的 RIB+bridge 路径，只是在 CPU 侧无需等待（异步写入）。
