$ErrorActionPreference = "Stop"

function Require-File {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Missing required file: $Path"
  }
}

function Require-Pattern {
  param(
    [string]$Name,
    [string]$Text,
    [string]$Pattern
  )
  if ($Text -notmatch $Pattern) {
    throw "Missing expected pattern for ${Name}: $Pattern"
  }
}

Require-File "rtl/soc_top.v"
Require-File "scripts/send_uart_image.ps1"
Require-File "tb/tb_soc_uart_reset_start.v"
Require-File "tb/programs/soc_fail.hex"

$socTop = Get-Content -Raw "rtl/soc_top.v"
$sendScript = Get-Content -Raw "scripts/send_uart_image.ps1"
$modelsim = Get-Content -Raw "scripts/run_modelsim.ps1"

Require-Pattern "BOOT_FROM_INIT default" $socTop "parameter\s+BOOT_FROM_INIT\s*=\s*1"
Require-Pattern "download mode signal" $socTop "wire\s+uart_debug_active\s*=\s*!uart_debug_key_n"
Require-Pattern "run armed register" $socTop "reg\s+run_armed_q"
Require-Pattern "start edge register" $socTop "reg\s+loader_start_cpu_q"
Require-Pattern "start pulse" $socTop "loader_start_pulse\s*=\s*loader_start_cpu\s*&&\s*!loader_start_cpu_q"
Require-Pattern "cpu reset from run armed" $socTop "cpu_rst\s*=\s*rst\s*\|\|\s*!run_armed_q"
Require-Pattern "download mode clears run armed" $socTop "if\s*\(\s*uart_debug_active\s*\)\s*begin\s*run_armed_q\s*<=\s*1'b0"
Require-Pattern "start pulse arms run" $socTop "else\s+if\s*\(\s*loader_start_pulse\s*\)\s*begin\s*run_armed_q\s*<=\s*1'b1"
Require-Pattern "reset arms normal boot" $socTop "run_armed_q\s*<=\s*\(BOOT_FROM_INIT\s*!=\s*0\)\s*&&\s*!uart_debug_active"

Require-Pattern "send script start option" $sendScript '\[switch\]\$StartAfterDownload'
Require-Pattern "send script conditional start" $sendScript 'if\s*\(\$StartAfterDownload\)'
Require-Pattern "send script default no start message" $sendScript "UART image sent without START"
Require-Pattern "reset-start regression wired" $modelsim "tb_soc_uart_reset_start"

Write-Host "soc_top reset-start flow OK"
