# Load Response EX Boundary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a parameterized timing-safe RTL boundary that prevents ordinary load responses from feeding the EX datapath directly.

**Architecture:** `cpu_core` gains `ENABLE_LOAD_RESP_EX_FORWARD`. When disabled, hazard logic stalls ordinary load consumers for the EX/MEM load-response cycle, while branch/JALR consumers still use the existing registered control replay path. FPGA-oriented tops default this parameter to timing-safe mode.

**Tech Stack:** Verilog RTL, ModelSim PowerShell scripts, Vivado implementation scripts.

---

### Task 1: RED Directed Regression

**Files:**
- Create: `tb/tb_load_use_timing_safe.v`
- Modify: `scripts/run_modelsim.ps1`

- [x] **Step 1: Add a timing-safe load-use test**

Create a testbench that runs `tb/programs/load_use.hex` with `ENABLE_LOAD_RESP_EX_FORWARD=0`. The test must check result word 2 equals 43 and hazard stall count equals 2.

- [x] **Step 2: Run RED**

Run: `powershell -ExecutionPolicy Bypass -File scripts\run_modelsim.ps1`

Expected: compile or simulation failure because `ENABLE_LOAD_RESP_EX_FORWARD` does not exist yet, or because current RTL only produces one stall.

### Task 2: RTL Parameter and Hazard Boundary

**Files:**
- Modify: `rtl/cpu_core.v`
- Modify: `rtl/cpu_top.v`
- Modify: `rtl/hazard_unit.v`
- Modify: `rtl/fpga_coremark_top.v`
- Modify: `rtl/soc_top.v`

- [x] **Step 1: Add `ENABLE_LOAD_RESP_EX_FORWARD` parameter pass-through**

Add the parameter to `cpu_core`, `cpu_top`, `fpga_coremark_top`, and `soc_top`. Keep `cpu_top` default at 1 for existing generic tests, and set FPGA-oriented top defaults to 0.

- [x] **Step 2: Gate ordinary load-response EX forwarding**

When the parameter is 0, ordinary `forward_a_data` and `forward_b_data` must not select `load_resp_data`. Use a separate replay-capture forwarding expression for load-to-branch/JALR replay.

- [x] **Step 3: Add second stall for ordinary EX consumers**

Extend `hazard_unit` so `ex_mem_load_use` causes a second stall when ordinary load-response EX forwarding is disabled. Keep branch/JALR replay consumers out of that second-stall class.

### Task 3: Script Support

**Files:**
- Modify: `tb/tb_external_program.v`
- Modify: `scripts/run_external_modelsim.ps1`
- Modify: `scripts/run_coremark.ps1`
- Modify: `scripts/run_riscv_test.ps1`
- Modify: `scripts/run_riscv_suite.ps1`

- [x] **Step 1: Add external simulation generic**

Expose `ENABLE_LOAD_RESP_EX_FORWARD` through `tb_external_program.v` and pass it from `run_external_modelsim.ps1`.

- [x] **Step 2: Add CoreMark parameter**

Expose `-LoadRespExForward` in `run_coremark.ps1` and forward it to `run_external_modelsim.ps1`.

### Task 4: Verification and Records

**Files:**
- Modify: `task_plan.md`
- Modify: `progress.md`
- Modify: `findings.md`

- [x] **Step 1: Run functional regressions**

Run `check_project`, full ModelSim, rv32um FPGA-like suite, and CoreMark 2/50 in timing-safe mode.

- [x] **Step 2: Run 100 MHz `soc_top` implementation**

Run the 100 MHz `alt_spread` timing sweep without the broad floorplan hook and compare WNS, resources, and CoreMark cycles against the previous baseline.

- [x] **Step 3: Update records**

Record the accepted RTL point, rejected observations, exact commands, timing numbers, and CoreMark numbers.
