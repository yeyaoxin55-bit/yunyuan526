$ErrorActionPreference = "Stop"

$iverilog = Get-Command iverilog -ErrorAction SilentlyContinue
if (-not $iverilog) {
  Write-Host "iverilog not found; skipping simulator run"
  exit 0
}

$outDir = "build"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$sources = @(
  "rtl/alu.v",
  "rtl/regfile.v",
  "rtl/decoder.v",
  "rtl/hazard_unit.v",
  "rtl/imem.v",
  "rtl/dmem.v",
  "rtl/cpu_core.v",
  "rtl/cpu_top.v",
  "tb/tb_cpu_top.v"
)

& iverilog -g2012 -I rtl -o "$outDir/tb_cpu_top.vvp" $sources
& vvp "$outDir/tb_cpu_top.vvp"
