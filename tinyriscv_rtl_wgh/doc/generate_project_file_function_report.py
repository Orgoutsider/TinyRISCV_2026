from __future__ import annotations

import html
import re
import subprocess
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "doc"
HTML_PATH = OUT_DIR / "tinyriscv_project_file_function_report.html"
PDF_PATH = OUT_DIR / "tinyriscv_project_file_function_report.pdf"


DESCRIPTION = {
    "README.md": (
        "工程总说明文件，保留 tinyriscv 项目的背景、构建方式、目录说明、SoC/CPU 结构说明以及课程修改后的使用提示。"
        "它是阅读整个仓库的入口，适合先了解处理器、外设、仿真和 FPGA 验证流程。"
    ),
    "readme.me": "补充说明文件，记录本地工程修改、验证或移植过程中的简短备注。",
    "LICENSE": "Apache License 2.0 授权文本，说明原 tinyriscv 代码及派生修改的许可边界。",
    "NOTICE": "第三方或原项目版权提示文件，和 LICENSE 一起用于保留开源合规信息。",
    "filelist_project.f": (
        "芯片侧 SoC 的 Icarus Verilog 编译文件列表。它定义 include 搜索路径，并按依赖顺序列出 utils、core、debug、perips、soc 下的 RTL。"
        "仿真和顶层 elaboration 依赖该文件。"
    ),
    "sim_project.vvp": "Icarus Verilog 编译出的仿真可执行中间文件，通常来自 SoC 级 testbench。",
    "sim_custom_unit.vvp": "custom_unit 单元测试编译产物，用于快速重跑自定义指令单元仿真。",
    "sim_chip_sel.vvp": "chip_sel 顶层隔离测试编译产物，用于验证未选中芯片时输出钳位和复位静默。",

    "core/defines.v": (
        "全局宏定义中心。定义 reset 极性、通用零值、写使能、RIB 请求、暂停等级、中断号、内存映射、寄存器/指令总线宽度、RV32I/M/CSR 指令编码以及课程新增 custom 指令编码。"
        "所有 RTL 基本都 include 此文件。"
    ),
    "core/pc_reg.v": "PC 寄存器模块。负责 reset 到 CpuResetAddr、响应 jump、响应流水线 hold，以及正常 PC+4 取指推进。",
    "core/if_id.v": "IF/ID 流水寄存器。通过 gen_pipe_dff 保存取指得到的指令和 PC，在 hold 时保持，在 reset 时注入 NOP。",
    "core/id.v": (
        "译码级。根据 opcode/funct3/funct7 生成寄存器读地址、操作数、跳转操作数、CSR 地址、写回控制等。"
        "课程 custom 指令 sID/rT/if 在此完成译码并传给 EX。"
    ),
    "core/id_ex.v": "ID/EX 流水寄存器。锁存译码级输出到执行级，使用统一 hold 条件，确保 EX stall 时当前指令保持不变。",
    "core/ex.v": (
        "执行级核心组合逻辑。实现 ALU、乘法、除法启动/写回、load/store 地址和数据处理、分支跳转、CSR 写数据生成、自定义指令握手。"
        "当前版本修复了 custom_start_o 重复拉高问题，sID/rT/if fire 多周期路径只发一次 start，ready 后释放 hold。"
    ),
    "core/div.v": "迭代除法器。接收 dividend/divisor/op/start，busy 期间迭代运算，ready 后返回 DIV/DIVU/REM/REMU 结果和写回寄存器号。",
    "core/regs.v": "32 个通用寄存器堆。支持 EX 写回、JTAG 写寄存器、两个组合读端口以及写后读旁路，x0 恒为 0。",
    "core/csr_reg.v": "CSR 寄存器文件。维护 cycle、mstatus、mie、mtvec、mepc、mcause、mscratch 等机器态 CSR，支持读写和中断相关更新。",
    "core/clint.v": "简化中断/异常控制模块。处理 int_assert、mret、CSR 交互、异常入口地址和流水线暂停请求。",
    "core/ctrl.v": "流水线控制器。合并 EX jump/hold、RIB hold、JTAG halt、CLINT hold，输出 PC/IF/ID 级暂停等级和跳转控制。",
    "core/rib.v": (
        "Reduced RIB 总线互连。仲裁 CPU 数据、取指、JTAG、UART downloader 四个 master。"
        "片外 ROM/RAM 窗口通过多周期 chip_mem_bridge FSM 访问；UART/PWM/I2C 等外设保持单周期 MMIO。"
    ),
    "core/tinyriscv.v": (
        "CPU 核顶层。实例化 pc_reg、if_id、id、id_ex、ex、regs、csr_reg、clint，并连接 RIB 接口、JTAG 寄存器接口和 custom_unit sideband。"
        "还包含片外 load 延迟写回辅助逻辑。"
    ),
    "core/custom_unit.v": (
        "课程 custom 指令执行单元。sID 通过 UART 逐字节发送学号；rT 通过 I2C 读取 LM75 温度并写 rd；if fire 通过 UART 发送 rs1[7:0] 并写 rd=0。"
        "内部有 busy/ready/reg_we 握手和状态机。"
    ),

    "debug/jtag_driver.v": "JTAG TAP/DTM 驱动。工作在 jtag_TCK 时钟域，实现 TAP 状态机、IR/DR 移位、DMI 请求生成和 TDO 输出。",
    "debug/jtag_dm.v": "Debug Module。将 DMI 操作转换成 CPU 寄存器访问、内存访问、halt/reset 请求等调试控制信号。",
    "debug/jtag_top.v": "JTAG 顶层封装。实例化 jtag_driver 和 jtag_dm，连接 TCK/TMS/TDI/TDO 与 SoC 内部调试接口。",

    "perips/uart_shared.v": (
        "当前 SoC 使用的 UART 外设。提供 CTRL/STATUS/BAUD/TX/RX MMIO 寄存器，包含 UART TX/RX bit-level 状态机。"
        "同时支持 custom_unit 通过 custom_tx_valid/data 共享 UART 发送通道。"
    ),
    "perips/uart_debug.v": (
        "UART 固件下载器。作为 RIB master-3，通过 UART 接收固定 35 byte packet，CRC16 校验后按顺序从 ROM_START_ADDR 写入片外 ROM/RAM。"
        "首包解析 fw_file_size，后续包每包写 8 个 32-bit word，并在 ACK/NAK 前等待 UART TX 空闲。"
    ),
    "perips/uart.v": "原始/备用 UART 外设文件。当前顶层使用 uart_shared.v，本文件保留作历史兼容或对照参考。",
    "perips/pwm.v": "PWM 外设。通过 MMIO 配置 period/high_time/enable，输出 4 路 PWM 波形。",
    "perips/i2c_lm75.v": (
        "LM75 温度传感器 I2C master/peripheral wrapper。支持 MMIO start 和 custom rT 请求，输出 busy/done/RX_DATA。"
        "SDA 使用 pad-facing 开漏 inout 语义，reset 时释放 SDA、SCL 保持高。"
    ),
    "perips/chip_mem_bridge.v": (
        "芯片侧片外 ROM/RAM bridge。把 RIB 32-bit 访问转换成 8-bit chip_data_o 帧，等待 FPGA 侧 8'h5A 响应并重组读数据。"
        "是 CPU/uart_debug 访问 FPGA 内部 ROM/RAM 的芯片侧桥。"
    ),

    "soc/tinyriscv_soc_top.v": (
        "SoC 顶层。实例化 CPU、RIB、chip_mem_bridge、UART、UART downloader、PWM、I2C、JTAG。"
        "当前版本加入 chip_sel_i 输出隔离：选中时正常工作，未选中时 core_rst 复位内部逻辑并钳位 UART/PWM/FPGA/JTAG/I2C SCL 等输出。"
    ),

    "utils/gen_dff.v": "参数化 DFF 工具库，包含普通流水寄存器、reset 到 0/1/默认值、带 enable 的 DFF 等基础单元。",
    "utils/gen_buf.v": "参数化同步/缓冲工具模块，供跨模块信号稳定化或简单同步使用。",
    "utils/full_handshake_tx.v": "全握手跨时钟发送端，用于 JTAG/核心等异步域之间传输请求，降低 CDC 风险。",
    "utils/full_handshake_rx.v": "全握手跨时钟接收端，与 full_handshake_tx 配对使用，负责捕获异步请求并返回应答。",

    "fpga/fpga_mem_bridge.v": (
        "FPGA 侧片外存储桥模型/实现。接收芯片侧 8-bit 帧，访问 FPGA 内部 ROM/RAM 数组，返回 8'h5A 和 32-bit 数据。"
        "包含 initial/$readmemh 风格行为，主要用于 FPGA/仿真侧，不属于 ASIC 芯片侧综合 RTL。"
    ),
    "fpga/filelist_fpga_bridge.f": "FPGA bridge 单独编译文件列表，用于只验证 fpga_mem_bridge 或 FPGA 侧模型。",

    "sim/tb_custom_unit.v": "custom_unit testbench。模拟 UART ready、I2C valid/busy，验证 sID/rT/if 三条 custom 指令的 busy/ready/writeback 行为。",
    "sim/tb_pwm.v": "PWM testbench。配置 PWM 寄存器并观察输出占空比/周期行为。",
    "sim/tb_i2c_lm75.v": "I2C LM75 testbench。模拟 SDA 输入响应，验证 I2C 状态机、温度数据和 valid/busy 输出。",
    "sim/tb_mem_bridge.v": "chip_mem_bridge 与 fpga_mem_bridge 联合测试，验证 8-bit 帧、读写 ROM/RAM 和响应拼接。",
    "sim/tb_soc_load.v": "SoC 级取指/load 测试，验证 CPU 通过 RIB 和片外 bridge 读取指令/数据。",
    "sim/tb_soc_mem_ops.v": "SoC 级内存操作测试，覆盖 load/store 以及 byte/halfword/word 对齐和写掩码相关行为。",
    "sim/tb_chip_sel.v": "chip_sel 顶层隔离测试，验证 chip_sel_i=0 时输出钳位、内部 reset、恢复选中后正常启动。",

    "doc/README_project_mod.md": "课程修改版工程说明文档，概述新增外设、片外存储桥、自定义指令和验证方式。",
    "doc/CHANGELOG.md": "工程修改日志，记录从原始 tinyriscv 到课程版本的功能变化、修复点和验证进展。",
    "doc/offchip_memory_access_timing.md": "片外 ROM/RAM 多周期访问时序说明，解释 RIB hold、bridge busy、读写帧和 CPU 等待关系。",
    "doc/verification_report.md": "较早的验证报告或摘要，记录当前工程通过的仿真和静态检查情况。",
    "doc/strict_verification_20260502/assignment_requirements.txt": "课程/作业要求整理文本，用于对照检查项目完成度。",
    "doc/strict_verification_20260502/run_verification.py": "严格验证脚本，自动运行 filelist 检查、编译、testbench、静态扫描并生成 summary/log。",
    "doc/strict_verification_20260502/generate_pdf_report.py": "严格验证报告 PDF 生成脚本，把 summary/log 转成 HTML/PDF。",
    "doc/strict_verification_20260502/verification_summary.json": "严格验证脚本输出的结构化汇总，记录每个步骤的 returncode、输出和状态。",
    "doc/strict_verification_20260502/run_time.txt": "严格验证执行时间记录。",
    "doc/strict_verification_20260502/tinyriscv_strict_verification_report.html": "严格验证 HTML 报告，可在浏览器查看完整检查结果。",
    "doc/strict_verification_20260502/tinyriscv_strict_verification_report.pdf": "严格验证 PDF 报告，用于提交或归档。",
}


