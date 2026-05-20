param(
  [string]$ToolPrefix = "xpack-riscv-none-elf-gcc-15.2.0-1\bin\riscv-none-elf-",
  [int]$TotalDataSize = 2000,
  [uint32]$CpuHz = 100000000,
  [int]$SmokeIterations = 2,
  [int]$TenMsIterations = 2,
  [int]$TenSecIterations = 1900,
  [string]$OptLevel = "-O3",
  [string]$ExtraCFlags = "-funroll-loops",
  [string]$OutDir = "build/coremark/fpga"
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$resolvedOutDir = if ([System.IO.Path]::IsPathRooted($OutDir)) { $OutDir } else { Join-Path $repoRoot $OutDir }
New-Item -ItemType Directory -Force -Path $resolvedOutDir | Out-Null

$objcopy = if ([System.IO.Path]::IsPathRooted($ToolPrefix)) {
  $ToolPrefix + "objcopy.exe"
} else {
  Join-Path $repoRoot ($ToolPrefix + "objcopy.exe")
}

function Build-CoreMarkImage {
  param(
    [string]$Name,
    [int]$Iterations
  )

  $imageDir = Join-Path $resolvedOutDir $Name
  New-Item -ItemType Directory -Force -Path $imageDir | Out-Null
  $fpgaExtraCFlags = "-DCOREMARK_UART_OUTPUT=1"
  if ($ExtraCFlags -ne "") {
    $fpgaExtraCFlags = "$ExtraCFlags $fpgaExtraCFlags"
  }

  $buildOutput = & powershell -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\build_coremark.ps1") `
    -ToolPrefix $ToolPrefix `
    -OutDir $imageDir `
    -Iterations $Iterations `
    -TotalDataSize $TotalDataSize `
    -CpuHz $CpuHz `
    -OptLevel $OptLevel `
    -ExtraCFlags $fpgaExtraCFlags 2>&1
  $buildOutput | ForEach-Object { Write-Host $_ }
  if ($LASTEXITCODE -ne 0) {
    throw "CoreMark build failed for $Name"
  }

  $elf = Join-Path $imageDir "coremark.elf"
  $hexOutput = & powershell -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\convert_elf_to_hex.ps1") `
    -Elf $elf `
    -Objcopy $objcopy `
    -OutDir $imageDir 2>&1
  $hexOutput | ForEach-Object { Write-Host $_ }
  if ($LASTEXITCODE -ne 0) {
    throw "CoreMark hex conversion failed for $Name"
  }

  $srcImem = Join-Path $imageDir "coremark.imem.hex"
  $srcDmem = Join-Path $imageDir "coremark.dmem.hex"
  $dstImem = Join-Path $resolvedOutDir "$Name.imem.hex"
  $dstDmem = Join-Path $resolvedOutDir "$Name.dmem.hex"
  Copy-Item -LiteralPath $srcImem -Destination $dstImem -Force
  Copy-Item -LiteralPath $srcDmem -Destination $dstDmem -Force
  Copy-Item -LiteralPath "$srcDmem.b0" -Destination "$dstDmem.b0" -Force
  Copy-Item -LiteralPath "$srcDmem.b1" -Destination "$dstDmem.b1" -Force
  Copy-Item -LiteralPath "$srcDmem.b2" -Destination "$dstDmem.b2" -Force
  Copy-Item -LiteralPath "$srcDmem.b3" -Destination "$dstDmem.b3" -Force

  return [pscustomobject]@{
    name = $Name
    iterations = $Iterations
    opt_level = $OptLevel
    extra_cflags = $ExtraCFlags
    imem_hex = $dstImem
    dmem_hex = $dstDmem
    elf = $elf
  }
}

$rows = New-Object System.Collections.Generic.List[object]
$rows.Add((Build-CoreMarkImage -Name "smoke" -Iterations $SmokeIterations))
$rows.Add((Build-CoreMarkImage -Name "ten_ms" -Iterations $TenMsIterations))
$rows.Add((Build-CoreMarkImage -Name "ten_sec" -Iterations $TenSecIterations))

$manifest = Join-Path $resolvedOutDir "manifest.csv"
$rows | Export-Csv -LiteralPath $manifest -NoTypeInformation -Encoding ASCII

$defaultImem = Join-Path $resolvedOutDir "coremark.imem.hex"
$defaultDmem = Join-Path $resolvedOutDir "coremark.dmem.hex"
Copy-Item -LiteralPath (Join-Path $resolvedOutDir "smoke.imem.hex") -Destination $defaultImem -Force
Copy-Item -LiteralPath (Join-Path $resolvedOutDir "smoke.dmem.hex") -Destination $defaultDmem -Force
Copy-Item -LiteralPath (Join-Path $resolvedOutDir "smoke.dmem.hex.b0") -Destination "$defaultDmem.b0" -Force
Copy-Item -LiteralPath (Join-Path $resolvedOutDir "smoke.dmem.hex.b1") -Destination "$defaultDmem.b1" -Force
Copy-Item -LiteralPath (Join-Path $resolvedOutDir "smoke.dmem.hex.b2") -Destination "$defaultDmem.b2" -Force
Copy-Item -LiteralPath (Join-Path $resolvedOutDir "smoke.dmem.hex.b3") -Destination "$defaultDmem.b3" -Force

Write-Host "COREMARK_FPGA_OUT=$resolvedOutDir"
Write-Host "COREMARK_FPGA_MANIFEST=$manifest"
Write-Host "COREMARK_FPGA_DEFAULT_IMEM=$defaultImem"
Write-Host "COREMARK_FPGA_DEFAULT_DMEM=$defaultDmem"
Write-Host "COREMARK_RESULT_PASS_ADDR=0x00017ff0"
Write-Host "COREMARK_RESULT_FAIL_ADDR=0x00017ff4"
Write-Host "COREMARK_RESULT_CYCLES_ADDR=0x00017ff8"
