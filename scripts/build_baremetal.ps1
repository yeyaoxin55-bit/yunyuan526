param(
  [Parameter(Mandatory = $true)]
  [string[]]$Sources,
  [string]$OutName = "program",
  [string]$ToolPrefix = "riscv64-unknown-elf-",
  [string]$OutDir = "build/baremetal",
  [string]$March = "rv32im",
  [string]$Mabi = "ilp32",
  [string]$ExtraCFlags = ""
)

$ErrorActionPreference = "Stop"

$gcc = Get-Command ($ToolPrefix + "gcc") -ErrorAction SilentlyContinue
if (-not $gcc) {
  throw "RISC-V gcc not found. Pass -ToolPrefix <path-prefix>, e.g. C:\riscv\bin\riscv64-unknown-elf-"
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$resolvedOutDir = if ([System.IO.Path]::IsPathRooted($OutDir)) { $OutDir } else { Join-Path $repoRoot $OutDir }
New-Item -ItemType Directory -Force -Path $resolvedOutDir | Out-Null

$elf = Join-Path $resolvedOutDir "$OutName.elf"
$map = Join-Path $resolvedOutDir "$OutName.map"
$linker = Join-Path $repoRoot "sw\linker\yl3_rv32im.ld"
$crt0 = Join-Path $repoRoot "sw\runtime\crt0.S"
$include = Join-Path $repoRoot "sw\runtime"

$resolvedSources = @($crt0)
foreach ($src in $Sources) {
  if (-not (Test-Path -LiteralPath $src)) {
    throw "Source not found: $src"
  }
  $resolvedSources += (Resolve-Path -LiteralPath $src).Path
}

$flags = @(
  "-march=$March",
  "-mabi=$Mabi",
  "-ffreestanding",
  "-fno-builtin",
  "-nostdlib",
  "-nostartfiles",
  "-O2",
  "-I", $include,
  "-T", $linker,
  "-Wl,-Map,$map",
  "-o", $elf
)
if ($ExtraCFlags -ne "") {
  $flags += ($ExtraCFlags -split "\s+")
}

& $gcc.Source @flags @resolvedSources
if ($LASTEXITCODE -ne 0) {
  throw "Baremetal build failed"
}

Write-Host "ELF=$elf"
Write-Host "MAP=$map"