def escape(text: object) -> str:
    return html.escape(str(text), quote=True)


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except Exception:
        return ""


def file_type(path: Path) -> str:
    suffix = path.suffix.lower()
    if suffix == ".v":
        return "Verilog RTL/Testbench"
    if suffix in (".md", ".me"):
        return "Markdown/说明文档"
    if suffix == ".f":
        return "Verilog filelist"
    if suffix == ".py":
        return "Python 脚本"
    if suffix == ".json":
        return "JSON 数据"
    if suffix == ".log":
        return "验证日志"
    if suffix == ".txt":
        return "文本"
    if suffix == ".pdf":
        return "PDF 文档"
    if suffix == ".html":
        return "HTML 文档"
    if suffix == ".vvp":
        return "Icarus 仿真产物"
    return suffix[1:] if suffix else "无扩展名文件"


def verilog_details(path: Path, text: str) -> list[str]:
    details: list[str] = []
    modules = re.findall(r"\bmodule\s+([A-Za-z_][A-Za-z0-9_]*)", text)
    if modules:
        details.append("模块: " + ", ".join(modules))
    includes = re.findall(r'`include\s+"([^"]+)"', text)
    if includes:
        details.append("include: " + ", ".join(includes))
    inputs = len(re.findall(r"\binput\b", text))
    outputs = len(re.findall(r"\boutput\b", text))
    inouts = len(re.findall(r"\binout\b", text))
    always_blocks = len(re.findall(r"\balways\s*@", text))
    assigns = len(re.findall(r"\bassign\b", text))
    localparams = len(re.findall(r"\blocalparam\b", text))
    regs = len(re.findall(r"\breg\b", text))
    wires = len(re.findall(r"\bwire\b", text))
    details.append(
        f"结构统计: input声明{inputs}处, output声明{outputs}处, inout声明{inouts}处, "
        f"always块{always_blocks}个, assign{assigns}处, localparam{localparams}处, reg{regs}处, wire{wires}处。"
    )
    states = sorted(set(re.findall(r"\bS_[A-Za-z0-9_]+", text)))
    if states:
        shown = ", ".join(states[:28])
        if len(states) > 28:
            shown += f", ... 共{len(states)}个"
        details.append("状态/阶段标识: " + shown)
    macros = sorted(set(re.findall(r"`[A-Za-z_][A-Za-z0-9_]*", text)))
    if macros:
        shown = ", ".join(macros[:36])
        if len(macros) > 36:
            shown += f", ... 共{len(macros)}个"
        details.append("使用宏: " + shown)
    if "1'bz" in text or "'bz" in text or "'z" in text:
        details.append("注意: 文件包含高阻语义，通常应仅限 pad-facing inout 或 testbench。")
    if "$readmemh" in text or "initial" in text:
        details.append("注意: 文件包含 initial/$readmemh 等仿真/FPGA 常用语义，ASIC 综合前需确认使用边界。")
    return details


