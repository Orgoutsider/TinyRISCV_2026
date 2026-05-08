# tinyriscv_project_mod

基于 tinyriscV 的数字集成电路设计与计算机体系结构课程设计工程。工程目标是把原始 tinyriscV 裁剪成适合课程 FPGA 验证、综合、后端实现和后续流片验证的 SoC 原型，并加入课程要求的片外存储桥、PWM、I2C/LM75、UART 下载调试、三条自定义指令和多芯片共 IO Ring 选择信号。

本 README 按开源工程交付方式编写：从顶层接口、地址空间、指令扩展、模块职责、逐文件行级索引、仿真命令、验证矩阵、综合/流片检查项到已知风险逐项说明。若源码后续继续修改，请同步维护本文档中的行号索引。

## 1. 工程状态

当前 RTL 已完成并通过 Icarus Verilog 回归仿真的内容：

| 功能 | 状态 | 主要源码 |
| --- | --- | --- |
| 基于 tinyriscV 的 RV32IM 简化处理器核 | 已保留 | `core/tinyriscv.v`, `core/id.v`, `core/ex.v`, `core/regs.v`, `core/csr_reg.v`, `core/clint.v`, `core/div.v` |
| 删除片上 ROM/RAM/Timer/GPIO/SPI 实例 | 已完成 | `soc/tinyriscv_soc_top.v` |
| 片外 ROM/RAM 8-bit 芯片到 FPGA 桥 | 已完成并修复多周期总线问题 | `core/rib.v`, `perips/chip_mem_bridge.v`, `fpga/fpga_mem_bridge.v`, `core/tinyriscv.v` |
| PWM 四通道外设 | 已完成 | `perips/pwm.v` |
| I2C/LM75 读温度外设 | 已完成 | `perips/i2c_lm75.v` |
| UART MMIO 与自定义指令共享发送 | 已完成 | `perips/uart_shared.v` |
| UART debug 35 字节下载辅助 | 已完成基础 RTL | `perips/uart_debug.v` |
| JTAG 调试模块 | 已保留并修正连接问题 | `debug/jtag_top.v`, `debug/jtag_dm.v`, `debug/jtag_driver.v` |
| 自定义指令 `sID` / `rT` / `if` | 已完成 RTL 与单元验证 | `core/defines.v`, `core/id.v`, `core/ex.v`, `core/custom_unit.v`, `core/tinyriscv.v` |
| `chip_sel_i` 多芯片选择输入 | 已完成单芯片顶层选择逻辑 | `soc/tinyriscv_soc_top.v`, `sim/tb_chip_sel.v` |

课程指导书还要求的后续物理交付项：

| 交付项 | 当前仓库状态 | 后续动作 |
| --- | --- | --- |
| FPGA 板级验证 | RTL 与 FPGA 侧 bridge 已具备 | 需要绑定具体 FPGA 管脚、下载 bitstream、用真实 UART/I2C/PWM 波形验证 |
| 综合与 STA | 未在本机完成，未发现 Yosys/Verilator | 使用课程指定综合工具跑 lint、综合、时序、面积、功耗 |
| 后端 DRC/LVS clean GDS | 仓库未包含版图脚本和工艺库 | 需要接入工艺 PDK、APR flow、IO Ring、pad frame 和签核脚本 |
| 回片芯片测试 | 未发生 | 需要回片后编写ATE/板级测试程序 |
| 多芯片共享 IO Ring | 当前只有单芯片 `chip_sel_i` 选择 | 需要 pad 顶层加入输出 mux/OE 互斥，避免多个 die 同时驱动同一 pad |

## 2. 目录结构

