Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$cpuCore = Get-Content -Raw -Path 'rtl/cpu_core.v'

$checks = @(
    @{
        Name = 'jump unpredicted flush has a dedicated raw condition'
        Pass = $cpuCore -match 'wire\s+jump_unpredicted_flush_raw\s*=\s*take_jump\s*&&\s*!ctrl_jump_early_redirect\s*;'
    },
    @{
        Name = 'JALR target mismatch is gated by early redirect'
        Pass = $cpuCore -match 'wire\s+jalr_target_mismatch_flush_raw\s*=\s*take_jump\s*&&\s*ctrl_jalr\s*&&\s*ctrl_jump_early_redirect\s*&&\s*\(\s*jalr_target\s*!=\s*ctrl_pred_target\s*\)\s*;'
    },
    @{
        Name = 'jump_needs_flush_raw only combines the split raw conditions'
        Pass = $cpuCore -match 'wire\s+jump_needs_flush_raw\s*=\s*jump_unpredicted_flush_raw\s*\|\|\s*jalr_target_mismatch_flush_raw\s*;'
    }
)

$failed = @($checks | Where-Object { -not $_.Pass })
if ($failed.Count -ne 0) {
    $failed | ForEach-Object { Write-Error $_.Name }
    exit 1
}

Write-Host 'Redirect jump mismatch gating checks passed'
