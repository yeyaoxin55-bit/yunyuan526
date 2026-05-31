param(
  [switch]$SkipVivado,
  [string]$VivadoPath = "",
  [string]$VivadoOutDir = "build/vivado_impl_soc_top_csr_phase54_id_boundary_100m",
  [ValidateSet("default", "explore", "alt_spread", "extra_net_delay")]
  [string]$VivadoStrategy = "alt_spread",
  [int]$Jobs = 4
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path

function Invoke-AcceptanceStep {
  param(
    [Parameter(Mandatory=$true)][string]$Name,
    [Parameter(Mandatory=$true)][scriptblock]$Body
  )

  Write-Host ""
  Write-Host "=== CSR_PHASE_STEP_BEGIN: $Name ==="
  & $Body
  Write-Host "=== CSR_PHASE_STEP_PASS: $Name ==="
}

function Get-VivadoDirectives {
  param([string]$Strategy)

  $directives = @{
    PlaceDirective = ""
    PhysOptDirective = ""
    RouteDirective = ""
    PostRoutePhysOptDirective = ""
  }

  if ($Strategy -eq "explore") {
    $directives.PlaceDirective = "Explore"
    $directives.PhysOptDirective = "AggressiveExplore"
    $directives.RouteDirective = "Explore"
    $directives.PostRoutePhysOptDirective = "AggressiveExplore"
  } elseif ($Strategy -eq "alt_spread") {
    $directives.PlaceDirective = "AltSpreadLogic_high"
    $directives.PhysOptDirective = "AggressiveExplore"
    $directives.RouteDirective = "Explore"
    $directives.PostRoutePhysOptDirective = "AggressiveExplore"
  } elseif ($Strategy -eq "extra_net_delay") {
    $directives.PlaceDirective = "ExtraNetDelay_high"
    $directives.PhysOptDirective = "AggressiveExplore"
    $directives.RouteDirective = "Explore"
    $directives.PostRoutePhysOptDirective = "AggressiveExplore"
  }

  return $directives
}

$csrTrapTests = @(
  "csr_rw",
  "ecall_mret",
  "ebreak",
  "illegal_csr",
  "illegal_instr",
  "misaligned_store",
  "misaligned_load",
  "misaligned_branch",
  "misaligned_jal",
  "misaligned_jalr",
  "trap_kills_id_redirect"
)

$rv32miTests = @(
  "csr",
  "mcsr",
  "illegal",
  "scall",
  "sbreak",
  "shamt",
  "lh-misaligned",
  "lw-misaligned",
  "sh-misaligned",
  "sw-misaligned",
  "ma_fetch",
  "ma_addr",
  "instret_overflow"
)

$rv32uiSmoke = @("add", "beq", "jal", "jalr", "lw", "sw")
$rv32umSmoke = @("mul", "div")

Invoke-AcceptanceStep -Name "project structure" -Body {
  & (Join-Path $repoRoot "scripts\check_project.ps1")
}

Invoke-AcceptanceStep -Name "CSR redirect ID timing boundary" -Body {
  & (Join-Path $repoRoot "scripts\check_csr_redirect_id_boundary.ps1")
}

Invoke-AcceptanceStep -Name "CSR counter increment timing boundary" -Body {
  & (Join-Path $repoRoot "scripts\check_csr_counter_increment_boundary.ps1")
}

Invoke-AcceptanceStep -Name "CSR trap commit timing boundary" -Body {
  & (Join-Path $repoRoot "scripts\check_csr_trap_commit_boundary.ps1")
}

Invoke-AcceptanceStep -Name "CSR branch predictor update timing boundary" -Body {
  & (Join-Path $repoRoot "scripts\check_csr_bp_update_boundary.ps1")
}

Invoke-AcceptanceStep -Name "CSR unit ModelSim regression" -Body {
  & (Join-Path $repoRoot "scripts\run_csr_unit_modelsim.ps1")
}

Invoke-AcceptanceStep -Name "local CSR trap programs" -Body {
  & (Join-Path $repoRoot "scripts\run_csr_trap_programs.ps1") -Tests $csrTrapTests
}

Invoke-AcceptanceStep -Name "official rv32mi CSR/trap acceptance" -Body {
  & (Join-Path $repoRoot "scripts\run_riscv_suite.ps1") -Suite rv32mi -Tests $rv32miTests
}

Invoke-AcceptanceStep -Name "official rv32ui smoke" -Body {
  & (Join-Path $repoRoot "scripts\run_riscv_suite.ps1") -Suite rv32ui -Tests $rv32uiSmoke
}

Invoke-AcceptanceStep -Name "official rv32um smoke" -Body {
  & (Join-Path $repoRoot "scripts\run_riscv_suite.ps1") -Suite rv32um -Tests $rv32umSmoke
}

Invoke-AcceptanceStep -Name "CoreMark 2 smoke" -Body {
  & (Join-Path $repoRoot "scripts\run_coremark.ps1") `
    -Iterations 2 `
    -TotalDataSize 2000 `
    -MaxCycles 2000000 `
    -OptLevel -O3 `
    -ExtraCFlags "-funroll-loops" `
    -PerfStats
}

if ($SkipVivado) {
  Write-Host ""
  Write-Host "CSR_PHASE_VIVADO_SKIPPED=1"
} else {
  $directives = Get-VivadoDirectives -Strategy $VivadoStrategy
  $implArgs = @{
    Top = "soc_top"
    Constraint = "huoyue_uart"
    OutDir = $VivadoOutDir
    Jobs = $Jobs
    PlaceDirective = $directives.PlaceDirective
    PhysOptDirective = $directives.PhysOptDirective
    RouteDirective = $directives.RouteDirective
    PostRoutePhysOptDirective = $directives.PostRoutePhysOptDirective
  }
  if ($VivadoPath -ne "") {
    $implArgs.VivadoPath = $VivadoPath
  }

  Invoke-AcceptanceStep -Name "soc_top Huoyue 100MHz Vivado implementation" -Body {
    & (Join-Path $repoRoot "scripts\run_vivado_impl.ps1") @implArgs
  }

  Invoke-AcceptanceStep -Name "soc_top BRAM QoR gate" -Body {
    & (Join-Path $repoRoot "scripts\check_vivado_qor.ps1") `
      -ReportDir $VivadoOutDir `
      -Top soc_top `
      -MaxDistributedRam 64 `
      -MinBlockRamTiles 1 `
      -RequireDmemBlockRam
  }

  Invoke-AcceptanceStep -Name "soc_top 100MHz timing gate" -Body {
    & (Join-Path $repoRoot "scripts\check_vivado_timing.ps1") `
      -ReportDir $VivadoOutDir `
      -MinWns 0.0 `
      -MaxSetupFailingEndpoints 0 `
      -MaxHoldFailingEndpoints 0
  }
}

Write-Host ""
Write-Host "CSR_PHASE_ACCEPTANCE_PASS=1"