```text
.
|-- core/                  # CPU core、译码、执行、CSR、中断、总线、除法、自定义指令
|-- debug/                 # JTAG DTM/DM 调试链路
|-- doc/                   # 修改说明、验证报告、变更日志
|-- fpga/                  # FPGA 侧片外 ROM/RAM bridge 和 FPGA filelist
|-- perips/                # UART、UART debug、PWM、I2C、芯片侧存储 bridge
|-- sim/                   # Icarus Verilog 仿真 testbench
|-- soc/                   # SoC 顶层
|-- utils/                 # 握手同步、DFF、buffer 等通用模块
|-- filelist_project.f     # 顶层仿真/综合 filelist
|-- readme.me              # 实验指导书要求到源码证据的逐项对应说明
|-- README.md              # 本开源工程说明
|-- LICENSE                # Apache-2.0 License
`-- NOTICE                 # 原始工程归属与本工程修改说明
```

## 3. 工具要求

推荐工具：

| 工具 | 用途 |
| --- | --- |
| Icarus Verilog `iverilog` / `vvp` | 当前已验证的 RTL 仿真 |
| GTKWave | 查看 testbench 生成的波形，当前 testbench 以 `$display` 断言为主 |
| Verilator | 推荐新增 lint 和更强的仿真检查，本机当前未安装 |
| 综合工具 | 课程或流片平台指定工具，如 Design Compiler、Genus、Yosys 等 |
| STA/APR/DRC/LVS 工具 | 后端签核、版图生成和检查 |

当前回归测试使用 Icarus Verilog，命令见第 12 节。

## 4. 顶层模块接口

顶层模块是 `soc/tinyriscv_soc_top.v` 的 `tinyriscv_soc_top`，端口位于 `soc/tinyriscv_soc_top.v:13-38`。

| 端口 | 方向 | 位宽 | 功能 |
| --- | --- | --- | --- |
| `clk` | input | 1 | SoC 主时钟 |
| `rst` | input | 1 | 低有效复位，与原 tinyriscV 定义一致 |
| `chip_sel_i` | input | 1 | 多芯片共享 IO Ring 时的芯片选择。为 0 时本芯片保持复位 |
| `over` | output reg | 1 | 仿真/测试结束指示，来自 `x26` 的反相 |
| `succ` | output reg | 1 | 仿真/测试成功指示，来自 `x27` 的反相 |
| `halted_ind` | output wire | 1 | JTAG halt 状态指示 |
| `uart_debug_pin` | input | 1 | UART 下载调试使能输入 |
| `uart_tx_pin` | output wire | 1 | UART TX |
| `uart_rx_pin` | input | 1 | UART RX |
| `jtag_TCK` | input | 1 | JTAG TCK |
| `jtag_TMS` | input | 1 | JTAG TMS |
| `jtag_TDI` | input | 1 | JTAG TDI |
| `jtag_TDO` | output wire | 1 | JTAG TDO |
| `fpga_data_i` | input | 8 | FPGA 侧返回给芯片的片外存储桥数据 |
| `fpga_data_o` | output | 8 | 芯片发送给 FPGA 的片外存储桥数据 |
| `pwm_o` | output | 4 | 四路 PWM 输出 |
| `i2c_scl` | output | 1 | I2C SCL |
| `i2c_sda` | inout | 1 | I2C SDA，开漏风格，外部需要上拉 |

`chip_sel_i` 的当前实现：

- `soc/tinyriscv_soc_top.v:41`：`core_rst = rst & chip_sel_i`。因为 `rst` 低有效，`chip_sel_i=0` 会强制内部复位。
- `soc/tinyriscv_soc_top.v:127-160`：CPU 使用 `core_rst`。
- `soc/tinyriscv_soc_top.v:163-215`：RIB 使用 `core_rst`。
- `soc/tinyriscv_soc_top.v:218-230`：片外桥使用 `core_rst`。
- `soc/tinyriscv_soc_top.v:232-243`：UART 使用 `core_rst`。
- `soc/tinyriscv_soc_top.v:246-253`：PWM 使用 `core_rst`。
- `soc/tinyriscv_soc_top.v:256-268`：I2C 使用 `core_rst`。
- `soc/tinyriscv_soc_top.v:271-279`：UART debug 使用 `core_rst`，且 `debug_en_i` 额外与 `chip_sel_i` 相与。
- `soc/tinyriscv_soc_top.v:282-303`：JTAG 复位使用 `core_rst`。

注意：当前 RTL 完成的是“单芯片内部受 `chip_sel_i` 选择”的逻辑。真正流片时若多颗芯片共用一个 IO Ring，必须在 pad 顶层增加输出多路选择和输出使能互斥，不能只靠复位。

## 5. 全局定义与地址空间

全局宏定义在 `core/defines.v`。

| 行号 | 内容 |
| --- | --- |
| `core/defines.v:12-15` | 复位地址与低有效复位约定 |
| `core/defines.v:16-41` | 零值、写使能、读使能、跳转、除法、hold、RIB、中断等全局常量 |
| `core/defines.v:43-47` | 中断总线和 timer 中断入口宏 |
| `core/defines.v:49-53` | 流水线 hold 级别：`Hold_None`、`Hold_Pc`、`Hold_If`、`Hold_Id` |
| `core/defines.v:55-67` | 修改后的 SoC 地址空间 |
| `core/defines.v:69-82` | ROM/RAM 深度、寄存器位宽、总线位宽 |
| `core/defines.v:84-161` | RV32I/M、CSR、自定义指令 opcode/funct3 宏 |
| `core/defines.v:163-172` | CSR 地址宏 |

地址空间：

| 地址范围 | 设备 | 说明 |
| --- | --- | --- |
| `0x0000_0000` - `0x0fff_ffff` | 片外 ROM 窗口 | FPGA bridge 中实际为 `256 x 32-bit` ROM |
| `0x1000_0000` - `0x1fff_ffff` | 片外 RAM 窗口 | FPGA bridge 中实际为 `16 x 32-bit` RAM |
| `0x3000_0000` - `0x3fff_ffff` | UART | MMIO UART，与自定义指令 TX 共享发送器 |
| `0x6000_0000` - `0x6fff_ffff` | PWM | 四通道 PWM |
| `0x7000_0000` - `0x7fff_ffff` | I2C/LM75 | I2C 温度读取 |

RIB 地址译码使用高 4 bit：

- `4'h0`：片外 ROM。
- `4'h1`：片外 RAM。
- `4'h3`：UART。
- `4'h6`：PWM。
- `4'h7`：I2C。

## 6. 自定义指令

自定义指令 opcode 定义在 `core/defines.v:157-161`：

| 指令 | opcode | funct3 | 功能 |
| --- | --- | --- | --- |
| `sID` | `7'b0101111` | `3'b000` | 通过 UART 依次发送学号 ASCII 字节，不写 GPR |
| `rT` | `7'b0101111` | `3'b001` | 触发 I2C 读 LM75 温度，完成后写回 `x[rd]` |
| `if` / `ifire` | `7'b0101111` | `3'b010` | 当 `imm==0 && signed(x[rs1])>=signed(x31)` 时发送 `x[rs1][7:0]` 并写 0；其他路径按普通写回逻辑处理 |

自定义指令数据路径：

1. `core/id.v:293-328` 识别 `INST_CUSTOM`。
2. `core/id.v:295-302` 译码 `sID`，不写 GPR，设置下一条指令地址用于完成后继续执行。
3. `core/id.v:303-310` 译码 `rT`，保留 `rd`，但实际 GPR 写回由 `custom_unit` 完成。
4. `core/id.v:311-320` 译码 `ifire`，读取 `rs1` 与 `x31`，准备条件判断。
5. `core/ex.v:878-944` 在 EX 阶段执行自定义指令控制。
6. `core/ex.v:890-902` 对 `sID` 拉起 custom unit，hold 当前流水线并跳到下一条指令地址。
7. `core/ex.v:903-915` 对 `rT` 拉起 custom unit，等待温度值写回。
8. `core/ex.v:916-938` 对 `ifire` 判断立即数和比较条件，满足条件时发送 UART 字节并由 custom unit 写 0。
9. `core/ex.v:158-166` 使自定义指令写回优先级高于除法和普通 EX 写回。
10. `core/ex.v:173` 在 `custom_busy_i` 为 1 时暂停流水线。
11. `core/tinyriscv.v:141-152` 声明 custom unit 连接线。
12. `core/tinyriscv.v:469-490` 实例化 `custom_unit`。
13. `core/custom_unit.v:12-49` 定义 custom unit 参数和端口。
14. `core/custom_unit.v:51-58` 定义 `sID`、`rT`、`ifire` 的多周期 FSM 状态。
15. `core/custom_unit.v:65-82` 按索引返回学号 ASCII 字节。
16. `core/custom_unit.v:105-126` 从 idle 接收启动请求并按 `funct3` 进入对应状态。
17. `core/custom_unit.v:129-145` 实现 `sID` 的逐字节 UART 发送。
18. `core/custom_unit.v:147-160` 实现 `rT` 的 I2C 请求和温度写回。
19. `core/custom_unit.v:162-176` 实现 `ifire` 的 UART 发送和写 0。
20. `core/custom_unit.v:178-182` 给出 `ready_o` 并回到空闲。

工程默认学号占位参数：

| 参数 | 默认 ASCII |
| --- | --- |
| `DEFAULT_ID0` - `DEFAULT_ID9` | `"2022123456"` |