def docs_details(path: Path, text: str) -> list[str]:
    if not text:
        return []
    lines = text.splitlines()
    details: list[str] = []
    headings = [line.strip("# ").strip() for line in lines if line.lstrip().startswith("#")]
    if headings:
        shown = "; ".join(headings[:12])
        if len(headings) > 12:
            shown += f"; ... 共{len(headings)}个标题"
        details.append("主要标题: " + shown)
    return details


def log_details(path: Path, text: str) -> list[str]:
    details: list[str] = []
    if "PASS" in text:
        details.append("包含 PASS 结果。")
    if "FAIL" in text or "error" in text.lower():
        details.append("包含 FAIL/error 字样，需结合上下文判断是否为真实失败。")
    if "warning" in text.lower():
        details.append("包含 warning 字样，适合用于后续 warning-free 清理。")
    return details


def generic_description(rel: str, path: Path) -> str:
    if rel in DESCRIPTION:
        return DESCRIPTION[rel]
    if rel.startswith("doc/strict_verification_20260502/logs/"):
        name = path.stem
        return f"严格验证流程的日志文件 {name}，保存对应检查步骤的原始命令输出，用于追踪 PASS/warning/error 细节。"
    return "工程文件。报告生成脚本未配置专门说明，但已记录其类型、大小、行数和可解析结构。"


