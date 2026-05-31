$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$cpuPath = Join-Path $repoRoot "rtl\cpu_core.v"
$cpu = Get-Content -LiteralPath $cpuPath -Raw

function Get-WireExpression {
  param(
    [string]$Text,
    [string]$Name
  )

  $match = [regex]::Match(
    $Text,
    "wire\s+(?:\[[^\]]+\]\s+)?$Name\s*=\s*(?<expr>.*?);",
    [System.Text.RegularExpressions.RegexOptions]::Singleline
  )
  if (-not $match.Success) {
    throw "Missing wire expression: $Name"
  }
  return $match.Groups["expr"].Value
}

$branchRawExpr = Get-WireExpression -Text $cpu -Name "bp_branch_update_raw"
$jalRawExpr = Get-WireExpression -Text $cpu -Name "bp_jal_update_raw"

$checks = @(
  @{
    Name = "has registered predictor update valid"
    Pass = $cpu -match "reg\s+bp_update_q"
  },
  @{
    Name = "has registered predictor update pc"
    Pass = $cpu -match "reg\s+\[31:0\]\s+bp_update_pc_q"
  },
  @{
    Name = "branch predictor consumes registered update valid"
    Pass = $cpu -match "\.update_i\s*\(\s*bp_update_q\s*\)"
  },
  @{
    Name = "branch predictor consumes registered update pc"
    Pass = $cpu -match "\.update_pc_i\s*\(\s*bp_update_pc_q\s*\)"
  },
  @{
    Name = "branch predictor consumes registered update taken"
    Pass = $cpu -match "\.actual_taken_i\s*\(\s*bp_update_taken_q\s*\)"
  },
  @{
    Name = "branch predictor consumes registered update target"
    Pass = $cpu -match "\.actual_target_i\s*\(\s*bp_update_target_q\s*\)"
  },
  @{
    Name = "raw branch update is killed by registered flush"
    Pass = $branchRawExpr -match "!flush"
  },
  @{
    Name = "raw jal update is still killed by csr redirect detection"
    Pass = $jalRawExpr -match "!csr_redirect_detect"
  },
  @{
    Name = "direct predictor update valid is removed"
    Pass = $cpu -notmatch "\.update_i\s*\(\s*bp_update\s*\)"
  }
)

$failed = @($checks | Where-Object { -not $_.Pass })
if ($failed.Count -ne 0) {
  $failed | ForEach-Object { Write-Error $_.Name }
  exit 1
}

Write-Host "CSR branch predictor update boundary checks passed"
