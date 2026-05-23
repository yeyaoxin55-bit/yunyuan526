$ErrorActionPreference = "Stop"

$core = Get-Content -Raw -Path "rtl/cpu_core.v"

if ($core -notmatch "m_ext_load_resp_forward_en") {
  throw "Missing m_ext_load_resp_forward_en timing boundary"
}
if ($core -notmatch "m_ext_load_resp_forward_en = \(FAST_MUL == 0\)") {
  throw "M-extension load-response forwarding must be limited to the registered FAST_MUL=0 path"
}
if ($core -notmatch "ex_load_resp_forward_en") {
  throw "Missing EX load-response forwarding gate"
}
if ($core -notmatch "if_id_m_ext_load_resp_dep") {
  throw "Missing M-extension load-response dependency marker"
}
if ($core -notmatch "m_ext_forward_a_data") {
  throw "Missing M-extension operand forwarding mux"
}
if ($core -notmatch "m_ext_forward_b_data") {
  throw "Missing M-extension operand forwarding mux"
}
if ($core -notmatch "\(forward_a_sel == 2'd3\) && ex_load_resp_forward_en") {
  throw "forward_a_data does not use the EX load-response forwarding gate"
}
if ($core -notmatch "\(forward_b_sel == 2'd3\) && ex_load_resp_forward_en") {
  throw "forward_b_data does not use the EX load-response forwarding gate"
}
if ($core -notmatch '\$signed\(m_ext_forward_a_data\) \* \$signed\(m_ext_forward_b_data\)') {
  throw "FAST_MUL still does not use the M-extension operand mux"
}
if ($core -notmatch '\.a_i\(m_ext_forward_a_data\)') {
  throw "Pipelined multiplier still does not use the M-extension operand mux"
}

Write-Host "M-extension load-response forwarding boundary OK"
