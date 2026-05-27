param(
  [string[]]$Tests = @("csr_rw"),
  [string]$ToolPrefix = "xpack-riscv-none-elf-gcc-15.2.0-1\bin\riscv-none-elf-",
  [int]$MaxCycles = 200000
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$gccPrefix = if ([System.IO.Path]::IsPathRooted($ToolPrefix)) {
  $ToolPrefix
} else {
  Join-Path $repoRoot $ToolPrefix
}
$objcopy = $gccPrefix + "objcopy.exe"

foreach ($test in $Tests) {
  $src = Join-Path $repoRoot "sw\csr_trap_tests\$test.S"
  if (-not (Test-Path -LiteralPath $src)) {
    throw "CSR trap test source not found: $src"
  }

  $buildOutput = & powershell -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\build_baremetal.ps1") `
    -Sources $src `
    -OutName $test `
    -ToolPrefix $gccPrefix `
    -OutDir (Join-Path $repoRoot "build\csr_trap_tests") `
    -March "rv32im_zicsr" `
    -Mabi "ilp32" 2>&1
  $buildOutput
  if ($LASTEXITCODE -ne 0) {
    throw "CSR trap test build failed: $test"
  }

  $elfLine = $buildOutput | Where-Object { $_ -match "^ELF=" } | Select-Object -Last 1
  if (-not $elfLine) {
    throw "Failed to parse ELF path for $test"
  }
  $elf = ($elfLine -replace "^ELF=", "").Trim()

  $hexOutput = & powershell -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\convert_elf_to_hex.ps1") `
    -Elf $elf `
    -Objcopy $objcopy `
    -OutDir (Join-Path $repoRoot "build\csr_trap_tests\hex") 2>&1
  $hexOutput
  if ($LASTEXITCODE -ne 0) {
    throw "CSR trap test hex conversion failed: $test"
  }

  $imemLine = $hexOutput | Where-Object { $_ -match "^IMEM_HEX=" } | Select-Object -Last 1
  $dmemLine = $hexOutput | Where-Object { $_ -match "^DMEM_HEX=" } | Select-Object -Last 1
  if (-not $imemLine -or -not $dmemLine) {
    throw "Failed to parse hex paths for $test"
  }
  $imem = ($imemLine -replace "^IMEM_HEX=", "").Trim()
  $dmem = ($dmemLine -replace "^DMEM_HEX=", "").Trim()

  Write-Host "RUN_CSR_TRAP_TEST=$test"
  & powershell -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\run_external_modelsim.ps1") `
    -IMemHex $imem `
    -DMemHex $dmem `
    -MaxCycles $MaxCycles `
    -DMemBase 65536 `
    -PassAddr 98288 `
    -FailAddr 98292
  if ($LASTEXITCODE -ne 0) {
    throw "CSR trap simulation failed: $test"
  }
}
