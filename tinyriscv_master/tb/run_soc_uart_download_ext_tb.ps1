param(
    [string]$FwData = "",
    [string]$Out = "",
    [switch]$NoRun,
    [switch]$Clean
)

$ErrorActionPreference = "Stop"

$tbDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $tbDir

$rtlDir = Join-Path $tbDir "..\rtl"
$repoDir = Resolve-Path (Join-Path $tbDir "..\..")
$buildDir = Join-Path $repoDir "sim_build"
$tbFile = "tinyriscv_soc_uart_download_ext_tb.v"
$vcdFile = "tinyriscv_soc_uart_download_ext_tb.vcd"

if ($Out -eq "") {
    $Out = Join-Path $buildDir "tinyriscv_soc_uart_download_ext_tb.vvp"
}

if (-not (Test-Path $buildDir)) {
    New-Item -ItemType Directory -Path $buildDir | Out-Null
}

if ($Clean) {
    Remove-Item -LiteralPath $Out -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $tbDir $vcdFile) -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $repoDir $vcdFile) -ErrorAction SilentlyContinue
}

if (-not (Get-Command iverilog -ErrorAction SilentlyContinue)) {
    throw "iverilog not found in PATH. Please install Icarus Verilog or add it to PATH."
}

if (-not (Get-Command vvp -ErrorAction SilentlyContinue)) {
    throw "vvp not found in PATH. Please install Icarus Verilog or add it to PATH."
}

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

foreach ($dir in $includeDirs) {
    $iverilogArgs += "-I"
    $iverilogArgs += $dir
}

$iverilogArgs += "-o"
$iverilogArgs += $Out
$iverilogArgs += $tbFile
$iverilogArgs += $rtlFiles

Write-Host "==> Compile/elaborate $tbFile"
& iverilog @iverilogArgs

if ($NoRun) {
    Write-Host "==> Compile done: $Out"
    exit 0
}

$vvpArgs = @($Out)
if ($FwData -ne "") {
    $fwPath = Resolve-Path -Path $FwData
    $vvpArgs += "+FW_DATA=$fwPath"
    Write-Host "==> FW_DATA: $fwPath"
} else {
    Write-Host "==> FW_DATA: default path inside testbench"
}

Write-Host "==> Run simulation"
& vvp @vvpArgs
