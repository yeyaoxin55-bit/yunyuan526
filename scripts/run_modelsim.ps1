$ErrorActionPreference = "Stop"

$vlib = Get-Command vlib -ErrorAction SilentlyContinue
$vlog = Get-Command vlog -ErrorAction SilentlyContinue
$vsim = Get-Command vsim -ErrorAction SilentlyContinue

if (-not $vlib -or -not $vlog -or -not $vsim) {
  Write-Error "ModelSim commands not found in PATH. Required: vlib, vlog, vsim."
}

$workDir = "build/modelsim"
if (Test-Path -LiteralPath $workDir) {
  Remove-Item -LiteralPath $workDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $workDir | Out-Null

& vlib "$workDir/work"

$sources = @(
  "rtl/alu.v",
  "rtl/regfile.v",
  "rtl/decoder.v",
  "rtl/hazard_unit.v",
  "rtl/imem.v",
  "rtl/dmem.v",
  "rtl/csr_unit.v",
  "rtl/branch_predictor.v",
  "rtl/prefetch.v",
  "rtl/divider.v",
  "rtl/multiplier.v",
  "rtl/uart.v",
  "rtl/cpu_core.v",
  "rtl/cpu_top.v",
  "rtl/clk_gen_50m_to_100m.v",
  "rtl/soc_top.v",
  "tb/tb_cpu_top.v",
  "tb/tb_forwarding.v",
  "tb/tb_load_use.v",
  "tb/tb_load_use_one_stall.v",
  "tb/tb_load_use_zero_stall_early_read.v",
  "tb/tb_load_use_zero_stall_early_read_width.v",
  "tb/tb_load_base_from_load_resp_no_early.v",
  "tb/tb_load_use_timing_safe.v",
  "tb/tb_load_false_dep_no_stall.v",
  "tb/tb_load_branch_one_stall.v",
  "tb/tb_load_jalr_one_stall.v",
  "tb/tb_load_branch_zero_stall.v",
  "tb/tb_load_jalr_zero_stall.v",
  "tb/tb_load_branch_same_rd_replay.v",
  "tb/tb_load_branch_wrong_path_wb.v",
  "tb/tb_branch.v",
  "tb/tb_mem_width.v",
  "tb/tb_alu_full.v",
  "tb/tb_jump.v",
  "tb/tb_branch_conditions.v",
  "tb/tb_branch_predict.v",
  "tb/tb_registered_redirect.v",
  "tb/tb_upper_jump.v",
  "tb/tb_csr_counter.v",
  "tb/tb_branch_predictor.v",
  "tb/tb_prefetch.v",
  "tb/tb_mem_pipeline.v",
  "tb/tb_loader_memory_ports.v",
  "tb/tb_uart_single_module.v",
  "tb/tb_uart_loader.v",
  "tb/tb_multiplier.v",
  "tb/tb_uart_rx.v",
  "tb/tb_uart_tx.v",
  "tb/tb_mul.v",
  "tb/tb_mul_nonblocking.v",
  "tb/tb_div.v",
  "tb/tb_rv64i_basic.v",
  "tb/tb_rv64m_basic.v",
  "tb/tb_soc_uart_hello.v",
  "tb/tb_soc_uart_reset_start.v",
  "tb/tb_soc_uart_loader.v",
  "tb/tb_external_program.v"
)

$compileOutput = & vlog -work "$workDir/work" +incdir+rtl @sources 2>&1
$compileOutput
if ($LASTEXITCODE -ne 0 -or (($compileOutput | Out-String) -match "Errors:\s*[1-9]")) {
  throw "ModelSim vlog failed"
}

$tests = @(
  "tb_cpu_top",
  "tb_forwarding",
  "tb_load_use",
  "tb_load_use_one_stall",
  "tb_load_use_zero_stall_early_read",
  "tb_load_use_zero_stall_early_read_width",
  "tb_load_base_from_load_resp_no_early",
  "tb_load_use_timing_safe",
  "tb_load_false_dep_no_stall",
  "tb_load_branch_one_stall",
  "tb_load_jalr_one_stall",
  "tb_load_branch_zero_stall",
  "tb_load_jalr_zero_stall",
  "tb_load_branch_same_rd_replay",
  "tb_load_branch_wrong_path_wb",
  "tb_branch",
  "tb_mem_width",
  "tb_alu_full",
  "tb_jump",
  "tb_branch_conditions",
  "tb_branch_predict",
  "tb_registered_redirect",
  "tb_upper_jump",
  "tb_csr_counter",
  "tb_branch_predictor",
  "tb_prefetch",
  "tb_mem_pipeline",
  "tb_loader_memory_ports",
  "tb_uart_single_module",
  "tb_uart_loader",
  "tb_multiplier",
  "tb_uart_rx",
  "tb_uart_tx",
  "tb_mul",
  "tb_mul_nonblocking",
  "tb_div",
  "tb_rv64i_basic",
  "tb_rv64m_basic",
  "tb_soc_uart_hello",
  "tb_soc_uart_reset_start",
  "tb_soc_uart_loader"
)

foreach ($test in $tests) {
  $simOutput = & vsim -c -lib "$workDir/work" $test -do "run -all; quit -f" 2>&1
  $simOutput
  $simText = $simOutput | Out-String
  if ($LASTEXITCODE -ne 0 -or $simText -match "FAIL " -or $simText -match "Errors:\s*[1-9]") {
    throw "ModelSim test failed: $test"
  }
}
