$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$cpuPath = Join-Path $repoRoot "rtl\cpu_core.v"
$cpu = Get-Content -LiteralPath $cpuPath -Raw

$checks = @(
  @{
    Name = "has registered trap commit valid"
    Pass = $cpu -match "reg\s+csr_trap_commit_q"
  },
  @{
    Name = "has registered mret commit valid"
    Pass = $cpu -match "reg\s+csr_mret_commit_q"
  },
  @{
    Name = "captures trap mtval metadata"
    Pass = $cpu -match "reg\s+\[31:0\]\s+csr_trap_mtval_q"
  },
  @{
    Name = "csr_unit trap commit uses registered request"
    Pass = $cpu -match "\.trap_commit_valid_i\s*\(\s*csr_trap_commit_q\s*\)"
  },
  @{
    Name = "csr_unit mret commit uses registered request"
    Pass = $cpu -match "\.mret_commit_valid_i\s*\(\s*csr_mret_commit_q\s*\)"
  },
  @{
    Name = "direct EX trap detect no longer drives csr_unit trap commit"
    Pass = $cpu -notmatch "\.trap_commit_valid_i\s*\(\s*trap_redirect_detect\s*\)"
  },
  @{
    Name = "direct EX mret detect no longer drives csr_unit mret commit"
    Pass = $cpu -notmatch "\.mret_commit_valid_i\s*\(\s*mret_redirect_detect\s*\)"
  }
)

$failed = @($checks | Where-Object { -not $_.Pass })
if ($failed.Count -ne 0) {
  $failed | ForEach-Object { Write-Error $_.Name }
  exit 1
}

Write-Host "CSR trap commit boundary checks passed"
