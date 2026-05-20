Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$cpuCore = Get-Content -Raw -Path 'rtl/cpu_core.v'
$earlyReadAssign = [regex]::Match($cpuCore, 'wire\s+id_load_early_read\s*=[\s\S]*?;').Value

$checks = @(
    @{
        Name = 'CPU stores a registered IF/ID load opcode flag'
        Pass = $cpuCore -match 'reg\s+if_id_mem_read_q'
    },
    @{
        Name = 'CPU predecodes load opcode from prefetch instruction'
        Pass = ($cpuCore -match 'prefetch_mem_read') -and
               ($cpuCore -match 'prefetch_instr\[6:0\]\s*==\s*`OPCODE_LOAD')
    },
    @{
        Name = 'CPU captures prefetch load opcode into IF/ID load flag'
        Pass = $cpuCore -match 'if_id_mem_read_q\s*<=\s*prefetch_valid\s*&&\s*prefetch_mem_read'
    },
    @{
        Name = 'ID early-read enable uses registered load opcode flag'
        Pass = ($earlyReadAssign -ne '') -and ($earlyReadAssign -match 'if_id_mem_read_q')
    },
    @{
        Name = 'ID early-read enable no longer directly uses decoder mem_read'
        Pass = ($earlyReadAssign -ne '') -and ($earlyReadAssign -notmatch 'dec_mem_read')
    }
)

$failed = @($checks | Where-Object { -not $_.Pass })
if ($failed.Count -ne 0) {
    $failed | ForEach-Object { Write-Error $_.Name }
    exit 1
}

Write-Host 'ID load early-read opcode boundary checks passed'
