Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$cpuCore = Get-Content -Raw -Path 'rtl/cpu_core.v'
$dividerInst = [regex]::Match($cpuCore, 'divider\s*#\([\s\S]*?\)\s*u_divider\s*\((?<body>[\s\S]*?)\);').Groups['body'].Value

$checks = @(
    @{
        Name = 'CPU has a registered divider command valid bit'
        Pass = $cpuCore -match 'reg\s+div_cmd_valid\s*;'
    },
    @{
        Name = 'CPU has registered divider operands and funct3'
        Pass = ($cpuCore -match 'reg\s+\[31:0\]\s+div_cmd_rs1_data\s*;') -and
               ($cpuCore -match 'reg\s+\[31:0\]\s+div_cmd_rs2_data\s*;') -and
               ($cpuCore -match 'reg\s+\[2:0\]\s+div_cmd_funct3\s*;')
    },
    @{
        Name = 'Divider starts from registered command valid'
        Pass = $cpuCore -match 'wire\s+div_start\s*=\s*div_cmd_valid\s*&&\s*!\s*div_busy\s*&&\s*!\s*div_valid\s*;'
    },
    @{
        Name = 'Divider operands come from registered command boundary'
        Pass = ($dividerInst -match '\.funct3_i') -or
               (($dividerInst -match '\.signed_i\(\s*\(div_cmd_funct3\s*==\s*3''b100\)') -and
                ($dividerInst -match '\.rem_i\(\s*div_cmd_funct3\[1\]\s*\)') -and
                ($dividerInst -match '\.dividend_i\(\s*div_cmd_rs1_data\s*\)') -and
                ($dividerInst -match '\.divisor_i\(\s*div_cmd_rs2_data\s*\)'))
    },
    @{
        Name = 'Divider no longer consumes forwarding data directly'
        Pass = ($dividerInst -ne '') -and
               ($dividerInst -notmatch 'forward_a_data') -and
               ($dividerInst -notmatch 'forward_b_data')
    }
)

$failed = @($checks | Where-Object { -not $_.Pass })
if ($failed.Count -ne 0) {
    $failed | ForEach-Object { Write-Error $_.Name }
    exit 1
}

Write-Host 'Divider operand boundary checks passed'
