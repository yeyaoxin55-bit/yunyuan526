$ErrorActionPreference = "Stop"

$core = Get-Content -Raw -Path "rtl/cpu_core.v"
$cpuTop = Get-Content -Raw -Path "rtl/cpu_top.v"
$socTop = Get-Content -Raw -Path "rtl/soc_top.v"
$fpgaTop = Get-Content -Raw -Path "rtl/fpga_coremark_top.v"

if ($core -notmatch "parameter\s+REGISTER_REDIRECT_TO_PC") {
  throw "cpu_core.v must expose REGISTER_REDIRECT_TO_PC."
}

if ($cpuTop -notmatch "parameter\s+REGISTER_REDIRECT_TO_PC") {
  throw "cpu_top.v must pass REGISTER_REDIRECT_TO_PC."
}

if ($socTop -notmatch "parameter\s+REGISTER_REDIRECT_TO_PC\s*=\s*1") {
  throw "soc_top board default must register redirect correction before PC update."
}

if ($fpgaTop -notmatch "parameter\s+REGISTER_REDIRECT_TO_PC\s*=\s*1") {
  throw "fpga_coremark_top default must register redirect correction before PC update."
}

foreach ($name in @(
    "redirect_stage_valid",
    "redirect_stage_pc_q",
    "redirect_stage_fallthrough_pc_q",
    "redirect_stage_taken_q",
    "redirect_stage_branch_mispredict",
    "redirect_stage_jump_flush"
  )) {
  if ($core -notmatch $name) {
    throw "Missing registered redirect pre-stage signal $name."
  }
}

if ($core -notmatch "redirect_valid <= redirect_stage_valid") {
  throw "redirect_valid must be driven from the registered redirect pre-stage when REGISTER_REDIRECT_TO_PC is enabled."
}

if ($core -notmatch "wire\s+redirect_kill_ex_mem\s*=\s*\(REGISTER_REDIRECT_TO_PC != 0\)\s*&&\s*redirect_detect\s*&&\s*ctrl_replay_valid") {
  throw "Replay redirect must kill only the wrong-path EX/MEM output instead of blocking all older EX/MEM retirement."
}

if ($core -notmatch "wire\s+id_jalr_ras_redirect\s*=\s*\(REGISTER_REDIRECT_TO_PC == 0\)") {
  throw "JALR/RET ID-stage fast redirect must be disabled when REGISTER_REDIRECT_TO_PC is enabled."
}

if ($core -notmatch "wire\s+frontend_flush\s*=\s*flush\s*\|\|\s*id_jal_redirect\s*;") {
  throw "frontend_flush should keep the JAL fast path but remove JALR/RET fast flushing."
}

if ($core -match "pc <= id_jalr_ras_redirect \? ras_top_target : id_jal_target") {
  throw "pc update must not keep the old JALR/RET direct fast path."
}

Write-Host "PASS: registered redirect-to-PC timing checks passed."
