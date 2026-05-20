Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$cpuCore = Get-Content -Raw -Path 'rtl/cpu_core.v'
$baseAssign = [regex]::Match($cpuCore, 'wire\s+\[31:0\]\s+id_load_early_base_data\s*=[\s\S]*?;').Value
$earlyReadAssign = [regex]::Match($cpuCore, 'wire\s+id_load_early_read\s*=[\s\S]*?;').Value

$checks = @(
    @{
        Name = 'ID early-read base excludes same-cycle MEM/WB retire bypass'
        Pass = ($baseAssign -ne '') -and ($baseAssign -notmatch 'mem_wb_write_en') -and ($baseAssign -notmatch 'wb_data')
    },
    @{
        Name = 'ID early-read base excludes same-cycle multiplier retire bypass'
        Pass = ($baseAssign -ne '') -and ($baseAssign -notmatch 'mul_resp_write_en') -and ($baseAssign -notmatch 'mul_resp_ready_data')
    },
    @{
        Name = 'ID early-read detects same-cycle MEM/WB base dependency'
        Pass = $cpuCore -match 'if_id_load_base_mem_wb_dep'
    },
    @{
        Name = 'ID early-read detects same-cycle multiplier-retire base dependency'
        Pass = $cpuCore -match 'if_id_load_base_mul_resp_dep'
    },
    @{
        Name = 'ID early-read enable is gated by stable retire-boundary dependencies'
        Pass = ($earlyReadAssign -ne '') -and
               ($earlyReadAssign -match '!if_id_load_base_mem_wb_dep') -and
               ($earlyReadAssign -match '!if_id_load_base_mul_resp_dep')
    }
)

$failed = @($checks | Where-Object { -not $_.Pass })
if ($failed.Count -ne 0) {
    $failed | ForEach-Object { Write-Error $_.Name }
    exit 1
}

Write-Host 'ID load early-read retire boundary checks passed'