流片前必须把 `core/custom_unit.v:14-23` 的 `DEFAULT_ID*` 替换为真实学号或通过上层参数覆盖。

## 7. CPU Core 数据通路

`core/tinyriscv.v` 是 CPU core 顶层，核心职责是把 PC、IF/ID、ID、ID/EX、EX、寄存器堆、CSR、CLINT、DIV、custom unit 接起来。

行级说明：

| 行号 | 功能 |
| --- | --- |
| `core/tinyriscv.v:20-54` | CPU core 端口，包括 RIB、JTAG、中断、片外 load 数据和 custom sideband |
| `core/tinyriscv.v:56-139` | 声明 PC、IF/ID、ID、EX、regs、CSR、ctrl、div 等模块间连接线 |
| `core/tinyriscv.v:141-152` | 声明 custom unit 连接线 |
| `core/tinyriscv.v:154-167` | 声明片外 load 延迟写回状态 |
| `core/tinyriscv.v:179-184` | 把 EX 访存请求与 PC 取指请求输出到 RIB |
| `core/tinyriscv.v:186-197` | 判断片外 load，屏蔽即时写回，等待 bridge 返回后再写 GPR |
| `core/tinyriscv.v:199-235` | 按 `LB/LH/LW/LBU/LHU` 格式化片外 load 返回数据 |
| `core/tinyriscv.v:237-260` | 保存片外 load 的 `funct3`、低地址位、目的寄存器，检测完成时机 |
| `core/tinyriscv.v:263-272` | 实例化 PC 寄存器 |
| `core/tinyriscv.v:274-287` | 实例化 ctrl，接入普通 RIB hold 和 full pipeline RIB hold |
| `core/tinyriscv.v:289-304` | 实例化 GPR regs，写端口接入 delayed off-chip load mux |
| `core/tinyriscv.v:306-324` | 实例化 CSR |
| `core/tinyriscv.v:326-337` | 实例化 IF/ID |
| `core/tinyriscv.v:339-364` | 实例化 ID |
| `core/tinyriscv.v:366-397` | 实例化 ID/EX |
| `core/tinyriscv.v:399-452` | 实例化 EX，接入 div/custom/JTAG/CSR/中断 |
| `core/tinyriscv.v:454-467` | 实例化除法器 |
| `core/tinyriscv.v:469-490` | 实例化 custom unit |
| `core/tinyriscv.v:493-515` | 实例化 CLINT |

这部分最重要的 tapeout 修复点是片外 load 延迟写回：

- 原始单周期 RIB 模型会让 EX 立即用 `rib_ex_data_i` 写回。
- 当前片外 ROM/RAM 经 8-bit 多周期 bridge，load 数据晚于 EX 当前周期返回。
- `core/tinyriscv.v:186-197` 禁止片外 load 的即时写回。
- `core/tinyriscv.v:237-260` 等 bridge 完成后发出一次真正写回。
- `sim/tb_soc_load.v` 和 `sim/tb_soc_mem_ops.v` 已覆盖该路径。

## 8. RIB 总线与片外存储桥

`core/rib.v` 是修改后 SoC 的总线互连。它保留外设单周期 MMIO，同时为片外 ROM/RAM 增加显式多周期事务 FSM。

RIB 主设备：

| master | 来源 | 说明 |
| --- | --- | --- |
| `m0` | CPU EX/load-store | 数据访存 |
| `m1` | CPU PC | 指令取指 |
| `m2` | JTAG DMI | 调试访存 |
| `m3` | UART downloader | UART 下载写存储 |

RIB 从设备：

| slave | 设备 | 地址高 nibble |
| --- | --- | --- |
| `s0` | 片外 ROM/RAM bridge | `0x0` / `0x1` |
| `s1` | UART | `0x3` |
| `s2` | PWM | `0x6` |
| `s3` | I2C | `0x7` |

行级说明：

| 行号 | 功能 |
| --- | --- |
| `core/rib.v:1-13` | 注释说明该 RIB 专门处理片外多周期 bridge |
| `core/rib.v:16-68` | 四主四从端口定义，以及普通 hold/full hold 输出 |
| `core/rib.v:71-79` | master 编号和片外事务 FSM 状态 |
| `core/rib.v:81-95` | 片外事务锁存寄存器、仲裁临时变量 |
| `core/rib.v:97-107` | 组合判断当前请求是否片外、是否启动事务、是否需要 full pipeline hold |
| `core/rib.v:109-119` | 仲裁优先级：UART downloader、CPU data、JTAG、CPU fetch |
| `core/rib.v:121-148` | 根据 grant 选出请求地址、写数据、写使能、请求信号 |
| `core/rib.v:150-204` | 片外事务 FSM：IDLE 锁存、ISSUE 单周期请求、WAIT 等 busy、RESP 返回 |
| `core/rib.v:206-229` | 默认输出清零，避免组合锁存 |
| `core/rib.v:230-267` | UART/PWM/I2C 单周期地址译码与读回 |
| `core/rib.v:269-276` | 片外返回数据只送给被锁存的 owner |
| `core/rib.v:278-280` | 输出两级 hold：PC-only hold 与 full pipeline hold |

两个 hold 的含义：

| 信号 | 用途 |
| --- | --- |
| `hold_flag_o` | 取指或非取指事务期间阻止 PC 继续乱跑，也在其他 master 请求时暂停取指 |
| `hold_flag_full_o` | 非取指片外访问时暂停完整流水线，保证 load/store/JTAG/UART 下载事务不会被年轻指令覆盖 |

`core/ctrl.v` 对这两个 hold 的处理：

- `core/ctrl.v:55-57`：EX、CLINT、跳转优先，暂停到 ID。
- `core/ctrl.v:58-60`：`hold_flag_rib_full_i` 暂停到 ID。
- `core/ctrl.v:61-62`：普通 RIB hold 只暂停 PC。

## 9. 片外桥协议

芯片侧 bridge：`perips/chip_mem_bridge.v`。FPGA 侧 bridge：`fpga/fpga_mem_bridge.v`。

请求帧由芯片每拍发送 1 字节：

| 字节序号 | 内容 |
| --- | --- |
| 0 | `8'hA5` 请求头 |
| 1 | `{we, is_ram, 6'b0}` |
| 2 | `word_addr[7:0]`，芯片侧实际发送 `addr[9:2]` |
| 3 | `wdata[7:0]` |
| 4 | `wdata[15:8]` |
| 5 | `wdata[23:16]` |
| 6 | `wdata[31:24]` |

响应帧由 FPGA 每拍返回 1 字节：

