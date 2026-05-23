$ErrorActionPreference = "Stop"

$core = Get-Content -Raw -Path "rtl/cpu_core.v"

if ($core -notmatch "if_id_load_rs1_nonzero_q") {
  throw "Missing registered IF/ID load rs1 nonzero boundary"
}

if ($core -match "id_load_early_base_data = \(if_id_load_rs1_q == 5'd0\)") {
  throw "ID early-read base mux still depends on a same-cycle rs1 zero compare"
}

if ($core -notmatch "id_load_early_base_data = !if_id_load_rs1_nonzero_q") {
  throw "ID early-read base mux must use the registered nonzero flag"
}

Write-Host "ID load rs1 nonzero boundary OK"
