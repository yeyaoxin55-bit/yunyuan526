# Phase62B Writeback Arbiter Extraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

## Final Result

Status: rejected and reverted.

The candidate passed focused RED/GREEN testing, structural checks, full ModelSim, and CSR phase acceptance with CoreMark 2 unchanged at `649893` cycles. It was rejected by the physical retention gate because full Huoyue `soc_top` implementation reached WNS `-1.856 ns`, worse than the retained artifact WNS `-1.064 ns`. QoR itself was acceptable (`RAMD64E=0`, `BlockRAM=24`), but the worst path remained in the redirect PC cone: `u_core/ex_mem_valid_reg/C` to `u_core/redirect_pc_q_reg[19]/D`.

RTL/test/check/source-list changes were reverted. This plan is retained as evidence that a writeback-only extraction is not enough to improve the current physical bottleneck.

**Goal:** Extract the writeback selection logic from `cpu_core` into a small XLEN-parameterized `writeback_arb` module without changing CPU behavior.

**Architecture:** `cpu_core` keeps pipeline timing, retire decisions, replay/flush kill, and M/load retirement policy. `writeback_arb` is a pure combinational selector for primary MEM/WB writeback and secondary shared load/M writeback, preserving load-over-multiply shared port priority even when the load targets `x0`.

**Tech Stack:** Verilog RTL, ModelSim, Vivado 2022.2, PowerShell structural checks, existing CSR/CoreMark/Vivado acceptance scripts.

---

## File Map

- Create `rtl/writeback_arb.v`: combinational writeback selector with `parameter XLEN = 32`.
- Create `tb/tb_writeback_arb.v`: focused tests for MEM/WB select, x0 suppression, shared load priority, and XLEN64 behavior.
- Create `scripts/check_writeback_arb_boundary.ps1`: structural guard that rejects redirect/trap/predictor/RAS coupling.
- Modify `rtl/cpu_core.v`: replace inline `wb_data`, `mem_wb_write_en`, and `shared_wb2_*` assignments with a `writeback_arb` instance.
- Modify `scripts/run_modelsim.ps1`: compile `writeback_arb.v` and run `tb_writeback_arb`.
- Modify `scripts/run_external_modelsim.ps1`: compile `writeback_arb.v` for program tests.
- Modify `scripts/vivado_synth.tcl` and `scripts/vivado_impl.tcl`: include `writeback_arb.v` in Vivado source lists.
- Modify `scripts/check_project.ps1`: require the new files and run the new structural check.
- Modify `task_plan.md`, `findings.md`, and `progress.md`: record Phase62B result and retention decision.

## Interface Contract

`writeback_arb` inputs:

```verilog
input wire mem_wb_retire_valid_i,
input wire mem_wb_reg_write_i,
input wire [4:0] mem_wb_rd_i,
input wire [1:0] mem_wb_wb_sel_i,
input wire [XLEN-1:0] mem_wb_alu_data_i,
input wire [XLEN-1:0] mem_wb_mem_data_i,
input wire [XLEN-1:0] mem_wb_pc4_i,
input wire load_resp_write_valid_i,
input wire [4:0] load_resp_rd_i,
input wire [XLEN-1:0] load_resp_data_i,
input wire mul_resp_write_valid_i,
input wire [4:0] mul_resp_rd_i,
input wire [XLEN-1:0] mul_resp_data_i,
```

`writeback_arb` outputs:

```verilog
output wire mem_wb_write_en_o,
output wire [XLEN-1:0] mem_wb_data_o,
output wire shared_wb2_is_load_o,
output wire shared_wb2_we_o,
output wire [4:0] shared_wb2_rd_o,
output wire [XLEN-1:0] shared_wb2_data_o
```

Required behavior:

- `mem_wb_data_o` selects memory data for `wb_sel=1`, PC+4 for `wb_sel=2`, and ALU data otherwise.
- `mem_wb_write_en_o = mem_wb_retire_valid_i && mem_wb_reg_write_i && (mem_wb_rd_i != 5'd0)`.
- `shared_wb2_is_load_o = load_resp_write_valid_i`.
- When `load_resp_write_valid_i=1`, shared port outputs load `rd/data`; `shared_wb2_we_o` is false only if `load_resp_rd_i == 0`.
- When `load_resp_write_valid_i=0`, shared port outputs multiply `rd/data`; `shared_wb2_we_o = mul_resp_write_valid_i && (mul_resp_rd_i != 0)`.
- Do not let a multiply response bypass a same-cycle load response that targets `x0`; this preserves the old shared port priority and M retire behavior.

