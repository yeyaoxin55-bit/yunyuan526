# Phase63A Repo Temp Toolchain Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make CSR and RISC-V program build verification deterministic by forcing RISC-V toolchain scripts to use repo-local `build\tmp` for `TEMP/TMP`.

**Architecture:** Add a silent helper `scripts/use_repo_temp.ps1` exposing `Set-RepoTemp`. Wire it into the RISC-V build entry points and CSR acceptance wrapper before external tools or nested PowerShell processes run. Guard the boundary with `scripts/check_repo_temp_boundary.ps1`.

**Tech Stack:** Windows PowerShell, RISC-V GCC xPack, ModelSim, existing CSR/CoreMark acceptance scripts.

---

## File Map

- Create `scripts/use_repo_temp.ps1`: reusable repo-local temp helper.
- Create `scripts/check_repo_temp_boundary.ps1`: structural and behavior check for temp helper integration.
- Modify `scripts/check_project.ps1`: require helper/check files and invoke the new boundary check.
- Modify `scripts/build_baremetal.ps1`: set repo-local temp before RISC-V GCC.
- Modify `scripts/build_riscv_test.ps1`: set repo-local temp before RISC-V GCC/objcopy.
- Modify `scripts/build_coremark.ps1`: set repo-local temp before RISC-V GCC/objcopy.
- Modify `scripts/run_csr_phase_acceptance.ps1`: set repo-local temp before nested build/test steps.
- Modify `task_plan.md`, `findings.md`, and `progress.md`: record Phase63A design, implementation, and verification.

## Task 1: RED Boundary Check

**Files:**

- Create `scripts/check_repo_temp_boundary.ps1`
- Modify `scripts/check_project.ps1`

- [ ] **Step 1: Add the failing boundary check**

Create `scripts/check_repo_temp_boundary.ps1`:

```powershell
$ErrorActionPreference = "Stop"

function Require-File($Path) {
  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Missing required file: $Path"
  }
}

function Require-Match($Path, $Pattern, $Description) {
  $text = Get-Content -Raw $Path
  if ($text -notmatch $Pattern) {
    throw "Missing $Description in $Path"
  }
}

$helper = "scripts/use_repo_temp.ps1"
Require-File $helper
Require-Match $helper "function\s+Set-RepoTemp\b" "Set-RepoTemp function"
Require-Match $helper '\$env:TEMP\s*=' "TEMP assignment"
Require-Match $helper '\$env:TMP\s*=' "TMP assignment"

$requiredUsers = @(
  "scripts/build_baremetal.ps1",
  "scripts/build_riscv_test.ps1",
  "scripts/build_coremark.ps1",
  "scripts/run_csr_phase_acceptance.ps1"
)

foreach ($path in $requiredUsers) {
  Require-File $path
  Require-Match $path "use_repo_temp\.ps1" "repo temp helper include"
  Require-Match $path 'Set-RepoTemp\s+-RepoRoot\s+\$repoRoot' "repo temp setup call"
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $repoRoot $helper)
$selected = Set-RepoTemp -RepoRoot $repoRoot
$expected = (Resolve-Path -LiteralPath (Join-Path $repoRoot "build\tmp")).Path

if ($selected -ne $expected) {
  throw "Set-RepoTemp returned '$selected', expected '$expected'"
}
if ($env:TEMP -ne $expected -or $env:TMP -ne $expected) {
  throw "TEMP/TMP not set to repo temp. TEMP='$env:TEMP' TMP='$env:TMP' expected='$expected'"
}
if (-not (Test-Path -LiteralPath $expected)) {
  throw "Repo temp directory was not created: $expected"
}

Write-Host "Repo temp boundary OK"
```

- [ ] **Step 2: Hook the check into `scripts/check_project.ps1`**

Add both required file entries:

```powershell
"scripts/use_repo_temp.ps1",
"scripts/check_repo_temp_boundary.ps1",
```

Add this invocation before the final `Project structure OK`:

```powershell
& scripts/check_repo_temp_boundary.ps1
```

- [ ] **Step 3: Run RED**

Run:

```powershell
scripts/check_repo_temp_boundary.ps1
```

Expected:

```text
Missing required file: scripts/use_repo_temp.ps1
```

## Task 2: Implement Helper

**Files:**

- Create `scripts/use_repo_temp.ps1`

- [ ] **Step 1: Add helper**

Create:

```powershell
$ErrorActionPreference = "Stop"

function Set-RepoTemp {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,
    [string]$RelativeTempDir = "build\tmp"
  )

  $resolvedRepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
  $tempDir = Join-Path $resolvedRepoRoot $RelativeTempDir
  New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
  $resolvedTempDir = (Resolve-Path -LiteralPath $tempDir).Path
  $env:TEMP = $resolvedTempDir
  $env:TMP = $resolvedTempDir
  return $resolvedTempDir
}
```

- [ ] **Step 2: Run partial GREEN**

Run:

```powershell
scripts/check_repo_temp_boundary.ps1
```

Expected failure now moves from missing helper to missing helper usage in build scripts:

```text
Missing repo temp helper include in scripts/build_baremetal.ps1
```

## Task 3: Wire Build Scripts

**Files:**

- Modify `scripts/build_baremetal.ps1`
- Modify `scripts/build_riscv_test.ps1`
- Modify `scripts/build_coremark.ps1`
- Modify `scripts/run_csr_phase_acceptance.ps1`

- [ ] **Step 1: Add helper call after `$repoRoot` in each script**

In each target script, after resolving `$repoRoot`, add:

```powershell
. (Join-Path $repoRoot "scripts\use_repo_temp.ps1")
$repoTemp = Set-RepoTemp -RepoRoot $repoRoot
```

Do not print `$repoTemp`.

- [ ] **Step 2: Run GREEN boundary**

Run:

```powershell
scripts/check_repo_temp_boundary.ps1
```

Expected:

```text
Repo temp boundary OK
```

## Task 4: Project and Functional Verification

**Files:**

- Modify `task_plan.md`
- Modify `findings.md`
- Modify `progress.md`

- [ ] **Step 1: Run structural checks**

Run:

```powershell
scripts/check_project.ps1
git diff --check
```

Expected:

```text
Repo temp boundary OK
Project structure OK
```

- [ ] **Step 2: Run baremetal build smoke without manual TEMP override**

Run:

```powershell
scripts/build_baremetal.ps1 -Sources sw\csr_trap_tests\csr_rw.S -OutName csr_rw_temp_smoke -ToolPrefix xpack-riscv-none-elf-gcc-15.2.0-1\bin\riscv-none-elf- -OutDir build\csr_trap_tests_temp_smoke -March rv32im_zicsr -Mabi ilp32
```

Expected:

```text
ELF=...
MAP=...
```

- [ ] **Step 3: Run CSR acceptance without manual TEMP override**

Run:

```powershell
scripts/run_csr_phase_acceptance.ps1 -SkipVivado
```

Expected:

```text
CSR_PHASE_ACCEPTANCE_PASS=1
COREMARK_RESULT_CYCLES=<682500
```

## Task 5: Commit and Push

**Files:**

- All Phase63A files and records

- [ ] **Step 1: Commit**

Run:

```powershell
git add -- scripts/use_repo_temp.ps1 scripts/check_repo_temp_boundary.ps1 scripts/check_project.ps1 scripts/build_baremetal.ps1 scripts/build_riscv_test.ps1 scripts/build_coremark.ps1 scripts/run_csr_phase_acceptance.ps1 task_plan.md findings.md progress.md docs/superpowers/specs/2026-06-09-repo-temp-toolchain-hardening-design.md docs/superpowers/plans/2026-06-09-repo-temp-toolchain-hardening.md
git commit -m "Harden RISC-V build temp handling"
```

- [ ] **Step 2: Push**

Run:

```powershell
git push
```
