param(
  [Parameter(Mandatory = $true)]
  [string]$Elf,
  [string]$Objcopy = "riscv64-unknown-elf-objcopy",
  [string]$OutDir = "build/external_hex",
  [uint32]$IMemBase = 0x00000000,
  [uint32]$IMemBytes = 0x00010000,
  [uint32]$DMemBase = 0x00010000,
  [uint32]$DMemBytes = 0x00008000
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
    [string]$Path
  )

  $wordCount = [int]($SizeBytes / 4)
  $lines = New-Object System.Collections.Generic.List[string]
  for ($i = 0; $i -lt $wordCount; $i++) {
    $a = [uint32]($Base + ($i * 4))
    $b0 = if ($Bytes.ContainsKey($a)) { [uint32]$Bytes[$a] } else { 0 }
    $b1 = if ($Bytes.ContainsKey($a + 1)) { [uint32]$Bytes[$a + 1] } else { 0 }
    $b2 = if ($Bytes.ContainsKey($a + 2)) { [uint32]$Bytes[$a + 2] } else { 0 }
    $b3 = if ($Bytes.ContainsKey($a + 3)) { [uint32]$Bytes[$a + 3] } else { 0 }
    $word = $b0 -bor ($b1 -shl 8) -bor ($b2 -shl 16) -bor ($b3 -shl 24)
    $lines.Add(("{0:x8}" -f ($word -band 0xffffffff)))
  }
  Set-Content -LiteralPath $Path -Value $lines -Encoding ASCII
}

function Write-RegionByteLanes {
  param(
    [hashtable]$Bytes,
    [uint32]$Base,
    [uint32]$SizeBytes,
    [string]$Path
  )

  $wordCount = [int]($SizeBytes / 4)
  $lane0 = New-Object System.Collections.Generic.List[string]
  $lane1 = New-Object System.Collections.Generic.List[string]
  $lane2 = New-Object System.Collections.Generic.List[string]
  $lane3 = New-Object System.Collections.Generic.List[string]
  for ($i = 0; $i -lt $wordCount; $i++) {
    $a = [uint32]($Base + ($i * 4))
    $b0 = if ($Bytes.ContainsKey($a)) { [uint32]$Bytes[$a] } else { 0 }
    $b1 = if ($Bytes.ContainsKey($a + 1)) { [uint32]$Bytes[$a + 1] } else { 0 }
    $b2 = if ($Bytes.ContainsKey($a + 2)) { [uint32]$Bytes[$a + 2] } else { 0 }
    $b3 = if ($Bytes.ContainsKey($a + 3)) { [uint32]$Bytes[$a + 3] } else { 0 }
    $lane0.Add(("{0:x2}" -f $b0))
    $lane1.Add(("{0:x2}" -f $b1))
    $lane2.Add(("{0:x2}" -f $b2))
    $lane3.Add(("{0:x2}" -f $b3))
  }
  Set-Content -LiteralPath "$Path.b0" -Value $lane0 -Encoding ASCII
  Set-Content -LiteralPath "$Path.b1" -Value $lane1 -Encoding ASCII
  Set-Content -LiteralPath "$Path.b2" -Value $lane2 -Encoding ASCII
  Set-Content -LiteralPath "$Path.b3" -Value $lane3 -Encoding ASCII
}

Write-RegionWords -Bytes $bytes -Base $IMemBase -SizeBytes $IMemBytes -Path $imemHex
Write-RegionWords -Bytes $bytes -Base $DMemBase -SizeBytes $DMemBytes -Path $dmemHex
Write-RegionByteLanes -Bytes $bytes -Base $DMemBase -SizeBytes $DMemBytes -Path $dmemHex

Write-Host "IMEM_HEX=$imemHex"
Write-Host "DMEM_HEX=$dmemHex"
