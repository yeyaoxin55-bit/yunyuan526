Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$cpuCore = Get-Content -Raw -Path 'rtl/cpu_core.v'
$assignMatches = [regex]::Matches(
    $cpuCore,
    'redirect_from_replay\s*<=\s*(?<expr>[^;]+);'
)
$normalAssigns = @(
    $assignMatches | Where-Object {
        $_.Groups['expr'].Value -notmatch "1'b0"
    }
)

$checks = @(
    @{
        Name = 'CPU updates redirect_from_replay in the redirect pipeline register block'
        Pass = $normalAssigns.Count -ne 0
    },
    @{
        Name = 'redirect_from_replay is registered from replay state only'
        Pass = @(
            $normalAssigns | Where-Object {
                ($_.Groups['expr'].Value -match 'ctrl_replay_valid') -and
                ($_.Groups['expr'].Value -match '!\s*pipe_wait')
            }
        ).Count -ne 0
    },
    @{
        Name = 'redirect_from_replay no longer depends on redirect_detect'
        Pass = $normalAssigns.Count -ne 0 -and
               @($normalAssigns | Where-Object {
                   $_.Groups['expr'].Value -match 'redirect_detect'
               }).Count -eq 0
    },
    @{
        Name = 'replay_flush remains gated by committed redirect flush'
        Pass = $cpuCore -match 'assign\s+replay_flush\s*=\s*flush\s*&&\s*redirect_from_replay\s*;'
    }
)

$failed = @($checks | Where-Object { -not $_.Pass })
if ($failed.Count -ne 0) {
    $failed | ForEach-Object { Write-Error $_.Name }
    exit 1
}

Write-Host 'Redirect-from-replay boundary checks passed'
