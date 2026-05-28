$ErrorActionPreference = "Stop"

$multiplier = Get-Content -Raw "rtl/multiplier.v"
$cpuCore = Get-Content -Raw "rtl/cpu_core.v"
$socTop = Get-Content -Raw "rtl/soc_top.v"
$fpgaTop = Get-Content -Raw "rtl/fpga_coremark_top.v"

if ($socTop -notmatch "parameter\s+MUL_STAGES\s*=\s*4") {
  throw "soc_top board default must use MUL_STAGES=4 for the RV64M timing-safe multiplier pipeline."
}

if ($fpgaTop -notmatch "parameter\s+MUL_STAGES\s*=\s*4") {
  throw "fpga_coremark_top default must use MUL_STAGES=4 for the RV64M timing-safe multiplier pipeline."
}

if ($socTop -notmatch "parameter\s+ENABLE_MUL_COMPLETE_FORWARD\s*=\s*0") {
  throw "soc_top board default must disable same-cycle multiply complete forwarding for RV64 timing closure."
}

if ($fpgaTop -notmatch "parameter\s+ENABLE_MUL_COMPLETE_FORWARD\s*=\s*0") {
  throw "fpga_coremark_top default must disable same-cycle multiply complete forwarding for RV64 timing closure."
}

if ($cpuCore -notmatch "parameter\s+ENABLE_MUL_COMPLETE_FORWARD") {
  throw "cpu_core.v must expose ENABLE_MUL_COMPLETE_FORWARD."
}

if ($cpuCore -notmatch "mul_complete_forward_valid\s*=\s*\(FAST_MUL == 0\)\s*&&\s*\(ENABLE_MUL_COMPLETE_FORWARD != 0\)") {
  throw "mul_complete_forward_valid must be gated by ENABLE_MUL_COMPLETE_FORWARD."
}

if ($multiplier -notmatch "gen_rv64_partial_pipeline") {
  throw "multiplier.v must provide the RV64 partial-product pipeline implementation."
}

if ($multiplier -notmatch "sum_valid") {
  throw "multiplier.v must include a registered unsigned partial-sum boundary for the RV64 pipeline."
}

if ($multiplier -notmatch "product_low_unsigned_q") {
  throw "multiplier.v must register product_low_unsigned before sign correction and result selection."
}

if ($multiplier -notmatch "product_high_unsigned_q") {
  throw "multiplier.v must register product_high_unsigned before sign correction and result selection."
}

if ($cpuCore -notmatch "MUL_INTERNAL_EXTRA") {
  throw "cpu_core.v must account for the extra RV64 multiplier sum stage in the multiplier metadata pipeline."
}

$directWidePattern = 'wire\s+signed\s+\[\(2\*XLEN\)-1:0\]\s+product_ss\s*=\s*\$signed\(a_q\)\s*\*\s*\$signed\(b_q\)'
if ($multiplier -match $directWidePattern) {
  throw "multiplier.v still contains the direct XLEN-wide signed product that caused the RV64 DSP cascade timing path."
}

Write-Host "PASS: RV64 multiplier pipeline structure checks passed."
