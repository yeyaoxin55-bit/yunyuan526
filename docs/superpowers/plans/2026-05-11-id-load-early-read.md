# ID Load Early Read Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an optional ID-stage early DMEM read path that can remove the ordinary adjacent `load -> consumer` stall when the load base register is already available.

**Architecture:** The decode stage may issue a speculative-but-safe early read for an IF/ID load when the DMEM port is free and the base register does not depend on an in-flight producer. The returned data is carried with the load into ID/EX and EX/MEM, then the hazard unit may suppress the normal load-use stall and EX forwarding may use the early data from EX/MEM. The feature is parameter-gated and defaults off for compatibility until timing/performance are accepted.

**Tech Stack:** Verilog RTL, ModelSim, PowerShell regression scripts, RISC-V CoreMark test images.

---

### Task 1: RED Regression

**Files:**
- Create: `tb/tb_load_use_zero_stall_early_read.v`
- Modify: `scripts/run_modelsim.ps1`

- [x] **Step 1: Write a failing directed test**

Create a test that runs `tb/programs/load_use.hex`, enables `ENABLE_ID_LOAD_EARLY_READ`, expects result `43`, and requires zero `hazard_stall` cycles.

- [x] **Step 2: Run the test before RTL support**

Run targeted ModelSim compilation/simulation. Expected RED result: compile fails because `ENABLE_ID_LOAD_EARLY_READ` is not yet a `cpu_top` parameter, or the test fails with one load-use stall if parameter plumbing exists.

### Task 2: RTL Parameter and Datapath

**Files:**
- Modify: `rtl/hazard_unit.v`
- Modify: `rtl/cpu_core.v`
- Modify: `rtl/cpu_top.v`
- Modify later if needed: `rtl/soc_top.v`, `rtl/fpga_coremark_top.v`, `scripts/run_external_modelsim.ps1`, `scripts/run_coremark.ps1`, `scripts/run_vivado_impl.ps1`

- [x] **Step 1: Add parameter plumbing**

Add `ENABLE_ID_LOAD_EARLY_READ`, defaulting to `0`, through CPU hierarchy and scripts.

- [x] **Step 2: Add safe early-read qualification**

Allow early read only when the IF/ID instruction is a valid load, the frontend is not being flushed or redirected, the DMEM port is free from older EX/MEM memory operations, and the base register does not require EX/MEM, load-response, or multiplier forwarding.

- [x] **Step 3: Carry early-load data**

Capture the returned early read data into ID/EX with a valid bit, then carry it into EX/MEM with the load.

- [x] **Step 4: Suppress the hazard only when data is available**

The hazard unit may suppress an ID/EX load-use stall only when the ID/EX load has valid early data.

- [x] **Step 5: Forward early data**

When EX/MEM is a load with valid early data, make EX/MEM forwarding use that data instead of the load address.

### Task 3: Verification and Screening

- [x] **Step 1: GREEN directed test**

Run the new zero-stall test. Expected: pass, result `43`, stall count `0`.

- [x] **Step 2: Regression**

Run `scripts/check_project.ps1` and full `scripts/run_modelsim.ps1`.

- [x] **Step 3: Performance screen**

Run CoreMark 2 with `ENABLE_ID_LOAD_EARLY_READ=1`, early replay enabled, local-history 64/64 profile. Compare against `695145` cycles.

- [x] **Step 4: Official tests if CoreMark improves**

Run full `rv32um` and applicable `rv32ui` excluding `fence_i` with the new parameter enabled.

- [x] **Step 5: Synthesis-only screen**

If functional and performance results are good, run Vivado synthesis first, not place/route, to check resource and inferred memory QoR.

### Results

- Added `ENABLE_ID_LOAD_EARLY_READ` as an optional parameter, default off.
- Added directed regressions for zero-stall `lw -> addi` and width-formatted `lh/lbu -> addi`.
- Full ModelSim regression, `rv32um`, and applicable `rv32ui` excluding `fence_i` passed with the feature enabled.
- CoreMark 50 with early replay and local-history 64/64 measured `17057625` cycles, about `2.931 CoreMark/MHz` at 100 MHz.
- Synthesis-only `soc_top` Huoyue run completed with generic overrides bound correctly. QoR remained valid: `RAMD64E=16`, `BlockRAM=24`.
- Synth resource/timing screen: LUT `6682`, FF `7727`, BRAM36 `24`, DSP48 `12`, WNS `-4.199 ns`. Worst synth setup path is DMEM BRAM output to `mmio_rdata_q_reg[10]/R`, so the next RTL timing cleanup should isolate the SoC MMIO/debug readback path before attempting post-route.
