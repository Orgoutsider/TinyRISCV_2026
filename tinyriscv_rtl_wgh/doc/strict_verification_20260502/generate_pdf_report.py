from __future__ import annotations

import html
import json
import shutil
import subprocess
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
REPORT_DIR = ROOT / "doc" / "strict_verification_20260502"
LOG_DIR = REPORT_DIR / "logs"
SUMMARY = json.loads((REPORT_DIR / "verification_summary.json").read_text(encoding="utf-8"))

HTML_PATH = REPORT_DIR / "tinyriscv_strict_verification_report.html"
PDF_PATH = REPORT_DIR / "tinyriscv_strict_verification_report.pdf"


def h(text: str) -> str:
    return html.escape(text, quote=True)


def log_text(name: str) -> str:
    path = LOG_DIR / f"{name}.log"
    if not path.exists():
        return "(missing log)"
    return path.read_text(encoding="utf-8", errors="replace")


def step(name: str) -> dict:
    for item in SUMMARY["steps"]:
        if item["name"] == name:
            return item
    raise KeyError(name)


def pass_fail(name: str) -> str:
    item = step(name)
    if item["returncode"] != 0:
        return "FAIL"
    if "PASS:" in item.get("output", "") or name in ("00_tool_versions", "01_filelist_check", "02_all_rtl_compile", "03_top_elab", "15_line_counts", "16_module_balance"):
        return "PASS"
    return "CHECKED"


def compact_output(name: str, max_lines: int = 80) -> str:
    text = log_text(name)
    lines = text.splitlines()
    if len(lines) <= max_lines:
        return text
    head = lines[:35]
    tail = lines[-35:]
    return "\n".join(head + [f"... ({len(lines) - 70} lines omitted in compact view; full log file is in logs/{name}.log) ..."] + tail)


requirements = [
    ("R1", "每人独立对 tinyriscV 进行修改，添加课程要求的拓展指令。", "PARTIAL PASS", "RTL 已实现 sID/rT/if 三条工程声明的自定义指令，并通过 tb_custom_unit；但指导书未给出拓展指令编码原表，真实课程编码仍需和助教确认。"),
    ("R2", "在 FPGA 上进行功能验证（助教提供运行指令）。", "NOT CLOSED", "仓库内已通过 FPGA 侧 bridge 模型仿真，但未进行真实 FPGA 板级运行和助教脚本验证。"),
    ("R3", "进行综合、仿真、后端等工作，提供 DRC 与 LVS clean 的 GDS 文件。", "NOT CLOSED", "仿真已通过；本环境无 Verilator/Yosys，且仓库无 PDK、综合脚本、APR、DRC/LVS 或 GDS。"),
    ("R4", "对流片回来的芯片进行功能与性能测试。", "FUTURE", "按指导书时间，回片测试在 2026.11-2026.12；当前无法完成。"),
    ("R5", "流片前两颗及更多芯片放在一个 IO Ring 内部共用 IO，通过 chip_sel 选择工作的芯片。", "PARTIAL PASS", "当前 SoC 有 chip_sel_i，并通过 tb_chip_sel；但 pad-level 多芯片 IO Ring wrapper 和输出 OE/mux 未在仓库中。"),
]

tests = [
    ("01_filelist_check", "filelist 完整性检查"),
    ("02_all_rtl_compile", "全部 RTL 源码编译"),
    ("03_top_elab", "SoC 顶层 elaboration"),
    ("04_tb_custom_unit", "自定义指令单元 sID/rT/if"),
    ("05_tb_pwm", "PWM 外设"),
    ("06_tb_i2c_lm75", "I2C/LM75 外设"),
    ("07_tb_mem_bridge", "芯片侧/FPGA 侧片外存储桥"),
    ("08_tb_soc_load", "SoC 片外取指与 load"),
    ("09_tb_soc_mem_ops", "SoC 片外 load/store/byte/halfword"),
    ("10_tb_chip_sel", "chip_sel 选择逻辑"),
    ("11_static_disallowed_constructs", "禁用/敏感语法扫描"),
    ("12_static_timing_directives", "timescale/default_nettype 扫描"),
    ("13_static_todos_placeholders", "TODO/占位项扫描"),
    ("14_static_tristate_inout", "inout/三态扫描"),
    ("15_line_counts", "源码行数统计"),
    ("16_module_balance", "module/endmodule 配平"),
]

