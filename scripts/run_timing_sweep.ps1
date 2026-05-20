param(
  [string]$Top = "soc_top",
  [string]$Part = "xc7z020clg400-1",
  [double[]]$FrequenciesMHz = @(50, 75, 100),
  [ValidateSet("default", "explore", "alt_spread", "extra_net_delay")]
  [string[]]$Strategies = @("default", "explore"),
  [string]$BaseConstraint = "constraints/tinyriscv_huoyue_uart.xdc",
  [string]$FloorplanTcl = "",
  [string]$OutRoot = "build/timing_sweep",
  [string]$CsvPath = "build/timing_sweep/results.csv",
  [int]$Jobs = 4,
  [string[]]$Generic = @()
)

$ErrorActionPreference = "Stop"

function Normalize-GenericList {
  param([string[]]$Values)
  $items = New-Object System.Collections.Generic.List[string]
  foreach ($value in $Values) {
    foreach ($entry in ($value -split "[,;]")) {
      $trimmed = $entry.Trim()
      if ($trimmed -ne "") {
        [void]$items.Add($trimmed)
      }
    }
  }
  return ,$items.ToArray()
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$genericList = Normalize-GenericList -Values $Generic
$resolvedOutRoot = Join-Path $repoRoot $OutRoot
$resolvedCsvPath = Join-Path $repoRoot $CsvPath
$resolvedBaseConstraint = if ([System.IO.Path]::IsPathRooted($BaseConstraint)) {
  $BaseConstraint
} else {
  Join-Path $repoRoot $BaseConstraint
}
if (-not (Test-Path -LiteralPath $resolvedBaseConstraint)) {
  throw "Missing base constraint: $resolvedBaseConstraint"
}
$resolvedFloorplanTcl = ""
if ($FloorplanTcl -ne "") {
  $resolvedFloorplanTcl = if ([System.IO.Path]::IsPathRooted($FloorplanTcl)) {
    $FloorplanTcl
  } else {
    Join-Path $repoRoot $FloorplanTcl
  }
  if (-not (Test-Path -LiteralPath $resolvedFloorplanTcl)) {
    throw "Missing floorplan Tcl: $resolvedFloorplanTcl"
  }
  $resolvedFloorplanTcl = (Resolve-Path -LiteralPath $resolvedFloorplanTcl).Path
}

New-Item -ItemType Directory -Force -Path $resolvedOutRoot | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $resolvedCsvPath) | Out-Null

function Get-ReportCount {
  param(
    [string]$ReportText,
    [string]$SiteType
  )
  $escaped = [regex]::Escape($SiteType)
  $match = [regex]::Match($ReportText, "\|\s*$escaped\s*\|\s*([0-9]+)\s*\|")
  if (-not $match.Success) { return 0 }
  return [int]$match.Groups[1].Value
}

function Get-TimingMetric {
  param(
    [string]$ReportText,
    [string]$Name
  )
  $pattern = switch ($Name) {
    "setup_fail" { "Setup\s+:\s+([0-9]+)\s+Failing Endpoints" }
    "hold_fail" { "Hold\s+:\s+([0-9]+)\s+Failing Endpoints" }
    default { "\b$Name\(ns\)\s+TNS\(ns\)" }
  }
  if ($Name -eq "setup_fail" -or $Name -eq "hold_fail") {
    $match = [regex]::Match($ReportText, $pattern)
    if ($match.Success) { return [int]$match.Groups[1].Value }
    return $null
  }

  $summary = [regex]::Match($ReportText, "(?m)^\s*(-?[0-9]+\.[0-9]+)\s+(-?[0-9]+\.[0-9]+)\s+([0-9]+)\s+")
  if (-not $summary.Success) { return $null }
  if ($Name -eq "WNS") { return [double]$summary.Groups[1].Value }
  if ($Name -eq "TNS") { return [double]$summary.Groups[2].Value }
  return $null
}

$baseLines = Get-Content -LiteralPath $resolvedBaseConstraint
$rows = @()

