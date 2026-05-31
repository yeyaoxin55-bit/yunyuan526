Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptPath = "scripts/run_csr_phase_acceptance.ps1"
if (-not (Test-Path -LiteralPath $scriptPath)) {
  throw "Missing CSR phase acceptance script: $scriptPath"
}

$text = Get-Content -Raw -Path $scriptPath

$checks = @(
  @{
    Name = "supports skipping Vivado for fast simulation-only acceptance"
    Pass = $text -match '\[switch\]\s*\$SkipVivado'
  },
  @{
    Name = "runs project structure check"
    Pass = $text -match "check_project\.ps1"
  },
  @{
    Name = "runs CSR redirect ID timing-boundary check"
    Pass = $text -match "check_csr_redirect_id_boundary\.ps1"
  },
  @{
    Name = "runs CSR counter increment timing-boundary check"
    Pass = $text -match "check_csr_counter_increment_boundary\.ps1"
  },
  @{
    Name = "runs CSR trap commit timing-boundary check"
    Pass = $text -match "check_csr_trap_commit_boundary\.ps1"
  },
  @{
    Name = "runs CSR branch predictor update timing-boundary check"
    Pass = $text -match "check_csr_bp_update_boundary\.ps1"
  },
  @{
    Name = "runs CSR unit regression"
    Pass = $text -match "run_csr_unit_modelsim\.ps1"
  },
  @{
    Name = "runs local CSR trap programs including ID redirect kill"
    Pass = ($text -match "run_csr_trap_programs\.ps1") -and
           ($text -match "trap_kills_id_redirect")
  },
  @{
    Name = "runs accepted rv32mi suite including instret_overflow"
    Pass = ($text -match "rv32mi") -and ($text -match "instret_overflow")
  },
  @{
    Name = "runs rv32ui smoke"
    Pass = $text -match "rv32ui"
  },
  @{
    Name = "runs rv32um smoke"
    Pass = $text -match "rv32um"
  },
  @{
    Name = "runs CoreMark smoke"
    Pass = $text -match "run_coremark\.ps1"
  },
  @{
    Name = "runs soc_top Vivado implementation"
    Pass = ($text -match "run_vivado_impl\.ps1") -and ($text -match "soc_top") -and ($text -match "huoyue_uart")
  },
  @{
    Name = "runs Vivado QoR gate"
    Pass = $text -match "check_vivado_qor\.ps1"
  },
  @{
    Name = "runs Vivado timing gate"
    Pass = $text -match "check_vivado_timing\.ps1"
  }
)

$failed = @($checks | Where-Object { -not $_.Pass })
if ($failed.Count -ne 0) {
  $failed | ForEach-Object { Write-Error $_.Name }
  exit 1
}

Write-Host "CSR phase acceptance script checks passed"
