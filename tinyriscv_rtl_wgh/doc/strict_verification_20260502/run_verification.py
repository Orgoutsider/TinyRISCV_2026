from __future__ import annotations

import json
import os
import shutil
import subprocess
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
REPORT_DIR = ROOT / "doc" / "strict_verification_20260502"
LOG_DIR = REPORT_DIR / "logs"
LOG_DIR.mkdir(parents=True, exist_ok=True)


def rel(path: Path) -> str:
    return str(path.relative_to(ROOT)).replace("/", "\\")


def write_log(name: str, command: str, output: str, returncode: int) -> None:
    text = (
        "===== COMMAND =====\n"
        f"{command}\n"
        "===== OUTPUT =====\n"
        f"{output.rstrip()}\n"
        f"===== EXIT_CODE: {returncode} =====\n"
    )
    (LOG_DIR / f"{name}.log").write_text(text, encoding="utf-8", errors="replace")


def run(name: str, cmd, *, shell: bool = False) -> dict:
    if isinstance(cmd, str):
        command_text = cmd
    else:
        command_text = " ".join(str(x) for x in cmd)
    print(f"===== {name} =====")
    completed = subprocess.run(
        cmd,
        cwd=ROOT,
        shell=shell,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    print(completed.stdout, end="")
    print(f"EXIT_CODE={completed.returncode}")
    write_log(name, command_text, completed.stdout, completed.returncode)
    return {
        "name": name,
        "command": command_text,
        "returncode": completed.returncode,
        "output": completed.stdout,
    }


def clean_generated() -> None:
    for name in (
        "sim_project.vvp",
        "sim_custom_unit.vvp",
        "sim_pwm.vvp",
        "sim_i2c.vvp",
        "sim_mem_bridge.vvp",
        "sim_soc_load.vvp",
        "sim_soc_mem_ops.vvp",
        "sim_chip_sel.vvp",
        "all_rtl_compile.vvp",
    ):
        path = ROOT / name
        if path.exists():
            path.unlink()


def filelist_check() -> dict:
    lines = []
    missing = []
    for raw in (ROOT / "filelist_project.f").read_text(encoding="utf-8").splitlines():
        item = raw.strip()
        if not item or item.startswith("#"):
            continue
        if item.startswith("+"):
            lines.append(f"{item} -> compiler option")
            continue
        path = ROOT / item
        ok = path.exists()
        lines.append(f"{item} -> {ok}")
        if not ok:
            missing.append(item)
    output = "\n".join(lines)
    code = 1 if missing else 0
    write_log("01_filelist_check", "internal Python filelist check", output, code)
    print("===== 01_filelist_check =====")
    print(output)
    print(f"EXIT_CODE={code}")
    return {
        "name": "01_filelist_check",
        "command": "internal Python filelist check",
        "returncode": code,
        "output": output,
        "missing": missing,
    }


def static_line_counts() -> dict:
    roots = ["core", "debug", "perips", "soc", "utils", "fpga", "sim"]
    rows = []
    for folder in roots:
        for path in sorted((ROOT / folder).rglob("*.v")):
            rows.append(f"{rel(path)}\t{len(path.read_text(encoding='utf-8', errors='replace').splitlines())}")
    output = "\n".join(rows)
    write_log("15_line_counts", "internal Python line count", output, 0)
    print("===== 15_line_counts =====")
    print(output)
    print("EXIT_CODE=0")
    return {"name": "15_line_counts", "command": "internal Python line count", "returncode": 0, "output": output}


def module_balance() -> dict:
    roots = ["core", "debug", "perips", "soc", "utils", "fpga"]
    rows = []
    code = 0
    for folder in roots:
        for path in sorted((ROOT / folder).rglob("*.v")):
            lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
            modules = sum(1 for line in lines if line.lstrip().startswith("module "))
            endmodules = sum(1 for line in lines if line.lstrip().startswith("endmodule"))
            if modules != endmodules:
                code = 1
            rows.append(f"{rel(path)}\tmodule={modules}\tendmodule={endmodules}")
    output = "\n".join(rows)
    write_log("16_module_balance", "internal Python module/endmodule balance", output, code)
    print("===== 16_module_balance =====")
    print(output)
    print(f"EXIT_CODE={code}")
    return {"name": "16_module_balance", "command": "internal Python module/endmodule balance", "returncode": code, "output": output}


def tool_versions() -> dict:
    output = []
    for tool in ("iverilog", "vvp"):
        p = shutil.which(tool)
        if p:
            completed = subprocess.run(
                [tool, "-V"],
                cwd=ROOT,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                encoding="utf-8",
                errors="replace",
            )
            output.append(f"$ {tool} -V")
            output.append(completed.stdout.rstrip())
        else:
            output.append(f"{tool}\tNOT_FOUND")
    for tool in ("verilator", "yosys", "pandoc", "wkhtmltopdf", "xelatex", "pdftotext", "python"):
        output.append(f"{tool}\t{shutil.which(tool) or 'NOT_FOUND'}")
    text = "\n".join(output)
    write_log("00_tool_versions", "tool version discovery", text, 0)
    print("===== 00_tool_versions =====")
    print(text)
    print("EXIT_CODE=0")
    return {"name": "00_tool_versions", "command": "tool version discovery", "returncode": 0, "output": text}


def main() -> None:
    for old in LOG_DIR.glob("*.log"):
        old.unlink()
    clean_generated()

    summary = {
        "generated_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "root": str(ROOT),
        "steps": [],
    }

    summary["steps"].append(tool_versions())
    summary["steps"].append(filelist_check())

    rtl_files = sorted(str(Path(p)) for p in (ROOT / "core").rglob("*.v"))
    for folder in ("debug", "perips", "soc", "utils", "fpga"):
        rtl_files.extend(sorted(str(Path(p)) for p in (ROOT / folder).rglob("*.v")))
    rtl_files_rel = [str(Path(p).relative_to(ROOT)) for p in rtl_files]

    summary["steps"].append(run("02_all_rtl_compile", ["iverilog", "-g2012", "-Wall", "-I", "core", "-o", "all_rtl_compile.vvp", *rtl_files_rel]))
    summary["steps"].append(run("03_top_elab", ["iverilog", "-g2012", "-Wall", "-o", "sim_project.vvp", "-s", "tinyriscv_soc_top", "-f", "filelist_project.f"]))
    summary["steps"].append(run("04_tb_custom_unit", "iverilog -g2012 -Wall -I core -o sim_custom_unit.vvp sim\\tb_custom_unit.v core\\custom_unit.v && vvp sim_custom_unit.vvp", shell=True))
    summary["steps"].append(run("05_tb_pwm", "iverilog -g2012 -Wall -I core -o sim_pwm.vvp sim\\tb_pwm.v perips\\pwm.v && vvp sim_pwm.vvp", shell=True))
    summary["steps"].append(run("06_tb_i2c_lm75", "iverilog -g2012 -Wall -I core -o sim_i2c.vvp sim\\tb_i2c_lm75.v perips\\i2c_lm75.v && vvp sim_i2c.vvp", shell=True))
    summary["steps"].append(run("07_tb_mem_bridge", "iverilog -g2012 -Wall -I core -o sim_mem_bridge.vvp sim\\tb_mem_bridge.v perips\\chip_mem_bridge.v fpga\\fpga_mem_bridge.v && vvp sim_mem_bridge.vvp", shell=True))
    summary["steps"].append(run("08_tb_soc_load", "iverilog -g2012 -Wall -I core -o sim_soc_load.vvp -f filelist_project.f sim\\tb_soc_load.v fpga\\fpga_mem_bridge.v && vvp sim_soc_load.vvp", shell=True))
    summary["steps"].append(run("09_tb_soc_mem_ops", "iverilog -g2012 -Wall -I core -o sim_soc_mem_ops.vvp -f filelist_project.f sim\\tb_soc_mem_ops.v fpga\\fpga_mem_bridge.v && vvp sim_soc_mem_ops.vvp", shell=True))
    summary["steps"].append(run("10_tb_chip_sel", "iverilog -g2012 -Wall -I core -o sim_chip_sel.vvp -f filelist_project.f sim\\tb_chip_sel.v fpga\\fpga_mem_bridge.v && vvp sim_chip_sel.vvp", shell=True))

    summary["steps"].append(run("11_static_disallowed_constructs", ["rg", "-n", r"\b(casex|casez|force|release|deassign|forever|wait)\b|\$display|\$finish|\$stop|\$readmemh|1'bx|1'bz|32'hx|\binitial\b", "core", "debug", "perips", "soc", "utils", "fpga"]))
    summary["steps"].append(run("12_static_timing_directives", ["rg", "-n", r"`timescale|timeunit|timeprecision|default_nettype", "core", "debug", "perips", "soc", "utils", "fpga", "sim"]))
    summary["steps"].append(run("13_static_todos_placeholders", ["rg", "-n", r"TODO|FIXME|XXX|Please replace|replace DEFAULT|signoff|流片|占位|placeholder", "core", "debug", "perips", "soc", "utils", "fpga"]))
    summary["steps"].append(run("14_static_tristate_inout", ["rg", "-n", r"\binout\b|1'bz|\btri\b|\btri1\b|\bwand\b|\bwor\b", "core", "debug", "perips", "soc", "utils", "fpga", "sim"]))
    summary["steps"].append(static_line_counts())
    summary["steps"].append(module_balance())

    clean_generated()
    leftovers = sorted(rel(p) for p in ROOT.rglob("*.vvp"))
    leftover_text = "\n".join(leftovers)
    write_log("17_leftover_vvp", "internal Python leftover .vvp scan", leftover_text, 0 if not leftovers else 1)
    summary["leftover_vvp"] = leftovers

    (REPORT_DIR / "verification_summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()

