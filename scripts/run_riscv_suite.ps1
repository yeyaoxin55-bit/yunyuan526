param(
  [string]$Suite = "rv32ui",
  [string[]]$Tests = @(),
  [string]$ToolPrefix = "xpack-riscv-none-elf-gcc-15.2.0-1\bin\riscv-none-elf-",
  [string]$March = "rv32im_zifencei",
  [string]$Mabi = "ilp32",
  [ValidateSet(32, 64)]
  [int]$XLEN = 32,
  [int]$MaxCycles = 200000,
  [int]$MulStages = 1,
  [int]$FastMul = 1,
  [int]$LoadRespExForward = 1,
  [int]$LoadControlEarlyReplay = 0,
  [int]$IdLoadEarlyRead = 0,
  [int]$BpBhtDepth = 128,
  [int]$BpBhrWidth = 3,
  [int]$BpBtbDepth = 64,
  [int]$BpLocalHistory = 1,
  [int]$BpBtbIndexHash = 0,
  [string]$ArtifactDir = "",
  [switch]$Wave,
  [switch]$LogAllSignals
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$suiteDir = Join-Path $repoRoot (Join-Path "riscv-tests\isa" $Suite)
if (-not (Test-Path -LiteralPath $suiteDir)) {
  throw "Suite not found: $suiteDir"
}

if ($Tests.Count -eq 0) {
  $Tests = Get-ChildItem -Path $suiteDir -File -Filter *.S |
    Sort-Object Name |
    ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) }
} elseif ($Tests.Count -eq 1 -and $Tests[0].Contains(",")) {
  $Tests = $Tests[0] -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
}

if ($ArtifactDir -eq "" -and ($Wave.IsPresent -or $LogAllSignals.IsPresent)) {
  $ArtifactDir = Join-Path (Join-Path "build\modelsim_riscv_artifacts" $Suite) "run"
}
$resolvedArtifactDir = ""
if ($ArtifactDir -ne "") {
  $resolvedArtifactDir = if ([System.IO.Path]::IsPathRooted($ArtifactDir)) { $ArtifactDir } else { Join-Path $repoRoot $ArtifactDir }
  New-Item -ItemType Directory -Force -Path $resolvedArtifactDir | Out-Null
}

$passed = New-Object System.Collections.Generic.List[string]
$failed = New-Object System.Collections.Generic.List[string]

foreach ($test in $Tests) {
  $src = Join-Path $suiteDir "$test.S"
  if (-not (Test-Path -LiteralPath $src)) {
    Write-Host "MISSING $Suite/$test"
    $failed.Add($test)
    continue
  }

  Write-Host "RUN $Suite/$test"
  try {
    $testArgs = @(
      "-TestSource", $src,
      "-ToolPrefix", $ToolPrefix,
      "-March", $March,
      "-Mabi", $Mabi,
      "-XLEN", $XLEN,
      "-MaxCycles", $MaxCycles,
      "-MulStages", $MulStages,
      "-FastMul", $FastMul,
      "-LoadRespExForward", $LoadRespExForward,
      "-LoadControlEarlyReplay", $LoadControlEarlyReplay,
      "-IdLoadEarlyRead", $IdLoadEarlyRead,
      "-BpBhtDepth", $BpBhtDepth,
      "-BpBhrWidth", $BpBhrWidth,
      "-BpBtbDepth", $BpBtbDepth,
      "-BpLocalHistory", $BpLocalHistory,
      "-BpBtbIndexHash", $BpBtbIndexHash
    )
    if ($resolvedArtifactDir -ne "") {
      $safeSuite = $Suite -replace "[^A-Za-z0-9_.-]", "_"
      $safeTest = $test -replace "[^A-Za-z0-9_.-]", "_"
      $artifactBase = "$safeSuite-$safeTest"
      $testArgs += @("-TranscriptFile", (Join-Path $resolvedArtifactDir "$artifactBase.modelsim.log"))
      if ($Wave.IsPresent) {
        $testArgs += @("-WaveFile", (Join-Path $resolvedArtifactDir "$artifactBase.wlf"))
      }
    }
    if ($LogAllSignals.IsPresent -or $Wave.IsPresent) {
      $testArgs += "-LogAllSignals"
    }

    & powershell -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\run_riscv_test.ps1") @testArgs
    if ($LASTEXITCODE -ne 0) {
      throw "non-zero exit"
    }
    $passed.Add($test)
  } catch {
    Write-Host "FAILED $Suite/$test"
    Write-Host $_
    $failed.Add($test)
    break
  }
}

Write-Host ("RISCV_SUITE_PASS={0}" -f ($passed -join ","))
Write-Host ("RISCV_SUITE_FAIL={0}" -f ($failed -join ","))

if ($failed.Count -gt 0) {
  throw "RISC-V suite failed: $($failed -join ',')"
}