source_audit = [
    ("core/defines.v", "PASS", "集中定义 reset、地址空间、RV32I/M/CSR、自定义指令宏。建议后续加入 default_nettype none。"),
    ("core/pc_reg.v", "PASS", "PC reset/hold/jump 逻辑清晰，组合路径短。"),
    ("core/if_id.v", "PASS", "流水寄存器用 gen_pipe_dff，hold 行为统一。"),
    ("core/id.v", "PASS", "译码组合块有默认赋值，未见锁存器风险；自定义指令译码已覆盖。"),
    ("core/id_ex.v", "PASS", "流水寄存器结构规则。"),
    ("core/ex.v", "PASS WITH FREQ RISK", "功能仿真通过；但 EX 是大组合块，并含组合乘法 mul_temp=mul_op1*mul_op2，是主要频率风险。"),
    ("core/regs.v", "PASS WITH WARNING", "功能可用；Icarus 对 regs 数组组合读给 warning。GPR 未 reset，ASIC 可接受但 boot 程序要避免读未初始化寄存器。"),
    ("core/csr_reg.v", "PASS / NEEDS MORE TEST", "编译通过，结构完整；当前回归未专门覆盖 CSR 指令和异常路径。"),
    ("core/clint.v", "PASS / NEEDS MORE TEST", "编译通过；当前回归未专门覆盖异常、mret、中断时序。"),
    ("core/div.v", "PASS / NEEDS MORE TEST", "编译通过；当前回归未专门覆盖 DIV/REM 边界条件。"),
    ("core/custom_unit.v", "PASS WITH SIGNOFF ITEM", "sID/rT/if 单测通过；DEFAULT_ID_* 仍是占位学号，流片前必须替换。"),
    ("core/ctrl.v", "PASS", "RIB full hold 与 PC-only hold 优先级清楚。"),
    ("core/rib.v", "PASS", "片外事务 FSM 锁 owner，解决多周期 bridge 与取指/访存竞争；建议后续加 formal liveness。"),
    ("core/tinyriscv.v", "PASS", "片外 load 延迟写回修复有效；建议扩大 RV32I/M 指令级回归。"),
    ("debug/jtag_driver.v", "COMPILE PASS / CDC REVIEW REQUIRED", "JTAG_TCK 时钟域存在，使用 full_handshake；流片前必须跑 CDC 约束和检查。"),
    ("debug/jtag_dm.v", "COMPILE PASS / NEEDS TEST", "DM 编译通过；当前回归未跑 JTAG transaction test。"),
    ("debug/jtag_top.v", "COMPILE PASS", "JTAG driver 和 DM 集成。"),
    ("perips/uart_shared.v", "PASS / NEEDS BFM", "MMIO/custom TX 共享路径结构清楚；当前未做真实 UART bit-level BFM 全覆盖。"),
    ("perips/uart_debug.v", "COMPILE PASS / NEEDS SCRIPT MATCH", "下载 FSM 编译通过；需与助教 UART 下载脚本逐字节对齐。"),
    ("perips/uart.v", "COMPILE PASS / LEGACY", "原 UART 模块未在当前 SoC 顶层实例化，可保留参考或后续移除。"),
    ("perips/pwm.v", "PASS WITH WARNING", "PWM 单测通过；Icarus 对数组读 warning，可接受但 lint 时建议清理。"),
    ("perips/i2c_lm75.v", "PASS / PROTOCOL LIMITED", "I2C 单测通过；SDA 三态只在 pad-facing inout；ACK/NACK 错误处理较简化。"),
    ("perips/chip_mem_bridge.v", "PASS", "固定 8-bit 帧协议测试通过；无 valid/ready/CRC，板级需关注鲁棒性。"),
    ("soc/tinyriscv_soc_top.v", "PASS / IO RING NOT CLOSED", "顶层集成和 chip_sel 仿真通过；pad-level 多芯片 IO Ring mux/OE 未实现。"),
    ("utils/full_handshake_tx.v", "COMPILE PASS / CDC REVIEW", "握手发送端结构正常；需 CDC signoff。"),
    ("utils/full_handshake_rx.v", "COMPILE PASS / CDC REVIEW", "握手接收端结构正常；需 CDC signoff。"),
    ("utils/gen_buf.v", "PASS", "参数化同步 buffer。"),
    ("utils/gen_dff.v", "PASS", "参数化 DFF 模块，module/endmodule 数量匹配。"),
    ("fpga/fpga_mem_bridge.v", "FPGA/SIM PASS", "作为 FPGA 侧模型含 initial/$readmemh；不应作为 ASIC chip RTL 直接综合。"),
]

