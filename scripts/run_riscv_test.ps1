param(
  [Parameter(Mandatory = $true)]
  [string]$TestSource,
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
  [string]$WaveFile = "",
  [string]$TranscriptFile = "",
  [switch]$LogAllSignals
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$outDir = Join-Path $repoRoot "build\riscv-tests"
$buildOutput = & powershell -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\build_riscv_test.ps1") `
  -TestSource $TestSource `
  -ToolPrefix $ToolPrefix `
  -March $March `
  -Mabi $Mabi `
  -OutDir $outDir 2>&1
$buildOutput
if ($LASTEXITCODE -ne 0) {
  throw "riscv-test build failed"
}

$elfLine = $buildOutput | Where-Object { $_ -match "^ELF=" } | Select-Object -Last 1
$objcopyLine = $buildOutput | Where-Object { $_ -match "^OBJCOPY=" } | Select-Object -Last 1
if (-not $elfLine -or -not $objcopyLine) {
  throw "Failed to parse build output"
}
$elf = ($elfLine -replace "^ELF=", "").Trim()
$objcopy = ($objcopyLine -replace "^OBJCOPY=", "").Trim()

$hexOutput = & powershell -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\convert_elf_to_hex.ps1") `
  -Elf $elf `
  -Objcopy $objcopy `
  -OutDir (Join-Path $repoRoot "build\riscv-tests\hex") `
  -DMemWordBytes ($XLEN / 8) 2>&1
$hexOutput
if ($LASTEXITCODE -ne 0) {
  throw "ELF to hex conversion failed"
}

$imemLine = $hexOutput | Where-Object { $_ -match "^IMEM_HEX=" } | Select-Object -Last 1
$dmemLine = $hexOutput | Where-Object { $_ -match "^DMEM_HEX=" } | Select-Object -Last 1
if (-not $imemLine -or -not $dmemLine) {
  throw "Failed to parse hex conversion output"
}
$imem = ($imemLine -replace "^IMEM_HEX=", "").Trim()
$dmem = ($dmemLine -replace "^DMEM_HEX=", "").Trim()

$simArgs = @(
  "-IMemHex", $imem,
  "-DMemHex", $dmem,
  "-MaxCycles", $MaxCycles,
  "-XLEN", $XLEN,
  "-DMemBase", 65536,
  "-PassAddr", 98288,
  "-FailAddr", 98292,
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
if ($WaveFile -ne "") {
  $simArgs += @("-WaveFile", $WaveFile)
}
if ($TranscriptFile -ne "") {
  $simArgs += @("-TranscriptFile", $TranscriptFile)
}
if ($LogAllSignals.IsPresent -or $WaveFile -ne "") {
  $simArgs += "-LogAllSignals"
}

& powershell -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\run_external_modelsim.ps1") @simArgs
if ($LASTEXITCODE -ne 0) {
  throw "riscv-test simulation failed"
}
