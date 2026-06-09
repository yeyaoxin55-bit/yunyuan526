$ErrorActionPreference = "Stop"

function Require-File($Path) {
  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Missing required file: $Path"
  }
}

function Require-Match($Path, $Pattern, $Description) {
  $text = Get-Content -Raw $Path
  if ($text -notmatch $Pattern) {
    throw "Missing $Description in $Path"
  }
}

$helper = "scripts/use_repo_temp.ps1"
Require-File $helper
Require-Match $helper "function\s+Set-RepoTemp\b" "Set-RepoTemp function"
Require-Match $helper '\$env:TEMP\s*=' "TEMP assignment"
Require-Match $helper '\$env:TMP\s*=' "TMP assignment"

$requiredUsers = @(
  "scripts/build_baremetal.ps1",
  "scripts/build_riscv_test.ps1",
  "scripts/build_coremark.ps1",
  "scripts/run_csr_phase_acceptance.ps1"
)

foreach ($path in $requiredUsers) {
  Require-File $path
  Require-Match $path "use_repo_temp\.ps1" "repo temp helper include"
  Require-Match $path 'Set-RepoTemp\s+-RepoRoot\s+\$repoRoot' "repo temp setup call"
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $repoRoot $helper)
$selected = Set-RepoTemp -RepoRoot $repoRoot
$expected = (Resolve-Path -LiteralPath (Join-Path $repoRoot "build\tmp")).Path

if ($selected -ne $expected) {
  throw "Set-RepoTemp returned '$selected', expected '$expected'"
}
if ($env:TEMP -ne $expected -or $env:TMP -ne $expected) {
  throw "TEMP/TMP not set to repo temp. TEMP='$env:TEMP' TMP='$env:TMP' expected='$expected'"
}
if (-not (Test-Path -LiteralPath $expected)) {
  throw "Repo temp directory was not created: $expected"
}

Write-Host "Repo temp boundary OK"
