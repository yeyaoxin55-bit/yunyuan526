param(
  [string]$VivadoPath = "",
  [string]$ProjectPath = "D:\Verilog_prj\yunyuan3_rv64\yunyuan3_rv64.xpr",
  [string]$SourceRtlDir = "rtl",
  [string]$Top = "soc_top",
  [switch]$NoSyncProjectRtl,
  [switch]$NoResetImpl,
  [switch]$PatchXprOnly,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

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
  $candidateVersions = @("2025.2", "2025.1", "2024.2", "2024.1", "2023.2", "2023.1", "2022.2", "2022.1", "2020.2", "2020.1")
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

function Resolve-PathFromRepo {
  param([string]$Path)
  if ([System.IO.Path]::IsPathRooted($Path)) {
    return $Path
  }
  return (Join-Path $repoRoot $Path)
}

function Disable-XprIncrementalCheckpoint {
  param(
    [string]$ProjectFile,
    [switch]$DryRun
  )

  $text = [System.IO.File]::ReadAllText($ProjectFile)
  $updated = $text

  $updated = [regex]::Replace(
    $updated,
    '(<Run\b[^>]*\bId="synth_1"[^>]*?)\s+AutoIncrementalCheckpoint="true"',
    '$1 AutoIncrementalCheckpoint="false"'
  )
  $updated = [regex]::Replace(
    $updated,
    '(<Run\b[^>]*\bId="synth_1"[^>]*?)\s+IncrementalCheckpoint="[^"]*"',
    '$1'
  )
  $updated = [regex]::Replace(
    $updated,
    '(<Run\b[^>]*\bId="impl_1"[^>]*?)\s+AutoIncrementalCheckpoint="true"',
    '$1 AutoIncrementalCheckpoint="false"'
  )
  $updated = [regex]::Replace(
    $updated,
    '(<Run\b[^>]*\bId="impl_1"[^>]*?)\s+IncrementalCheckpoint="[^"]*"',
    '$1'
  )

  if ($updated -ne $text) {
    if ($DryRun) {
      Write-Host "DRY_RUN would patch XPR incremental checkpoint settings: $ProjectFile"
    } else {
      $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
      [System.IO.File]::WriteAllText($ProjectFile, $updated, $utf8NoBom)
      Write-Host "Patched XPR incremental checkpoint settings: $ProjectFile"
    }
  } else {
    Write-Host "XPR incremental checkpoint settings already disabled: $ProjectFile"
  }
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$tcl = Join-Path $repoRoot "scripts\vivado_project_reset_runs.tcl"
if (-not (Test-Path -LiteralPath $tcl)) {
  throw "Missing Tcl script: $tcl"
}

$project = Resolve-PathFromRepo -Path $ProjectPath
if (-not (Test-Path -LiteralPath $project)) {
  throw "Vivado project not found: $project"
}
$project = (Resolve-Path -LiteralPath $project).Path

Disable-XprIncrementalCheckpoint -ProjectFile $project -DryRun:$DryRun

if ($PatchXprOnly) {
  Write-Host "Vivado project XPR patch completed"
  exit 0
}

if (-not $NoSyncProjectRtl) {
  $syncScript = Join-Path $repoRoot "scripts\sync_vivado_project_rtl.ps1"
  if (-not (Test-Path -LiteralPath $syncScript)) {
    throw "Missing RTL sync script: $syncScript"
  }
  $syncArgs = @("-SourceRtlDir", $SourceRtlDir, "-ProjectPath", $project)
  if ($DryRun) {
    $syncArgs += "-DryRun"
  }
  & powershell -ExecutionPolicy Bypass -File $syncScript @syncArgs
  if ($LASTEXITCODE -ne 0) {
    throw "Vivado project RTL sync failed"
  }
}

$resetImplValue = if ($NoResetImpl) { "0" } else { "1" }
$vivadoArgs = @(
  "-mode", "batch",
  "-source", $tcl,
  "-tclargs",
  "-project", $project,
  "-top", $Top,
  "-reset_impl", $resetImplValue
)

Write-Host "Vivado project: $project"
Write-Host "Top: $Top"
Write-Host "Reset impl_1: $(-not $NoResetImpl)"
Write-Host "Incremental checkpoint: disabled for project runs"

if ($DryRun) {
  Write-Host ("DRY_RUN vivado {0}" -f ($vivadoArgs -join " "))
  Write-Host "Vivado project run reset dry run completed"
  exit 0
}

$vivado = Resolve-Vivado -ExplicitPath $VivadoPath
Write-Host "Vivado: $vivado"

$output = & $vivado @vivadoArgs 2>&1
$output
if ($LASTEXITCODE -ne 0) {
  throw "Vivado project run reset failed"
}

Disable-XprIncrementalCheckpoint -ProjectFile $project
Write-Host "Vivado project runs reset completed"