| 字节序号 | 内容 |
| --- | --- |
| 0 | `8'h5A` 响应头 |
| 1 | `rdata[7:0]` |
| 2 | `rdata[15:8]` |
| 3 | `rdata[23:16]` |
| 4 | `rdata[31:24]` |

芯片侧行级说明：

| 行号 | 功能 |
| --- | --- |
| `perips/chip_mem_bridge.v:1-21` | 协议注释 |
| `perips/chip_mem_bridge.v:24-38` | 模块端口 |
| `perips/chip_mem_bridge.v:40-53` | 发送和接收状态 |
| `perips/chip_mem_bridge.v:55-62` | 状态寄存器、请求锁存、busy 输出 |
| `perips/chip_mem_bridge.v:64-109` | 完整状态机，固定帧格式发送请求并收集响应 |

FPGA 侧行级说明：

| 行号 | 功能 |
| --- | --- |
| `fpga/fpga_mem_bridge.v:1-5` | FPGA 侧 bridge 功能注释 |
| `fpga/fpga_mem_bridge.v:6-13` | 模块端口和可选 ROM 初始化文件参数 |
| `fpga/fpga_mem_bridge.v:15-26` | 协议状态定义 |
| `fpga/fpga_mem_bridge.v:35-45` | `256 x 32-bit` ROM 与 `16 x 32-bit` RAM 初始化 |
| `fpga/fpga_mem_bridge.v:47-97` | 接收请求、执行读写、返回响应 |

注意：当前协议没有额外 valid/ready 或 CRC。FPGA 仿真和课程 demo 足够简单，但流片前若 pad 数允许，建议增加帧 valid、ready、timeout 或奇偶校验，以增强真实板级鲁棒性。

## 10. 外设说明

### 10.1 UART Shared

`perips/uart_shared.v` 是 MMIO UART，同时允许 custom unit 插入 TX 字节。

MMIO 寄存器：

| 偏移 | 名称 | 功能 |
| --- | --- | --- |
| `+0x00` | `CTRL` | bit0 TX enable，bit1 RX enable |
| `+0x04` | `STATUS` | bit0 TX busy，bit1 RX over |
| `+0x08` | `BAUD` | 波特率分频 |
| `+0x0c` | `TXDATA` | 写低 8 bit 发送 |
| `+0x10` | `RXDATA` | 读低 8 bit 接收数据 |

行级说明：

| 行号 | 功能 |
| --- | --- |
| `perips/uart_shared.v:12-25` | MMIO 与 custom TX 端口 |
| `perips/uart_shared.v:27-38` | 默认 baud 和 TX 状态机编码 |
| `perips/uart_shared.v:65-70` | MMIO TX 请求条件与 custom TX ready |
| `perips/uart_shared.v:73-118` | UART 控制寄存器、MMIO 写、custom TX 仲裁 |
| `perips/uart_shared.v:120-132` | MMIO 读回 |
| `perips/uart_shared.v:134-181` | TX bit 级状态机 |
| `perips/uart_shared.v:183-274` | RX 同步、起始检测、采样、接收完成状态 |

custom TX 和 MMIO TX 的仲裁规则：在 `perips/uart_shared.v:84-104` 中，MMIO 写 `TXDATA` 优先；当本周期不是 MMIO 写且 custom valid/ready 同时成立时，custom 字节进入 TX。

### 10.2 UART Debug

`perips/uart_debug.v` 用于 UART 下载辅助，保留原始 master-3 总线接口，通过 RIB 配置 UART、接收数据、写存储并返回 ACK。

关键定义：

| 行号 | 功能 |
| --- | --- |
| `perips/uart_debug.v:18-29` | UART 地址、状态位、packet 长度、ACK/NAK |
| `perips/uart_debug.v:31-40` | 模块端口，输出 RIB master 请求 |
| `perips/uart_debug.v:42-51` | 下载状态机 |
| `perips/uart_debug.v:79-95` | 初始化 UART 控制和波特率，清 RX 状态 |
| `perips/uart_debug.v:101-114` | 等待和读取 RX 字节 |
| `perips/uart_debug.v:126-139` | 按 word 写入 memory |
| `perips/uart_debug.v:144-145` | 返回 ACK |

当前下载包参数：

- `UART_PACKET_LEN = 35`
- `UART_PAYLOAD_BYTES = 28`

如果课程提供固定 PC 端下载脚本，必须用脚本逐字节对齐包格式。

### 10.3 PWM

`perips/pwm.v` 是四通道 PWM 外设。

PWM 地址映射在 RIB 去掉高 nibble 后如下：

| SoC 地址 | RIB 后地址 | 寄存器 |
| --- | --- | --- |
| `0x6000_0000` | `0x0000_0000` | PWM0 period |
| `0x6001_0000` | `0x0001_0000` | PWM1 period |
| `0x6002_0000` | `0x0002_0000` | PWM2 period |
| `0x6003_0000` | `0x0003_0000` | PWM3 period |
| `0x6010_0000` | `0x0010_0000` | PWM0 high time |
| `0x6011_0000` | `0x0011_0000` | PWM1 high time |
| `0x6012_0000` | `0x0012_0000` | PWM2 high time |
| `0x6013_0000` | `0x0013_0000` | PWM3 high time |
| `0x6004_0000` | `0x0004_0000` | `enable[3:0]` |

行级说明：

| 行号 | 功能 |
| --- | --- |
| `perips/pwm.v:1-13` | 地址映射注释 |
| `perips/pwm.v:16-24` | 模块端口 |
| `perips/pwm.v:26-34` | period、high_time、enable、counter 寄存器和地址解码 |
| `perips/pwm.v:36-70` | 复位、寄存器写、计数器递增/回绕 |
| `perips/pwm.v:72-86` | MMIO 读回 |
| `perips/pwm.v:88-91` | 四路 PWM 输出比较 |

设计细节：

- period 写 0 时自动替换为 1，避免 `period-1` 下溢造成异常周期。
- enable 为 0 的通道 counter 清 0，输出恒 0。
- 输出逻辑为 `enable[i] & (cnt[i] < high_time[i])`。

### 10.4 I2C/LM75

`perips/i2c_lm75.v` 是最小 I2C master，用于读取 LM75 温度 MSB。

MMIO 寄存器：

| RIB 后地址 | 名称 | 功能 |
| --- | --- | --- |
| `0x0000_0000` | CTRL/STATUS | 写 bit0 启动读；读 bit1 busy，bit2 done |
| `0x0001_0000` | SLAVE_ADDR | 7-bit LM75 地址，默认 `0x48` |
| `0x0002_0000` | TX_DATA | 预留/可读写寄存器 |
| `0x0003_0000` | RX_DATA | `{24'h0, temperature_msb}` |

