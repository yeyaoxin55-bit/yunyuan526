param(
  [string]$ToolPrefix = "riscv64-unknown-elf-",
  [string]$OutDir = "build/coremark",
  [ValidateSet(32, 64)]
  [int]$XLEN = 64,
  [string]$March = "",
  [string]$Mabi = "",
  [string]$Linker = "",
  [int]$Iterations = 1,
  [int]$TotalDataSize = 2000,
  [uint32]$CpuHz = 100000000,
  [string]$OptLevel = "-O3",
  [string]$ExtraCFlags = "-funroll-loops"
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path

function Resolve-ToolPath {
  param(
    [string]$Prefix,
    [string]$Name
  )

  $exeName = "$Name.exe"
  $cmdName = "$Prefix$Name"
  if ([System.IO.Path]::IsPathRooted($Prefix)) {
    $candidate = "$Prefix$exeName"
    if (Test-Path -LiteralPath $candidate) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }
  } else {
    $repoCandidate = Join-Path $repoRoot ("$Prefix$exeName")
    if (Test-Path -LiteralPath $repoCandidate) {
      return (Resolve-Path -LiteralPath $repoCandidate).Path
    }
  }

  $cmd = Get-Command $cmdName -ErrorAction SilentlyContinue
  if ($cmd) {
    return $cmd.Source
  }

  throw "$Name not found. Pass -ToolPrefix <path-prefix> or put $cmdName in PATH."
}

$gccPath = Resolve-ToolPath -Prefix $ToolPrefix -Name "gcc"
$objcopyPath = Resolve-ToolPath -Prefix $ToolPrefix -Name "objcopy"

$resolvedOutDir = if ([System.IO.Path]::IsPathRooted($OutDir)) { $OutDir } else { Join-Path $repoRoot $OutDir }
New-Item -ItemType Directory -Force -Path $resolvedOutDir | Out-Null

$elf = Join-Path $resolvedOutDir "coremark.elf"
$map = Join-Path $resolvedOutDir "coremark.map"
if ($March -eq "") {
  $March = if ($XLEN -eq 64) { "rv64im" } else { "rv32im" }
}
if ($Mabi -eq "") {
  $Mabi = if ($XLEN -eq 64) { "lp64" } else { "ilp32" }
}
if ($Linker -eq "") {
  $Linker = if ($XLEN -eq 64) { "sw\linker\yl3_rv64im.ld" } else { "sw\linker\yl3_rv32im.ld" }
}
$linkerPath = if ([System.IO.Path]::IsPathRooted($Linker)) { $Linker } else { Join-Path $repoRoot $Linker }
if (-not (Test-Path -LiteralPath $linkerPath)) {
  throw "Linker script not found: $linkerPath"
}

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
  "-march=$March",
  "-mabi=$Mabi",
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
  "-T", $linkerPath,
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
Write-Host "COREMARK_XLEN=$XLEN"
Write-Host "COREMARK_MARCH=$March"
Write-Host "COREMARK_MABI=$Mabi"
Write-Host "COREMARK_LINKER=$linkerPath"
