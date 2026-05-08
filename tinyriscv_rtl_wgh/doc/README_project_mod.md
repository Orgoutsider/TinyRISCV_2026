# tinyriscv 课程大作业修改版说明

本目录是基于用户提供的 tinyriscv RTL 做的课程大作业第一版功能修改，目标是对应课件中的以下要求：资源删减、ROM/RAM 移到片外、PWM/I2C 外设添加、以及 sID/rT/if 三条拓展指令。

## 1. 已完成的 RTL 修改

### 1.1 资源删减

- 删除片上 `rom.v`、`ram.v`、`timer.v`、`gpio.v`、`spi.v` 在 SoC 顶层中的实例化。
- 新 SoC 顶层只保留：CPU core、RIB、UART、UART debug、JTAG、片外 ROM/RAM bridge、PWM、I2C。
- `int_i` 固定为 `INT_NONE`，因为 Timer 外设已经移除。

### 1.2 uart_debug packet 缩小到 35 x 8-bit

- 文件：`perips/uart_debug.v`
- 内部接收 buffer 改为：

```verilog
reg [7:0] rx_data[0:34];
```

- 新 packet 长度：35 Byte。
- 当前采用的简化下载协议：
  - byte0：命令，`8'h01` 表示写 payload；
  - byte1..4：base byte address，大端；
  - byte5..32：28 Byte payload，写成 7 个 32-bit word；
  - byte33..34：保留给 CRC，当前版本直接接受。

> 注意：如果助教提供的上位机下载脚本使用了不同 35-byte packet 格式，需要按照脚本格式微调 `uart_debug.v` 中的 packet 解析部分。

### 1.3 ROM/RAM 移到片外

- 芯片侧文件：`perips/chip_mem_bridge.v`
- FPGA 侧文件：`fpga/fpga_mem_bridge.v`
- 芯片顶层新增 8-bit 输入/输出接口：

```verilog
input  wire [7:0] fpga_data_i;
output wire [7:0] fpga_data_o;
```

- FPGA 侧 ROM/RAM 规模：
  - ROM：256 x 32-bit；
  - RAM：16 x 32-bit。

桥接协议采用固定帧格式：

```text
chip -> FPGA:
  0: 0xA5
  1: {we, is_ram, 6'b0}
  2: word_addr[7:0]
  3: wdata[7:0]
  4: wdata[15:8]
  5: wdata[23:16]
  6: wdata[31:24]

FPGA -> chip:
  0: 0x5A
  1: rdata[7:0]
  2: rdata[15:8]
  3: rdata[23:16]
  4: rdata[31:24]
```

### 1.4 PWM 外设

- 文件：`perips/pwm.v`
- 地址空间：`0x6000_0000 ~ 0x6fff_ffff`
- 内部寄存器：

| 地址 | 含义 |
|---|---|
| 0x6000_0000 | A0，PWM0 period |
| 0x6001_0000 | A1，PWM1 period |
| 0x6002_0000 | A2，PWM2 period |
| 0x6003_0000 | A3，PWM3 period |
| 0x6010_0000 | B0，PWM0 high time |
| 0x6011_0000 | B1，PWM1 high time |
| 0x6012_0000 | B2，PWM2 high time |
| 0x6013_0000 | B3，PWM3 high time |
| 0x6004_0000 | C[3:0]，通道使能 |

### 1.5 I2C 外设 / LM75 读温度

- 文件：`perips/i2c_lm75.v`
- 地址空间：`0x7000_0000 ~ 0x7fff_ffff`
- 内部寄存器：

| 地址 | 含义 |
|---|---|
| 0x7000_0000 | CTRL/STATUS，写 bit0 启动一次读；读 bit1=busy，bit2=done |
| 0x7001_0000 | LM75 slave address，默认 0x48 |
| 0x7002_0000 | TX data/reserved |
| 0x7003_0000 | RX data，`{24'h0, temp_msb}` |

`rT` 指令通过 custom sideband 直接触发该 I2C 模块读 LM75，并把 8-bit 温度值写回 `x[rd]`。

### 1.6 拓展指令

新增 opcode/funct3 定义在 `core/defines.v`：

```verilog
`define INST_CUSTOM 7'b0101111
`define INST_SID    3'b000
`define INST_RT     3'b001
`define INST_IFIRE  3'b010
```

实现位置：

- `core/id.v`：完成 custom 指令译码；
- `core/ex.v`：完成 custom 指令发射和 if 指令立即数分支；
- `core/custom_unit.v`：完成多周期 UART/I2C 操作；
- `core/tinyriscv.v`：连接 custom unit 与 UART/I2C sideband。

当前默认 sID 学号为课件示例 `2022123456`，在 `core/custom_unit.v` 里用参数 `DEFAULT_ID0` 到 `DEFAULT_ID9` 表示。正式提交前需要替换成你的实际学号 ASCII。

## 2. 新顶层端口

新的 `tinyriscv_soc_top` 端口相比原始工程删除了 GPIO/SPI，新增：

```verilog
input  wire       chip_sel_i;
input  wire [7:0] fpga_data_i;
output wire [7:0] fpga_data_o;
output wire [3:0] pwm_o;
output wire       i2c_scl;
inout  wire       i2c_sda;
```

`chip_sel_i=0` 时，核心处于 reset，用于后续三颗芯片共享 IO ring 时选择当前工作的芯片。

## 3. 文件列表

使用 `filelist_project.f` 编译芯片侧 RTL。FPGA 侧桥接模块单独放在：

```text
fpga/fpga_mem_bridge.v
```

## 4. 重要工程说明

1. 当前版本是第一版结构性修改，已经尽量保持原 tinyriscv 的接口风格。
2. 本环境没有 iverilog/VCS/DC 等工具，因此没有声称完成编译、仿真或综合回归。
3. 片外 ROM/RAM 的 8-bit 桥接协议已经给出芯片侧与 FPGA 侧配套 RTL，但真实 FPGA 检查时仍建议优先用助教给的 basic/extend/other example 做波形校准。
4. 若助教提供的 UART 下载脚本已经固定 packet 格式，需要用实际脚本重新对齐 `uart_debug.v` 的 byte layout。
5. `custom_unit.v` 中的学号 ASCII 必须在最终版本替换。

## 5. 推荐验证顺序

1. 先只跑基本指令：确认取指/访存桥接能稳定工作。
2. 跑 PWM 读写测试：写 A/B/C 寄存器，观察 `pwm_o[3:0]`。
3. 跑 sID：确认 UART 能回传学号 ASCII。
4. 跑 if：分别测试 `imm != 0`、`imm == 0 && x[rs1] < x31`、`imm == 0 && x[rs1] >= x31` 三条路径。
5. 跑 rT：确认 I2C 读 LM75 的 8-bit 温度值写回 `x[rd]`。

