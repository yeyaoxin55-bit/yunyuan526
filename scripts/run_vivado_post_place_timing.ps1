param(
  [string]$VivadoPath = "",
  [string]$Part = "xc7z020clg400-1",
  [string]$Top = "soc_top",
  [string]$ProjectPath = "D:\Verilog_prj\yunyuan3_rv64\yunyuan3_rv64.xpr",
  [string]$SourceRtlDir = "rtl",
  [ValidateSet("100m", "125m", "huoyue_uart")]
  [string]$Constraint = "huoyue_uart",
  [string]$XdcPath = "",
  [string]$OutDir = "build/vivado_fast_place",
  [int]$Jobs = 4,
  [string[]]$Generic = @(),
  [string]$PlaceDirective = "Explore",
  [switch]$NoSyncProjectRtl,
  [switch]$AllowIncrementalCheckpoint,
  [switch]$DryRun
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

function Resolve-Xdc {
  param(
    [string]$RepoRoot,
    [string]$Constraint,
    [string]$XdcPath
  )

  $xdc = if ($XdcPath -ne "") {
    if ([System.IO.Path]::IsPathRooted($XdcPath)) {
      $XdcPath
    } else {
      Join-Path $RepoRoot $XdcPath
    }
  } else {
    $xdcName = if ($Constraint -eq "100m") {
      "top_100m.xdc"
    } elseif ($Constraint -eq "huoyue_uart") {
      "tinyriscv_huoyue_uart.xdc"
    } else {
      "top_125m.xdc"
    }
    Join-Path $RepoRoot (Join-Path "constraints" $xdcName)
  }

  if (-not (Test-Path -LiteralPath $xdc)) {
    throw "Missing XDC file: $xdc"
  }
  return (Resolve-Path -LiteralPath $xdc).Path
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$tcl = Join-Path $repoRoot "scripts\vivado_project_fast_timing.tcl"
if (-not (Test-Path -LiteralPath $tcl)) {
  throw "Missing Tcl script: $tcl"
}
$syncScript = Join-Path $repoRoot "scripts\sync_vivado_project_rtl.ps1"
if (-not (Test-Path -LiteralPath $syncScript)) {
  throw "Missing RTL sync script: $syncScript"
}

$project = if ([System.IO.Path]::IsPathRooted($ProjectPath)) {
  $ProjectPath
} else {
  Join-Path $repoRoot $ProjectPath
}
if (-not (Test-Path -LiteralPath $project)) {
  throw "Vivado project not found: $project"
}
$project = (Resolve-Path -LiteralPath $project).Path
$genericList = Normalize-GenericList -Values $Generic
$resolvedOutDir = if ([System.IO.Path]::IsPathRooted($OutDir)) {
  $OutDir
} else {
  Join-Path $repoRoot $OutDir
}

New-Item -ItemType Directory -Force -Path $resolvedOutDir | Out-Null
$resolvedOutDir = (Resolve-Path -LiteralPath $resolvedOutDir).Path

$vivadoArgs = @(
  "-mode", "batch",
  "-source", $tcl,
  "-tclargs",
  "-stage", "place",
  "-project", $project,
  "-top", $Top,
  "-out_dir", $resolvedOutDir,
  "-jobs", $Jobs
)
foreach ($generic in $genericList) {
  $vivadoArgs += @("-generic", $generic)
}
if ($PlaceDirective -ne "") {
  $vivadoArgs += @("-place_directive", $PlaceDirective)
}
if ($AllowIncrementalCheckpoint) {
  $vivadoArgs += "-allow_incremental_checkpoint"
}

Write-Host "Fast timing stage: post-place"
Write-Host "Top: $Top"
Write-Host "Vivado project: $project"
Write-Host "Place directive: $PlaceDirective"
Write-Host "Report dir: $resolvedOutDir"
if ($genericList.Count -gt 0) {
  Write-Host ("Generic overrides: {0}" -f ($genericList -join ", "))
}
if (-not $AllowIncrementalCheckpoint) {
  Write-Host "Incremental checkpoint: disabled for project synth run"
}

if (-not $NoSyncProjectRtl) {
  $syncArgs = @("-SourceRtlDir", $SourceRtlDir, "-ProjectPath", $project)
  if ($DryRun) {
    $syncArgs += "-DryRun"
  }
  & powershell -ExecutionPolicy Bypass -File $syncScript @syncArgs
  if ($LASTEXITCODE -ne 0) {
    throw "Vivado project RTL sync failed"
  }
}

if ($DryRun) {
  Write-Host ("DRY_RUN vivado {0}" -f ($vivadoArgs -join " "))
  Write-Host "Vivado post-place fast timing dry run completed"
  exit 0
}

$vivado = Resolve-Vivado -ExplicitPath $VivadoPath
Write-Host "Vivado: $vivado"

$output = & $vivado @vivadoArgs 2>&1
$output
if ($LASTEXITCODE -ne 0) {
  throw "Vivado post-place fast timing failed"
}

$timingReport = Join-Path $resolvedOutDir "timing_summary_post_place.rpt"
$pathReport = Join-Path $resolvedOutDir "timing_paths_post_place.rpt"
if (-not (Test-Path -LiteralPath $timingReport)) {
  throw "Missing timing report: $timingReport"
}
if (-not (Test-Path -LiteralPath $pathReport)) {
  throw "Missing timing path report: $pathReport"
}

Write-Host "Vivado post-place fast timing completed"
