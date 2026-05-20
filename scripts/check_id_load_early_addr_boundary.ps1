Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$cpuCore = Get-Content -Raw -Path 'rtl/cpu_core.v'
$baseAssign = [regex]::Match($cpuCore, 'wire\s+\[31:0\]\s+id_load_early_base_data\s*=[\s\S]*?;').Value
$checks = @(
    @{
        Name = 'ID early-read has a stable base-data signal'
        Pass = $cpuCore -match 'id_load_early_base_data'
    },
    @{
        Name = 'ID early-read address is not driven directly from bypassed rf_rs1_data'
        Pass = $cpuCore -notmatch 'id_load_early_addr\s*=\s*rf_rs1_data\s*\+'
    },
    @{
        Name = 'ID early-read base excludes same-cycle load response data'
        Pass = ($baseAssign -ne '') -and ($baseAssign -notmatch 'load_resp_data')
    }
)

$failed = @($checks | Where-Object { -not $_.Pass })
if ($failed.Count -ne 0) {
    $failed | ForEach-Object { Write-Error $_.Name }
    exit 1
}

Write-Host 'ID load early-read address boundary checks passed'