Forbidden coupling:

- no `redirect`
- no `trap`
- no `mret`
- no `bp_update`
- no `ras`
- no `csr_`
- no `branch`
- no `jump`
- no `flush`
- no clocked state

## Retention Gate

Functional gate:

```powershell
scripts/check_writeback_arb_boundary.ps1
scripts/check_project.ps1
git diff --check
scripts/run_modelsim.ps1
scripts/run_csr_phase_acceptance.ps1 -SkipVivado
```

Physical gate:

```powershell
scripts/run_vivado_impl.ps1 -Top soc_top -Constraint huoyue_uart -OutDir build\vivado_impl_soc_top_phase62b_writeback_arb_extra_net_delay_100m -Jobs 4 -PlaceDirective ExtraNetDelay_high -PhysOptDirective AggressiveExplore -RouteDirective Explore -PostRoutePhysOptDirective AggressiveExplore
scripts/check_vivado_qor.ps1 -ReportDir build\vivado_impl_soc_top_phase62b_writeback_arb_extra_net_delay_100m -Top soc_top -RequireDmemBlockRam
scripts/check_vivado_timing.ps1 -ReportDir build\vivado_impl_soc_top_phase62b_writeback_arb_extra_net_delay_100m
```

Retention rule:

- Reject if CSR acceptance fails.
- Reject if CoreMark 2 exceeds `682500` cycles.
- Reject if timing-sensitive physical WNS is worse than the retained artifact WNS `-1.064 ns`.
- If function passes but timing is worse, revert RTL/test/check/source-list changes and keep only the documented finding.

## Task 1: RED Test and Structural Check

**Files:**

- Create `tb/tb_writeback_arb.v`
- Create `scripts/check_writeback_arb_boundary.ps1`
- Modify `scripts/check_project.ps1`

- [ ] **Step 1: Create `tb/tb_writeback_arb.v`**

Create a focused testbench that instantiates `writeback_arb` with `XLEN=32` and `XLEN=64`.

Key cases:

- MEM/WB ALU write selects ALU data and asserts write enable.
- MEM/WB memory write selects memory data.
- MEM/WB PC+4 write selects PC+4 data.
- MEM/WB `rd=x0` suppresses write enable.
- Load response wins shared port over multiply response.
- Load response to `x0` still selects load and suppresses shared write instead of allowing multiply through.
- Multiply response writes when no load response is present.
- Multiply response to `x0` suppresses shared write.
- XLEN64 instance preserves 64-bit data.

- [ ] **Step 2: Run RED focused test**

Run:

```powershell
$workDir = "build/modelsim_writeback_arb_red"; if (Test-Path -LiteralPath $workDir) { Remove-Item -LiteralPath $workDir -Recurse -Force }; New-Item -ItemType Directory -Force -Path $workDir | Out-Null; vlib "$workDir/work"; vlog -work "$workDir/work" rtl/writeback_arb.v tb/tb_writeback_arb.v; vsim -c -lib "$workDir/work" tb_writeback_arb -do "run -all; quit -f"
```

Expected before implementation:

```text
Cannot open `rtl/writeback_arb.v`
```

- [ ] **Step 3: Create structural check**

Create `scripts/check_writeback_arb_boundary.ps1` that:

- requires `rtl/writeback_arb.v`;
- requires `tb/tb_writeback_arb.v`;
- requires `parameter XLEN`;
- requires output names `mem_wb_write_en_o`, `shared_wb2_we_o`, and `shared_wb2_is_load_o`;
- rejects forbidden coupling terms;
- requires a `writeback_arb #` instantiation in `rtl/cpu_core.v`;
- requires `scripts/check_project.ps1` to invoke the check.

- [ ] **Step 4: Run RED structural check**

Run:

```powershell
scripts/check_writeback_arb_boundary.ps1
```

Expected before implementation:

```text
Missing required file: rtl/writeback_arb.v
```

## Task 2: Implement `writeback_arb`

**Files:**

- Create `rtl/writeback_arb.v`

- [ ] **Step 1: Add the combinational module**

Implement the exact interface contract from this plan. Keep it pure combinational: no `clk`, no `rst`, no `always @(posedge ...)`.

- [ ] **Step 2: Run focused GREEN**

Run:

