param(
  [Parameter(Mandatory=$true)][string]$ReportDir,
  [string]$Top = "soc_top",
  [int]$MaxDistributedRam = 64,
  [int]$MinBlockRamTiles = 1,
  [switch]$RequireDmemBlockRam
)

$ErrorActionPreference = "Stop"

$resolvedReportDir = if ([System.IO.Path]::IsPathRooted($ReportDir)) {
  $ReportDir
} else {
  Join-Path (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path $ReportDir
}

$utilReport = Join-Path $resolvedReportDir "utilization_synth.rpt"
if (-not (Test-Path -LiteralPath $utilReport)) {
  $utilReport = Join-Path $resolvedReportDir "utilization_post_route.rpt"
}
if (-not (Test-Path -LiteralPath $utilReport)) {
  throw "Missing utilization report in $resolvedReportDir"
}

$text = Get-Content -LiteralPath $utilReport -Raw
$ramReport = Join-Path $resolvedReportDir "ram_utilization_synth.rpt"
if (-not (Test-Path -LiteralPath $ramReport)) {
  $ramReport = Join-Path $resolvedReportDir "ram_utilization_post_route.rpt"
}
$ramText = if (Test-Path -LiteralPath $ramReport) {
  Get-Content -LiteralPath $ramReport -Raw
} else {
  $text
}

function Get-UsedCount {
  param(
    [string]$ReportText,
    [string]$SiteType
  )
  $escaped = [regex]::Escape($SiteType)
  $match = [regex]::Match($ReportText, "\|\s*$escaped\s*\|\s*([0-9]+)\s*\|")
  if (-not $match.Success) {
    return 0
  }
  return [int]$match.Groups[1].Value
}

$distRam = Get-UsedCount -ReportText $text -SiteType "RAMD64E"
$blockRam = Get-UsedCount -ReportText $text -SiteType "Block RAM Tile"

if ($distRam -gt $MaxDistributedRam) {
  throw "$Top uses too much distributed RAM: RAMD64E=$distRam max=$MaxDistributedRam"
}
if ($blockRam -lt $MinBlockRamTiles) {
  throw "$Top uses too few block RAM tiles: BlockRAM=$blockRam min=$MinBlockRamTiles"
}
if ($RequireDmemBlockRam) {
  if ($ramText -notmatch "u_dmem/.+\|\s+RAMB36E1\s+\|") {
    throw "$Top DMEM is not reported as RAMB36E1 in $ramReport"
  }
  if ($ramText -match "u_dmem/.+RAM64M|u_dmem/.+RAMD64E") {
    throw "$Top DMEM is still using distributed RAM in $ramReport"
  }
}

Write-Host "QoR OK: TOP=$Top RAMD64E=$distRam BlockRAM=$blockRam REPORT=$utilReport"
