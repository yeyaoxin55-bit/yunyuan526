$ErrorActionPreference = "Stop"

$core = Get-Content -LiteralPath "rtl/cpu_core.v" -Raw

function Require-Pattern {
  param(
    [string]$Name,
    [string]$Pattern
  )

  if ($core -notmatch $Pattern) {
    throw "Missing registered forward-select boundary: $Name"
  }
}

function Reject-Pattern {
  param(
    [string]$Name,
    [string]$Pattern
  )

  if ($core -match $Pattern) {
    throw "Forward-select boundary still has forbidden timing path: $Name"
  }
}

Require-Pattern "registered forward A select" "reg\s+\[1:0\]\s+id_ex_forward_a_sel"
Require-Pattern "registered forward B select" "reg\s+\[1:0\]\s+id_ex_forward_b_sel"
Require-Pattern "decode forward A candidate" "wire\s+\[1:0\]\s+dec_forward_a_sel"
Require-Pattern "decode forward B candidate" "wire\s+\[1:0\]\s+dec_forward_b_sel"
Require-Pattern "registered control load-response dependency" "reg\s+id_ex_control_load_resp_dep"
Require-Pattern "decode control load-response dependency candidate" "wire\s+dec_control_load_resp_dep"
Require-Pattern "EX data mux uses registered forward A" "forward_a_data\s*=\s*\(id_ex_forward_a_sel\s*==\s*2'd1\)"
Require-Pattern "EX data mux uses registered forward B" "forward_b_data\s*=\s*\(id_ex_forward_b_sel\s*==\s*2'd1\)"
Require-Pattern "hazard unit receives precomputed forward A" "\.id_ex_forward_a_i\s*\(id_ex_forward_a_sel\)"
Require-Pattern "hazard unit receives precomputed forward B" "\.id_ex_forward_b_i\s*\(id_ex_forward_b_sel\)"
Require-Pattern "control replay uses registered dependency bit" "wire\s+control_load_resp_dep\s*=\s*id_ex_valid\s*&&\s*id_ex_control_load_resp_dep\s*;"
Reject-Pattern "control_load_resp_dep depends directly on registered forward A select" "wire\s+control_load_resp_dep\s*=[^;]*id_ex_forward_a_sel\s*==\s*2'd3"
Reject-Pattern "control_load_resp_dep depends directly on registered forward B select" "wire\s+control_load_resp_dep\s*=[^;]*id_ex_forward_b_sel\s*==\s*2'd3"

Write-Host "Registered forward-select boundary OK"
