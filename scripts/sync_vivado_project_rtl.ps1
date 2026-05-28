param(
  [string]$SourceRtlDir = "rtl",
  [string]$ProjectPath = "D:\Verilog_prj\yunyuan3_rv64\yunyuan3_rv64.xpr",
  [switch]$Prune,
  [switch]$KeepIncrementalCheckpoint,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Resolve-PathFromRepo {
  param([string]$Path)
  $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
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

$resolvedSource = Resolve-PathFromRepo -Path $SourceRtlDir
if (-not (Test-Path -LiteralPath $resolvedSource)) {
  throw "Source RTL directory not found: $resolvedSource"
}
$resolvedSource = (Resolve-Path -LiteralPath $resolvedSource).Path

$resolvedProject = Resolve-PathFromRepo -Path $ProjectPath
if (-not (Test-Path -LiteralPath $resolvedProject)) {
  throw "Vivado project not found: $resolvedProject"
}
$resolvedProject = (Resolve-Path -LiteralPath $resolvedProject).Path
$projectDir = Split-Path -Parent $resolvedProject
$projectName = [System.IO.Path]::GetFileNameWithoutExtension($resolvedProject)
$projectRtlDir = Join-Path $projectDir (Join-Path "$projectName.srcs" "sources_1\imports\rtl")

if (-not (Test-Path -LiteralPath $projectRtlDir)) {
  if ($DryRun) {
    Write-Host "DRY_RUN would create project RTL directory: $projectRtlDir"
  } else {
    New-Item -ItemType Directory -Force -Path $projectRtlDir | Out-Null
  }
}

$sourceFiles = Get-ChildItem -LiteralPath $resolvedSource -File |
  Where-Object { $_.Extension -in @(".v", ".vh", ".sv", ".svh") } |
  Sort-Object Name

if ($sourceFiles.Count -eq 0) {
  throw "No RTL source files found in $resolvedSource"
}

$copied = 0
foreach ($file in $sourceFiles) {
  $target = Join-Path $projectRtlDir $file.Name
  if ($DryRun) {
    Write-Host ("DRY_RUN Copy-Item {0} -> {1}" -f $file.FullName, $target)
  } else {
    Copy-Item -LiteralPath $file.FullName -Destination $target -Force
  }
  $copied++
}

if ($Prune -and (Test-Path -LiteralPath $projectRtlDir)) {
  $sourceNames = New-Object System.Collections.Generic.HashSet[string]
  foreach ($file in $sourceFiles) {
    [void]$sourceNames.Add($file.Name)
  }
  $staleFiles = Get-ChildItem -LiteralPath $projectRtlDir -File |
    Where-Object { $_.Extension -in @(".v", ".vh", ".sv", ".svh") -and -not $sourceNames.Contains($_.Name) }
  foreach ($file in $staleFiles) {
    if ($DryRun) {
      Write-Host ("DRY_RUN Remove stale RTL file {0}" -f $file.FullName)
    } else {
      Remove-Item -LiteralPath $file.FullName -Force
    }
  }
}

if (-not $KeepIncrementalCheckpoint) {
  Disable-XprIncrementalCheckpoint -ProjectFile $resolvedProject -DryRun:$DryRun
}

Write-Host "Source RTL: $resolvedSource"
Write-Host "Vivado project RTL: $projectRtlDir"
Write-Host "RTL files synchronized: $copied"
