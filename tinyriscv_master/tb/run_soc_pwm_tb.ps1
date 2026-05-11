param(
    [string]$Inst = "",
    [string]$Out = "tinyriscv_soc_pwm_tb.vvp",
    [switch]$Jtag,
    [switch]$NoRun
)

$ErrorActionPreference = "Stop"

$tbDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $tbDir

$rtlDir = Join-Path $tbDir "..\rtl"
$includeDirs = @(
    "..\rtl\core",
    "..\rtl\perips",
    "..\rtl\debug",
    "..\rtl\fpga",
    "..\rtl\soc"
)

$rtlFiles = Get-ChildItem -Path $rtlDir -Recurse -Filter *.v |
    Where-Object {
        $_.FullName -notlike "*uart_debug_old.v" -and
        $_.FullName -notlike "*fpga_top.v"
    } |
    ForEach-Object { $_.FullName }

$iverilogArgs = @("-Wall", "-g2001")

if ($Jtag) {
    $iverilogArgs += "-D"
    $iverilogArgs += "TEST_JTAG"
}

foreach ($dir in $includeDirs) {
    $iverilogArgs += "-I"
    $iverilogArgs += $dir
}

$iverilogArgs += "-o"
$iverilogArgs += $Out
$iverilogArgs += "tinyriscv_soc_pwm_tb.v"
$iverilogArgs += $rtlFiles

Write-Host "==> Compile tinyriscv_soc_pwm_tb.v"
& iverilog @iverilogArgs

if ($NoRun) {
    Write-Host "==> Compile done: $Out"
    exit 0
}

$vvpArgs = @($Out)
if ($Inst -ne "") {
    $vvpArgs += "+INST=$Inst"
}

Write-Host "==> Run simulation"
& vvp @vvpArgs
