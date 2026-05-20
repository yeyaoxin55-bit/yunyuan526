$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$corePath = Join-Path $repoRoot "rtl\cpu_core.v"
$text = Get-Content -LiteralPath $corePath -Raw

$match = [regex]::Match($text, "wire\s+id_load_early_read\s*=\s*(?<expr>.*?);", [System.Text.RegularExpressions.RegexOptions]::Singleline)
if (-not $match.Success) {
  throw "Cannot find id_load_early_read expression"
}

$expr = $match.Groups["expr"].Value
$forbidden = @("flush", "ctrl_replay_valid")
foreach ($name in $forbidden) {
  if ($expr -match "(^|[^A-Za-z0-9_])$name([^A-Za-z0-9_]|$)") {
    throw "id_load_early_read still depends on $name"
  }
}

foreach ($name in @("dmem_port_busy", "ctrl_load_pending_valid")) {
  if ($expr -notmatch "(^|[^A-Za-z0-9_])$name([^A-Za-z0-9_]|$)") {
    throw "id_load_early_read lost required guard $name"
  }
}

Write-Host "ID early-read control cone OK"
