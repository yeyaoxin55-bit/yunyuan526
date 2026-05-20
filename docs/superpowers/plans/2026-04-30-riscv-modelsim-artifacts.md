# RISC-V ModelSim Artifacts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run the applicable official RV32UI/RV32UM tests and save reproducible ModelSim transcript logs plus `.wlf` waveform files.

**Architecture:** Keep the existing build/convert/sim flow unchanged by default. Add optional artifact parameters that only affect runs when explicitly requested.

**Tech Stack:** PowerShell, ModelSim/Questa `vlib`/`vlog`/`vsim`, existing Verilog testbench `tb/tb_external_program.v`.

---

### Task 1: Add Optional Artifact Parameters

**Files:**
- Modify: `scripts/run_external_modelsim.ps1`
- Modify: `scripts/run_riscv_test.ps1`
- Modify: `scripts/run_riscv_suite.ps1`

- [x] **Step 1: Verify current script rejects artifact parameters**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_riscv_suite.ps1 -Suite rv32ui -Tests simple -ArtifactDir build\modelsim_riscv_artifacts\red -Wave -FastMul 0 -MulStages 1
```

Expected: FAIL because `-ArtifactDir` and `-Wave` are not defined yet.

Actual: The test still ran because PowerShell accepted the unknown arguments as extra positional input, but the requested artifact files were absent. This verified the missing behavior.

- [x] **Step 2: Add pass-through parameters**

Add `WaveFile`, `TranscriptFile`, and `LogAllSignals` to `run_external_modelsim.ps1`; add pass-through arguments to `run_riscv_test.ps1`; add `ArtifactDir`, `Wave`, and `LogAllSignals` to `run_riscv_suite.ps1`.

- [x] **Step 3: Verify one official test creates artifacts**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_riscv_suite.ps1 -Suite rv32ui -Tests simple -ArtifactDir build\modelsim_riscv_artifacts\smoke -Wave -LogAllSignals -FastMul 0 -MulStages 1
```

Expected: PASS and create `rv32ui-simple.modelsim.log` plus `rv32ui-simple.wlf`.

### Task 2: Run Official Applicable Suites

**Files:**
- No RTL edits.
- Output: `build\modelsim_riscv_artifacts\rv32ui`
- Output: `build\modelsim_riscv_artifacts\rv32um`

- [x] **Step 1: Run RV32UI excluding unsupported `fence_i`**

Run all RV32UI tests except `fence_i` with FPGA-like `FAST_MUL=0 / MUL_STAGES=1`.

- [x] **Step 2: Run RV32UM**

Run all RV32UM tests with FPGA-like `FAST_MUL=0 / MUL_STAGES=1`.

- [x] **Step 3: Record `fence_i` separately**

Run `rv32ui/fence_i` separately with artifacts and report it as an expected architectural limitation if it fails.
