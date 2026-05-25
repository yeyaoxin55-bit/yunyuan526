param(
  [string]$ToolPrefix = "riscv64-unknown-elf-",
  [ValidateSet(32, 64)]
  [int]$XLEN = 64,
  [string]$March = "",
  [string]$Mabi = "",
  [int]$Iterations = 1,
  [int]$TotalDataSize = 2000,
  [int]$MaxCycles = 2000000,
  [uint32]$CpuHz = 100000000,
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
  [string]$OptLevel = "-O3",
  [string]$ExtraCFlags = "-funroll-loops",
  [switch]$PerfStats
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path

$buildArgs = @(
  "-ExecutionPolicy", "Bypass",
  "-File", (Join-Path $repoRoot "scripts\build_coremark.ps1"),
  "-ToolPrefix", $ToolPrefix,
  "-XLEN", $XLEN,
  "-Iterations", $Iterations,
  "-TotalDataSize", $TotalDataSize,
  "-CpuHz", $CpuHz,
  "-OptLevel", $OptLevel
)
if ($March -ne "") {
  $buildArgs += @("-March", $March)
}
if ($Mabi -ne "") {
  $buildArgs += @("-Mabi", $Mabi)
}
if ($ExtraCFlags -ne "") {
  $buildArgs += @("-ExtraCFlags", $ExtraCFlags)
}
$buildOutput = & powershell @buildArgs 2>&1
$buildOutput
if ($LASTEXITCODE -ne 0) {
  throw "CoreMark build failed"
}

$elfLine = $buildOutput | Where-Object { $_ -match "^ELF=" } | Select-Object -Last 1
$objcopyLine = $buildOutput | Where-Object { $_ -match "^OBJCOPY=" } | Select-Object -Last 1
if (-not $elfLine -or -not $objcopyLine) {
  throw "Failed to parse CoreMark build output"
}
$elf = ($elfLine -replace "^ELF=", "").Trim()
$objcopy = ($objcopyLine -replace "^OBJCOPY=", "").Trim()

$hexOutput = & powershell -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\convert_elf_to_hex.ps1") `
  -Elf $elf `
  -Objcopy $objcopy `
  -OutDir (Join-Path $repoRoot "build\coremark\hex") `
  -DMemWordBytes ($XLEN / 8) 2>&1
$hexOutput
if ($LASTEXITCODE -ne 0) {
  throw "CoreMark ELF to hex conversion failed"
}

$imemLine = $hexOutput | Where-Object { $_ -match "^IMEM_HEX=" } | Select-Object -Last 1
$dmemLine = $hexOutput | Where-Object { $_ -match "^DMEM_HEX=" } | Select-Object -Last 1
if (-not $imemLine -or -not $dmemLine) {
  throw "Failed to parse CoreMark hex output"
}
$imem = ($imemLine -replace "^IMEM_HEX=", "").Trim()
$dmem = ($dmemLine -replace "^DMEM_HEX=", "").Trim()

$simArgs = @(
  "-ExecutionPolicy", "Bypass",
  "-File", (Join-Path $repoRoot "scripts\run_external_modelsim.ps1"),
  "-IMemHex", $imem,
  "-DMemHex", $dmem,
  "-MaxCycles", $MaxCycles,
  "-DMemBase", 65536,
  "-XLEN", $XLEN,
  "-PassAddr", 98288,
  "-FailAddr", 98292,
  "-ResultAddr", 98296,
  "-MulStages", $MulStages,
  "-FastMul", $FastMul,
  "-LoadRespExForward", $LoadRespExForward,
  "-LoadControlEarlyReplay", $LoadControlEarlyReplay,
  "-IdLoadEarlyRead", $IdLoadEarlyRead,
  "-BpBhtDepth", $BpBhtDepth,
  "-BpBhrWidth", $BpBhrWidth,
  "-BpBtbDepth", $BpBtbDepth,
  "-BpLocalHistory", $BpLocalHistory,
  "-BpInitTaken", $BpInitTaken
)
if ($PerfStats.IsPresent) {
  $simArgs += "-PerfStats"
}
$simOutput = & powershell @simArgs 2>&1
$simOutput
if ($LASTEXITCODE -ne 0) {
  throw "CoreMark simulation failed"
}

$simText = $simOutput | Out-String
$passMatch = [regex]::Match($simText, "PASS external program completed cycle=(\d+)(?: result=([0-9a-fA-F]+))?")
if ($passMatch.Success) {
  Write-Host ("COREMARK_SIM_CYCLE={0}" -f $passMatch.Groups[1].Value)
  if ($passMatch.Groups[2].Success) {
    Write-Host ("COREMARK_RESULT_CYCLES={0}" -f ([Convert]::ToUInt32($passMatch.Groups[2].Value, 16)))
  }
}

$statsMatch = [regex]::Match($simText, "PERF_STATS retired=(\d+) loads=(\d+) stores=(\d+) branches=(\d+) jumps=(\d+) muls=(\d+) divs=(\d+) load_use_stalls=(\d+) exec_wait_stalls=(\d+)(?: mem_wait_stalls=(\d+))?(?: mul_wait_stalls=(\d+) div_wait_stalls=(\d+))? flushes=(\d+)(?: branch_mispredict_flushes=(\d+) jump_flushes=(\d+) jal_flushes=(\d+) jalr_flushes=(\d+)(?: jal_early_redirects=(\d+))? taken_branches=(\d+) not_taken_branches=(\d+) pred_taken_branches=(\d+))?")
if ($statsMatch.Success) {
  Write-Host ("COREMARK_RETIRED={0}" -f $statsMatch.Groups[1].Value)
  Write-Host ("COREMARK_LOADS={0}" -f $statsMatch.Groups[2].Value)
  Write-Host ("COREMARK_STORES={0}" -f $statsMatch.Groups[3].Value)
  Write-Host ("COREMARK_BRANCHES={0}" -f $statsMatch.Groups[4].Value)
  Write-Host ("COREMARK_JUMPS={0}" -f $statsMatch.Groups[5].Value)
  Write-Host ("COREMARK_MULS={0}" -f $statsMatch.Groups[6].Value)
  Write-Host ("COREMARK_DIVS={0}" -f $statsMatch.Groups[7].Value)
  Write-Host ("COREMARK_LOAD_USE_STALLS={0}" -f $statsMatch.Groups[8].Value)
  Write-Host ("COREMARK_EXEC_WAIT_STALLS={0}" -f $statsMatch.Groups[9].Value)
  if ($statsMatch.Groups[11].Success) {
    Write-Host ("COREMARK_MUL_WAIT_STALLS={0}" -f $statsMatch.Groups[11].Value)
    Write-Host ("COREMARK_DIV_WAIT_STALLS={0}" -f $statsMatch.Groups[12].Value)
  }
  if ($statsMatch.Groups[10].Success) {
    Write-Host ("COREMARK_MEM_WAIT_STALLS={0}" -f $statsMatch.Groups[10].Value)
  }
  Write-Host ("COREMARK_FLUSHES={0}" -f $statsMatch.Groups[13].Value)
  if ($statsMatch.Groups[14].Success) {
    Write-Host ("COREMARK_BRANCH_MISPREDICT_FLUSHES={0}" -f $statsMatch.Groups[14].Value)
    Write-Host ("COREMARK_JUMP_FLUSHES={0}" -f $statsMatch.Groups[15].Value)
    Write-Host ("COREMARK_JAL_FLUSHES={0}" -f $statsMatch.Groups[16].Value)
    Write-Host ("COREMARK_JALR_FLUSHES={0}" -f $statsMatch.Groups[17].Value)
    if ($statsMatch.Groups[18].Success) {
      Write-Host ("COREMARK_JAL_EARLY_REDIRECTS={0}" -f $statsMatch.Groups[18].Value)
    }
    Write-Host ("COREMARK_TAKEN_BRANCHES={0}" -f $statsMatch.Groups[19].Value)
    Write-Host ("COREMARK_NOT_TAKEN_BRANCHES={0}" -f $statsMatch.Groups[20].Value)
    Write-Host ("COREMARK_PRED_TAKEN_BRANCHES={0}" -f $statsMatch.Groups[21].Value)
  }
  if ($passMatch.Success -and $passMatch.Groups[2].Success -and [int]$statsMatch.Groups[1].Value -ne 0) {
    $cycles = [Convert]::ToUInt32($passMatch.Groups[2].Value, 16)
    $retired = [int]$statsMatch.Groups[1].Value
    Write-Host ("COREMARK_CPI={0:N6}" -f ([double]$cycles / [double]$retired))
  }
}
