param(
  [Parameter(Mandatory = $true)]
  [string]$TestSource,
  [string]$ToolPrefix = "xpack-riscv-none-elf-gcc-15.2.0-1\bin\riscv-none-elf-",
  [string]$OutDir = "build/riscv-tests",
  [string]$March = "rv32im_zifencei",
  [string]$Mabi = "ilp32"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $TestSource)) {
  throw "Test source not found: $TestSource"
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$gccPath = if ([System.IO.Path]::IsPathRooted($ToolPrefix)) { $ToolPrefix + "gcc.exe" } else { Join-Path $repoRoot ($ToolPrefix + "gcc.exe") }
$objcopyPath = if ([System.IO.Path]::IsPathRooted($ToolPrefix)) { $ToolPrefix + "objcopy.exe" } else { Join-Path $repoRoot ($ToolPrefix + "objcopy.exe") }

if (-not (Test-Path -LiteralPath $gccPath)) {
  $cmd = Get-Command ($ToolPrefix + "gcc") -ErrorAction SilentlyContinue
  if ($cmd) { $gccPath = $cmd.Source } else { throw "gcc not found: $gccPath" }
}
if (-not (Test-Path -LiteralPath $objcopyPath)) {
  $cmd = Get-Command ($ToolPrefix + "objcopy") -ErrorAction SilentlyContinue
  if ($cmd) { $objcopyPath = $cmd.Source } else { throw "objcopy not found: $objcopyPath" }
}

$resolvedOutDir = if ([System.IO.Path]::IsPathRooted($OutDir)) { $OutDir } else { Join-Path $repoRoot $OutDir }
New-Item -ItemType Directory -Force -Path $resolvedOutDir | Out-Null

$testName = [System.IO.Path]::GetFileNameWithoutExtension($TestSource)
$suiteName = Split-Path (Split-Path $TestSource -Parent) -Leaf
$name = "$suiteName-$testName"
$elf = Join-Path $resolvedOutDir "$name.elf"
$map = Join-Path $resolvedOutDir "$name.map"
$linker = Join-Path $repoRoot "sw\linker\yl3_rv32im.ld"
$envInclude = Join-Path $repoRoot "sw\riscv-tests-env"
$macroInclude = Join-Path $repoRoot "riscv-tests\isa\macros\scalar"
$isaInclude = Join-Path $repoRoot "riscv-tests\isa"
$resolvedSource = (Resolve-Path -LiteralPath $TestSource).Path

& $gccPath `
  "-march=$March" `
  "-mabi=$Mabi" `
  "-nostdlib" `
  "-nostartfiles" `
  "-ffreestanding" `
  "-x" "assembler-with-cpp" `
  "-I" $envInclude `
  "-I" $macroInclude `
  "-I" $isaInclude `
  "-T" $linker `
  "-Wl,-Map,$map" `
  "-o" $elf `
  $resolvedSource

if ($LASTEXITCODE -ne 0) {
  throw "riscv-test build failed: $TestSource"
}

Write-Host "ELF=$elf"
Write-Host "MAP=$map"
Write-Host "OBJCOPY=$objcopyPath"
