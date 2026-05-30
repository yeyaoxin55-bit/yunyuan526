param(
  [Parameter(Mandatory = $true)]
  [string]$IMemHex,
  [string]$DMemHex = "",
  [ValidateSet(32, 64)]
  [int]$XLEN = 64,
  [int]$MaxCycles = 200000,
  [uint32]$DMemBase = 0x00010000,
  [uint32]$PassAddr = 0x00017ff0,
  [uint32]$FailAddr = 0x00017ff4,
  [uint32]$PassValue = 1,
  [uint32]$FailValue = 1,
  [uint32]$ResultAddr = 0,
  [int]$TraceInterval = 0,
  [int]$MulStages = 1,
  [int]$FastMul = 1,
  [int]$LoadRespExForward = 1,
  [int]$LoadControlEarlyReplay = 0,
  [int]$IdLoadEarlyRead = 0,
  [int]$BpBhtDepth = 128,
  [int]$BpBhrWidth = 3,
  [int]$BpBtbDepth = 64,
  [int]$BpLocalHistory = 1,
  [int]$BpInitTaken = 0,
  [switch]$PerfStats,
  [int]$ReplayTrace = 0,
  [int]$ReplayTraceStart = 0,
  [int]$ReplayTraceEnd = 2147483647,
  [int]$MemTraceAddr = -1,
  [int]$MemTraceStart = 0,
  [int]$MemTraceEnd = 2147483647,
  [string]$WaveFile = "",
  [string]$TranscriptFile = "",
  [int]$VlibTimeoutSec = 10,
  [int]$VlogTimeoutSec = 45,
  [int]$VsimTimeoutSec = 120,
  [switch]$LogAllSignals
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path

function Resolve-ArtifactPath {
  param(
    [string]$Path
  )

  if ($Path -eq "") {
    return ""
  }

  $resolved = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $repoRoot $Path }
  $parent = Split-Path -Parent $resolved
  if ($parent -ne "" -and -not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }
  return $resolved
}

function Clear-StaleModelSimLock {
  param([string]$LibraryPath)

  $lockFile = Join-Path $LibraryPath "_lock"
  if (-not (Test-Path -LiteralPath $lockFile)) {
    return
  }

  $lockText = Get-Content -LiteralPath $lockFile -Raw -ErrorAction SilentlyContinue
  $pidMatch = [regex]::Match($lockText, "pid\s*=\s*(\d+)")
  if ($pidMatch.Success) {
    $ownerPid = [int]$pidMatch.Groups[1].Value
    $owner = Get-Process -Id $ownerPid -ErrorAction SilentlyContinue
    if ($owner) {
      throw "ModelSim work library is locked by live process pid=$ownerPid at $lockFile"
    }
  }

  for ($attempt = 1; $attempt -le 20; $attempt++) {
    try {
      Remove-Item -LiteralPath $lockFile -Force -ErrorAction Stop
      Write-Host "Removed stale ModelSim lock: $lockFile"
      return
    } catch {
      Start-Sleep -Milliseconds 250
    }
  }

  throw "Stale ModelSim lock still present after retries: $lockFile"
}

function Quote-ProcessArg {
  param([string]$Arg)

  if ($Arg -match '[\s"]') {
    return '"' + ($Arg -replace '"', '\"') + '"'
  }
  return $Arg
}

