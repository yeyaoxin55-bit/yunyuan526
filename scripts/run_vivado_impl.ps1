param(
  [string]$VivadoPath = "",
  [string]$Part = "xc7z020clg400-1",
  [string]$Top = "cpu_top",
  [ValidateSet("100m", "125m", "huoyue_uart")]
  [string]$Constraint = "100m",
  [string]$XdcPath = "",
  [string]$FloorplanTcl = "",
  [string]$OutDir = "build/vivado_impl",
  [int]$Jobs = 4,
  [string[]]$Generic = @(),
  [string]$PlaceDirective = "",
  [string]$PhysOptDirective = "",
  [string]$RouteDirective = "",
  [string]$PostRoutePhysOptDirective = ""
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

function Resolve-Vivado {
  param([string]$ExplicitPath)

  if ($ExplicitPath -ne "") {
    if (-not (Test-Path -LiteralPath $ExplicitPath)) {
      throw "VivadoPath not found: $ExplicitPath"
    }
    return (Resolve-Path -LiteralPath $ExplicitPath).Path
  }

  $cmd = Get-Command vivado -ErrorAction SilentlyContinue
  if ($cmd) {
    return $cmd.Source
  }

  $candidateRoots = @("C:\Xilinx\Vivado", "D:\Xilinx\Vivado", "E:\Xilinx\Vivado")
  $candidateVersions = @("2025.2", "2025.1", "2024.2", "2024.1", "2023.2", "2023.1", "2022.2", "2022.1", "2021.2", "2021.1", "2020.2", "2020.1")
  foreach ($root in $candidateRoots) {
    foreach ($version in $candidateVersions) {
      $bat = Join-Path $root (Join-Path $version "bin\vivado.bat")
      $exe = Join-Path $root (Join-Path $version "bin\vivado.exe")
      if (Test-Path -LiteralPath $bat) { return (Resolve-Path -LiteralPath $bat).Path }
      if (Test-Path -LiteralPath $exe) { return (Resolve-Path -LiteralPath $exe).Path }
    }
  }

  throw "Vivado not found. Add vivado to PATH or pass -VivadoPath C:\Xilinx\Vivado\<version>\bin\vivado.bat"
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$tcl = Join-Path $repoRoot "scripts\vivado_impl.tcl"
if (-not (Test-Path -LiteralPath $tcl)) {
  throw "Missing Tcl script: $tcl"
}

$xdc = if ($XdcPath -ne "") {
  if ([System.IO.Path]::IsPathRooted($XdcPath)) {
    $XdcPath
  } else {
    Join-Path $repoRoot $XdcPath
  }
} else {
  $xdcName = if ($Constraint -eq "100m") {
    "top_100m.xdc"
  } elseif ($Constraint -eq "huoyue_uart") {
    "tinyriscv_huoyue_uart.xdc"
  } else {
    "top_125m.xdc"
  }
  Join-Path $repoRoot (Join-Path "constraints" $xdcName)
}
if (-not (Test-Path -LiteralPath $xdc)) {
  throw "Missing XDC file: $xdc"
}
$xdc = (Resolve-Path -LiteralPath $xdc).Path

$resolvedFloorplanTcl = ""
if ($FloorplanTcl -ne "") {
  $resolvedFloorplanTcl = if ([System.IO.Path]::IsPathRooted($FloorplanTcl)) {
    $FloorplanTcl
  } else {
    Join-Path $repoRoot $FloorplanTcl
  }
  if (-not (Test-Path -LiteralPath $resolvedFloorplanTcl)) {
    throw "Missing floorplan Tcl file: $resolvedFloorplanTcl"
  }
  $resolvedFloorplanTcl = (Resolve-Path -LiteralPath $resolvedFloorplanTcl).Path
}

$vivado = Resolve-Vivado -ExplicitPath $VivadoPath
$genericList = Normalize-GenericList -Values $Generic
$resolvedOutDir = if ([System.IO.Path]::IsPathRooted($OutDir)) {
  $OutDir
} else {
  Join-Path $repoRoot $OutDir
}
New-Item -ItemType Directory -Force -Path $resolvedOutDir | Out-Null
$resolvedOutDir = (Resolve-Path -LiteralPath $resolvedOutDir).Path

Write-Host "Vivado: $vivado"
Write-Host "Part: $Part"
Write-Host "Constraint: $xdc"
if ($resolvedFloorplanTcl -ne "") {
  Write-Host "Floorplan Tcl: $resolvedFloorplanTcl"
}
if ($genericList.Count -gt 0) {
  Write-Host ("Generic overrides: {0}" -f ($genericList -join ", "))
}
Write-Host "Report dir: $resolvedOutDir"

$vivadoArgs = @(
  "-mode", "batch",
  "-source", $tcl,
  "-tclargs",
  "-top", $Top,
  "-part", $Part,
  "-xdc", $xdc,
  "-out_dir", $resolvedOutDir,
  "-jobs", $Jobs
)
if ($resolvedFloorplanTcl -ne "") {
  $vivadoArgs += @("-floorplan_tcl", $resolvedFloorplanTcl)
}
foreach ($generic in $genericList) {
  $vivadoArgs += @("-generic", $generic)
}
if ($PlaceDirective -ne "") {
  $vivadoArgs += @("-place_directive", $PlaceDirective)
}
if ($PhysOptDirective -ne "") {
  $vivadoArgs += @("-phys_opt_directive", $PhysOptDirective)
}
if ($RouteDirective -ne "") {
  $vivadoArgs += @("-route_directive", $RouteDirective)
}
if ($PostRoutePhysOptDirective -ne "") {
  $vivadoArgs += @("-post_route_phys_opt_directive", $PostRoutePhysOptDirective)
}

$oldErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$output = & $vivado @vivadoArgs 2>&1 | ForEach-Object { $_.ToString() }
$exitCode = $LASTEXITCODE
$ErrorActionPreference = $oldErrorActionPreference
$output
if ($exitCode -ne 0) {
  throw "Vivado implementation failed"
}

$timingReport = Join-Path $resolvedOutDir "timing_summary_post_route.rpt"
$utilReport = Join-Path $resolvedOutDir "utilization_post_route.rpt"
if (-not (Test-Path -LiteralPath $timingReport)) {
  throw "Missing timing report: $timingReport"
}
if (-not (Test-Path -LiteralPath $utilReport)) {
  throw "Missing utilization report: $utilReport"
}
$bitstream = Join-Path $resolvedOutDir "$Top.bit"
if (-not (Test-Path -LiteralPath $bitstream)) {
  throw "Missing bitstream: $bitstream"
}

Write-Host "Bitstream: $bitstream"
Write-Host "Vivado implementation completed"
