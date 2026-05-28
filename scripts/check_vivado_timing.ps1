param(
  [Parameter(Mandatory=$true)][string]$ReportDir,
  [double]$MinWns = 0.0,
  [int]$MaxSetupFailingEndpoints = 0,
  [int]$MaxHoldFailingEndpoints = 0
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$resolvedReportDir = if ([System.IO.Path]::IsPathRooted($ReportDir)) {
  $ReportDir
} else {
  Join-Path $repoRoot $ReportDir
}

$timingReport = Join-Path $resolvedReportDir "timing_summary_post_route.rpt"
if (-not (Test-Path -LiteralPath $timingReport)) {
  throw "Missing post-route timing report: $timingReport"
}

$text = Get-Content -LiteralPath $timingReport -Raw
$summary = [regex]::Match(
  $text,
  "(?m)^\s*(?<wns>-?[0-9]+\.[0-9]+)\s+(?<tns>-?[0-9]+\.[0-9]+)\s+(?<setup>[0-9]+)\s+[0-9]+\s+(?<whs>-?[0-9]+\.[0-9]+)\s+(?<ths>-?[0-9]+\.[0-9]+)\s+(?<hold>[0-9]+)\s+"
)
if (-not $summary.Success) {
  throw "Could not parse timing summary: $timingReport"
}

$wns = [double]$summary.Groups["wns"].Value
$tns = [double]$summary.Groups["tns"].Value
$setupFail = [int]$summary.Groups["setup"].Value
$whs = [double]$summary.Groups["whs"].Value
$ths = [double]$summary.Groups["ths"].Value
$holdFail = [int]$summary.Groups["hold"].Value

if ($wns -lt $MinWns) {
  throw "Timing WNS failed: WNS=$wns ns minimum=$MinWns ns report=$timingReport"
}
if ($setupFail -gt $MaxSetupFailingEndpoints) {
  throw "Setup failing endpoints exceeded: setup=$setupFail max=$MaxSetupFailingEndpoints report=$timingReport"
}
if ($holdFail -gt $MaxHoldFailingEndpoints) {
  throw "Hold failing endpoints exceeded: hold=$holdFail max=$MaxHoldFailingEndpoints report=$timingReport"
}

Write-Host "Timing OK: WNS=$wns TNS=$tns SETUP_FAIL=$setupFail WHS=$whs THS=$ths HOLD_FAIL=$holdFail REPORT=$timingReport"
