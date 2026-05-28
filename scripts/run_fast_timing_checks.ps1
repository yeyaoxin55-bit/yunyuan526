param(
  [ValidateSet("rtl", "synth", "place", "all")]
  [string]$Mode = "rtl",
  [string]$VivadoPath = "",
  [string]$Part = "xc7z020clg400-1",
  [string]$Top = "soc_top",
  [string]$ProjectPath = "D:\Verilog_prj\yunyuan3_rv64\yunyuan3_rv64.xpr",
  [string]$SourceRtlDir = "rtl",
  [ValidateSet("100m", "125m", "huoyue_uart")]
  [string]$Constraint = "huoyue_uart",
  [string]$XdcPath = "",
  [string]$OutDirRoot = "build",
  [int]$Jobs = 4,
  [string[]]$Generic = @(),
  [string]$PlaceDirective = "Explore",
  [switch]$FailOnRtlRisk,
  [switch]$NoSyncProjectRtl,
  [switch]$AllowIncrementalCheckpoint,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Invoke-Script {
  param(
    [string]$Path,
    [string[]]$ArgList
  )

  Write-Host ""
  Write-Host ("==> {0} {1}" -f $Path, ($ArgList -join " "))
  & powershell -ExecutionPolicy Bypass -File $Path @ArgList
  if ($LASTEXITCODE -ne 0) {
    throw "Command failed: $Path"
  }
}

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

$rtlScript = Join-Path $repoRoot "scripts\check_rtl_timing_risk.ps1"
$synthScript = Join-Path $repoRoot "scripts\run_vivado_post_synth_timing.ps1"
$placeScript = Join-Path $repoRoot "scripts\run_vivado_post_place_timing.ps1"

if ($Mode -eq "rtl" -or $Mode -eq "all") {
  $args = @()
  if ($FailOnRtlRisk) {
    $args += "-FailOnRisk"
  }
  Invoke-Script -Path $rtlScript -ArgList $args
}

if ($Mode -eq "synth" -or $Mode -eq "all") {
  $outDir = Join-Path $OutDirRoot "vivado_fast_synth"
  $args = @(
    "-Part", $Part,
    "-Top", $Top,
    "-ProjectPath", $ProjectPath,
    "-SourceRtlDir", $SourceRtlDir,
    "-Constraint", $Constraint,
    "-OutDir", $outDir,
    "-Jobs", "$Jobs"
  )
  if ($VivadoPath -ne "") {
    $args += @("-VivadoPath", $VivadoPath)
  }
  if ($XdcPath -ne "") {
    $args += @("-XdcPath", $XdcPath)
  }
  foreach ($generic in $genericList) {
    $args += @("-Generic", $generic)
  }
  if ($DryRun) {
    $args += "-DryRun"
  }
  if ($NoSyncProjectRtl) {
    $args += "-NoSyncProjectRtl"
  }
  if ($AllowIncrementalCheckpoint) {
    $args += "-AllowIncrementalCheckpoint"
  }
  Invoke-Script -Path $synthScript -ArgList $args
}

if ($Mode -eq "place" -or $Mode -eq "all") {
  $outDir = Join-Path $OutDirRoot "vivado_fast_place"
  $args = @(
    "-Part", $Part,
    "-Top", $Top,
    "-ProjectPath", $ProjectPath,
    "-SourceRtlDir", $SourceRtlDir,
    "-Constraint", $Constraint,
    "-OutDir", $outDir,
    "-Jobs", "$Jobs",
    "-PlaceDirective", $PlaceDirective
  )
  if ($VivadoPath -ne "") {
    $args += @("-VivadoPath", $VivadoPath)
  }
  if ($XdcPath -ne "") {
    $args += @("-XdcPath", $XdcPath)
  }
  foreach ($generic in $genericList) {
    $args += @("-Generic", $generic)
  }
  if ($DryRun) {
    $args += "-DryRun"
  }
  if ($NoSyncProjectRtl) {
    $args += "-NoSyncProjectRtl"
  }
  if ($AllowIncrementalCheckpoint) {
    $args += "-AllowIncrementalCheckpoint"
  }
  Invoke-Script -Path $placeScript -ArgList $args
}

Write-Host ""
Write-Host "Fast timing check flow completed"
