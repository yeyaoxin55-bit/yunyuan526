$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$cpuCorePath = Join-Path $repoRoot "rtl\cpu_core.v"
$cpuCore = Get-Content -LiteralPath $cpuCorePath -Raw

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

$idJalExpr = Get-WireExpression -Text $cpuCore -Name "id_jal_redirect"
$idJalrExpr = Get-WireExpression -Text $cpuCore -Name "id_jalr_ras_redirect"
$idStageAcceptExpr = Get-WireExpression -Text $cpuCore -Name "id_stage_accept"
$bpJalUpdateExpr = Get-WireExpression -Text $cpuCore -Name "bp_jal_update_raw"
$rasPopReqExpr = Get-WireExpression -Text $cpuCore -Name "ras_pop_req"
$rasPopExpr = Get-WireExpression -Text $cpuCore -Name "ras_pop"

if ($idJalExpr -match "!csr_redirect_detect") {
  throw "id_jal_redirect must not put csr_redirect_detect on the same-cycle PC-select path"
}

if ($idJalrExpr -match "!csr_redirect_detect") {
  throw "id_jalr_ras_redirect must not put csr_redirect_detect on the same-cycle PC-select path"
}

if ($idStageAcceptExpr -notmatch "!csr_redirect_detect") {
  throw "id_stage_accept must still kill younger ID side effects during CSR/trap redirect detection"
}

if ($bpJalUpdateExpr -notmatch "!csr_redirect_detect") {
  throw "bp_jal_update_raw must still be gated by csr_redirect_detect"
}

if ($cpuCore -notmatch "reg\s+ras_pop_q") {
  throw "RAS pop must use a registered side-effect boundary"
}

if ($cpuCore -notmatch "reg\s+ras_push_q") {
  throw "RAS push must use a registered side-effect boundary"
}

if ($rasPopReqExpr -notmatch "id_stage_accept") {
  throw "ras_pop_req must be formed from id_stage_accept so CSR/trap detection kills younger RAS side effects"
}

if ($rasPopExpr -notmatch "ras_pop_q\s*&&\s*!flush") {
  throw "ras_pop must commit only from the registered request and be killed by flush"
}

Write-Host "CSR redirect ID boundary checks passed"