行级说明：

| 行号 | 功能 |
| --- | --- |
| `perips/i2c_lm75.v:1-11` | 功能和寄存器映射注释 |
| `perips/i2c_lm75.v:14-31` | 模块参数和端口，包括 custom `rT` 侧带接口 |
| `perips/i2c_lm75.v:33-51` | 寄存器地址和 I2C 状态机编码 |
| `perips/i2c_lm75.v:53-69` | 状态寄存器、SDA 开漏输出和 busy 输出 |
| `perips/i2c_lm75.v:71-83` | I2C 分频 tick 计数 |
| `perips/i2c_lm75.v:85-108` | MMIO/custom 启动请求锁存 |
| `perips/i2c_lm75.v:110-239` | I2C start、发送地址、ACK、读字节、NACK、stop、done 主 FSM |
| `perips/i2c_lm75.v:241-250` | MMIO 读回 |

当前 I2C 简化点：

- ACK 阶段采样但不因 NACK 失败退出。
- 只读取一个 8-bit 温度 MSB。
- `done` 保持到下一次 start，便于软件轮询。
- 默认 `CLK_DIV=250`，若 `clk=50MHz`，SCL 大约为 `50MHz/(4*250)=50kHz`。

## 11. SoC 顶层连接

`soc/tinyriscv_soc_top.v` 是当前工程的主要集成点。

行级说明：

| 行号 | 功能 |
| --- | --- |
| `soc/tinyriscv_soc_top.v:1-10` | 顶层修改目标注释 |
| `soc/tinyriscv_soc_top.v:13-38` | 顶层端口 |
| `soc/tinyriscv_soc_top.v:41` | `core_rst = rst & chip_sel_i` |
| `soc/tinyriscv_soc_top.v:43-66` | RIB 四个 master 的信号定义 |
| `soc/tinyriscv_soc_top.v:68-93` | RIB 四个 slave 的信号定义 |
| `soc/tinyriscv_soc_top.v:95-113` | RIB hold、JTAG、custom sideband 信号 |
| `soc/tinyriscv_soc_top.v:115-125` | `halted_ind`、`over`、`succ` 测试状态输出 |
| `soc/tinyriscv_soc_top.v:127-160` | CPU core 实例化 |
| `soc/tinyriscv_soc_top.v:163-215` | RIB 实例化 |
| `soc/tinyriscv_soc_top.v:218-230` | 芯片侧片外存储 bridge 实例化 |
| `soc/tinyriscv_soc_top.v:232-243` | UART shared 实例化 |
| `soc/tinyriscv_soc_top.v:246-253` | PWM 实例化 |
| `soc/tinyriscv_soc_top.v:256-268` | I2C/LM75 实例化 |
| `soc/tinyriscv_soc_top.v:271-279` | UART debug 实例化 |
| `soc/tinyriscv_soc_top.v:282-303` | JTAG top 实例化 |

## 12. 仿真与验证

当前验证基于 Icarus Verilog。所有命令在仓库根目录执行。

### 12.1 顶层 elaboration

```powershell
iverilog -g2012 -Wall -o .\sim_project.vvp -s tinyriscv_soc_top -f filelist_project.f
```

目的：确认所有 RTL 文件可被编译和顶层实例化。

### 12.2 custom unit

```powershell
iverilog -g2012 -Wall -I core -o .\sim_custom_unit.vvp sim\tb_custom_unit.v core\custom_unit.v
vvp .\sim_custom_unit.vvp
```

期望输出：

```text
PASS: tb_custom_unit
```

覆盖：

- `sID` 连续发送 10 个 ASCII 字节。
- `rT` 发出 I2C 请求并写回温度。
- `ifire` 满足条件时发送低 8 bit 并写回 0。

### 12.3 PWM

```powershell
iverilog -g2012 -Wall -I core -o .\sim_pwm.vvp sim\tb_pwm.v perips\pwm.v
vvp .\sim_pwm.vvp
```

期望输出：

```text
PASS: tb_pwm
```

覆盖：

- period 写入和读回。
- high_time 写入和读回。
- enable 写入和读回。
- PWM 高低相位。

### 12.4 I2C/LM75

```powershell
iverilog -g2012 -Wall -I core -o .\sim_i2c.vvp sim\tb_i2c_lm75.v perips\i2c_lm75.v
vvp .\sim_i2c.vvp
```

期望输出：

```text
PASS: tb_i2c_lm75
```

覆盖：

- custom request 启动温度读取。
- I2C 状态机完成。
- `custom_temp_valid_o` 拉高。
- `done` sticky 可被 MMIO 读回。

### 12.5 片外桥

```powershell
iverilog -g2012 -Wall -I core -o .\sim_mem_bridge.vvp sim\tb_mem_bridge.v perips\chip_mem_bridge.v fpga\fpga_mem_bridge.v
vvp .\sim_mem_bridge.vvp
```

期望输出：

```text
PASS: tb_mem_bridge
```

覆盖：

- 芯片侧发送固定请求帧。
- FPGA 侧识别 ROM/RAM。
- RAM 写入后读回。
- 响应头和 32-bit 数据组包。

### 12.6 SoC load

```powershell
iverilog -g2012 -Wall -I core -o .\sim_soc_load.vvp -f filelist_project.f sim\tb_soc_load.v fpga\fpga_mem_bridge.v
vvp .\sim_soc_load.vvp
```

期望输出：

```text
PASS: tb_soc_load
```

覆盖：

- CPU 从片外 ROM 取指。
- CPU 执行片外 RAM load。
- delayed off-chip load 写回。

### 12.7 SoC memory operations

```powershell
iverilog -g2012 -Wall -I core -o .\sim_soc_mem_ops.vvp -f filelist_project.f sim\tb_soc_mem_ops.v fpga\fpga_mem_bridge.v
vvp .\sim_soc_mem_ops.vvp
```

期望输出：

```text
PASS: tb_soc_mem_ops
```

覆盖：

- `SW` 到片外 RAM。
- `LW` 从片外 RAM。
- `LB/LBU/LH/LHU` 返回格式化。
- 片外 load/store 与取指竞争时 RIB hold 行为。

### 12.8 chip_sel

```powershell
iverilog -g2012 -Wall -I core -o .\sim_chip_sel.vvp -f filelist_project.f sim\tb_chip_sel.v fpga\fpga_mem_bridge.v
vvp .\sim_chip_sel.vvp
```

期望输出：

```text
PASS: tb_chip_sel
```