def row_for_file(path: Path) -> str:
    rel = path.relative_to(ROOT).as_posix()
    text = read_text(path)
    size = path.stat().st_size
    line_count = len(text.splitlines()) if text else 0
    desc = generic_description(rel, path)
    details: list[str] = []
    if path.suffix.lower() == ".v":
        details.extend(verilog_details(path, text))
    elif path.suffix.lower() in (".md", ".me", ".txt", ".html"):
        details.extend(docs_details(path, text))
    elif path.suffix.lower() == ".log":
        details.extend(log_details(path, text))
    elif path.suffix.lower() == ".f":
        entries = [line.strip() for line in text.splitlines() if line.strip() and not line.strip().startswith("+incdir")]
        incdirs = [line.strip() for line in text.splitlines() if line.strip().startswith("+incdir")]
        if incdirs:
            details.append("include路径: " + ", ".join(incdirs))
        if entries:
            details.append("列出源文件: " + ", ".join(entries[:20]) + (f", ... 共{len(entries)}项" if len(entries) > 20 else ""))
    elif path.suffix.lower() == ".json":
        details.append("结构化数据文件，可由脚本读取生成报告或汇总验证结果。")
    elif path.suffix.lower() == ".vvp":
        details.append("二进制/中间仿真产物，不是源代码；可由 vvp 命令运行。")
    elif path.suffix.lower() == ".pdf":
        details.append("已生成的 PDF 文档，通常作为验证或说明材料归档。")

    detail_html = "".join(f"<li>{escape(item)}</li>" for item in details)
    if not detail_html:
        detail_html = "<li>无额外自动解析信息。</li>"

    return f"""
    <section class="file-card">
      <h3>{escape(rel)}</h3>
      <table>
        <tr><th>类型</th><td>{escape(file_type(path))}</td></tr>
        <tr><th>大小</th><td>{size} bytes</td></tr>
        <tr><th>行数</th><td>{line_count}</td></tr>
        <tr><th>功能说明</th><td>{escape(desc)}</td></tr>
      </table>
      <ul>{detail_html}</ul>
    </section>
    """


