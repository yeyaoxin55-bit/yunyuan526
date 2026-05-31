$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$csrPath = Join-Path $repoRoot "rtl\csr_unit.v"
$csr = Get-Content -LiteralPath $csrPath -Raw

function Get-WireExpression {
  param(
    [string]$Text,
    [string]$Name
  )

  $match = [regex]::Match(
    $Text,
    "wire\s+$Name\s*=\s*(?<expr>.*?);",
    [System.Text.RegularExpressions.RegexOptions]::Singleline
  )
  if (-not $match.Success) {
    throw "Missing wire expression: $Name"
  }
  return $match.Groups["expr"].Value
}

$normalExpr = Get-WireExpression -Text $csr -Name "normal_csr_commit_active"
$counterExpr = Get-WireExpression -Text $csr -Name "csr_commit_counter_write"
$mcycleExpr = Get-WireExpression -Text $csr -Name "csr_commit_mcycle"
$minstretExpr = Get-WireExpression -Text $csr -Name "csr_commit_minstret"

if (($normalExpr -notmatch "trap_commit_valid_i") -or
    ($normalExpr -notmatch "mret_commit_valid_i")) {
  throw "normal CSR state writes must still be lower priority than trap/MRET updates"
}

if (($counterExpr -match "trap_commit_valid_i") -or
    ($counterExpr -match "mret_commit_valid_i") -or
    ($counterExpr -notmatch "csr_commit_do_write")) {
  throw "counter increment suppression must depend on the explicit CSR write request, not EX trap/MRET detection"
}

if ($mcycleExpr -notmatch "csr_commit_counter_write") {
  throw "mcycle increment suppression must use csr_commit_counter_write"
}

if ($minstretExpr -notmatch "csr_commit_counter_write") {
  throw "minstret increment suppression must use csr_commit_counter_write"
}

if ($csr -notmatch "if\s*\(\s*csr_commit_mcycle\s*\)\s*begin") {
  throw "mcycle writes must be handled outside the normal CSR state priority case"
}

if ($csr -notmatch "if\s*\(\s*csr_commit_minstret\s*\)\s*begin") {
  throw "minstret writes must be handled outside the normal CSR state priority case"
}

if ($csr -match 'else if\s*\(\s*normal_csr_commit_active\s*\)\s*begin[\s\S]*`CSR_MCYCLE') {
  throw "normal CSR state priority case must not drive mcycle"
}

if ($csr -match 'else if\s*\(\s*normal_csr_commit_active\s*\)\s*begin[\s\S]*`CSR_MINSTRET') {
  throw "normal CSR state priority case must not drive minstret"
}

Write-Host "CSR counter increment boundary checks passed"