覆盖：

- `chip_sel_i=0` 时 core 保持复位。
- `chip_sel_i=1` 后 core 正常运行。
- UART debug enable 被 `chip_sel_i` 屏蔽。

### 12.9 一次性回归命令

```powershell
$tests = @(
  @{name='top_elab'; cmd='iverilog -g2012 -Wall -o .\sim_project.vvp -s tinyriscv_soc_top -f filelist_project.f'},
  @{name='custom_unit'; cmd='iverilog -g2012 -Wall -I core -o .\sim_custom_unit.vvp sim\tb_custom_unit.v core\custom_unit.v; if ($LASTEXITCODE -eq 0) { vvp .\sim_custom_unit.vvp }'},
  @{name='pwm'; cmd='iverilog -g2012 -Wall -I core -o .\sim_pwm.vvp sim\tb_pwm.v perips\pwm.v; if ($LASTEXITCODE -eq 0) { vvp .\sim_pwm.vvp }'},
  @{name='i2c'; cmd='iverilog -g2012 -Wall -I core -o .\sim_i2c.vvp sim\tb_i2c_lm75.v perips\i2c_lm75.v; if ($LASTEXITCODE -eq 0) { vvp .\sim_i2c.vvp }'},
  @{name='mem_bridge'; cmd='iverilog -g2012 -Wall -I core -o .\sim_mem_bridge.vvp sim\tb_mem_bridge.v perips\chip_mem_bridge.v fpga\fpga_mem_bridge.v; if ($LASTEXITCODE -eq 0) { vvp .\sim_mem_bridge.vvp }'},
  @{name='soc_load'; cmd='iverilog -g2012 -Wall -I core -o .\sim_soc_load.vvp -f filelist_project.f sim\tb_soc_load.v fpga\fpga_mem_bridge.v; if ($LASTEXITCODE -eq 0) { vvp .\sim_soc_load.vvp }'},
  @{name='soc_mem_ops'; cmd='iverilog -g2012 -Wall -I core -o .\sim_soc_mem_ops.vvp -f filelist_project.f sim\tb_soc_mem_ops.v fpga\fpga_mem_bridge.v; if ($LASTEXITCODE -eq 0) { vvp .\sim_soc_mem_ops.vvp }'},
  @{name='chip_sel'; cmd='iverilog -g2012 -Wall -I core -o .\sim_chip_sel.vvp -f filelist_project.f sim\tb_chip_sel.v fpga\fpga_mem_bridge.v; if ($LASTEXITCODE -eq 0) { vvp .\sim_chip_sel.vvp }'}
)
foreach ($t in $tests) {
  Write-Output "===== $($t.name) ====="
  Invoke-Expression $t.cmd
  if ($LASTEXITCODE -ne 0) { throw "test failed: $($t.name)" }
}
```

最近一次回归结果：

```text
top_elab        PASS
tb_custom_unit  PASS
tb_pwm          PASS
tb_i2c_lm75     PASS
tb_mem_bridge   PASS
tb_soc_load     PASS
tb_soc_mem_ops  PASS
tb_chip_sel     PASS
```

已知 Icarus warning：

- `regs.v` / `pwm.v` 中数组被组合块读出时，Icarus 会提示 array word sensitivity 相关 warning。
- 部分 testbench 没有显式 timescale，会出现 inherited timescale 提示。
- 这些 warning 不影响当前 PASS，但流片前建议用 Verilator 和综合 lint 再扫一遍。

## 13. Testbench 覆盖索引

| testbench | 覆盖对象 | 覆盖功能 |
| --- | --- | --- |
| `sim/tb_custom_unit.v` | 自定义指令单元 | `sID`、`rT`、`ifire` FSM、UART/I2C sideband、GPR 写回 |
| `sim/tb_pwm.v` | PWM 外设 | 寄存器写读、period/high_time/enable、输出比较 |
| `sim/tb_i2c_lm75.v` | I2C 外设 | custom 启动、I2C 状态机、done/valid |
| `sim/tb_mem_bridge.v` | 片外桥 | request/response 帧、RAM 写读 |
| `sim/tb_soc_load.v` | SoC load | 片外取指、片外 RAM load、延迟写回 |
| `sim/tb_soc_mem_ops.v` | SoC memory | load/store、byte/halfword/word 格式化 |
| `sim/tb_chip_sel.v` | 芯片选择 | 未选中复位、选中后运行 |

更完整的验证说明见 `doc/verification_report.md`。

## 14. filelist

`filelist_project.f` 是当前 SoC 顶层使用的 RTL filelist。

当前包含：

```text
core/defines.v
core/pc_reg.v
core/if_id.v
core/id.v
core/id_ex.v
core/ex.v
core/regs.v
core/csr_reg.v
core/clint.v
core/div.v
core/custom_unit.v
core/ctrl.v
core/rib.v
core/tinyriscv.v
utils/gen_dff.v
utils/gen_buf.v
utils/full_handshake_tx.v
utils/full_handshake_rx.v
debug/jtag_driver.v
debug/jtag_dm.v
debug/jtag_top.v
perips/uart_shared.v
perips/uart_debug.v
perips/pwm.v
perips/i2c_lm75.v
perips/chip_mem_bridge.v
soc/tinyriscv_soc_top.v
```

若加入 pad wrapper、PLL、reset synchronizer、FPGA top 或后端 wrapper，需要新增专门 filelist，不建议污染当前核心 RTL filelist。

## 15. 逐文件行级索引

本节覆盖所有主要源码文件。行号来自当前仓库状态；若 RTL 被改动，需重新生成。

### 15.1 `core/defines.v`

| 行号 | 功能 |
| --- | --- |
| 1-7 | 工程配置注释 |
| 9-10 | include guard |
| 12-15 | reset 地址和 reset 极性 |
| 16-41 | 基础控制宏 |
| 43-47 | 中断宏 |
| 49-53 | hold 级别宏 |
| 55-67 | 地址映射宏 |
| 69-82 | 总线宽度、寄存器数量 |
| 84-107 | I/L/S 指令宏 |
| 109-126 | R/M 指令宏 |
| 128-146 | B/J/U/fence/exception 指令宏 |
| 148-155 | CSR 指令宏 |
| 157-161 | 自定义指令宏 |
| 163-172 | CSR 地址宏 |
| 173 | include guard 结束 |

### 15.2 `core/tinyriscv.v`

