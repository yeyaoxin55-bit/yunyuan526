param(
  [ValidateSet("generic", "xilinx_dsp")]
  [string]$Backend = "generic",
  [ValidateSet(32, 64)]
  [int]$Xlen = 32,
  [string]$VivadoPath = "",
  [int]$Jobs = 4
)

$ErrorActionPreference = "Stop"

$backendValue = if ($Backend -eq "xilinx_dsp") { 1 } else { 0 }
$outDir = "build/vivado_synth_m_unit_${Backend}_xlen${Xlen}_100m"

& scripts/run_vivado_synth.ps1 `
  -VivadoPath $VivadoPath `
  -Top m_unit `
  -Constraint 100m `
  -OutDir $outDir `
  -Jobs $Jobs `
  -Generic @("XLEN=$Xlen", "M_BACKEND=$backendValue", "MUL_PIPE_STAGES=4", "EPOCH_WIDTH=2")

if ($LASTEXITCODE -ne 0) {
  throw "M-unit OOC synthesis failed"
}

Write-Host "M_UNIT_OOC_BACKEND=$Backend"
Write-Host "M_UNIT_OOC_XLEN=$Xlen"
Write-Host "M_UNIT_OOC_REPORT_DIR=$outDir"
