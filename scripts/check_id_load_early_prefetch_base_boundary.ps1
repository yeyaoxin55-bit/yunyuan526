Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$cpuCore = Get-Content -Raw -Path 'rtl/cpu_core.v'
$regfile = Get-Content -Raw -Path 'rtl/regfile.v'
$baseAssign = [regex]::Match($cpuCore, 'wire\s+\[31:0\]\s+id_load_early_base_data\s*=[\s\S]*?;').Value

$checks = @(
    @{
        Name = 'Regfile exposes a third prefetch read-data port'
        Pass = ($regfile -match 'raddr3') -and ($regfile -match 'rdata3')
    },
    @{
        Name = 'CPU stores a registered IF/ID rs1 raw value for early-read base'
        Pass = $cpuCore -match 'reg\s+\[31:0\]\s+if_id_rs1_raw_data_q'
    },
    @{
        Name = 'CPU captures prefetch rs1 data into the IF/ID base register'
        Pass = ($cpuCore -match 'prefetch_rs1') -and ($cpuCore -match 'rf_prefetch_rs1_data') -and
               ($cpuCore -match 'if_id_rs1_raw_data_q\s*<=\s*prefetch_valid\s*\?\s*rf_prefetch_rs1_data')
    },
    @{
        Name = 'ID early-read base uses the registered IF/ID rs1 value'
        Pass = ($baseAssign -ne '') -and ($baseAssign -match 'if_id_rs1_raw_data_q')
    },
    @{
        Name = 'ID early-read base no longer directly uses the current regfile raw read port'
        Pass = ($baseAssign -ne '') -and ($baseAssign -notmatch 'rf_rs1_raw_data')
    }
)

$failed = @($checks | Where-Object { -not $_.Pass })
if ($failed.Count -ne 0) {
    $failed | ForEach-Object { Write-Error $_.Name }
    exit 1
}

Write-Host 'ID load early-read prefetch base boundary checks passed'
