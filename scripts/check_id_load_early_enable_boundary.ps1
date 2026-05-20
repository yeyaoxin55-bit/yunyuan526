Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$cpuCore = Get-Content -Raw -Path 'rtl/cpu_core.v'
$enableAssign = [regex]::Match($cpuCore, 'wire\s+id_load_early_read\s*=[\s\S]*?;').Value
$checks = @(
    @{
        Name = 'ID early-read enable assignment exists'
        Pass = $enableAssign -ne ''
    },
    @{
        Name = 'ID early-read enable is not gated by global hazard stall'
        Pass = $enableAssign -notmatch 'hazard_stall'
    },
    @{
        Name = 'ID early-read enable is not gated by global pipe/control stalls'
        Pass = $enableAssign -notmatch 'pipe_wait|control_conflict_stall|ctrl_pending_conflict_stall'
    }
)

$failed = @($checks | Where-Object { -not $_.Pass })
if ($failed.Count -ne 0) {
    $failed | ForEach-Object { Write-Error $_.Name }
    exit 1
}

Write-Host 'ID load early-read enable boundary checks passed'
