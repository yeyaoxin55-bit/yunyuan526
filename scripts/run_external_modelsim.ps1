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

$workDir = Join-Path "build" ("modelsim_external_{0}" -f $PID)
if (Test-Path -LiteralPath $workDir) {
  Remove-Item -LiteralPath $workDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $workDir | Out-Null
$workLib = ((Join-Path $workDir "work") -replace "\\", "/")

& vlib $workLib

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

$compileOutput = & vlog -work $workLib +incdir+rtl @sources 2>&1
$compileOutput
if ($LASTEXITCODE -ne 0 -or (($compileOutput | Out-String) -match "Errors:\s*[1-9]")) {
  throw "ModelSim vlog failed"
}

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

$simOutput = & vsim @vsimArgs 2>&1
$simOutput
$simText = $simOutput | Out-String
if ($resolvedTranscriptFile -ne "") {
  Write-Host "MODELSIM_LOG=$resolvedTranscriptFile"
}
if ($resolvedWaveFile -ne "") {
  Write-Host "MODELSIM_WLF=$resolvedWaveFile"
}
if ($LASTEXITCODE -ne 0 -or $simText -match "FAIL " -or $simText -match "Errors:\s*[1-9]") {
  throw "External ModelSim test failed"
}