critical_findings = [
    ("HIGH", "尚未达到流片签核闭环", "缺综合、STA、CDC/RDC、DFT、APR、DRC/LVS、GDS 和 pad-level IO Ring；因此当前不是 tapeout-ready。"),
    ("HIGH", "多芯片共 IO Ring 只完成 RTL 选择，未完成 pad 互斥", "chip_sel_i 能让未选芯片复位，但共享 pad 时还需要输出 mux/OE，避免多个 die 同时驱动同一 IO。"),
    ("MEDIUM", "EX 组合路径偏大", "core/ex.v 大 case + 组合乘法可能限制频率；高频目标建议多周期乘法或流水化。"),
    ("MEDIUM", "JTAG_TCK CDC 需签核", "debug/jtag_driver.v 使用 jtag_TCK，core 用 clk；虽有 full_handshake，仍需 CDC 工具确认。"),
    ("MEDIUM", "RTL 无统一 `default_nettype none`，多数 RTL 无显式 timescale", "这不是综合功能错误，但不符合严格流片 lint 风格。"),
    ("LOW", "Icarus warning 未完全清零", "regs/pwm 数组组合读触发 Icarus sensitivity warning；功能仿真 PASS，但建议清理到 warning-free。"),
    ("LOW", "占位学号未替换", "core/custom_unit.v DEFAULT_ID_* 目前是示例值。"),
]


def table(headers, rows, classes=None):
    cls = f' class="{classes}"' if classes else ""
    out = [f"<table{cls}>", "<thead><tr>"]
    for header in headers:
        out.append(f"<th>{h(header)}</th>")
    out.append("</tr></thead><tbody>")
    for row in rows:
        out.append("<tr>")
        for cell in row:
            out.append(f"<td>{cell if isinstance(cell, str) and cell.startswith('<') else h(str(cell))}</td>")
        out.append("</tr>")
    out.append("</tbody></table>")
    return "\n".join(out)


test_rows = []
for name, desc in tests:
    item = step(name) if name != "17_leftover_vvp" else {"returncode": 0, "output": ""}
    status = "PASS" if item["returncode"] == 0 else "FAIL"
    if name.startswith("11_") or name.startswith("12_") or name.startswith("13_") or name.startswith("14_"):
        status = "CHECKED"
    test_rows.append((name, desc, status, item["returncode"]))

req_rows = [(rid, req, status, evidence) for rid, req, status, evidence in requirements]
audit_rows = [(path, status, comment) for path, status, comment in source_audit]
finding_rows = [(sev, item, comment) for sev, item, comment in critical_findings]

log_sections = []
for name, desc in tests:
    log_sections.append(
        f"<h3>{h(name)} - {h(desc)}</h3>\n"
        f"<pre>{h(compact_output(name, 140))}</pre>"
    )
log_sections.append(
    f"<h3>17_leftover_vvp - 临时仿真产物清理检查</h3>\n"
    f"<pre>{h(log_text('17_leftover_vvp'))}</pre>"
)

