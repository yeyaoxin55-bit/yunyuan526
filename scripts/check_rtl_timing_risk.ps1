param(
  [string]$RtlDir = "rtl",
  [switch]$FailOnRisk
)

$ErrorActionPreference = "Stop"

function Resolve-RepoPath {
  param([string]$Path)
  $repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
  if ([System.IO.Path]::IsPathRooted($Path)) {
    return $Path
  }
  return (Join-Path $repoRoot $Path)
}

function Add-Finding {
  param(
    [System.Collections.Generic.List[object]]$Findings,
    [string]$Severity,
    [string]$Family,
    [string]$Message,
    [object[]]$Matches
  )

  if ($Matches.Count -eq 0) {
    return
  }

  foreach ($match in $Matches) {
    [void]$Findings.Add([pscustomobject]@{
      Severity = $Severity
      Family = $Family
      Path = $match.Path
      Line = $match.LineNumber
      Text = $match.Line.Trim()
      Message = $Message
    })
  }
}

function Find-Pattern {
  param(
    [string[]]$Paths,
    [string]$Pattern
  )

  $items = @()
  foreach ($path in $Paths) {
    if (Test-Path -LiteralPath $path) {
      $items += Select-String -LiteralPath $path -Pattern $Pattern
    }
  }
  return ,$items
}

$resolvedRtlDir = Resolve-RepoPath -Path $RtlDir
if (-not (Test-Path -LiteralPath $resolvedRtlDir)) {
  throw "RTL directory not found: $resolvedRtlDir"
}

$cpuCore = Join-Path $resolvedRtlDir "cpu_core.v"
$dmem = Join-Path $resolvedRtlDir "dmem.v"
$prefetch = Join-Path $resolvedRtlDir "prefetch.v"
$socTop = Join-Path $resolvedRtlDir "soc_top.v"
$hazardUnit = Join-Path $resolvedRtlDir "hazard_unit.v"
$regfile = Join-Path $resolvedRtlDir "regfile.v"
$rtlFiles = @($cpuCore, $dmem, $prefetch, $socTop, $hazardUnit, $regfile)

foreach ($path in $rtlFiles) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Missing RTL file for timing scan: $path"
  }
}

$RiskFamilies = @(
  @{
    Name = "forward to redirect/control family"
    Severity = "WARN"
    Pattern = "forward.*redirect|redirect.*forward|control_forward|replay_forward"
    Message = "Forwarding or replay data is close to redirect/control logic; check that it is registered before driving PC correction."
  },
  @{
    Name = "flush data clear family"
    Severity = "WARN"
    Pattern = "flush.*data|flush\s*\|\||if\s*\(\s*flush\s*\)|frontend_flush"
    Message = "Flush/control clears wide pipeline data; inspect fanout and whether wide clears can be localized."
  },
  @{
    Name = "load response to execute family"
    Severity = "INFO"
    Pattern = "load_resp_forward_data|load_resp_forward_mem_data|ENABLE_LOAD_RESP_EX_FORWARD|ENABLE_M_EXT_LOAD_RESP_FORWARD"
    Message = "Load response data can enter EX/control paths; keep M-extension and redirect paths off this direct arc unless timing allows it."
  },
  @{
    Name = "early data memory family"
    Severity = "INFO"
    Pattern = "id_load_early_read|id_load_early_addr|dmem_read_early"
    Message = "ID-stage early load path touches DMEM address/read control; useful for CPI, but worth checking as a separate timing family."
  },
  @{
    Name = "redirect to PC family"
    Severity = "WARN"
    Pattern = "redirect_register_wait|redirect_valid|redirect_pc|pc\s*<="
    Message = "Redirect and PC update logic is timing-sensitive; prefer registered correction for JALR/branch/RET while keeping JAL early."
  },
  @{
    Name = "RV64M multiplier family"
    Severity = "INFO"
    Pattern = "mul_early_forward|mul_complete_forward|product_high|fast_mul_product|m_ext_forward"
    Message = "RV64M datapath width and multiplier forwarding can dominate delay; keep product metadata/result boundaries explicit."
  }
)

$findings = New-Object System.Collections.Generic.List[object]

foreach ($family in $RiskFamilies) {
  $matches = Find-Pattern -Paths $rtlFiles -Pattern $family.Pattern
  Add-Finding -Findings $findings `
              -Severity $family.Severity `
              -Family $family.Name `
              -Message $family.Message `
              -Matches $matches
}

$hardRegressions = New-Object System.Collections.Generic.List[object]
$cpuText = Get-Content -Raw -LiteralPath $cpuCore
$hazardText = Get-Content -Raw -LiteralPath $hazardUnit
$regfileText = Get-Content -Raw -LiteralPath $regfile