| 行号 | 功能 |
| --- | --- |
| 1-17 | Apache 头和 include |
| 20-54 | 模块端口 |
| 56-139 | 基础流水线和运算单元连线 |
| 141-152 | custom unit 连线 |
| 154-167 | 片外 load 延迟写回状态 |
| 169-176 | CLINT 连线 |
| 179-184 | RIB 输出绑定 |
| 186-197 | 片外 load 检测与 GPR 写回 mux |
| 199-235 | load 数据格式化 |
| 237-260 | 片外 load pending FSM |
| 263-515 | 各子模块实例化 |
| 518 | endmodule |

### 15.3 `core/rib.v`

| 行号 | 功能 |
| --- | --- |
| 1-13 | RIB 修改说明 |
| 16-68 | 模块端口 |
| 71-79 | grant 和状态编码 |
| 81-95 | 事务状态寄存器和仲裁寄存器 |
| 97-107 | 片外事务开始和 hold 条件 |
| 109-119 | master 仲裁 |
| 121-148 | 被 grant master 的请求 mux |
| 150-204 | 片外事务时序状态机 |
| 206-229 | 默认输出 |
| 230-267 | 单周期外设译码 |
| 269-276 | 片外响应返回给 owner |
| 278-280 | hold 输出 |
| 283 | endmodule |

### 15.4 `core/id.v`

| 行号 | 功能 |
| --- | --- |
| 1-17 | Apache 头和 include |
| 21-57 | 模块端口 |
| 59-64 | 指令字段拆分 |
| 67-84 | 组合译码默认值 |
| 85-155 | I/R/M 指令译码 |
| 156-191 | Load/Store 指令译码 |
| 192-261 | Branch/Jump/Fence 译码 |
| 262-292 | CSR 指令译码 |
| 293-328 | 自定义指令译码 |
| 329-335 | 未识别 opcode 默认处理 |
| 338 | endmodule |

### 15.5 `core/ex.v`

| 行号 | 功能 |
| --- | --- |
| 1-17 | Apache 头和 include |
| 21-84 | 模块端口 |
| 86-126 | 内部信号 |
| 127-154 | 指令字段、加法、比较、乘法、访存低位 |
| 156-178 | 写回、访存、hold、jump、CSR 输出 |
| 181-206 | 乘法操作数预处理 |
| 208-255 | 除法启动/等待/写回控制 |
| 257-269 | EX 主组合逻辑默认值 |
| 270-878 | RV32I/M/CSR/访存/跳转执行逻辑 |
| 878-944 | 自定义指令执行逻辑 |
| 945-955 | 默认 opcode 处理 |
| 958 | endmodule |

### 15.6 `core/custom_unit.v`

| 行号 | 功能 |
| --- | --- |
| 1-9 | 自定义指令单元说明和学号替换提醒 |
| 12-24 | 参数定义，默认学号 ASCII |
| 25-49 | 模块端口 |
| 51-58 | FSM 状态 |
| 60-63 | 状态、索引和暂存寄存器 |
| 65-82 | `id_byte` 查询函数 |
| 84-190 | 主时序 FSM |
| 105-126 | 接收 start 并按 funct3 分派 |
| 129-145 | `sID` UART 发送 |
| 147-160 | `rT` I2C 请求和写回 |
| 162-176 | `ifire` UART 发送和写 0 |
| 178-182 | done/ready |
| 192 | endmodule |

### 15.7 `core/ctrl.v`

| 行号 | 功能 |
| --- | --- |
| 1-17 | Apache 头和 include |
| 21-46 | 模块端口 |
| 49-69 | hold 和 jump 组合控制 |
| 55-57 | EX/CLINT/jump 最高优先级 full hold |
| 58-60 | RIB full hold |
| 61-62 | RIB PC-only hold |
| 63-65 | JTAG halt full hold |
| 71 | endmodule |

### 15.8 `core/regs.v`

| 行号范围 | 功能 |
| --- | --- |
| 全文件 | 32 个通用寄存器，`x0` 恒 0，支持 CPU 写、双读和 JTAG 读写 |

### 15.9 `core/div.v`

| 行号范围 | 功能 |
| --- | --- |
| 全文件 | RV32M 除法/取余多周期单元，支持有符号/无符号 DIV/REM |

### 15.10 `core/csr_reg.v`

| 行号范围 | 功能 |
| --- | --- |
| 全文件 | CSR 寄存器组，支持 `cycle/cycleh/mtvec/mcause/mepc/mie/mstatus/mscratch` 和 CLINT 访问 |

### 15.11 `core/clint.v`

| 行号范围 | 功能 |
| --- | --- |
| 全文件 | 中断/异常控制，处理同步异常、外部中断、`mret` 以及 CSR 写回序列 |

### 15.12 `core/pc_reg.v`

| 行号范围 | 功能 |
| --- | --- |
| 全文件 | PC 寄存器，复位到 `CpuResetAddr`，支持 hold、jump、JTAG reset |

### 15.13 `core/if_id.v`

| 行号范围 | 功能 |
| --- | --- |
| 全文件 | IF 到 ID 的流水线寄存器，hold 时保持或插入 NOP |

### 15.14 `core/id_ex.v`

| 行号范围 | 功能 |
| --- | --- |
| 全文件 | ID 到 EX 的流水线寄存器，传递指令、操作数、CSR、写回信息 |

### 15.15 `perips/chip_mem_bridge.v`

| 行号 | 功能 |
| --- | --- |
| 1-21 | 协议说明 |
| 24-38 | 模块端口 |
| 40-53 | 状态编码 |
| 55-62 | 锁存寄存器和 busy |
| 64-109 | 固定帧发送/接收状态机 |
| 111 | endmodule |

### 15.16 `fpga/fpga_mem_bridge.v`

| 行号 | 功能 |
| --- | --- |
| 1-5 | 模块说明 |
| 6-13 | 模块端口 |
| 15-26 | 状态编码 |
| 28-36 | 状态、请求锁存、ROM/RAM |
| 39-45 | ROM/RAM 初始化 |
| 47-97 | 协议接收和响应状态机 |
| 99 | endmodule |

### 15.17 `perips/uart_shared.v`

| 行号 | 功能 |
| --- | --- |
| 1-9 | MMIO map 说明 |
| 12-25 | 模块端口 |
| 27-38 | baud 和状态编码 |
| 40-63 | UART 寄存器和 TX/RX 状态 |
| 65-70 | TX 请求和 ready |
| 73-118 | 控制寄存器和 TX 仲裁 |
| 120-132 | MMIO 读 |
| 134-181 | TX 状态机 |
| 183-274 | RX 状态机 |
| 276 | endmodule |

### 15.18 `perips/uart_debug.v`

