$ErrorActionPreference = "Stop"

$core = Get-Content -Raw -Path "rtl/cpu_core.v"
$cpuTop = Get-Content -Raw -Path "rtl/cpu_top.v"
$socTop = Get-Content -Raw -Path "rtl/soc_top.v"
$fpgaTop = Get-Content -Raw -Path "rtl/fpga_coremark_top.v"

if ($core -notmatch "m_ext_load_resp_forward_en") {
  throw "Missing m_ext_load_resp_forward_en timing boundary"
}
if ($core -notmatch "parameter\s+ENABLE_M_EXT_LOAD_RESP_FORWARD") {
  throw "cpu_core.v must expose ENABLE_M_EXT_LOAD_RESP_FORWARD"
}
if ($cpuTop -notmatch "parameter\s+ENABLE_M_EXT_LOAD_RESP_FORWARD") {
  throw "cpu_top.v must pass ENABLE_M_EXT_LOAD_RESP_FORWARD"
}
if ($socTop -notmatch "parameter\s+ENABLE_M_EXT_LOAD_RESP_FORWARD\s*=\s*0") {
  throw "soc_top board default must disable M-extension load-response forwarding"
}
if ($fpgaTop -notmatch "parameter\s+ENABLE_M_EXT_LOAD_RESP_FORWARD\s*=\s*0") {
  throw "fpga_coremark_top default must disable M-extension load-response forwarding"
}
if ($core -notmatch "m_ext_load_resp_forward_en = \(FAST_MUL == 0\) &&\s*\(ENABLE_M_EXT_LOAD_RESP_FORWARD != 0\)") {
  throw "M-extension load-response forwarding must be gated by ENABLE_M_EXT_LOAD_RESP_FORWARD"
}
if ($core -notmatch "dec_m_ext &&\s*\(\(\s*FAST_MUL != 0\s*\)\s*\|\|\s*\(\(ENABLE_M_EXT_LOAD_RESP_FORWARD == 0\)") {
  throw "M-extension load-response forwarding disable must add a decode stall for load->M dependencies"
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
if ($core -notmatch "\(id_ex_forward_a_sel == 2'd3\) && ex_load_resp_forward_en") {
  throw "forward_a_data does not use the EX load-response forwarding gate"
}
if ($core -notmatch "\(id_ex_forward_b_sel == 2'd3\) && ex_load_resp_forward_en") {
  throw "forward_b_data does not use the EX load-response forwarding gate"
}
if ($core -notmatch '\$signed\(m_ext_forward_a_data\) \* \$signed\(m_ext_forward_b_data\)') {
  throw "FAST_MUL still does not use the M-extension operand mux"
}
if ($core -notmatch '\.a_i\(m_ext_forward_a_data\)') {
  throw "Pipelined multiplier still does not use the M-extension operand mux"
}

Write-Host "M-extension load-response forwarding boundary OK"
