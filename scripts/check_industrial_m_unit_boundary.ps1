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

function Reject-Match($Path, $Pattern, $Description) {
  $text = Get-Content -Raw $Path
  if ($text -match $Pattern) {
    throw "Rejected $Description in $Path"
  }
}

Require-File "rtl/m_unit.v"
Require-Match "rtl/m_unit.v" "module\s+m_unit\b" "m_unit module"
Require-Match "rtl/m_unit.v" "parameter\s+XLEN\s*=" "XLEN parameter"
Require-Match "rtl/m_unit.v" "req_valid_i" "request valid input"
Require-Match "rtl/m_unit.v" "req_ready_o" "request ready output"
Require-Match "rtl/m_unit.v" "resp_valid_o" "response valid output"
Require-Match "rtl/m_unit.v" "resp_ready_i" "response ready input"
Require-Match "rtl/m_unit.v" "req_epoch_i" "request epoch metadata"
Require-Match "rtl/m_unit.v" "current_epoch_i" "current epoch kill input"
Require-Match "rtl/m_unit.v" "lhs_ext" "unified operand extension"
Require-Match "rtl/m_unit.v" "rhs_ext" "unified operand extension"
Require-Match "rtl/m_unit.v" '\$signed\(lhs_ext\)\s*\*\s*\$signed\(rhs_ext\)' "single signed product"
Require-Match "rtl/m_unit.v" "product_pipe" "registered full-width product pipeline"
Require-Match "rtl/m_unit.v" "product_pipe\s*\[1\]\s*<=\s*product" "registered product before result selection"
Require-Match "rtl/m_unit.v" "product_pipe\s*\[2\]\s*<=\s*product_pipe\s*\[1\]" "second registered product stage for DSP MREG/PREG"
Require-Match "rtl/m_unit.v" "product_pipe\s*\[2\]\s*\[XLEN-1:0\]" "result selection from second registered product stage"
Reject-Match "rtl/m_unit.v" "product_ss" "parallel signed-signed product"
Reject-Match "rtl/m_unit.v" "product_uu" "parallel unsigned product"
Reject-Match "rtl/m_unit.v" "product_su" "parallel signed-unsigned product"

Write-Host "Industrial M-unit boundary OK"