function Invoke-ProcessWithTimeout {
  param(
    [string]$FilePath,
    [string[]]$ArgumentList,
    [int]$TimeoutSec,
    [string]$StdoutPath,
    [string]$StderrPath
  )

  $argString = ($ArgumentList | ForEach-Object { Quote-ProcessArg $_ }) -join " "
  $process = Start-Process -FilePath $FilePath `
                           -ArgumentList $argString `
                           -NoNewWindow `
                           -PassThru `
                           -RedirectStandardOutput $StdoutPath `
                           -RedirectStandardError $StderrPath
  if (-not $process.WaitForExit($TimeoutSec * 1000)) {
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    throw "Process timed out after ${TimeoutSec}s: $FilePath $argString"
  }
  return $process.ExitCode
}

$resolvedWaveFile = Resolve-ArtifactPath $WaveFile
$resolvedTranscriptFile = Resolve-ArtifactPath $TranscriptFile

if (-not (Test-Path -LiteralPath $IMemHex)) {
  throw "IMEM hex not found: $IMemHex"
}
if ($DMemHex -ne "" -and -not (Test-Path -LiteralPath $DMemHex)) {
  throw "DMEM hex not found: $DMemHex"
}

$vlib = Get-Command vlib -ErrorAction SilentlyContinue
$vlog = Get-Command vlog -ErrorAction SilentlyContinue
$vsim = Get-Command vsim -ErrorAction SilentlyContinue
if (-not $vlib -or -not $vlog -or -not $vsim) {
  throw "ModelSim commands not found in PATH. Required: vlib, vlog, vsim."
}

$workStamp = "{0}_{1}_{2}" -f $PID, (Get-Date -Format "yyyyMMddHHmmssfff"), ([Guid]::NewGuid().ToString("N").Substring(0, 8))
$workDir = Join-Path "build" ("modelsim_external_{0}" -f $workStamp)
New-Item -ItemType Directory -Force -Path $workDir | Out-Null
$workLib = ((Join-Path $workDir "work") -replace "\\", "/")

$vlibStdoutPath = Join-Path $workDir "vlib_stdout.log"
$vlibStderrPath = Join-Path $workDir "vlib_stderr.log"
$vlibExitCode = Invoke-ProcessWithTimeout -FilePath $vlib.Source `
                                          -ArgumentList @($workLib) `
                                          -TimeoutSec $VlibTimeoutSec `
                                          -StdoutPath $vlibStdoutPath `
                                          -StderrPath $vlibStderrPath
if ($vlibExitCode -ne 0) {
  throw "ModelSim vlib failed; see $vlibStdoutPath and $vlibStderrPath"
}

$sources = @(
  "rtl/alu.v",
  "rtl/regfile.v",
  "rtl/decoder.v",
  "rtl/hazard_unit.v",
  "rtl/imem.v",
  "rtl/dmem.v",
  "rtl/csr_unit.v",
  "rtl/branch_predictor.v",
  "rtl/prefetch.v",
  "rtl/divider.v",
  "rtl/multiplier.v",
  "rtl/cpu_core.v",
  "rtl/cpu_top.v",
  "tb/tb_external_program.v"
)

$vlogStdoutPath = Join-Path $workDir "vlog_stdout.log"
$vlogStderrPath = Join-Path $workDir "vlog_stderr.log"
$vlogArgs = @("-work", $workLib, "+incdir+rtl") + $sources
$vlogExitCode = Invoke-ProcessWithTimeout -FilePath $vlog.Source `
                                          -ArgumentList $vlogArgs `
                                          -TimeoutSec $VlogTimeoutSec `
                                          -StdoutPath $vlogStdoutPath `
                                          -StderrPath $vlogStderrPath
$compileOutput = @()
if (Test-Path -LiteralPath $vlogStdoutPath) {
  $compileOutput += Get-Content -LiteralPath $vlogStdoutPath
}
if (Test-Path -LiteralPath $vlogStderrPath) {
  $compileOutput += Get-Content -LiteralPath $vlogStderrPath
}
$compileOutput
if ($vlogExitCode -ne 0 -or (($compileOutput | Out-String) -match "Errors:\s*[1-9]")) {
  throw "ModelSim vlog failed; see $vlogStdoutPath and $vlogStderrPath"
}
Clear-StaleModelSimLock -LibraryPath $workLib

$resolvedIMem = (Resolve-Path -LiteralPath $IMemHex).Path
$plusargs = @(
  "+IMEM_HEX=$resolvedIMem",
  "+PASS_ADDR=$PassAddr",
  "+FAIL_ADDR=$FailAddr",
  "+PASS_VALUE=$PassValue",
  "+FAIL_VALUE=$FailValue",
  "+RESULT_ADDR=$ResultAddr",
  "+PERF_STATS=$([int]$PerfStats.IsPresent)",
  "+TRACE_INTERVAL=$TraceInterval",
  "+REPLAY_TRACE=$ReplayTrace",
  "+REPLAY_TRACE_START=$ReplayTraceStart",
  "+REPLAY_TRACE_END=$ReplayTraceEnd",
  "+MEM_TRACE_ADDR=$MemTraceAddr",
  "+MEM_TRACE_START=$MemTraceStart",
  "+MEM_TRACE_END=$MemTraceEnd"
)
if ($DMemHex -ne "") {
  $resolvedDMem = (Resolve-Path -LiteralPath $DMemHex).Path
  $plusargs += "+DMEM_HEX=$resolvedDMem"
}

$vsimArgs = @("-c")
if ($resolvedTranscriptFile -ne "") {
  $vsimArgs += @("-l", $resolvedTranscriptFile)
}
if ($resolvedWaveFile -ne "") {
  $vsimArgs += @("-wlf", $resolvedWaveFile)
}
if ($LogAllSignals.IsPresent -or $resolvedWaveFile -ne "") {
  $vsimArgs += "-voptargs=+acc"
}
$vsimArgs += @(
  "-lib", $workLib,
  "tb_external_program",
  "-gXLEN=$XLEN",
  "-gMAX_CYCLES=$MaxCycles",
  "-gDMEM_BASE=$DMemBase",
  "-gMUL_STAGES=$MulStages",
  "-gFAST_MUL=$FastMul",
  "-gENABLE_LOAD_RESP_EX_FORWARD=$LoadRespExForward",
  "-gENABLE_LOAD_CONTROL_EARLY_REPLAY=$LoadControlEarlyReplay",
  "-gENABLE_ID_LOAD_EARLY_READ=$IdLoadEarlyRead",
  "-gBP_BHT_DEPTH=$BpBhtDepth",
  "-gBP_BHR_WIDTH=$BpBhrWidth",
  "-gBP_BTB_DEPTH=$BpBtbDepth",
  "-gBP_LOCAL_HISTORY=$BpLocalHistory",
  "-gBP_INIT_TAKEN=$BpInitTaken"
)
$vsimArgs += $plusargs
$doCommand = if ($LogAllSignals.IsPresent -or $resolvedWaveFile -ne "") { "log -r /*; run -all; quit -f" } else { "run -all; quit -f" }
$vsimArgs += @("-do", $doCommand)

$stdoutPath = Join-Path $workDir "vsim_stdout.log"
$stderrPath = Join-Path $workDir "vsim_stderr.log"
$vsimExitCode = Invoke-ProcessWithTimeout -FilePath $vsim.Source `
                                          -ArgumentList $vsimArgs `
                                          -TimeoutSec $VsimTimeoutSec `
                                          -StdoutPath $stdoutPath `
                                          -StderrPath $stderrPath
$simOutput = @()
if (Test-Path -LiteralPath $stdoutPath) {
  $simOutput += Get-Content -LiteralPath $stdoutPath
}
if (Test-Path -LiteralPath $stderrPath) {
  $simOutput += Get-Content -LiteralPath $stderrPath
}
$simOutput
$simText = $simOutput | Out-String
if ($resolvedTranscriptFile -ne "") {
  Write-Host "MODELSIM_LOG=$resolvedTranscriptFile"
}
if ($resolvedWaveFile -ne "") {
  Write-Host "MODELSIM_WLF=$resolvedWaveFile"
}
if ($vsimExitCode -ne 0 -or $simText -match "FAIL " -or $simText -match "Errors:\s*[1-9]") {
  throw "External ModelSim test failed"
}
