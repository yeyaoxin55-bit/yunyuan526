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
Require-File "rtl/m_unit_backend_generic.v"
Require-File "rtl/m_unit_backend_xilinx_dsp.v"
Require-Match "rtl/m_unit.v" "module\s+m_unit\b" "m_unit module"
Require-Match "rtl/m_unit.v" "parameter\s+XLEN\s*=" "XLEN parameter"
Require-Match "rtl/m_unit.v" "parameter\s+M_BACKEND\s*=" "M_BACKEND parameter"
Require-Match "rtl/m_unit.v" "req_valid_i" "request valid input"
Require-Match "rtl/m_unit.v" "req_ready_o" "request ready output"
Require-Match "rtl/m_unit.v" "resp_valid_o" "response valid output"
Require-Match "rtl/m_unit.v" "resp_ready_i" "response ready input"
Require-Match "rtl/m_unit.v" "req_epoch_i" "request epoch metadata"
Require-Match "rtl/m_unit.v" "current_epoch_i" "current epoch kill input"
Require-Match "rtl/m_unit.v" "m_unit_backend_generic" "generic backend instantiation"
Require-Match "rtl/m_unit.v" "m_unit_backend_xilinx_dsp" "xilinx backend instantiation"
Require-Match "rtl/m_unit_backend_generic.v" "lhs_ext" "generic unified operand extension"
Require-Match "rtl/m_unit_backend_generic.v" "rhs_ext" "generic unified operand extension"
Require-Match "rtl/m_unit_backend_generic.v" '\$signed\(lhs_ext\)\s*\*\s*\$signed\(rhs_ext\)' "generic single signed product"
Require-Match "rtl/m_unit_backend_generic.v" "product_pipe" "generic registered full-width product pipeline"
Require-Match "rtl/m_unit_backend_generic.v" "product_pipe\s*\[1\]\s*<=\s*product" "generic registered product before result selection"
Require-Match "rtl/m_unit_backend_generic.v" "product_pipe\s*\[2\]\s*<=\s*product_pipe\s*\[1\]" "generic second registered product stage"
Require-Match "rtl/m_unit_backend_generic.v" "product_pipe\s*\[2\]\s*\[XLEN-1:0\]" "generic result selection from second product stage"
Require-Match "rtl/m_unit_backend_xilinx_dsp.v" "use_dsp" "xilinx DSP synthesis attribute"
Require-Match "rtl/m_unit_backend_xilinx_dsp.v" "product_pipe" "xilinx registered full-width product pipeline"
Reject-Match "rtl/m_unit_backend_generic.v" "product_ss" "parallel signed-signed product"
Reject-Match "rtl/m_unit_backend_generic.v" "product_uu" "parallel unsigned product"
Reject-Match "rtl/m_unit_backend_generic.v" "product_su" "parallel signed-unsigned product"

Write-Host "Industrial M-unit boundary OK"
