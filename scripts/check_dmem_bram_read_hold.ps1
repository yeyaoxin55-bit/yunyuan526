$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$dmemPath = Join-Path $repoRoot "rtl\dmem.v"
$dmem = Get-Content -Raw -LiteralPath $dmemPath

$bramBlockMatch = [regex]::Match($dmem, 'begin\s*:\s*gen_bram_friendly(?<body>[\s\S]*?)end\s*endgenerate')
if (-not $bramBlockMatch.Success) {
  throw "Could not find gen_bram_friendly block in rtl/dmem.v"
}
$bramBlock = $bramBlockMatch.Groups["body"].Value

$checks = @(
  @{
    Name = "BRAM read output updates only on valid in-range reads"
    Pass = $bramBlock -match 'if\s*\(\s*mem_read\s*&&\s*\(word_index\s*<\s*DMEM_DEPTH\)\s*\)\s*begin\s*read_word_q\s*<='
  },
  @{
    Name = "BRAM read output does not clear on non-read cycles"
    Pass = $bramBlock -notmatch 'else\s*begin\s*read_word_q\s*<=\s*32''h00000000\s*;\s*read_offset_q\s*<=\s*2''d0\s*;'
  },
  @{
    Name = "BRAM read registers have deterministic initial values"
    Pass = ($bramBlock -match 'read_word_q\s*=\s*32''h00000000') -and
           ($bramBlock -match 'read_offset_q\s*=\s*2''d0')
  }
)

$failed = @()
foreach ($check in $checks) {
  if (-not $check.Pass) {
    $failed += $check.Name
  }
}

if ($failed.Count -gt 0) {
  throw ("DMEM BRAM read-hold checks failed:`n" + ($failed -join "`n"))
}

Write-Host "DMEM BRAM read-hold checks passed"
