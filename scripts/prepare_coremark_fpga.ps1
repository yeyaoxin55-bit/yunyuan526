param(
  [string]$ToolPrefix = "riscv64-unknown-elf-",
  [ValidateSet(32, 64)]
  [int]$XLEN = 64,
  [int]$Iterations = 2200,
  [int]$TotalDataSize = 2000,
  [uint32]$CpuHz = 100000000,
  [string]$OutDir = "build/coremark/fpga",
  [switch]$PreserveExisting
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$resolvedOutDir = if ([System.IO.Path]::IsPathRooted($OutDir)) { $OutDir } else { Join-Path $repoRoot $OutDir }
$resolvedOutParent = Split-Path -Parent $resolvedOutDir
New-Item -ItemType Directory -Force -Path $resolvedOutParent | Out-Null
New-Item -ItemType Directory -Force -Path $resolvedOutDir | Out-Null
$resolvedOutDir = (Resolve-Path -LiteralPath $resolvedOutDir).Path

if (-not $resolvedOutDir.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw "Refusing to clean output directory outside repo: $resolvedOutDir"
}

if (-not $PreserveExisting) {
  Get-ChildItem -LiteralPath $resolvedOutDir -Force | Remove-Item -Recurse -Force
}

$stagingRoot = Join-Path (Split-Path -Parent $resolvedOutDir) ("_prepare_coremark_fpga_{0}" -f $PID)
if (Test-Path -LiteralPath $stagingRoot) {
  Remove-Item -LiteralPath $stagingRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $stagingRoot | Out-Null

$cases = @(
  [pscustomobject]@{ Name = "o1"; OptLevel = "-O1"; ExtraCFlags = "-DCOREMARK_UART_OUTPUT=1" },
  [pscustomobject]@{ Name = "o2"; OptLevel = "-O2"; ExtraCFlags = "-DCOREMARK_UART_OUTPUT=1" },
  [pscustomobject]@{ Name = "o3"; OptLevel = "-O3"; ExtraCFlags = "-funroll-loops -DCOREMARK_UART_OUTPUT=1" }
)

function Build-FinalCoreMarkImage {
  param(
    [pscustomobject]$Case
  )

  $imageDir = Join-Path $stagingRoot $Case.Name
  New-Item -ItemType Directory -Force -Path $imageDir | Out-Null

  Write-Host "BUILD_COREMARK_FPGA_IMAGE=$($Case.Name)"
  $buildOutput = & powershell -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\build_coremark.ps1") `
    -ToolPrefix $ToolPrefix `
    -OutDir $imageDir `
    -XLEN $XLEN `
    -Iterations $Iterations `
    -TotalDataSize $TotalDataSize `
    -CpuHz $CpuHz `
    -OptLevel $Case.OptLevel `
    -ExtraCFlags $Case.ExtraCFlags 2>&1
  $buildOutput | ForEach-Object { Write-Host $_ }
  if ($LASTEXITCODE -ne 0) {
    throw "CoreMark build failed for $($Case.Name)"
  }

  $objcopyLine = $buildOutput | Where-Object { $_ -match "^OBJCOPY=" } | Select-Object -Last 1
  if (-not $objcopyLine) {
    throw "Failed to parse objcopy path for $($Case.Name)"
  }
  $objcopy = ($objcopyLine -replace "^OBJCOPY=", "").Trim()
  $elf = Join-Path $imageDir "coremark.elf"

  $hexOutput = & powershell -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\convert_elf_to_hex.ps1") `
    -Elf $elf `
    -Objcopy $objcopy `
    -OutDir $imageDir `
    -DMemWordBytes ($XLEN / 8) 2>&1
  $hexOutput | ForEach-Object { Write-Host $_ }
  if ($LASTEXITCODE -ne 0) {
    throw "CoreMark hex conversion failed for $($Case.Name)"
  }

  $dstImem = Join-Path $resolvedOutDir "coremark_$($Case.Name).imem.hex"
  $dstDmem = Join-Path $resolvedOutDir "coremark_$($Case.Name).dmem.hex"
  Copy-Item -LiteralPath (Join-Path $imageDir "coremark.imem.hex") -Destination $dstImem -Force
  Copy-Item -LiteralPath (Join-Path $imageDir "coremark.dmem.hex") -Destination $dstDmem -Force

  & powershell -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\send_uart_image.ps1") `
    -ValidateOnly `
    -DMemWordBytes ($XLEN / 8) `
    -IMemHex $dstImem `
    -DMemHex $dstDmem
  if ($LASTEXITCODE -ne 0) {
    throw "CoreMark UART image validation failed for $($Case.Name)"
  }

  return [pscustomobject]@{
    name = $Case.Name
    opt = $Case.OptLevel
    iterations = $Iterations
    total_data_size = $TotalDataSize
    extra_cflags = $Case.ExtraCFlags
    imem_hex = Split-Path -Leaf $dstImem
    dmem_hex = Split-Path -Leaf $dstDmem
  }
}

try {
  $rows = New-Object System.Collections.Generic.List[object]
  foreach ($case in $cases) {
    $rows.Add((Build-FinalCoreMarkImage -Case $case))
  }

  $manifest = Join-Path $resolvedOutDir "manifest.csv"
  $rows | Export-Csv -LiteralPath $manifest -NoTypeInformation -Encoding ASCII

  Write-Host "COREMARK_FPGA_OUT=$resolvedOutDir"
  Write-Host "COREMARK_FPGA_MANIFEST=$manifest"
  foreach ($row in $rows) {
    Write-Host "COREMARK_FPGA_$($row.name.ToUpper())_IMEM=$($row.imem_hex)"
    Write-Host "COREMARK_FPGA_$($row.name.ToUpper())_DMEM=$($row.dmem_hex)"
  }
} finally {
  if (Test-Path -LiteralPath $stagingRoot) {
    Remove-Item -LiteralPath $stagingRoot -Recurse -Force
  }
}