if ($cpuText -match "control_load_resp_dep\s*=.*dec_forward_[ab]_sel") {
  [void]$hardRegressions.Add([pscustomobject]@{
    Severity = "ERROR"
    Family = "forward to redirect/control family"
    Path = $cpuCore
    Line = 0
    Text = "control_load_resp_dep direct decode forwarding dependency"
    Message = "control_load_resp_dep must remain registered through id_ex_control_load_resp_dep before redirect/control replay."
  })
}

if ($cpuText -match "\(\(id_ex_forward_[ab]_sel\s*==\s*2'd3\).*control_load_resp_dep") {
  [void]$hardRegressions.Add([pscustomobject]@{
    Severity = "ERROR"
    Family = "load response to execute family"
    Path = $cpuCore
    Line = 0
    Text = "control_load_resp_dep uses live id_ex_forward_*_sel"
    Message = "Control replay dependency should not be recomputed from live forward select on the redirect path."
  })
}

if ($cpuText -notmatch "wire\s+id_load_early_base_wait\s*=\s*\(ENABLE_ID_LOAD_EARLY_READ != 0\)\s*&&") {
  [void]$hardRegressions.Add([pscustomobject]@{
    Severity = "ERROR"
    Family = "early data memory family"
    Path = $cpuCore
    Line = 0
    Text = "id_load_early_base_wait missing ENABLE_ID_LOAD_EARLY_READ gate"
    Message = "Board-default builds disable ID early load read, so its wait path must not keep driving frontend hold/reset timing."
  })
}

if ($cpuText -match "wire\s+\[XLEN-1:0\]\s+wb_data\s*=\s*\(mem_wb_wb_sel") {
  [void]$hardRegressions.Add([pscustomobject]@{
    Severity = "ERROR"
    Family = "load response to execute family"
    Path = $cpuCore
    Line = 0
    Text = "wb_data recomputes the MEM/WB select mux"
    Message = "The WB forward/write data should be registered at the MEM/WB boundary so mem_wb_wb_sel does not fan out into EX timing paths."
  })
}

if (($cpuText -notmatch "wire\s+rf_write2_load_bypass_en\s*=\s*load_wb_write_en\s*&&\s*\(ENABLE_LOAD_RESP_EX_FORWARD != 0\)") -or
    ($cpuText -notmatch "wire\s+\[XLEN-1:0\]\s+rf_write2_bypass_data\s*=\s*rf_write2_load_bypass_en\s*\?\s*load_resp_data\s*:")) {
  [void]$hardRegressions.Add([pscustomobject]@{
    Severity = "ERROR"
    Family = "load response to execute family"
    Path = $cpuCore
    Line = 0
    Text = "rf_write2 load-response bypass data is not separately gated"
    Message = "Timing-safe load response mode must not feed DMEM data into the register-file second write-port read bypass data cone."
  })
}

if ($hazardText -notmatch "load_resp_rf_bypass_stall\s*=\s*\(ENABLE_LOAD_RESP_EX_FORWARD == 0\)\s*&&\s*load_resp_decode_use") {
  [void]$hardRegressions.Add([pscustomobject]@{
    Severity = "ERROR"
    Family = "load response to execute family"
    Path = $hazardUnit
    Line = 0
    Text = "load_resp_rf_bypass_stall missing"
    Message = "Disabling the load-response register-file read bypass requires a decode stall while load_resp writes back."
  })
}

if (($regfileText -notmatch "input wire \[XLEN-1:0\] bypass2_data") -or
    ($regfileText -notmatch "bypass2_en\s*&&\s*we2\s*&&") -or
    ($regfileText -notmatch "\?\s*bypass2_data\s*:")) {
  [void]$hardRegressions.Add([pscustomobject]@{
    Severity = "ERROR"
    Family = "load response to execute family"
    Path = $regfile
    Line = 0
    Text = "regfile second write-port read bypass is not separated from write data"
    Message = "The register-file second write port must keep writeback data separate from same-cycle read bypass data."
  })
}

if ($hardRegressions.Count -gt 0) {
  foreach ($finding in $hardRegressions) {
    Write-Host ("[{0}] {1}: {2}" -f $finding.Severity, $finding.Family, $finding.Message)
    Write-Host ("  {0}:{1} {2}" -f $finding.Path, $finding.Line, $finding.Text)
  }
  throw "RTL timing hard regression detected"
}

$grouped = $findings | Group-Object Severity, Family | Sort-Object Name
foreach ($group in $grouped) {
  $sample = $group.Group | Select-Object -First 3
  Write-Host ("[{0}] matches={1}" -f $group.Name, $group.Count)
  foreach ($item in $sample) {
    Write-Host ("  {0}:{1} {2}" -f $item.Path, $item.Line, $item.Text)
  }
}

if ($FailOnRisk -and (($findings | Where-Object { $_.Severity -eq "WARN" }).Count -gt 0)) {
  throw "RTL timing risk warnings found"
}

Write-Host "RTL timing risk scan completed"
