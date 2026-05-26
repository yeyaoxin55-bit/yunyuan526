param(
  [string]$ToolPrefix = "xpack-riscv-none-elf-gcc-15.2.0-1\bin\riscv-none-elf-",
  [int]$Iterations = 2,
  [int]$TotalDataSize = 2000,
  [int]$MaxCycles = 2000000,
  [uint32]$CpuHz = 100000000,
  [int]$MulStages = 1,
  [int]$FastMul = 0,
  [int]$LoadRespExForward = 1,
  [int]$LoadControlEarlyReplay = 1,
  [int]$IdLoadEarlyRead = 0,
  [int]$BpBhtDepth = 64,
  [int]$BpBhrWidth = 2,
  [int]$BpBtbDepth = 64,
  [int]$BpLocalHistory = 1,
  [int]$BpBtbIndexHash = 0,
  [string]$OptLevel = "-O3",
  [string]$ExtraCFlags = "-funroll-loops",
  [string]$OutDir = "build/coremark/hotspots"
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$resolvedOutDir = Join-Path $repoRoot $OutDir
New-Item -ItemType Directory -Force -Path $resolvedOutDir | Out-Null

function Resolve-RepoTool {
  param([string]$Suffix)
  $candidate = "${ToolPrefix}${Suffix}.exe"
  if (Test-Path -LiteralPath $candidate) {
    return (Resolve-Path -LiteralPath $candidate).Path
  }
  $repoCandidate = Join-Path $repoRoot $candidate
  if (Test-Path -LiteralPath $repoCandidate) {
    return (Resolve-Path -LiteralPath $repoCandidate).Path
  }
  throw "Cannot find tool: $candidate"
}

function Get-CoremarkValue {
  param(
    [string[]]$Lines,
    [string]$Name
  )
  $match = $Lines | Where-Object { $_ -match "^$Name=(.+)$" } | Select-Object -Last 1
  if ($match -and $match -match "^$Name=(.+)$") {
    return $Matches[1].Trim()
  }
  return ""
}

function Get-SymbolTable {
  param([string]$Elf)
  $nm = Resolve-RepoTool "nm"
  $symbols = @()
  & $nm -n $Elf | ForEach-Object {
    if ($_ -match "^([0-9a-fA-F]+)\s+[Tt]\s+(.+)$") {
      $symbols += [pscustomobject]@{
        addr = [Convert]::ToUInt32($Matches[1], 16)
        name = $Matches[2].Trim()
      }
    }
  }
  return $symbols | Sort-Object addr
}

function Resolve-Symbol {
  param(
    [object[]]$Symbols,
    [uint32]$Pc
  )
  $best = $null
  foreach ($sym in $Symbols) {
    if ($sym.addr -le $Pc) {
      $best = $sym
    } else {
      break
    }
  }
  if ($null -eq $best) {
    return [pscustomobject]@{ function = ""; offset = "" }
  }
  return [pscustomobject]@{
    function = $best.name
    offset = ("0x{0:x}" -f ($Pc - [uint32]$best.addr))
  }
}

function Write-CsvRows {
  param(
    [object[]]$Rows,
    [string]$Path
  )
  $Rows |
    Sort-Object @{ Expression = "count"; Descending = $true } |
    Export-Csv -LiteralPath $Path -NoTypeInformation
}

$runArgs = @(
  "-ExecutionPolicy", "Bypass",
  "-File", (Join-Path $repoRoot "scripts\run_coremark.ps1"),
  "-ToolPrefix", $ToolPrefix,
  "-Iterations", $Iterations,
  "-TotalDataSize", $TotalDataSize,
  "-MaxCycles", $MaxCycles,
  "-CpuHz", $CpuHz,
  "-MulStages", $MulStages,
  "-FastMul", $FastMul,
  "-LoadRespExForward", $LoadRespExForward,
  "-LoadControlEarlyReplay", $LoadControlEarlyReplay,
  "-IdLoadEarlyRead", $IdLoadEarlyRead,
  "-BpBhtDepth", $BpBhtDepth,
  "-BpBhrWidth", $BpBhrWidth,
  "-BpBtbDepth", $BpBtbDepth,
  "-BpLocalHistory", $BpLocalHistory,
  "-BpBtbIndexHash", $BpBtbIndexHash,
  "-OptLevel", $OptLevel,
  "-PerfStats"
)
if ($ExtraCFlags -ne "") {
  $runArgs += @("-ExtraCFlags", $ExtraCFlags)
}

$raw = & powershell @runArgs 2>&1
$lines = $raw | ForEach-Object { $_.ToString() }

$tag = "iter${Iterations}_lctrl${LoadControlEarlyReplay}_idload${IdLoadEarlyRead}_bht${BpBhtDepth}_bhr${BpBhrWidth}_btb${BpBtbDepth}_hash${BpBtbIndexHash}"
$logPath = Join-Path $resolvedOutDir "$tag.log"
$lines | Set-Content -LiteralPath $logPath -Encoding ASCII

if ($LASTEXITCODE -ne 0) {
  $lines
  throw "CoreMark hotspot run failed"
}

$elfLine = $lines | Where-Object { $_ -match "^ELF=" } | Select-Object -Last 1
if (-not $elfLine -or $elfLine -notmatch "^ELF=(.+)$") {
  throw "Cannot find ELF path in CoreMark output"
}
$elf = $Matches[1].Trim()
$symbols = Get-SymbolTable $elf

$loadUseRows = @()
$loadUsePairRows = @()
$jalrRows = @()
$jalrPairRows = @()
$branchRows = @()
$jumpRows = @()

foreach ($line in $lines) {
  if ($line -match "LOAD_USE_TOP consumer_pc=([0-9a-fA-F]+) count=(\d+)") {
    $pc = [Convert]::ToUInt32($Matches[1], 16)
    $sym = Resolve-Symbol $symbols $pc
    $loadUseRows += [pscustomobject]@{
      count = [int]$Matches[2]
      consumer_pc = ("0x{0:x8}" -f $pc)
      consumer_function = $sym.function
      consumer_offset = $sym.offset
    }
  } elseif ($line -match "LOAD_USE_PAIR_TOP load_pc=([0-9a-fA-F]+) consumer_pc=([0-9a-fA-F]+) count=(\d+)") {
    $loadPc = [Convert]::ToUInt32($Matches[1], 16)
    $consumerPc = [Convert]::ToUInt32($Matches[2], 16)
    $loadSym = Resolve-Symbol $symbols $loadPc
    $consumerSym = Resolve-Symbol $symbols $consumerPc
    $loadUsePairRows += [pscustomobject]@{
      count = [int]$Matches[3]
      load_pc = ("0x{0:x8}" -f $loadPc)
      load_function = $loadSym.function
      load_offset = $loadSym.offset
      consumer_pc = ("0x{0:x8}" -f $consumerPc)
      consumer_function = $consumerSym.function
      consumer_offset = $consumerSym.offset
    }
  } elseif ($line -match "JALR_TOP pc=([0-9a-fA-F]+) count=(\d+)") {
    $pc = [Convert]::ToUInt32($Matches[1], 16)
    $sym = Resolve-Symbol $symbols $pc
    $jalrRows += [pscustomobject]@{
      count = [int]$Matches[2]
      pc = ("0x{0:x8}" -f $pc)
      function = $sym.function
      offset = $sym.offset
    }
  } elseif ($line -match "JALR_PAIR_TOP pc=([0-9a-fA-F]+) target=([0-9a-fA-F]+) count=(\d+)") {
    $pc = [Convert]::ToUInt32($Matches[1], 16)
    $target = [Convert]::ToUInt32($Matches[2], 16)
    $pcSym = Resolve-Symbol $symbols $pc
    $targetSym = Resolve-Symbol $symbols $target
    $jalrPairRows += [pscustomobject]@{
      count = [int]$Matches[3]
      pc = ("0x{0:x8}" -f $pc)
      function = $pcSym.function
      offset = $pcSym.offset
      target = ("0x{0:x8}" -f $target)
      target_function = $targetSym.function
      target_offset = $targetSym.offset
    }
  } elseif ($line -match "BRANCH_MISPREDICT_TOP pc=([0-9a-fA-F]+) count=(\d+)") {
    $pc = [Convert]::ToUInt32($Matches[1], 16)
    $sym = Resolve-Symbol $symbols $pc
    $branchRows += [pscustomobject]@{
      count = [int]$Matches[2]
      pc = ("0x{0:x8}" -f $pc)
      function = $sym.function
      offset = $sym.offset
    }
  } elseif ($line -match "JUMP_FLUSH_TOP pc=([0-9a-fA-F]+) count=(\d+)") {
    $pc = [Convert]::ToUInt32($Matches[1], 16)
    $sym = Resolve-Symbol $symbols $pc
    $jumpRows += [pscustomobject]@{
      count = [int]$Matches[2]
      pc = ("0x{0:x8}" -f $pc)
      function = $sym.function
      offset = $sym.offset
    }
  }
}

$loadUseCsv = Join-Path $resolvedOutDir "$tag.load_use.csv"
$loadUsePairCsv = Join-Path $resolvedOutDir "$tag.load_use_pair.csv"
$jalrCsv = Join-Path $resolvedOutDir "$tag.jalr.csv"
$jalrPairCsv = Join-Path $resolvedOutDir "$tag.jalr_pair.csv"
$branchCsv = Join-Path $resolvedOutDir "$tag.branch_mispredict.csv"
$jumpCsv = Join-Path $resolvedOutDir "$tag.jump_flush.csv"
Write-CsvRows $loadUseRows $loadUseCsv
Write-CsvRows $loadUsePairRows $loadUsePairCsv
Write-CsvRows $jalrRows $jalrCsv
Write-CsvRows $jalrPairRows $jalrPairCsv
Write-CsvRows $branchRows $branchCsv
Write-CsvRows $jumpRows $jumpCsv

$summaryPath = Join-Path $resolvedOutDir "$tag.summary.txt"
$summary = @(
  "COREMARK_HOTSPOT_TAG=$tag",
  "COREMARK_LOG=$logPath",
  "COREMARK_RESULT_CYCLES=$(Get-CoremarkValue $lines 'COREMARK_RESULT_CYCLES')",
  "COREMARK_RETIRED=$(Get-CoremarkValue $lines 'COREMARK_RETIRED')",
  "COREMARK_LOAD_USE_STALLS=$(Get-CoremarkValue $lines 'COREMARK_LOAD_USE_STALLS')",
  "COREMARK_BRANCH_MISPREDICT_FLUSHES=$(Get-CoremarkValue $lines 'COREMARK_BRANCH_MISPREDICT_FLUSHES')",
  "COREMARK_JUMP_FLUSHES=$(Get-CoremarkValue $lines 'COREMARK_JUMP_FLUSHES')",
  "COREMARK_JALR_FLUSHES=$(Get-CoremarkValue $lines 'COREMARK_JALR_FLUSHES')",
  "COREMARK_CPI=$(Get-CoremarkValue $lines 'COREMARK_CPI')",
  "LOAD_USE_TOP_CSV=$loadUseCsv",
  "LOAD_USE_PAIR_TOP_CSV=$loadUsePairCsv",
  "JALR_TOP_CSV=$jalrCsv",
  "JALR_PAIR_TOP_CSV=$jalrPairCsv",
  "BRANCH_MISPREDICT_TOP_CSV=$branchCsv",
  "JUMP_FLUSH_TOP_CSV=$jumpCsv"
)
$summary | Set-Content -LiteralPath $summaryPath -Encoding ASCII

$summary
Write-Host "LOAD_USE_TOP5"
$loadUseRows | Sort-Object @{ Expression = "count"; Descending = $true } | Select-Object -First 5 | Format-Table -AutoSize
Write-Host "LOAD_USE_PAIR_TOP8"
$loadUsePairRows | Sort-Object @{ Expression = "count"; Descending = $true } | Select-Object -First 8 | Format-Table -AutoSize
Write-Host "JALR_TOP5"
$jalrRows | Sort-Object @{ Expression = "count"; Descending = $true } | Select-Object -First 5 | Format-Table -AutoSize
Write-Host "BRANCH_MISPREDICT_TOP8"
$branchRows | Sort-Object @{ Expression = "count"; Descending = $true } | Select-Object -First 8 | Format-Table -AutoSize
Write-Host "JUMP_FLUSH_TOP8"
$jumpRows | Sort-Object @{ Expression = "count"; Descending = $true } | Select-Object -First 8 | Format-Table -AutoSize
