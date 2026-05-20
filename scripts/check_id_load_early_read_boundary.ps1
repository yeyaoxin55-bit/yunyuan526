param()

$ErrorActionPreference = "Stop"

$cpuCore = Get-Content -Raw "rtl/cpu_core.v"

$checks = @(
  @{
    Name = "ID early read detects load response base dependency";
    Pass = $cpuCore -match "if_id_load_base_load_resp_dep"
  },
  @{
    Name = "ID early read is gated by load response base dependency";
    Pass = $cpuCore -match "id_load_early_read[\s\S]*?!if_id_load_base_load_resp_dep"
  }
)

$failed = @()
foreach ($check in $checks) {
  if (-not $check.Pass) {
    $failed += $check.Name
  }
}

if ($failed.Count -gt 0) {
  Write-Error ("ID load early-read boundary check failed: {0}" -f ($failed -join "; "))
  exit 1
}

Write-Host "ID load early-read boundary OK"
