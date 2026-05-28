$ErrorActionPreference = "Stop"

$core = Get-Content -Raw "rtl/cpu_core.v"

if ($core -match "assign\s+redirect_register_wait\s*=\s*\(REGISTER_REDIRECT_TO_PC != 0\)\s*&&\s*\(\s*redirect_detect\s*\|\|\s*redirect_stage_valid\s*\)") {
  throw "redirect_register_wait still depends on live redirect_detect; this keeps writeback/forwarding data on ID/EX CE/R timing paths."
}

if ($core -match "if\s*\(\s*flush\s*\|\|\s*redirect_register_wait\s*\)") {
  throw "ID/EX clear still uses redirect_register_wait directly; use a registered redirect-clear event instead."
}

if ($core -match "if\s*\(\s*redirect_clear_pipe\s*\|\|\s*redirect_kill_ex_mem\s*\)") {
  throw "EX/MEM clear still uses live redirect_kill_ex_mem; keep this clear on the registered redirect boundary."
}

foreach ($name in @("redirect_stage_fire", "redirect_clear_pipe", "redirect_fetch_hold", "redirect_decode_kill")) {
  if ($core -notmatch $name) {
    throw "Missing registered redirect control boundary signal $name."
  }
}

if ($core -notmatch "redirect_clear_pipe\s*=\s*flush\s*\|\|\s*redirect_stage_fire") {
  throw "redirect_clear_pipe should be driven by committed flush or registered redirect_stage_fire."
}

if ($core -notmatch "redirect_fetch_hold\s*=\s*redirect_stage_fire") {
  throw "redirect_fetch_hold should be driven from registered redirect_stage_fire only."
}

if ($core -notmatch "redirect_decode_kill\s*=\s*\(REGISTER_REDIRECT_TO_PC != 0\)\s*&&\s*redirect_detect") {
  throw "redirect_decode_kill should squash wrong-path decode controls on the live detect cycle."
}

Write-Host "PASS: redirect registered control boundary checks passed."