| 行号范围 | 功能 |
| --- | --- |
| 1-29 | UART debug 用到的寄存器地址、packet 长度和响应码 |
| 31-51 | 模块端口和状态编码 |
| 53-65 | 状态、索引、包缓冲、写 word 状态 |
| 67-149 | 初始化 UART、接收 packet、写内存、发送 ACK 的主 FSM |

### 15.19 `perips/pwm.v`

| 行号 | 功能 |
| --- | --- |
| 1-13 | 地址映射 |
| 16-24 | 模块端口 |
| 26-34 | 寄存器和地址解析 |
| 36-70 | 写寄存器和计数器 |
| 72-86 | 读寄存器 |
| 88-91 | PWM 输出 |
| 93 | endmodule |

### 15.20 `perips/i2c_lm75.v`

| 行号 | 功能 |
| --- | --- |
| 1-11 | 功能和寄存器说明 |
| 14-31 | 模块参数和端口 |
| 33-51 | 寄存器地址和状态编码 |
| 53-69 | 状态寄存器、开漏 SDA、busy |
| 71-83 | 分频 tick |
| 85-108 | MMIO/custom start 请求 |
| 110-239 | I2C 主状态机 |
| 241-250 | MMIO 读 |
| 252 | endmodule |

### 15.21 `debug/jtag_top.v`

| 行号范围 | 功能 |
| --- | --- |
| 全文件 | JTAG 顶层，连接 TAP driver 与 debug module |

### 15.22 `debug/jtag_driver.v`

| 行号范围 | 功能 |
| --- | --- |
| 全文件 | JTAG TAP 状态机，处理 IR/DR 扫描、IDCODE、DTMCS、DMI |

### 15.23 `debug/jtag_dm.v`

| 行号范围 | 功能 |
| --- | --- |
| 全文件 | Debug Module，支持寄存器访问、系统总线访问、halt/reset 请求 |

### 15.24 `utils/*.v`

| 文件 | 功能 |
| --- | --- |
| `utils/full_handshake_tx.v` | 跨域 full handshake 发送端 |
| `utils/full_handshake_rx.v` | 跨域 full handshake 接收端 |
| `utils/gen_buf.v` | 同步 buffer |
| `utils/gen_dff.v` | 参数化 DFF、复位 DFF、enable DFF |

## 16. 设计质量检查清单

流片前必须完成：

| 检查项 | 当前状态 | 处理建议 |
| --- | --- | --- |
| RTL 仿真 | 已跑 Icarus 回归 PASS | 增加随机 load/store、UART BFM、I2C BFM |
| Lint | 未跑 Verilator/SpyGlass | 安装工具并清理 warning |
| 综合 | 未跑 | 使用目标工艺库综合，检查频率、面积、未连接端口、latch |
| STA | 未跑 | 多 corner、多 mode、复位/调试路径约束 |
| CDC/RDC | 未跑 | JTAG TCK 与 core clk 跨域需要重点检查 |
| Reset strategy | 当前低有效 `rst` 直连 | 流片建议 pad 后做同步释放 |
| IO Ring | 未实现 pad 顶层 | 必须增加多芯片 mux/OE |
| DFT | 未实现 scan/mbist | 按课程/MPW 平台要求添加 |
| DRC/LVS | 未跑 | 后端完成后签核 |
| Formal | 未跑 | 可对 RIB/bridge FSM 做简单互斥和 liveness 断言 |

## 17. 性能和频率优化建议

当前 RTL 为课程 SoC 原型，已避免最明显的多周期总线错误。若目标是“综合频率尽量高”，建议按以下顺序优化：

1. EX 大组合逻辑拆分：`core/ex.v` 当前包含大量 RV32I/M/CSR/custom 组合 case，可能成为关键路径。可考虑把乘法、访存格式化、自定义指令控制拆出或流水化。
2. 乘法器：`assign mul_temp = mul_op1 * mul_op2` 会综合成组合乘法器，面积和路径都较重。若目标频率高，可换成多周期乘法或调用工艺库 DW。
3. RIB 地址译码：当前 RIB 简单清晰，路径短。保持不要加入复杂优先级/大 mux。
4. 片外 bridge：当前固定帧 FSM 频率压力小，但带宽低。若系统性能要求高，片外 ROM/RAM 应改为真正 SRAM/Flash 控制器或宽总线。
5. JTAG 跨时钟：JTAG TCK 与 core clk 关系需要 CDC 处理和约束，避免综合后时序不可控。
6. UART/I2C：低速外设对主频影响小，但要确保输出到 pad 的时序约束正确。

## 18. 开源说明

原始 tinyriscV 源码文件头声明为 Apache License 2.0。本仓库保留原始文件头，并在新增文件中继续采用 Apache-2.0 授权，便于课程提交、展示和后续开源。

开源发布前请确认：

- 保留所有原作者 copyright 和 license header。
- 根目录保留 `LICENSE`。
- 根目录保留 `NOTICE`，说明本工程基于 `https://gitee.com/liangkangnan/tinyriscv` 修改。
- 若加入第三方 IP、工艺库、PDK、标准单元库、IO pad 或课程平台文件，必须确认其许可证允许公开。通常 PDK 和工艺库不能开源。
- 不要提交真实流片账号、服务器路径、商业工具 license、PDK 文件、密钥、学生隐私信息。

## 19. 快速上手

1. 安装 Icarus Verilog。
2. 在仓库根目录执行第 12.9 节回归命令。
3. 若只检查编译，执行：

```powershell
iverilog -g2012 -Wall -o .\sim_project.vvp -s tinyriscv_soc_top -f filelist_project.f
```

4. 若要修改学号，编辑 `core/custom_unit.v:14-23`。
5. 若要修改 ROM 程序，给 `fpga/fpga_mem_bridge.v` 的 `ROM_INIT_FILE` 参数传入 hex 文件，或在 testbench 中直接写 `rom[]`。
6. 若要移植 FPGA，新增 FPGA top，实例化 `tinyriscv_soc_top` 与 `fpga_mem_bridge`，绑定 UART/JTAG/PWM/I2C/bridge 管脚。
7. 若要准备流片，新增 pad wrapper 和后端脚本，不要把 PDK 文件提交到公开仓库。

## 20. 相关文档

| 文件 | 内容 |
| --- | --- |
| `readme.me` | 对实验指导书功能要求逐条给出设计证据和验证结果 |
| `doc/README_project_mod.md` | 修改版工程的早期说明 |
| `doc/verification_report.md` | 失败原因、修复说明、验证命令和 PASS 结果 |
| `doc/CHANGELOG.md` | 变更摘要 |
