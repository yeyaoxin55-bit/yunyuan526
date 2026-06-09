# Phase63A Repo Temp Toolchain Hardening Design

## Problem

CSR acceptance can fail for an environmental reason unrelated to RTL: the RISC-V GCC toolchain writes temporary assembler/object files under `%TEMP%`, which currently resolves to `C:\Users\yayaoxin\AppData\Local\Temp`. On this machine C: reached `0` free bytes, causing `No space left on device` during `scripts/run_csr_phase_acceptance.ps1 -SkipVivado`.

This makes the verification gate nondeterministic. A candidate can appear broken even when the retained RTL is functionally unchanged.

## Goal

Make PowerShell build and acceptance scripts use a repo-local temporary directory, `build\tmp`, before invoking external build tools or nested PowerShell scripts.

## Scope

In scope:

- Add one helper script that sets `$env:TEMP` and `$env:TMP` to a resolved repo-local directory.
- Use the helper from script entry points that build RISC-V programs or run CSR acceptance.
- Add a structural/behavioral check that verifies the helper exists, is wired into the build scripts, and actually creates/sets `build\tmp`.
- Add the check to `scripts/check_project.ps1`.

Out of scope:

- No RTL changes.
- No changes to Vivado timing strategy.
- No cleanup of C: drive contents.
- No change to generated build artifacts or memory image formats.
- No broad rewrite of every PowerShell script. Vivado/ModelSim scripts can inherit the environment from acceptance scripts; the hard gate is on RISC-V GCC build paths.

## Architecture

Create `scripts/use_repo_temp.ps1` with a single function:

```powershell
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

Scripts dot-source the helper after resolving `$repoRoot`:

```powershell
. (Join-Path $repoRoot "scripts\use_repo_temp.ps1")
$repoTemp = Set-RepoTemp -RepoRoot $repoRoot
```

The function returns the selected directory for debugging, but callers do not print it during normal operation. This keeps existing parsers that search for `ELF=`, `MAP=`, `IMEM_HEX=`, `DMEM_HEX=`, and `COREMARK_*` stable.

## Files

- Create `scripts/use_repo_temp.ps1`
- Create `scripts/check_repo_temp_boundary.ps1`
- Modify `scripts/check_project.ps1`
- Modify `scripts/build_baremetal.ps1`
- Modify `scripts/build_riscv_test.ps1`
- Modify `scripts/build_coremark.ps1`
- Modify `scripts/run_csr_phase_acceptance.ps1`
- Modify `task_plan.md`
- Modify `findings.md`
- Modify `progress.md`

## Verification

Required checks:

```powershell
scripts/check_repo_temp_boundary.ps1
scripts/check_project.ps1
git diff --check
scripts/build_baremetal.ps1 -Sources sw\csr_trap_tests\csr_rw.S -OutName csr_rw_temp_smoke -ToolPrefix xpack-riscv-none-elf-gcc-15.2.0-1\bin\riscv-none-elf- -OutDir build\csr_trap_tests_temp_smoke -March rv32im_zicsr -Mabi ilp32
scripts/run_csr_phase_acceptance.ps1 -SkipVivado
```

Acceptance criteria:

- The structural check proves helper usage in all required build/acceptance entry points.
- `build\tmp` exists and `$env:TEMP/$env:TMP` are set to it inside the helper behavior check.
- Baremetal build succeeds without manually exporting `$env:TEMP` or `$env:TMP` at the command prompt.
- CSR acceptance passes and reports `CSR_PHASE_ACCEPTANCE_PASS=1`.
- CoreMark 2 remains under `682500` cycles.

## Risk

The main risk is accidentally printing extra output that breaks parser expectations in callers. The helper must be silent by default. The second risk is setting temporary paths too late; each build script must call the helper before invoking GCC, objcopy, or nested build scripts.
