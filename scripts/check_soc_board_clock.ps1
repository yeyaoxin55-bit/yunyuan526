$ErrorActionPreference = "Stop"

function Require-File {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Missing required file: $Path"
  }
}

function Require-Pattern {
  param(
    [string]$Name,
    [string]$Text,
    [string]$Pattern
  )
  if ($Text -notmatch $Pattern) {
    throw "Missing expected pattern for ${Name}: $Pattern"
  }
}

function Reject-Pattern {
  param(
    [string]$Name,
    [string]$Text,
    [string]$Pattern
  )
  if ($Text -match $Pattern) {
    throw "Unexpected pattern for ${Name}: $Pattern"
  }
}

Require-File "rtl/clk_gen_50m_to_100m.v"
Require-File "rtl/soc_top.v"
Require-File "scripts/run_modelsim.ps1"
Require-File "scripts/vivado_synth.tcl"
Require-File "scripts/vivado_impl.tcl"

$clkGen = Get-Content -Raw "rtl/clk_gen_50m_to_100m.v"
$socTop = Get-Content -Raw "rtl/soc_top.v"
$modelsim = Get-Content -Raw "scripts/run_modelsim.ps1"
$synthTcl = Get-Content -Raw "scripts/vivado_synth.tcl"
$implTcl = Get-Content -Raw "scripts/vivado_impl.tcl"

Require-Pattern "clock generator module" $clkGen "module\s+clk_gen_50m_to_100m"
Require-Pattern "clock generator MMCM" $clkGen "MMCME2_BASE"
Require-Pattern "clock generator input period" $clkGen "CLKIN1_PERIOD\s*\(\s*20\.000\s*\)"
Require-Pattern "clock generator multiply" $clkGen "CLKFBOUT_MULT_F\s*\(\s*20\.000\s*\)"
Require-Pattern "clock generator output divide" $clkGen "CLKOUT0_DIVIDE_F\s*\(\s*10\.000\s*\)"
Require-Pattern "clock generator BUFG" $clkGen "BUFG"
Require-Pattern "clock generator simulation bypass" $clkGen "`ifndef\s+SYNTHESIS"

Require-Pattern "soc_top UART 100MHz divisor" $socTop "parameter\s+UART_CLKS_PER_BIT\s*=\s*868"
Require-Pattern "soc_top clock generator instance" $socTop "clk_gen_50m_to_100m\s+u_clk_gen"
Require-Pattern "soc_top raw reset" $socTop "wire\s+raw_rst\s*=\s*~sys_rst_n"
Require-Pattern "soc_top locked reset gate" $socTop "wire\s+rst\s*=\s*raw_rst\s*\|\|\s*!clk_locked"
Require-Pattern "soc_top cpu reset gate" $socTop "cpu_rst\s*=\s*rst\s*\|\|\s*!run_armed_q"
Reject-Pattern "soc_top direct sys_clk use" $socTop "wire\s+clk\s*=\s*sys_clk\s*;"

Require-Pattern "ModelSim source list" $modelsim "rtl/clk_gen_50m_to_100m\.v"
Require-Pattern "Vivado synth source list" $synthTcl "clk_gen_50m_to_100m\.v"
Require-Pattern "Vivado impl source list" $implTcl "clk_gen_50m_to_100m\.v"
Require-Pattern "Vivado synth clock report" $synthTcl "report_clocks\s+-file"
Require-Pattern "Vivado impl clock report" $implTcl "report_clocks\s+-file"

Write-Host "soc_top board clocking OK"
