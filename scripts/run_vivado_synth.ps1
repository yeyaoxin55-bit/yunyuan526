param(
  [string]$VivadoPath = "",
  [string]$Part = "xc7z020clg400-1",
  [string]$Top = "cpu_top",
  [ValidateSet("100m", "125m", "huoyue_uart")]
  [string]$Constraint = "125m",
  [string]$XdcPath = "",
  [string]$OutDir = "build/vivado_synth",
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
$tcl = Join-Path $repoRoot "scripts\vivado_synth.tcl"
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
foreach ($generic in $genericList) {
  $vivadoArgs += @("-generic", $generic)
}

$output = & $vivado @vivadoArgs 2>&1
$output
if ($LASTEXITCODE -ne 0) {
  throw "Vivado synthesis failed"
}

$timingReport = Join-Path $resolvedOutDir "timing_summary_synth.rpt"
$utilReport = Join-Path $resolvedOutDir "utilization_synth.rpt"
if (-not (Test-Path -LiteralPath $timingReport)) {
  throw "Missing timing report: $timingReport"
}
if (-not (Test-Path -LiteralPath $utilReport)) {
  throw "Missing utilization report: $utilReport"
}

Write-Host "Vivado synthesis completed"
