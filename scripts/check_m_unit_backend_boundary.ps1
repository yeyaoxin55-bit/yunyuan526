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
Require-File "tb/tb_m_unit_backend_select.v"

Require-Match "rtl/m_unit.v" "parameter\s+M_BACKEND\s*=" "M_BACKEND parameter"
Require-Match "rtl/m_unit.v" "M_BACKEND_GENERIC" "generic backend selector"
Require-Match "rtl/m_unit.v" "M_BACKEND_XILINX_DSP" "xilinx backend selector"
Require-Match "rtl/m_unit.v" "m_unit_backend_generic" "generic backend instantiation"
Require-Match "rtl/m_unit.v" "m_unit_backend_xilinx_dsp" "xilinx backend instantiation"

Require-Match "rtl/m_unit_backend_generic.v" "module\s+m_unit_backend_generic\b" "generic backend module"
Require-Match "rtl/m_unit_backend_generic.v" '\$signed\(lhs_ext\)\s*\*\s*\$signed\(rhs_ext\)' "generic single signed product"
Require-Match "rtl/m_unit_backend_generic.v" "product_pipe\s*\[1\]\s*<=\s*product" "generic registered product stage 1"
Require-Match "rtl/m_unit_backend_generic.v" "product_pipe\s*\[2\]\s*<=\s*product_pipe\s*\[1\]" "generic registered product stage 2"

Require-Match "rtl/m_unit_backend_xilinx_dsp.v" "module\s+m_unit_backend_xilinx_dsp\b" "xilinx backend module"
Require-Match "rtl/m_unit_backend_xilinx_dsp.v" "use_dsp" "DSP synthesis attribute"
Require-Match "rtl/m_unit_backend_xilinx_dsp.v" "product_pipe" "xilinx full product pipeline"
Reject-Match "rtl/m_unit_backend_xilinx_dsp.v" "redirect|fallthrough|bp_update|csr_|trap|mret" "CPU control coupling in backend"

Write-Host "M-unit backend boundary OK"
