param(
  [Parameter(Mandatory=$true)]
  [string]$ReportDir,
  [switch]$RequireDsp,
  [double]$MinWns = 0.0
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $ReportDir)) {
  throw "Missing report directory: $ReportDir"
}

$timing = Join-Path $ReportDir "timing_summary_synth.rpt"
$util = Join-Path $ReportDir "utilization_synth.rpt"
$dsp = Join-Path $ReportDir "dsp_utilization_synth.rpt"

foreach ($path in @($timing, $util)) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Missing report: $path"
  }
}

$timingText = Get-Content -Raw $timing
$utilText = Get-Content -Raw $util
$dspText = if (Test-Path -LiteralPath $dsp) { Get-Content -Raw $dsp } else { "" }
$allText = $timingText + "`n" + $utilText + "`n" + $dspText

if ($allText -match "MREG[^\r\n]*(not|missing|warning)|PREG[^\r\n]*(not|missing|warning)|not\s+pipelined|unpipeline|un-pipeline") {
  throw "Rejected OOC report: found DSP pipeline warning text"
}

$wns = $null
$wnsPatterns = @(
  "WNS\(ns\)\s+([-+]?[0-9]*\.?[0-9]+)",
  "WNS\(ns\).*?`r?`n\s*([-+]?[0-9]*\.?[0-9]+)",
  "\|\s*WNS\(ns\)\s*\|\s*TNS\(ns\).*?`r?`n\s*\|\s*([-+]?[0-9]*\.?[0-9]+)\s*\|"
)

foreach ($pattern in $wnsPatterns) {
  $match = [regex]::Match(
    $timingText,
    $pattern,
    [System.Text.RegularExpressions.RegexOptions]::Singleline
  )
  if ($match.Success) {
    $wns = [double]$match.Groups[1].Value
    break
  }
}

if ($null -eq $wns) {
  throw "Could not parse WNS from $timing"
}

if ($wns -lt $MinWns) {
  throw "OOC WNS below threshold: $wns < $MinWns"
}

if ($RequireDsp) {
  $hasDsp = ($utilText -match "DSPs\s*\|\s*[1-9]") -or
            ($utilText -match "DSP48E1\s*\|\s*[1-9]") -or
            ($dspText -match "DSP48E1\s*\|\s*[1-9]") -or
            ($dspText -match "DSPs\s*\|\s*[1-9]")
  if (-not $hasDsp) {
    throw "Required DSP usage was not found in OOC reports"
  }
}

Write-Host "M-unit OOC reports OK"
Write-Host "M_UNIT_OOC_WNS_NS=$wns"
