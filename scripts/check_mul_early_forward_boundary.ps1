Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$cpuCore = Get-Content -Raw -Path 'rtl/cpu_core.v'

$hasExpression = $cpuCore -match 'wire\s+mul_early_forward_valid\s*=\s*(?<expr>[^;]+);'
$expr = if ($hasExpression) { $Matches['expr'] } else { '' }

$checks = @(
    @{
        Name = 'cpu_core defines mul_early_forward_valid expression'
        Pass = $hasExpression
    },
    @{
        Name = 'mul_early_forward_valid is driven by multiplier early_valid'
        Pass = $expr -match '\bmul_early_valid\b'
    },
    @{
        Name = 'mul_early_forward_valid keeps rd zero guard'
        Pass = $expr -match '\(\s*mul_meta_rd_pipe\[1\]\s*!=\s*5''d0\s*\)'
    },
    @{
        Name = 'mul_early_forward_valid does not pull meta valid into EX forward mux'
        Pass = $expr -notmatch 'mul_meta_valid_pipe\s*\[\s*1\s*\]'
    },
    @{
        Name = 'mul_early_forward_valid does not pull meta reg_write into EX forward mux'
        Pass = $expr -notmatch 'mul_meta_reg_write_pipe\s*\[\s*1\s*\]'
    }
)

$failed = @($checks | Where-Object { -not $_.Pass })
if ($failed.Count -ne 0) {
    $failed | ForEach-Object { Write-Error $_.Name }
    exit 1
}

Write-Host 'Multiply early-forward boundary checks passed'
