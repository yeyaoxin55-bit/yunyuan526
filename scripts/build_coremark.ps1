param(
  [string]$ToolPrefix = "xpack-riscv-none-elf-gcc-15.2.0-1\bin\riscv-none-elf-",
  [string]$OutDir = "build/coremark",
  [int]$Iterations = 1,
  [int]$TotalDataSize = 2000,
  [uint32]$CpuHz = 100000000,
  [string]$OptLevel = "-O3",
  [string]$ExtraCFlags = "-funroll-loops"
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$gccPath = if ([System.IO.Path]::IsPathRooted($ToolPrefix)) { $ToolPrefix + "gcc.exe" } else { Join-Path $repoRoot ($ToolPrefix + "gcc.exe") }
$objcopyPath = if ([System.IO.Path]::IsPathRooted($ToolPrefix)) { $ToolPrefix + "objcopy.exe" } else { Join-Path $repoRoot ($ToolPrefix + "objcopy.exe") }

if (-not (Test-Path -LiteralPath $gccPath)) {
  throw "gcc not found: $gccPath"
}
if (-not (Test-Path -LiteralPath $objcopyPath)) {
  throw "objcopy not found: $objcopyPath"
}

$resolvedOutDir = if ([System.IO.Path]::IsPathRooted($OutDir)) { $OutDir } else { Join-Path $repoRoot $OutDir }
New-Item -ItemType Directory -Force -Path $resolvedOutDir | Out-Null

$elf = Join-Path $resolvedOutDir "coremark.elf"
$map = Join-Path $resolvedOutDir "coremark.map"
$linker = Join-Path $repoRoot "sw\linker\yl3_rv32im.ld"

$sources = @(
  "sw\runtime\crt0.S",
  "coremark\core_main.c",
  "coremark\core_list_join.c",
  "coremark\core_matrix.c",
  "coremark\core_state.c",
  "coremark\core_util.c",
  "sw\coremark_port\core_portme.c"
) | ForEach-Object { Join-Path $repoRoot $_ }

$flags = @(
  "-march=rv32im_zicsr_zifencei",
  "-mabi=ilp32",
  "-ffreestanding",
  "-fno-builtin",
  "-nostdlib",
  "-nostartfiles",
  $OptLevel,
  "-I", (Join-Path $repoRoot "sw\coremark_port"),
  "-I", (Join-Path $repoRoot "coremark"),
  "-DITERATIONS=$Iterations",
  "-DTOTAL_DATA_SIZE=$TotalDataSize",
  "-DCPU_HZ=$CpuHz",
  "-DPERFORMANCE_RUN=0",
  "-DVALIDATION_RUN=1",
  "-DPROFILE_RUN=0",
  "-T", $linker,
  "-Wl,-Map,$map",
  "-Wl,--print-memory-usage",
  "-o", $elf
)
if ($ExtraCFlags -ne "") {
  $flags += ($ExtraCFlags -split "\s+")
}
$flags += $sources

& $gccPath @flags

if ($LASTEXITCODE -ne 0) {
  throw "CoreMark build failed"
}

Write-Host "ELF=$elf"
Write-Host "MAP=$map"
Write-Host "OBJCOPY=$objcopyPath"
Write-Host "COREMARK_OPT_LEVEL=$OptLevel"
Write-Host "COREMARK_EXTRA_CFLAGS=$ExtraCFlags"