```powershell
$workDir = "build/modelsim_writeback_arb_green"; if (Test-Path -LiteralPath $workDir) { Remove-Item -LiteralPath $workDir -Recurse -Force }; New-Item -ItemType Directory -Force -Path $workDir | Out-Null; vlib "$workDir/work"; vlog -work "$workDir/work" rtl/writeback_arb.v tb/tb_writeback_arb.v; vsim -c -lib "$workDir/work" tb_writeback_arb -do "run -all; quit -f"
```

Expected:

```text
PASS writeback arb regression completed
Errors: 0, Warnings: 0
```

## Task 3: Integrate into `cpu_core`

**Files:**

- Modify `rtl/cpu_core.v`

- [ ] **Step 1: Replace inline writeback assignments**

Remove inline assignments for:

- `wb_data`
- `mem_wb_write_en`
- `shared_wb2_is_load`
- `shared_wb2_we`
- `shared_wb2_rd`
- `shared_wb2_data`

Declare them as wires and drive them from `writeback_arb`.

- [ ] **Step 2: Preserve M retire policy**

Keep this existing policy outside `writeback_arb`:

```verilog
assign mul_retire_valid = mul_resp_ready_valid && !load_wb_write_en;
```

`load_wb_write_en` remains the raw load writeback slot request:

```verilog
wire load_wb_write_en = load_resp_retire_valid && load_resp_reg_write;
```

This preserves the old behavior where a load response occupies the shared writeback slot before a multiply response.

## Task 4: Source Lists and Structural GREEN

**Files:**

- Modify `scripts/run_modelsim.ps1`
- Modify `scripts/run_external_modelsim.ps1`
- Modify `scripts/vivado_synth.tcl`
- Modify `scripts/vivado_impl.tcl`
- Modify `scripts/check_project.ps1`

- [ ] **Step 1: Add RTL/test to source lists**

Add `rtl/writeback_arb.v` before `rtl/cpu_core.v` in every source list that compiles `cpu_core`.

Add `tb/tb_writeback_arb.v` to full ModelSim sources and tests.

- [ ] **Step 2: Run structural checks**

Run:

```powershell
scripts/check_writeback_arb_boundary.ps1
scripts/check_project.ps1
git diff --check
```

Expected:

```text
Writeback arb boundary OK
Project structure OK
```

## Task 5: Functional and Physical Acceptance

**Files:**

- Modify `task_plan.md`
- Modify `findings.md`
- Modify `progress.md`

- [ ] **Step 1: Run full ModelSim**

Run:

```powershell
scripts/run_modelsim.ps1
```

- [ ] **Step 2: Run CSR acceptance**

Run:

```powershell
scripts/run_csr_phase_acceptance.ps1 -SkipVivado
```

Expected:

```text
CSR_PHASE_ACCEPTANCE_PASS=1
```

CoreMark must stay below `682500` cycles.

- [ ] **Step 3: Run Vivado implementation**

Run:

```powershell
scripts/run_vivado_impl.ps1 -Top soc_top -Constraint huoyue_uart -OutDir build\vivado_impl_soc_top_phase62b_writeback_arb_extra_net_delay_100m -Jobs 4 -PlaceDirective ExtraNetDelay_high -PhysOptDirective AggressiveExplore -RouteDirective Explore -PostRoutePhysOptDirective AggressiveExplore
scripts/check_vivado_qor.ps1 -ReportDir build\vivado_impl_soc_top_phase62b_writeback_arb_extra_net_delay_100m -Top soc_top -RequireDmemBlockRam
scripts/check_vivado_timing.ps1 -ReportDir build\vivado_impl_soc_top_phase62b_writeback_arb_extra_net_delay_100m
```

## Task 6: Retain or Revert

**Files:**

- Retain path: all Phase62B RTL/test/script/doc changes.
- Reject path: keep only plan/findings/progress documentation and revert RTL/test/script/source-list changes.

- [ ] **Step 1: Apply decision**

If retained:

```powershell
git add -- rtl/writeback_arb.v tb/tb_writeback_arb.v scripts/check_writeback_arb_boundary.ps1 scripts/check_project.ps1 scripts/run_modelsim.ps1 scripts/run_external_modelsim.ps1 scripts/vivado_synth.tcl scripts/vivado_impl.tcl rtl/cpu_core.v task_plan.md findings.md progress.md docs/superpowers/plans/2026-06-09-writeback-arb-extraction.md
git commit -m "Extract writeback arbiter from cpu core"
```

If rejected:

```powershell
git add -- task_plan.md findings.md progress.md docs/superpowers/plans/2026-06-09-writeback-arb-extraction.md
git commit -m "Document rejected writeback arbiter extraction"
```

- [ ] **Step 2: Push**

Run:

```powershell
git push
```