def group_title(dirname: str) -> str:
    return {
        ".": "根目录",
        "core": "core: CPU 核心 RTL",
        "debug": "debug: JTAG 调试链路",
        "perips": "perips: 片上外设与下载器",
        "soc": "soc: SoC 顶层集成",
        "utils": "utils: 通用基础单元",
        "fpga": "fpga: FPGA 侧存储桥",
        "sim": "sim: testbench",
        "doc": "doc: 工程文档",
    }.get(dirname, dirname)


def find_chrome() -> Path:
    candidates = [
        Path(r"C:\Program Files\Google\Chrome\Application\chrome.exe"),
        Path(r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"),
        Path(r"C:\Program Files\Microsoft\Edge\Application\msedge.exe"),
        Path(r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"),
    ]
    for item in candidates:
        if item.exists():
            return item
    raise RuntimeError("Cannot find Chrome or Edge to print HTML to PDF")


def main() -> None:
    files = sorted([p for p in ROOT.rglob("*") if p.is_file()], key=lambda p: p.relative_to(ROOT).as_posix())
    groups: dict[str, list[Path]] = {}
    for path in files:
        rel = path.relative_to(ROOT)
        top = rel.parts[0] if len(rel.parts) > 1 else "."
        groups.setdefault(top, []).append(path)

    sections = []
    order = [".", "core", "debug", "perips", "soc", "utils", "fpga", "sim", "doc"]
    for group in order:
        if group not in groups:
            continue
        sections.append(f"<h2>{escape(group_title(group))}</h2>")
        for path in groups[group]:
            sections.append(row_for_file(path))

    html_text = f"""<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<title>tinyriscv_project_mod 全文件功能说明</title>
<style>
@page {{ size: A4; margin: 13mm 12mm; }}
body {{
  font-family: "Noto Sans SC", "Microsoft YaHei", "SimSun", Arial, sans-serif;
  color: #162033;
  font-size: 11px;
  line-height: 1.45;
}}
h1 {{ font-size: 24px; color: #102a43; border-bottom: 2px solid #1f4e79; padding-bottom: 8px; }}
h2 {{ font-size: 17px; color: #1f4e79; margin-top: 22px; break-after: avoid; }}
h3 {{ font-size: 13px; color: #263238; margin: 8px 0; break-after: avoid; }}
.meta {{ color: #52616b; margin: 8px 0 16px; }}
.summary {{ border: 1px solid #9fb3c8; background: #f0f6fb; padding: 9px 11px; margin: 12px 0 16px; }}
.file-card {{ break-inside: avoid; border-top: 1px solid #d7dee8; padding-top: 8px; margin-top: 8px; }}
table {{ border-collapse: collapse; width: 100%; margin: 5px 0; }}
th, td {{ border: 1px solid #c7d0dd; padding: 4px 6px; vertical-align: top; }}
th {{ width: 20%; background: #edf2f7; color: #243b53; }}
ul {{ margin-top: 5px; }}
li {{ margin-bottom: 2px; }}
code {{ font-family: Consolas, "Courier New", monospace; }}
</style>
</head>
<body>
<h1>tinyriscv_project_mod 全文件功能说明</h1>
<div class="meta">
生成时间: {escape(datetime.now().strftime("%Y-%m-%d %H:%M:%S"))}<br>
工程路径: {escape(ROOT)}<br>
文件数量: {len(files)}
</div>
<div class="summary">
本报告按工程目录逐一说明每个文件的用途。RTL 文件额外列出模块名、include、always/assign/localparam 等结构统计、状态机标识和使用宏；文档、日志、filelist、仿真产物则说明它们在验证和归档中的作用。
对于源码功能，说明以当前工程实现为准，包含最近修改过的 <code>uart_debug.v</code>、<code>ex.v</code> 和 <code>tinyriscv_soc_top.v</code>。
</div>
{''.join(sections)}
</body>
</html>
"""
    HTML_PATH.write_text(html_text, encoding="utf-8")
    chrome = find_chrome()
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


if __name__ == "__main__":
    main()
