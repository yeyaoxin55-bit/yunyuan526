Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$cpuCore = Get-Content -Raw -Path 'rtl/cpu_core.v'
$earlyReadAssign = [regex]::Match($cpuCore, 'wire\s+id_load_early_read\s*=[\s\S]*?;').Value
$inflightAssign = [regex]::Match($cpuCore, 'wire\s+if_id_load_base_inflight_dep\s*=[\s\S]*?;').Value

$checks = @(
    @{
        Name = 'ID early-read has a registered multiplier base-dependency boundary'
        Pass = $cpuCore -match 'reg\s+if_id_load_base_mul_pending_dep_q'
    },
    @{
        Name = 'ID early-read inflight base dependency excludes direct multiplier scoreboard dependency'
        Pass = ($inflightAssign -ne '') -and ($inflightAssign -notmatch 'if_id_rs1_mul_pending_dep') -and ($inflightAssign -notmatch 'mul_scoreboard')
    },
    @{
        Name = 'ID early-read enable is gated by the registered multiplier base-dependency boundary'
        Pass = ($earlyReadAssign -ne '') -and ($earlyReadAssign -match '!if_id_load_base_mul_pending_dep_q')
    },
    @{
        Name = 'ID early-read enable excludes direct multiplier scoreboard control'
        Pass = ($earlyReadAssign -ne '') -and
               ($earlyReadAssign -notmatch 'if_id_rs1_mul_pending_dep') -and
               ($earlyReadAssign -notmatch 'mul_scoreboard') -and
               ($earlyReadAssign -notmatch 'mul_pending_valid') -and
               ($earlyReadAssign -notmatch 'mul_resp_valid')
    }
)

$failed = @($checks | Where-Object { -not $_.Pass })
if ($failed.Count -ne 0) {
    $failed | ForEach-Object { Write-Error $_.Name }
    exit 1
}

Write-Host 'ID load early-read multiplier boundary checks passed'
