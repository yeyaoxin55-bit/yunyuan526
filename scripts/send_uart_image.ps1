param(
  [Parameter(Mandatory=$true)][string]$PortName,
  [string]$IMemHex = "build/coremark/fpga/coremark.imem.hex",
  [string]$DMemHex = "build/coremark/fpga/coremark.dmem.hex",
  [ValidateSet(4, 8)]
  [int]$DMemWordBytes = 8,
  [int]$BaudRate = 115200,
  [int]$ChunkWords = 64,
  [switch]$StartAfterDownload
)

$ErrorActionPreference = "Stop"

function Resolve-RepoPath {
  param([string]$Path)
  if ([System.IO.Path]::IsPathRooted($Path)) {
    return $Path
  }
  return (Join-Path (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path $Path)
}

function Read-HexWords {
  param(
    [string]$Path,
    [ValidateSet(4, 8)]
    [int]$WordBytes = 4
  )
  $resolved = Resolve-RepoPath $Path
  if (-not (Test-Path -LiteralPath $resolved)) {
    throw "Missing hex image: $resolved"
  }

  $words = New-Object System.Collections.Generic.List[UInt32]
  $lineNumber = 0
  foreach ($line in Get-Content -LiteralPath $resolved) {
    $lineNumber++
    $clean = ($line -replace "//.*$", "").Trim()
    if ($clean.Length -eq 0) {
      continue
    }
    if ($clean.StartsWith("@")) {
      continue
    }
    if ($WordBytes -eq 4) {
      if ($clean.Length -gt 8) {
        throw "Expected 32-bit hex word in $resolved line $lineNumber, got '$clean'"
      }
      [void]$words.Add([Convert]::ToUInt32($clean, 16))
    } else {
      if ($clean.Length -gt 16) {
        throw "Expected 64-bit hex word in $resolved line $lineNumber, got '$clean'"
      }
      $value = [Convert]::ToUInt64($clean, 16)
      [void]$words.Add([UInt32]($value -band ([UInt64]0xffffffff)))
      [void]$words.Add([UInt32](($value -shr 32) -band ([UInt64]0xffffffff)))
    }
  }
  return ,$words.ToArray()
}

function Add-U32BE {
  param(
    [System.Collections.Generic.List[byte]]$Bytes,
    [UInt32]$Value
  )
  [void]$Bytes.Add([byte](($Value -shr 24) -band 0xff))
  [void]$Bytes.Add([byte](($Value -shr 16) -band 0xff))
  [void]$Bytes.Add([byte](($Value -shr 8) -band 0xff))
  [void]$Bytes.Add([byte]($Value -band 0xff))
}

function New-UartPacket {
  param(
    [byte]$Command,
    [UInt32]$Address,
    [UInt32[]]$Words
  )
  $payload = New-Object System.Collections.Generic.List[byte]
  [void]$payload.Add($Command)
  Add-U32BE -Bytes $payload -Value $Address
  Add-U32BE -Bytes $payload -Value ([UInt32]$Words.Count)
  foreach ($word in $Words) {
    Add-U32BE -Bytes $payload -Value $word
  }

  [byte]$checksum = 0
  foreach ($b in $payload) {
    $checksum = [byte](($checksum + $b) -band 0xff)
  }

  $packet = New-Object System.Collections.Generic.List[byte]
  foreach ($b in @([byte]0x59, [byte]0x4c, [byte]0x33, [byte]0x4c)) {
    [void]$packet.Add($b)
  }
  foreach ($b in $payload) {
    [void]$packet.Add($b)
  }
  [void]$packet.Add($checksum)
  return ,$packet.ToArray()
}

function Send-Image {
  param(
    [System.IO.Ports.SerialPort]$Port,
    [byte]$Command,
    [UInt32]$BaseAddress,
    [UInt32[]]$Words
  )
  for ($offset = 0; $offset -lt $Words.Count; $offset += $ChunkWords) {
    $count = [Math]::Min($ChunkWords, $Words.Count - $offset)
    $chunk = New-Object UInt32[] $count
    [Array]::Copy($Words, $offset, $chunk, 0, $count)
    $packet = New-UartPacket -Command $Command -Address ([UInt32]($BaseAddress + ($offset * 4))) -Words $chunk
    $Port.Write($packet, 0, $packet.Length)
    Start-Sleep -Milliseconds 20
  }
}

$imemWords = Read-HexWords -Path $IMemHex -WordBytes 4
$dmemWords = Read-HexWords -Path $DMemHex -WordBytes $DMemWordBytes

$serial = [System.IO.Ports.SerialPort]::new($PortName, $BaudRate, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
$serial.WriteTimeout = 5000
$serial.ReadTimeout = 5000

try {
  $serial.Open()
  Send-Image -Port $serial -Command 0x01 -BaseAddress 0x00000000 -Words $imemWords
  Send-Image -Port $serial -Command 0x02 -BaseAddress 0x00010000 -Words $dmemWords
  if ($StartAfterDownload) {
    $startPacket = New-UartPacket -Command 0x03 -Address 0x00000000 -Words @()
    $serial.Write($startPacket, 0, $startPacket.Length)
    Write-Host "UART image sent and START packet sent: IMEM=$($imemWords.Count) words DMEM=$($dmemWords.Count) 32-bit chunks DMEM_WORD_BYTES=$DMemWordBytes PORT=$PortName BAUD=$BaudRate"
  } else {
    Write-Host "UART image sent without START: IMEM=$($imemWords.Count) words DMEM=$($dmemWords.Count) 32-bit chunks DMEM_WORD_BYTES=$DMemWordBytes PORT=$PortName BAUD=$BaudRate"
    Write-Host "Open the serial terminal, release uart_debug_key_n, then press sys_rst_n reset to run the loaded image."
  }
} finally {
  if ($serial.IsOpen) {
    $serial.Close()
  }
}