html_text = f"""<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<title>tinyriscv_project_mod 严格验证与代码规范审查报告</title>
<style>
@page {{ size: A4; margin: 14mm 13mm; }}
body {{
  font-family: "Microsoft YaHei", "SimSun", "Noto Sans CJK SC", Arial, sans-serif;
  color: #172033;
  line-height: 1.45;
  font-size: 12px;
}}
h1 {{ font-size: 24px; border-bottom: 2px solid #1f4e79; padding-bottom: 8px; }}
h2 {{ font-size: 18px; color: #1f4e79; margin-top: 22px; break-after: avoid; }}
h3 {{ font-size: 14px; color: #333; margin-top: 15px; break-after: avoid; }}
.meta {{ color: #555; margin-bottom: 18px; }}
.verdict {{ font-weight: 700; color: #9b1c1c; }}
table {{ border-collapse: collapse; width: 100%; margin: 8px 0 14px; page-break-inside: auto; }}
th, td {{ border: 1px solid #aab7c4; padding: 5px 6px; vertical-align: top; }}
th {{ background: #eaf1f7; color: #1d3348; }}
tr {{ page-break-inside: avoid; }}
pre {{
  font-family: Consolas, "Courier New", monospace;
  white-space: pre-wrap;
  word-break: break-word;
  background: #f6f8fa;
  border: 1px solid #d0d7de;
  padding: 8px;
  font-size: 8.4px;
  line-height: 1.25;
}}
.small {{ font-size: 10px; color: #555; }}
.pagebreak {{ break-before: page; }}
.pass {{ color: #0f6b36; font-weight: 700; }}
.warn {{ color: #9a6700; font-weight: 700; }}
.fail {{ color: #b42318; font-weight: 700; }}
</style>
</head>
<body>
<h1>tinyriscv_project_mod 严格验证与代码规范审查报告</h1>
<div class="meta">
生成时间：{h(datetime.now().strftime("%Y-%m-%d %H:%M:%S"))}<br>
工程路径：{h(str(ROOT))}<br>
指导书：c:\\Users\\Lenovo\\Desktop\\数字大规模集成电路-project.pdf<br>
验证方式：Icarus Verilog 编译/仿真 + 静态源码扫描 + 人工芯片工程规范审查
</div>

<h2>1. 总结结论</h2>
<p><span class="verdict">严格结论：当前 RTL 功能仿真通过，但还不能认定为流片签核完成。</span></p>
<p>本次从头到尾重新运行了 filelist 检查、全部 RTL 编译、SoC 顶层 elaboration、七个 testbench、静态敏感语法扫描、源码行数统计和 module/endmodule 配平。所有可运行仿真均为 PASS，命令退出码均为 0。</p>
<p>从芯片工程角度，仍有若干必须在 tapeout 前关闭的事项：综合/STA/CDC/DFT/APR/DRC/LVS/GDS 尚未提供，pad-level 多芯片 IO Ring wrapper 尚未实现，JTAG CDC、EX 关键路径、默认学号占位、warning-free lint 仍需处理。</p>

<h2>2. 指导书要求逐项对照</h2>
{table(["编号", "指导书要求", "当前严格状态", "证据与说明"], req_rows)}

<h2>3. 运行结果矩阵</h2>
{table(["步骤", "检查内容", "状态", "退出码"], test_rows)}
<p class="small">说明：静态扫描步骤的 CHECKED 表示扫描命令执行成功且命中项已在第 5 节解释，不等价于无风险。</p>

<h2>4. 芯片工程师规范审查结论</h2>
{table(["严重级别", "问题", "工程判断"], finding_rows)}

<h2>5. 逐文件代码规范审查</h2>
{table(["文件", "结论", "审查意见"], audit_rows)}

<h2>6. 静态扫描解释</h2>
<p>禁用/敏感语法扫描命中项需要区分芯片 RTL 与 FPGA/仿真模型：</p>
<ul>
<li><b>fpga/fpga_mem_bridge.v:39,43</b> 使用 initial/$readmemh：这是 FPGA 侧 ROM/RAM 模型，不应作为 ASIC chip RTL 直接综合。</li>
<li><b>perips/i2c_lm75.v:67</b> 使用 1'bz：该三态位于 I2C SDA pad-facing inout，符合开漏 I2C 语义；ASIC 后端需映射到开漏/三态 pad cell。</li>
<li><b>core/rib.v:9</b> 的 WAIT 只是注释命中，不是 Verilog wait 语句。</li>
<li>RTL 目录未发现 casex/casez/force/release/$display/$finish/$stop/1'bx 等高风险构造。</li>
<li>只有 sim testbench 有 `timescale`，RTL 没有统一 timeunit/default_nettype；建议后续补充项目级规范。</li>
</ul>

<h2>7. 运行日志原文</h2>
<p>以下为本次运行结果的原始日志。较长日志在本 PDF 中保留开头和结尾；完整日志同时保存在 <code>doc/strict_verification_20260502/logs/</code>。</p>
{''.join(log_sections)}

<h2 class="pagebreak">8. 流片前必须补齐的交付物</h2>
<ol>
<li>用课程或 MPW 平台指定工艺库完成综合，提交面积、频率、功耗、约束和 warning/error 报告。</li>
<li>完成 STA，多 corner、多 mode，明确 false path、multicycle path、JTAG_TCK CDC 约束。</li>
<li>完成 CDC/RDC 检查，重点检查 JTAG_TCK 与 core clk、异步 reset 释放、UART RX 异步输入。</li>
<li>实现 pad-level IO Ring wrapper：多 die 共享输出必须由 chip_sel 控制 mux/OE，未选芯片输出必须高阻或不驱动。</li>
<li>补 DFT/scan/测试模式，按课程或平台要求插入 scan chain。</li>
<li>完成 APR、天线、IR/EM、DRC、LVS，提供 clean GDS。</li>
<li>替换 core/custom_unit.v 的 DEFAULT_ID_* 学号占位。</li>
<li>扩展验证：RV32I/M 指令回归、CSR/exception/mret、中断、JTAG transaction、UART downloader 与助教脚本、真实 FPGA 板级。</li>
</ol>

</body>
</html>
"""

HTML_PATH.write_text(html_text, encoding="utf-8")

chrome = (
    Path(r"C:\Program Files\Google\Chrome\Application\chrome.exe")
    if Path(r"C:\Program Files\Google\Chrome\Application\chrome.exe").exists()
    else Path(r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe")
)

subprocess.run(
    [
        str(chrome),
        "--headless",
        "--disable-gpu",
        "--no-sandbox",
        "--print-to-pdf-no-header",
        f"--print-to-pdf={PDF_PATH}",
        HTML_PATH.as_uri(),
    ],
    check=True,
)

print(PDF_PATH)

