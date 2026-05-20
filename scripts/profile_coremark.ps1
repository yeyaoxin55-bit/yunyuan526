param(
  [string]$ToolPrefix = "xpack-riscv-none-elf-gcc-15.2.0-1\bin\riscv-none-elf-",
  [string[]]$TotalDataSizes = @("1200", "2000"),
  [string[]]$Iterations = @("1"),
  [int]$MaxCycles = 30000000,
  [uint32]$CpuHz = 100000000,
  [string]$OutCsv = "build/coremark/coremark_profile.csv",
  [switch]$PerfStats
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$resolvedCsv = if ([System.IO.Path]::IsPathRooted($OutCsv)) { $OutCsv } else { Join-Path $repoRoot $OutCsv }
$csvDir = Split-Path -Parent $resolvedCsv
if ($csvDir -ne "") {
  New-Item -ItemType Directory -Force -Path $csvDir | Out-Null
}

$rows = New-Object System.Collections.Generic.List[object]

function ConvertTo-IntList {
  param([string[]]$Values)

  $items = New-Object System.Collections.Generic.List[int]
  foreach ($value in $Values) {
    foreach ($part in ($value -split ",")) {
      $trimmed = $part.Trim()
      if ($trimmed -ne "") {
        $items.Add([int]$trimmed)
      }
    }
  }
  return $items
}

$dataSizeList = ConvertTo-IntList -Values $TotalDataSizes
$iterationList = ConvertTo-IntList -Values $Iterations

foreach ($dataSize in $dataSizeList) {
  foreach ($iter in $iterationList) {
    Write-Host ("RUN_COREMARK_PROFILE data_size={0} iterations={1}" -f $dataSize, $iter)
    $runArgs = @(
      "-ExecutionPolicy", "Bypass",
      "-File", (Join-Path $repoRoot "scripts\run_coremark.ps1"),
      "-ToolPrefix", $ToolPrefix,
      "-Iterations", $iter,
      "-TotalDataSize", $dataSize,
      "-CpuHz", $CpuHz,
      "-MaxCycles", $MaxCycles
    )
    if ($PerfStats.IsPresent) {
      $runArgs += "-PerfStats"
    }
    $output = & powershell @runArgs 2>&1
    $text = $output | Out-String
    if ($LASTEXITCODE -ne 0) {
      $output
      throw "CoreMark profile run failed for data_size=$dataSize iterations=$iter"
    }

    $imemMatch = [regex]::Match($text, "IMEM:\s+(\d+)\s+B\s+\d+\s+KB\s+([0-9.]+)%")
    $dmemMatch = [regex]::Match($text, "DMEM:\s+(\d+)\s+B\s+\d+\s+KB\s+([0-9.]+)%")
    $simMatch = [regex]::Match($text, "COREMARK_SIM_CYCLE=(\d+)")
    $resultMatch = [regex]::Match($text, "COREMARK_RESULT_CYCLES=(\d+)")
    $retiredMatch = [regex]::Match($text, "COREMARK_RETIRED=(\d+)")
    $loadsMatch = [regex]::Match($text, "COREMARK_LOADS=(\d+)")
    $storesMatch = [regex]::Match($text, "COREMARK_STORES=(\d+)")
    $branchesMatch = [regex]::Match($text, "COREMARK_BRANCHES=(\d+)")
    $jumpsMatch = [regex]::Match($text, "COREMARK_JUMPS=(\d+)")
    $mulsMatch = [regex]::Match($text, "COREMARK_MULS=(\d+)")
    $divsMatch = [regex]::Match($text, "COREMARK_DIVS=(\d+)")
    $loadUseStallsMatch = [regex]::Match($text, "COREMARK_LOAD_USE_STALLS=(\d+)")
    $execWaitStallsMatch = [regex]::Match($text, "COREMARK_EXEC_WAIT_STALLS=(\d+)")
    $memWaitStallsMatch = [regex]::Match($text, "COREMARK_MEM_WAIT_STALLS=(\d+)")
    $mulWaitStallsMatch = [regex]::Match($text, "COREMARK_MUL_WAIT_STALLS=(\d+)")
    $divWaitStallsMatch = [regex]::Match($text, "COREMARK_DIV_WAIT_STALLS=(\d+)")
    $flushesMatch = [regex]::Match($text, "COREMARK_FLUSHES=(\d+)")
    $branchMispredictFlushesMatch = [regex]::Match($text, "COREMARK_BRANCH_MISPREDICT_FLUSHES=(\d+)")
    $jumpFlushesMatch = [regex]::Match($text, "COREMARK_JUMP_FLUSHES=(\d+)")
    $jalFlushesMatch = [regex]::Match($text, "COREMARK_JAL_FLUSHES=(\d+)")
    $jalrFlushesMatch = [regex]::Match($text, "COREMARK_JALR_FLUSHES=(\d+)")
    $jalEarlyRedirectsMatch = [regex]::Match($text, "COREMARK_JAL_EARLY_REDIRECTS=(\d+)")
    $takenBranchesMatch = [regex]::Match($text, "COREMARK_TAKEN_BRANCHES=(\d+)")
    $notTakenBranchesMatch = [regex]::Match($text, "COREMARK_NOT_TAKEN_BRANCHES=(\d+)")
    $predTakenBranchesMatch = [regex]::Match($text, "COREMARK_PRED_TAKEN_BRANCHES=(\d+)")
    $cpiMatch = [regex]::Match($text, "COREMARK_CPI=([0-9.]+)")

    $row = [pscustomobject]@{
      total_data_size = $dataSize
      iterations = $iter
      imem_bytes = if ($imemMatch.Success) { [int]$imemMatch.Groups[1].Value } else { $null }
      imem_percent = if ($imemMatch.Success) { [double]$imemMatch.Groups[2].Value } else { $null }
      dmem_bytes = if ($dmemMatch.Success) { [int]$dmemMatch.Groups[1].Value } else { $null }
      dmem_percent = if ($dmemMatch.Success) { [double]$dmemMatch.Groups[2].Value } else { $null }
      sim_cycle = if ($simMatch.Success) { [int]$simMatch.Groups[1].Value } else { $null }
      coremark_cycles = if ($resultMatch.Success) { [int]$resultMatch.Groups[1].Value } else { $null }
      cycles_per_iteration = if ($resultMatch.Success -and $iter -ne 0) { [double]([int]$resultMatch.Groups[1].Value) / [double]$iter } else { $null }
      retired = if ($retiredMatch.Success) { [int]$retiredMatch.Groups[1].Value } else { $null }
      cpi = if ($cpiMatch.Success) { [double]$cpiMatch.Groups[1].Value } else { $null }
      loads = if ($loadsMatch.Success) { [int]$loadsMatch.Groups[1].Value } else { $null }
      stores = if ($storesMatch.Success) { [int]$storesMatch.Groups[1].Value } else { $null }
      branches = if ($branchesMatch.Success) { [int]$branchesMatch.Groups[1].Value } else { $null }
      jumps = if ($jumpsMatch.Success) { [int]$jumpsMatch.Groups[1].Value } else { $null }
      muls = if ($mulsMatch.Success) { [int]$mulsMatch.Groups[1].Value } else { $null }
      divs = if ($divsMatch.Success) { [int]$divsMatch.Groups[1].Value } else { $null }
      load_use_stalls = if ($loadUseStallsMatch.Success) { [int]$loadUseStallsMatch.Groups[1].Value } else { $null }
      exec_wait_stalls = if ($execWaitStallsMatch.Success) { [int]$execWaitStallsMatch.Groups[1].Value } else { $null }
      mem_wait_stalls = if ($memWaitStallsMatch.Success) { [int]$memWaitStallsMatch.Groups[1].Value } else { $null }
      mul_wait_stalls = if ($mulWaitStallsMatch.Success) { [int]$mulWaitStallsMatch.Groups[1].Value } else { $null }
      div_wait_stalls = if ($divWaitStallsMatch.Success) { [int]$divWaitStallsMatch.Groups[1].Value } else { $null }
      flushes = if ($flushesMatch.Success) { [int]$flushesMatch.Groups[1].Value } else { $null }
      branch_mispredict_flushes = if ($branchMispredictFlushesMatch.Success) { [int]$branchMispredictFlushesMatch.Groups[1].Value } else { $null }
      jump_flushes = if ($jumpFlushesMatch.Success) { [int]$jumpFlushesMatch.Groups[1].Value } else { $null }
      jal_flushes = if ($jalFlushesMatch.Success) { [int]$jalFlushesMatch.Groups[1].Value } else { $null }
      jalr_flushes = if ($jalrFlushesMatch.Success) { [int]$jalrFlushesMatch.Groups[1].Value } else { $null }
      jal_early_redirects = if ($jalEarlyRedirectsMatch.Success) { [int]$jalEarlyRedirectsMatch.Groups[1].Value } else { $null }
      taken_branches = if ($takenBranchesMatch.Success) { [int]$takenBranchesMatch.Groups[1].Value } else { $null }
      not_taken_branches = if ($notTakenBranchesMatch.Success) { [int]$notTakenBranchesMatch.Groups[1].Value } else { $null }
      pred_taken_branches = if ($predTakenBranchesMatch.Success) { [int]$predTakenBranchesMatch.Groups[1].Value } else { $null }
    }
    $rows.Add($row)
    Write-Host ("PROFILE_RESULT data_size={0} iterations={1} coremark_cycles={2} sim_cycle={3}" -f $row.total_data_size, $row.iterations, $row.coremark_cycles, $row.sim_cycle)
  }
}

$rows | Export-Csv -LiteralPath $resolvedCsv -NoTypeInformation -Encoding ASCII
Write-Host "COREMARK_PROFILE_CSV=$resolvedCsv"
