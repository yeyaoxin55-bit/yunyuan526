Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$cpuCore = Get-Content -Raw -Path 'rtl/cpu_core.v'
$cpuTop = Get-Content -Raw -Path 'rtl/cpu_top.v'
$socTop = Get-Content -Raw -Path 'rtl/soc_top.v'

$checks = @(
    @{
        Name = 'cpu_core exports early-read qualifier'
        Pass = $cpuCore -match 'output\s+reg\s+dmem_read_early'
    },
    @{
        Name = 'cpu_top consumes early-read qualifier'
        Pass = $cpuTop -match 'wire\s+dmem_read_early' -and
               $cpuTop -match '\.dmem_read_early\(dmem_read_early\)'
    },
    @{
        Name = 'soc_top consumes early-read qualifier'
        Pass = $socTop -match 'wire\s+cpu_dmem_read_early' -and
               $socTop -match '\.dmem_read_early\(cpu_dmem_read_early\)'
    },
    @{
        Name = 'soc_top gates MMIO reads with architectural read'
        Pass = $socTop -match 'wire\s+cpu_dmem_arch_read\s*=\s*cpu_dmem_read\s*&&\s*!cpu_dmem_read_early\s*;' -and
               $socTop -notmatch 'mmio_read_q\s*<=\s*cpu_dmem_read\s*&&\s*mmio_sel\s*;' -and
               $socTop -notmatch 'if\s*\(\s*cpu_dmem_read\s*&&\s*mmio_sel\s*\)'
    }
)

$failed = @($checks | Where-Object { -not $_.Pass })
if ($failed.Count -ne 0) {
    $failed | ForEach-Object { Write-Error $_.Name }
    exit 1
}

Write-Host 'SoC early-read/MMIO boundary checks passed'
