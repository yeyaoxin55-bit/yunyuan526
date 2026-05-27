$ErrorActionPreference = "Stop"

$vlib = Get-Command vlib -ErrorAction SilentlyContinue
$vlog = Get-Command vlog -ErrorAction SilentlyContinue
$vsim = Get-Command vsim -ErrorAction SilentlyContinue
if (-not $vlib -or -not $vlog -or -not $vsim) {
  throw "ModelSim commands not found in PATH. Required: vlib, vlog, vsim."
}

$workDir = "build/modelsim_csr_unit"
if (Test-Path -LiteralPath $workDir) {
  Remove-Item -LiteralPath $workDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $workDir | Out-Null
& vlib "$workDir/work"

$sources = @(
  "rtl/csr_unit.v",
  "tb/tb_csr_unit_zicsr.v",
  "tb/tb_csr_unit_trap_mret.v",
  "tb/tb_csr_unit_xlen64.v"
)

$compileOutput = & vlog -work "$workDir/work" +incdir+rtl @sources 2>&1
$compileOutput
if ($LASTEXITCODE -ne 0 -or (($compileOutput | Out-String) -match "Errors:\s*[1-9]")) {
  throw "ModelSim vlog failed"
}

$tests = @(
  "tb_csr_unit_zicsr",
  "tb_csr_unit_trap_mret",
  "tb_csr_unit_xlen64"
)

foreach ($test in $tests) {
  $simOutput = & vsim -c -lib "$workDir/work" $test -do "run -all; quit -f" 2>&1
  $simOutput
  $simText = $simOutput | Out-String
  if ($LASTEXITCODE -ne 0 -or $simText -match "FAIL " -or $simText -match "Errors:\s*[1-9]") {
    if (-not $failedTests) {
      $failedTests = @()
    }
    $failedTests += $test
  }
}

if ($failedTests) {
  throw "CSR unit test failed: $($failedTests -join ', ')"
}
