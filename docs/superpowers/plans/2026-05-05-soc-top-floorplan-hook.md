# soc_top Floorplan Hook Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a low-risk Vivado floorplan hook and run one light `soc_top` 100 MHz floorplanning experiment without changing CPU RTL.

**Architecture:** The PowerShell wrapper resolves an optional floorplan Tcl path and passes it to `scripts/vivado_impl.tcl`. The Vivado implementation script sources that Tcl after `opt_design` and before `place_design`, so pblocks can bind synthesized cells before placement. A dedicated check script verifies the hook wiring and the presence of the floorplan constraint file.

**Tech Stack:** PowerShell, Vivado Tcl, Xilinx Vivado 2022.2, existing RTL and timing reports.

---

### Task 1: Add a Failing Hook Check

**Files:**
- Create: `scripts/check_floorplan_hook.ps1`

- [x] **Step 1: Create the check script**

The script verifies:
- `scripts/run_vivado_impl.ps1` exposes `-FloorplanTcl`.
- `scripts/vivado_impl.tcl` accepts `-floorplan_tcl`.
- `scripts/vivado_impl.tcl` sources the floorplan Tcl before placement.
- `constraints/floorplan_soc_top_light.tcl` exists and contains pblock commands.

- [x] **Step 2: Run the check and verify RED**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\check_floorplan_hook.ps1
```

Expected before implementation: nonzero exit because the hook or floorplan file is missing.

### Task 2: Wire the Floorplan Hook

**Files:**
- Modify: `scripts/run_vivado_impl.ps1`
- Modify: `scripts/vivado_impl.tcl`
- Modify: `scripts/run_timing_sweep.ps1`

- [x] **Step 1: Add `-FloorplanTcl` to the PowerShell wrapper**

The wrapper resolves relative paths from the repository root, validates the file, prints it in the run header, and passes `-floorplan_tcl <path>` to Vivado.

- [x] **Step 2: Add `-floorplan_tcl` to the Vivado Tcl parser**

The Tcl script stores the normalized file path and sources it after `opt_design`, before `place_design`.

- [x] **Step 3: Let timing sweep pass the floorplan path**

The timing sweep wrapper exposes an optional `-FloorplanTcl` parameter and forwards it to each implementation run.

### Task 3: Add the Light Floorplan Experiment

**Files:**
- Create: `constraints/floorplan_soc_top_light.tcl`

- [x] **Step 1: Add a conservative pblock**

The floorplan Tcl creates a pblock for `u_core` and `u_dmem`, adds those cells if present, and applies a broad resource range on xc7z020. The pblock intentionally stays broad because the current timing failures are route dominated and move across multiple cones.

- [x] **Step 2: Verify the hook check is GREEN**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\check_floorplan_hook.ps1
```

Expected after implementation: prints `Floorplan hook OK`.

### Task 4: Run and Compare One 100 MHz Experiment

**Files:**
- Output: `build/vivado_impl_soc_top_100m_floorplan_light`

- [x] **Step 1: Run Vivado implementation**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_vivado_impl.ps1 -Top soc_top -Constraint huoyue_uart -OutDir build\vivado_impl_soc_top_100m_floorplan_light -FloorplanTcl constraints\floorplan_soc_top_light.tcl -Jobs 4 -PlaceDirective AltSpreadLogic_high -PhysOptDirective AggressiveExplore -RouteDirective Explore -PostRoutePhysOptDirective AggressiveExplore
```

- [x] **Step 2: Run QoR gate**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\check_vivado_qor.ps1 -ReportDir build\vivado_impl_soc_top_100m_floorplan_light -Top soc_top -MaxDistributedRam 64 -MinBlockRamTiles 24 -RequireDmemBlockRam
```

- [x] **Step 3: Compare against `alt_spread`**

Result: the correct 100 MHz floorplan run is `build/timing_sweep_soc_top_100m_floorplan_light/soc_top_100MHz_alt_spread`. It passes timing and QoR but only reaches WNS 0.000 ns, worse than the existing no-floorplan `alt_spread` baseline at WNS 0.013 ns. Keep the hook for future experiments, but keep the existing no-floorplan `alt_spread` bitstream as the board baseline.

Compare WNS, TNS, WHS, worst path, LUT, FF, RAMB36, DSP48. Keep `alt_spread` as board baseline unless the floorplan run is clearly better.
