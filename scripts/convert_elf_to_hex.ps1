param(
  [Parameter(Mandatory = $true)]
  [string]$Elf,
  [string]$Objcopy = "riscv64-unknown-elf-objcopy",
  [string]$OutDir = "build/external_hex",
  [uint32]$IMemBase = 0x00000000,
  [uint32]$IMemBytes = 0x00010000,
  [uint32]$DMemBase = 0x00010000,
  [uint32]$DMemBytes = 0x00008000,
  [ValidateSet(4, 8)]
  [int]$DMemWordBytes = 4
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $Elf)) {
  throw "ELF not found: $Elf"
}

$objcopyCmd = Get-Command $Objcopy -ErrorAction SilentlyContinue
if (-not $objcopyCmd) {
  if (Test-Path -LiteralPath $Objcopy) {
    $objcopyCmd = (Resolve-Path -LiteralPath $Objcopy).Path
  } else {
    throw "objcopy not found. Pass -Objcopy <path-to-riscv64-unknown-elf-objcopy.exe>"
  }
} else {
  $objcopyCmd = $objcopyCmd.Source
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$resolvedOutDir = if ([System.IO.Path]::IsPathRooted($OutDir)) { $OutDir } else { Join-Path $repoRoot $OutDir }
New-Item -ItemType Directory -Force -Path $resolvedOutDir | Out-Null

$name = [System.IO.Path]::GetFileNameWithoutExtension($Elf)
$vmem = Join-Path $resolvedOutDir "$name.vmem"
$imemHex = Join-Path $resolvedOutDir "$name.imem.hex"
$dmemHex = Join-Path $resolvedOutDir "$name.dmem.hex"

& $objcopyCmd -O verilog $Elf $vmem
if ($LASTEXITCODE -ne 0) {
  throw "objcopy failed"
}

$bytes = @{}
$addr = 0
foreach ($rawLine in Get-Content -LiteralPath $vmem) {
  $line = $rawLine.Trim()
  if ($line -eq "") { continue }
  foreach ($tok in ($line -split "\s+")) {
    if ($tok -eq "") { continue }
    if ($tok.StartsWith("@")) {
      $addr = [Convert]::ToUInt32($tok.Substring(1), 16)
    } else {
      $bytes[$addr] = [Convert]::ToByte($tok, 16)
      $addr++
    }
  }
}

function Write-RegionWords {
  param(
    [hashtable]$Bytes,
    [uint32]$Base,
    [uint32]$SizeBytes,
    [string]$Path,
    [ValidateSet(4, 8)]
    [int]$WordBytes = 4
  )

  $wordCount = [int]($SizeBytes / $WordBytes)
  $lines = New-Object System.Collections.Generic.List[string]
  for ($i = 0; $i -lt $wordCount; $i++) {
    $a = [uint32]($Base + ($i * $WordBytes))
    $word = [uint64]0
    for ($j = 0; $j -lt $WordBytes; $j++) {
      $b = if ($Bytes.ContainsKey($a + $j)) { [uint64]$Bytes[$a + $j] } else { [uint64]0 }
      $word = $word -bor ($b -shl (8 * $j))
    }
    if ($WordBytes -eq 8) {
      $lines.Add(("{0:x16}" -f $word))
    } else {
      $lines.Add(("{0:x8}" -f ([uint32]($word -band 0xffffffff))))
    }
  }
  Set-Content -LiteralPath $Path -Value $lines -Encoding ASCII
}

function Write-RegionByteLanes {
  param(
    [hashtable]$Bytes,
    [uint32]$Base,
    [uint32]$SizeBytes,
    [string]$Path,
    [ValidateSet(4, 8)]
    [int]$WordBytes = 4
  )

  $wordCount = [int]($SizeBytes / $WordBytes)
  $lanes = @()
  for ($j = 0; $j -lt $WordBytes; $j++) {
    $lanes += ,(New-Object System.Collections.Generic.List[string])
  }
  for ($i = 0; $i -lt $wordCount; $i++) {
    $a = [uint32]($Base + ($i * $WordBytes))
    for ($j = 0; $j -lt $WordBytes; $j++) {
      $b = if ($Bytes.ContainsKey($a + $j)) { [uint32]$Bytes[$a + $j] } else { 0 }
      $lanes[$j].Add(("{0:x2}" -f $b))
    }
  }
  for ($j = 0; $j -lt $WordBytes; $j++) {
    Set-Content -LiteralPath "$Path.b$j" -Value $lanes[$j] -Encoding ASCII
  }
}

Write-RegionWords -Bytes $bytes -Base $IMemBase -SizeBytes $IMemBytes -Path $imemHex -WordBytes 4
Write-RegionWords -Bytes $bytes -Base $DMemBase -SizeBytes $DMemBytes -Path $dmemHex -WordBytes $DMemWordBytes
Write-RegionByteLanes -Bytes $bytes -Base $DMemBase -SizeBytes $DMemBytes -Path $dmemHex -WordBytes $DMemWordBytes

Write-Host "IMEM_HEX=$imemHex"
Write-Host "DMEM_HEX=$dmemHex"
Write-Host "DMEM_WORD_BYTES=$DMemWordBytes"
