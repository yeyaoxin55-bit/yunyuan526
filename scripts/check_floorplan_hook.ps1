$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path

function Assert-TextContains {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][string]$Pattern,
    [Parameter(Mandatory=$true)][string]$Description
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Missing file for check: $Path"
  }
  $text = Get-Content -LiteralPath $Path -Raw
  if ($text -notmatch $Pattern) {
    throw "Missing $Description in $Path"
  }
}

$runImpl = Join-Path $repoRoot "scripts\run_vivado_impl.ps1"
$implTcl = Join-Path $repoRoot "scripts\vivado_impl.tcl"
$timingSweep = Join-Path $repoRoot "scripts\run_timing_sweep.ps1"
$floorplan = Join-Path $repoRoot "constraints\floorplan_soc_top_light.tcl"

$runImplCommand = Get-Command $runImpl
if (-not $runImplCommand.Parameters.ContainsKey("FloorplanTcl")) {
  throw "scripts\run_vivado_impl.ps1 is missing -FloorplanTcl"
}

Assert-TextContains -Path $implTcl -Pattern '\-floorplan_tcl' -Description "Vivado Tcl -floorplan_tcl parser"
Assert-TextContains -Path $implTcl -Pattern 'source\s+\$floorplan_tcl' -Description "Vivado Tcl floorplan source call"
Assert-TextContains -Path $timingSweep -Pattern 'FloorplanTcl' -Description "timing sweep floorplan forwarding"
Assert-TextContains -Path $floorplan -Pattern 'create_pblock' -Description "floorplan pblock creation"
Assert-TextContains -Path $floorplan -Pattern 'add_cells_to_pblock' -Description "floorplan cell binding"
Assert-TextContains -Path $floorplan -Pattern 'resize_pblock' -Description "floorplan pblock resource range"

Write-Host "Floorplan hook OK"
