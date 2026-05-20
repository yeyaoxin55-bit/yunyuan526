Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$cpuCore = Get-Content -Raw -Path 'rtl/cpu_core.v'

$checks = @(
    @{
        Name = 'IF/ID carries predecoded load rs1'
        Pass = $cpuCore -match 'reg\s+\[4:0\]\s+if_id_load_rs1_q\s*;'
    },
    @{
        Name = 'IF/ID carries predecoded load immediate'
        Pass = $cpuCore -match 'reg\s+\[31:0\]\s+if_id_load_imm_q\s*;'
    },
    @{
        Name = 'Prefetch load immediate is decoded before IF/ID register'
        Pass = $cpuCore -match 'wire\s+\[31:0\]\s+prefetch_load_imm\s*=\s*\{\{20\{prefetch_instr\[31\]\}\},\s*prefetch_instr\[31:20\]\}\s*;'
    },
    @{
        Name = 'Early-read address uses predecoded load immediate'
        Pass = $cpuCore -match 'id_load_early_addr\s*=\s*id_load_early_base_data\s*\+\s*if_id_load_imm_q\s*;'
    },
    @{
        Name = 'Early-read base zero check uses predecoded load rs1'
        Pass = $cpuCore -match 'id_load_early_base_data\s*=\s*\(if_id_load_rs1_q\s*==\s*5''d0\)\s*\?\s*32''h00000000\s*:'
    },
    @{
        Name = 'Early-read dependency checks use predecoded load rs1'
        Pass = ($cpuCore -match 'if_id_load_base_inflight_dep\s*=\s*\(if_id_load_rs1_q\s*!=\s*5''d0\)') -and
               ($cpuCore -match 'if_id_load_base_load_resp_dep\s*=\s*\(if_id_load_rs1_q\s*!=\s*5''d0\)') -and
               ($cpuCore -match 'if_id_load_base_mem_wb_dep\s*=\s*\(if_id_load_rs1_q\s*!=\s*5''d0\)') -and
               ($cpuCore -match 'if_id_load_base_mul_resp_dep\s*=\s*\(if_id_load_rs1_q\s*!=\s*5''d0\)')
    }
)

$failed = @($checks | Where-Object { -not $_.Pass })
if ($failed.Count -ne 0) {
    $failed | ForEach-Object { Write-Error $_.Name }
    exit 1
}

Write-Host 'ID early-read predecode boundary checks passed'