foreach ($freq in $FrequenciesMHz) {
  if ($freq -le 0) {
    throw "Frequency must be positive: $freq"
  }
  $period = [math]::Round(1000.0 / $freq, 3)
  $freqTag = ("{0:g}" -f $freq).Replace(".", "p")

  foreach ($strategy in $Strategies) {
    $runName = "${Top}_${freqTag}MHz_${strategy}"
    $runDir = Join-Path $resolvedOutRoot $runName
    $xdcPath = Join-Path $runDir "constraint.xdc"
    New-Item -ItemType Directory -Force -Path $runDir | Out-Null

    $newLines = foreach ($line in $baseLines) {
      if ($line -match "^\s*create_clock\s+") {
        "create_clock -period $period -name sys_clk [get_ports sys_clk]"
      } else {
        $line
      }
    }
    Set-Content -LiteralPath $xdcPath -Value $newLines -Encoding ASCII

    $implParams = @{
      Top = $Top
      Part = $Part
      XdcPath = $xdcPath
      OutDir = (Resolve-Path -LiteralPath $runDir).Path
      Jobs = $Jobs
    }
    if ($resolvedFloorplanTcl -ne "") {
      $implParams.FloorplanTcl = $resolvedFloorplanTcl
    }
    if ($genericList.Count -gt 0) {
      $implParams.Generic = $genericList
    }
    if ($strategy -eq "explore") {
      $implParams.PlaceDirective = "Explore"
      $implParams.PhysOptDirective = "AggressiveExplore"
      $implParams.RouteDirective = "Explore"
      $implParams.PostRoutePhysOptDirective = "AggressiveExplore"
    } elseif ($strategy -eq "alt_spread") {
      $implParams.PlaceDirective = "AltSpreadLogic_high"
      $implParams.PhysOptDirective = "AggressiveExplore"
      $implParams.RouteDirective = "Explore"
      $implParams.PostRoutePhysOptDirective = "AggressiveExplore"
    } elseif ($strategy -eq "extra_net_delay") {
      $implParams.PlaceDirective = "ExtraNetDelay_high"
      $implParams.PhysOptDirective = "AggressiveExplore"
      $implParams.RouteDirective = "Explore"
      $implParams.PostRoutePhysOptDirective = "AggressiveExplore"
    }

    $status = "pass"
    $message = ""
    try {
      & (Join-Path $PSScriptRoot "run_vivado_impl.ps1") @implParams
    } catch {
      $status = "fail"
      $message = $_.Exception.Message
    }

    $timingReport = Join-Path $runDir "timing_summary_post_route.rpt"
    $utilReport = Join-Path $runDir "utilization_post_route.rpt"
    $timingText = if (Test-Path -LiteralPath $timingReport) { Get-Content -LiteralPath $timingReport -Raw } else { "" }
    $utilText = if (Test-Path -LiteralPath $utilReport) { Get-Content -LiteralPath $utilReport -Raw } else { "" }
    $wns = if ($timingText -ne "") { Get-TimingMetric -ReportText $timingText -Name "WNS" } else { $null }
    $tns = if ($timingText -ne "") { Get-TimingMetric -ReportText $timingText -Name "TNS" } else { $null }
    $setupFail = if ($timingText -ne "") { Get-TimingMetric -ReportText $timingText -Name "setup_fail" } else { $null }
    $holdFail = if ($timingText -ne "") { Get-TimingMetric -ReportText $timingText -Name "hold_fail" } else { $null }
    if ($status -eq "pass" -and (($setupFail -ne $null -and $setupFail -gt 0) -or ($holdFail -ne $null -and $holdFail -gt 0) -or ($wns -ne $null -and $wns -lt 0))) {
      $status = "timing_fail"
    }

    $rows += [pscustomobject]@{
      top = $Top
      frequency_mhz = $freq
      period_ns = $period
      strategy = $strategy
      status = $status
      wns_ns = $wns
      tns_ns = $tns
      setup_fail_endpoints = $setupFail
      hold_fail_endpoints = $holdFail
      lut = if ($utilText -ne "") { Get-ReportCount -ReportText $utilText -SiteType "Slice LUTs" } else { $null }
      ff = if ($utilText -ne "") { Get-ReportCount -ReportText $utilText -SiteType "Slice Registers" } else { $null }
      bram36 = if ($utilText -ne "") { Get-ReportCount -ReportText $utilText -SiteType "RAMB36E1 only" } else { $null }
      dsp48 = if ($utilText -ne "") { Get-ReportCount -ReportText $utilText -SiteType "DSPs" } else { $null }
      generic = ($genericList -join ";")
      report_dir = $runDir
      message = $message
    }

    $rows | Export-Csv -LiteralPath $resolvedCsvPath -NoTypeInformation -Encoding ASCII
    Write-Host "Sweep row recorded: TOP=$Top FREQ=${freq}MHz STRATEGY=$strategy STATUS=$status"
  }
}

Write-Host "Timing sweep CSV: $resolvedCsvPath"
