Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$socTop = Get-Content -Raw -Path 'rtl/soc_top.v'
$zeroAssigns = [regex]::Matches($socTop, "mmio_rdata_q\s*<=\s*32'h00000000;").Count
$checks = @(
    @{
        Name = 'MMIO read data is reset to zero'
        Pass = $socTop -match "if\s*\(rst\)[\s\S]*?mmio_rdata_q\s*<=\s*32'h00000000;"
    },
    @{
        Name = 'Unsupported MMIO reads hold read data instead of driving address-dependent clear'
        Pass = $socTop -notmatch "mmio_cycle_sel[\s\S]*?cycle_latched;[\s\S]*?else\s+begin\s+mmio_rdata_q\s*<=\s*32'h00000000;"
    },
    @{
        Name = 'MMIO read data only has reset-time zero assignment'
        Pass = $zeroAssigns -eq 1
    }
)

$failed = @($checks | Where-Object { -not $_.Pass })
if ($failed.Count -ne 0) {
    $failed | ForEach-Object { Write-Error $_.Name }
    exit 1
}

Write-Host 'SoC MMIO registered read-hold checks passed'
