$ErrorActionPreference = "Stop"

$cpuCore = Get-Content -Raw "rtl/cpu_core.v"
$socTop = Get-Content -Raw "rtl/soc_top.v"
$fpgaTop = Get-Content -Raw "rtl/fpga_coremark_top.v"
$bp = Get-Content -Raw "rtl/branch_predictor.v"

$checks = @(
  @{ Name = "cpu_core exposes BP_BHT_DEPTH"; Text = $cpuCore; Pattern = "parameter\s+BP_BHT_DEPTH\s*=" },
  @{ Name = "cpu_core passes BP_BHT_DEPTH"; Text = $cpuCore; Pattern = "\.BHT_DEPTH\(BP_BHT_DEPTH\)" },
  @{ Name = "cpu_core passes BP_BTB_DEPTH"; Text = $cpuCore; Pattern = "\.BTB_DEPTH\(BP_BTB_DEPTH\)" },
  @{ Name = "cpu_core passes BP_LOCAL_HISTORY"; Text = $cpuCore; Pattern = "\.LOCAL_HISTORY\(BP_LOCAL_HISTORY\)" },
  @{ Name = "cpu_core passes BP_INIT_TAKEN"; Text = $cpuCore; Pattern = "\.INIT_TAKEN\(BP_INIT_TAKEN\)" },
  @{ Name = "cpu_core passes BP_BTB_INDEX_HASH"; Text = $cpuCore; Pattern = "\.BTB_INDEX_HASH\(BP_BTB_INDEX_HASH\)" },
  @{ Name = "soc_top init-taken default off"; Text = $socTop; Pattern = "parameter\s+BP_INIT_TAKEN\s*=\s*0" },
  @{ Name = "soc_top BTB hash default off"; Text = $socTop; Pattern = "parameter\s+BP_BTB_INDEX_HASH\s*=\s*0" },
  @{ Name = "fpga_coremark_top init-taken default off"; Text = $fpgaTop; Pattern = "parameter\s+BP_INIT_TAKEN\s*=\s*0" },
  @{ Name = "fpga_coremark_top BTB hash default off"; Text = $fpgaTop; Pattern = "parameter\s+BP_BTB_INDEX_HASH\s*=\s*0" },
  @{ Name = "soc_top resource LOCAL_HISTORY default"; Text = $socTop; Pattern = "parameter\s+BP_LOCAL_HISTORY\s*=\s*0" },
  @{ Name = "soc_top resource BHT default"; Text = $socTop; Pattern = "parameter\s+BP_BHT_DEPTH\s*=\s*64" },
  @{ Name = "soc_top resource BTB default"; Text = $socTop; Pattern = "parameter\s+BP_BTB_DEPTH\s*=\s*32" },
  @{ Name = "fpga_coremark_top resource LOCAL_HISTORY default"; Text = $fpgaTop; Pattern = "parameter\s+BP_LOCAL_HISTORY\s*=\s*0" },
  @{ Name = "fpga_coremark_top resource BHT default"; Text = $fpgaTop; Pattern = "parameter\s+BP_BHT_DEPTH\s*=\s*64" },
  @{ Name = "fpga_coremark_top resource BTB default"; Text = $fpgaTop; Pattern = "parameter\s+BP_BTB_DEPTH\s*=\s*32" },
  @{ Name = "branch_predictor removes PHT when local history disabled"; Text = $bp; Pattern = "if\s*\(\s*LOCAL_HISTORY\s*!=\s*0\s*\)\s*begin\s*:\s*gen_local_history" },
  @{ Name = "branch_predictor has no-local-history branch"; Text = $bp; Pattern = "begin\s*:\s*gen_no_local_history" }
)

$failed = @()
foreach ($check in $checks) {
  if ($check.Text -notmatch $check.Pattern) {
    $failed += $check.Name
  }
}

if ($failed.Count -gt 0) {
  Write-Error ("Branch predictor resource profile check failed:`n" + ($failed -join "`n"))
}

Write-Host "Branch predictor resource profile OK"
