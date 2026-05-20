param()

$ErrorActionPreference = "Stop"
$path = Join-Path $PSScriptRoot "..\rtl\cpu_core.v"
$text = Get-Content -Raw -Path $path

if ($text -notmatch "generate\s+if\s*\(\s*FAST_MUL\s*!=\s*0\s*\)") {
    throw "cpu_core.v must wrap fast multiplier combinational products in generate if (FAST_MUL != 0)."
}

if ($text -notmatch "assign\s+fast_mul_result\s*=\s*32'h00000000") {
    throw "cpu_core.v must assign fast_mul_result to zero in the FAST_MUL=0 generate branch."
}

Write-Host "PASS: fast multiplier combinational products are isolated from FAST_MUL=0 synthesis."
