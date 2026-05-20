# soc_top 100MHz MMCM Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `soc_top` run the CPU/IMEM/DMEM/UART domain at a real 100MHz on the Huoyue board from the 50MHz `sys_clk` input.

**Architecture:** Add a small 7-series MMCM wrapper that generates `clk_100m` and `locked` from `sys_clk`. In RTL simulation the wrapper bypasses the vendor primitive so ModelSim does not need Xilinx simulation libraries. `soc_top` uses the generated clock for all existing logic and holds the CPU in reset until the MMCM is locked.

**Tech Stack:** Verilog RTL, Xilinx `MMCME2_BASE`/`BUFG`, PowerShell checks, ModelSim, Vivado 2022.2-compatible batch scripts.

---

### Task 1: Clocking Static Check

**Files:**
- Create: `scripts/check_soc_board_clock.ps1`
- Modify later: `scripts/check_project.ps1`

- [x] **Step 1: Write the failing static check**

Create a PowerShell check that requires:
- `rtl/clk_gen_50m_to_100m.v` exists.
- `soc_top` instantiates `clk_gen_50m_to_100m`.
- `soc_top` no longer has `wire clk = sys_clk`.
- `UART_CLKS_PER_BIT` defaults to `868`.
- ModelSim and Vivado source lists include the new clock module.

- [x] **Step 2: Run check to verify RED**

Run: `powershell -ExecutionPolicy Bypass -File scripts\check_soc_board_clock.ps1`

Expected: fails because the clock module and `soc_top` integration are not present yet.

### Task 2: Add MMCM Clock Module

**Files:**
- Create: `rtl/clk_gen_50m_to_100m.v`

- [ ] **Step 1: Implement simulation bypass and synthesis MMCM**

Use `ifndef SYNTHESIS` for ModelSim bypass. Use `MMCME2_BASE` with 50MHz input, VCO 1000MHz, and 100MHz output in synthesis.

- [ ] **Step 2: Connect clock domain in soc_top**

Modify `rtl/soc_top.v` so `clk` comes from the clock generator, CPU reset includes `!clk_locked`, and UART default divisor is `868`.

### Task 3: Update Build Flows

**Files:**
- Modify: `scripts/run_modelsim.ps1`
- Modify: `scripts/vivado_synth.tcl`
- Modify: `scripts/vivado_impl.tcl`
- Modify: `scripts/check_project.ps1`

- [ ] **Step 1: Add the new clock source to all RTL source lists**

Place `rtl/clk_gen_50m_to_100m.v` before `rtl/soc_top.v`.

- [ ] **Step 2: Add static check to project structure**

Require `rtl/clk_gen_50m_to_100m.v` and `scripts/check_soc_board_clock.ps1`.

### Task 4: Verification

**Files:**
- No production edits unless a verification failure identifies a needed fix.

- [ ] **Step 1: Run clocking check**

Run: `powershell -ExecutionPolicy Bypass -File scripts\check_soc_board_clock.ps1`

Expected: `soc_top board clocking OK`.

- [ ] **Step 2: Run project check**

Run: `powershell -ExecutionPolicy Bypass -File scripts\check_project.ps1`

Expected: `Project structure OK`.

- [ ] **Step 3: Run ModelSim regression**

Run: `powershell -ExecutionPolicy Bypass -File scripts\run_modelsim.ps1`

Expected: all testbenches pass.

- [ ] **Step 4: Run Vivado implementation with real board XDC**

Run: `powershell -ExecutionPolicy Bypass -File scripts\run_vivado_impl.ps1 -Top soc_top -Constraint huoyue_uart -OutDir build\vivado_impl_soc_top_huoyue_100m_mmcm -PlaceDirective AltSpreadLogic_high -PhysOptDirective AggressiveExplore -RouteDirective Explore -PostRoutePhysOptDirective AggressiveExplore -Jobs 4`

Expected: timing passes on generated 100MHz MMCM output clock and bitstream is generated.
