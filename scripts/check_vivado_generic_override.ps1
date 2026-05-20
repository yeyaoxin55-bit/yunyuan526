param()

$ErrorActionPreference = "Stop"

$runImpl = Get-Content -Raw "scripts/run_vivado_impl.ps1"
$runSynth = Get-Content -Raw "scripts/run_vivado_synth.ps1"
$implTcl = Get-Content -Raw "scripts/vivado_impl.tcl"
$synthTcl = Get-Content -Raw "scripts/vivado_synth.tcl"
$sweep = Get-Content -Raw "scripts/run_timing_sweep.ps1"

$checks = @(
  @{ Name = "run_vivado_synth exposes Generic parameter"; Text = $runSynth; Pattern = '\[string\[\]\]\s*\$Generic' },
  @{ Name = "run_vivado_synth forwards generic tclargs"; Text = $runSynth; Pattern = '"-generic",\s*\$generic' },
  @{ Name = "vivado_synth parses generic option"; Text = $synthTcl; Pattern = '\$key eq "-generic"' },
  @{ Name = "vivado_synth passes generic to synth_design"; Text = $synthTcl; Pattern = 'synth_design[^\r\n]+-generic\s+\$generic_overrides' },
  @{ Name = "run_vivado_impl exposes Generic parameter"; Text = $runImpl; Pattern = '\[string\[\]\]\s*\$Generic' },
  @{ Name = "run_vivado_impl forwards generic tclargs"; Text = $runImpl; Pattern = '"-generic",\s*\$generic' },
  @{ Name = "vivado_impl parses generic option"; Text = $implTcl; Pattern = '\$key eq "-generic"' },
  @{ Name = "vivado_impl passes generic to synth_design"; Text = $implTcl; Pattern = 'synth_design[^\r\n]+-generic\s+\$generic_overrides' },
  @{ Name = "run_timing_sweep exposes Generic parameter"; Text = $sweep; Pattern = '\[string\[\]\]\s*\$Generic' },
  @{ Name = "run_timing_sweep forwards Generic parameter"; Text = $sweep; Pattern = '\$implParams\.Generic\s*=\s*\$Generic' }
)

$failed = @()
foreach ($check in $checks) {
  if ($check.Text -notmatch $check.Pattern) {
    $failed += $check.Name
  }
}

if ($failed.Count -gt 0) {
  Write-Error ("Vivado generic override check failed: {0}" -f ($failed -join "; "))
  exit 1
}

Write-Host "Vivado generic override OK"
