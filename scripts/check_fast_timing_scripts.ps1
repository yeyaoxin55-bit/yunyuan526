$ErrorActionPreference = "Stop"

function Require-File {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Missing fast timing script: $Path"
  }
}

function Require-Pattern {
  param(
    [string]$Path,
    [string]$Name,
    [string]$Pattern
  )

  $text = Get-Content -Raw -LiteralPath $Path
  if ($text -notmatch $Pattern) {
    throw "Missing fast timing script feature '$Name' in $Path"
  }
}

$scripts = @(
  "scripts/check_rtl_timing_risk.ps1",
  "scripts/run_vivado_post_synth_timing.ps1",
  "scripts/run_vivado_post_place_timing.ps1",
  "scripts/run_fast_timing_checks.ps1",
  "scripts/sync_vivado_project_rtl.ps1",
  "scripts/vivado_project_fast_timing.tcl",
  "scripts/vivado_fast_timing.tcl"
)

foreach ($script in $scripts) {
  Require-File $script
}

Require-Pattern "scripts/run_fast_timing_checks.ps1" "RTL lint entry" "check_rtl_timing_risk\.ps1"
Require-Pattern "scripts/run_fast_timing_checks.ps1" "post-synth entry" "run_vivado_post_synth_timing\.ps1"
Require-Pattern "scripts/run_fast_timing_checks.ps1" "post-place entry" "run_vivado_post_place_timing\.ps1"
Require-Pattern "scripts/run_vivado_post_synth_timing.ps1" "project fast timing Tcl" "vivado_project_fast_timing\.tcl"
Require-Pattern "scripts/run_vivado_post_place_timing.ps1" "project fast timing Tcl" "vivado_project_fast_timing\.tcl"
Require-Pattern "scripts/run_vivado_post_synth_timing.ps1" "existing Vivado project path" "ProjectPath"
Require-Pattern "scripts/run_vivado_post_place_timing.ps1" "existing Vivado project path" "ProjectPath"
Require-Pattern "scripts/sync_vivado_project_rtl.ps1" "RTL project overwrite" "Copy-Item"
Require-Pattern "scripts/vivado_project_fast_timing.tcl" "open existing project" "open_project"
Require-Pattern "scripts/vivado_project_fast_timing.tcl" "synth run" "launch_runs\s+synth_1"
Require-Pattern "scripts/vivado_project_fast_timing.tcl" "implementation run to place" "launch_runs\s+impl_1\s+-to_step\s+place_design"
Require-Pattern "scripts/vivado_fast_timing.tcl" "post-synth stage" 'stage\s+"synth"'
Require-Pattern "scripts/vivado_fast_timing.tcl" "post-place stage" 'stage\s+"place"'
Require-Pattern "scripts/vivado_fast_timing.tcl" "timing paths report" "report_timing\s+-max_paths"
Require-Pattern "scripts/vivado_fast_timing.tcl" "high fanout report" "report_high_fanout_nets"
Require-Pattern "scripts/vivado_fast_timing.tcl" "design analysis report" "report_design_analysis"
Require-Pattern "scripts/vivado_fast_timing.tcl" "qor suggestions report" "report_qor_suggestions"
Require-Pattern "scripts/vivado_fast_timing.tcl" "control sets report" "report_control_sets"
Require-Pattern "scripts/check_rtl_timing_risk.ps1" "risk family summary" "RiskFamilies"
Require-Pattern "scripts/check_rtl_timing_risk.ps1" "forwarding redirect risk" "forward.*redirect"
Require-Pattern "scripts/check_rtl_timing_risk.ps1" "flush data clear risk" "flush.*data"

Write-Host "Fast timing script structure OK"
