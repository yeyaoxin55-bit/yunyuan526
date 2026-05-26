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
  "rtl/csr_unit.v",
  "rtl/branch_predictor.v",
  "rtl/prefetch.v",
  "rtl/divider.v",
  "rtl/multiplier.v",
  "rtl/cpu_core.v",
  "rtl/cpu_top.v"
)

$tests = @(
  "tb/tb_cpu_top.v",
  "tb/tb_rv64i_basic.v",
  "tb/tb_rv64m_basic.v"
)

foreach ($test in $tests) {
  $testName = [System.IO.Path]::GetFileNameWithoutExtension($test)
  & iverilog -g2012 -I rtl -s $testName -o "$outDir/$testName.vvp" ($sources + $test)
  if ($LASTEXITCODE -ne 0) {
    throw "iverilog compile failed: $testName"
  }
  & vvp "$outDir/$testName.vvp"
  if ($LASTEXITCODE -ne 0) {
    throw "iverilog simulation failed: $testName"
  }
}
