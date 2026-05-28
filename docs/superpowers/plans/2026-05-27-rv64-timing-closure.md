# RV64 Timing Closure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the RV64 `soc_top` 100 MHz timing violation by removing the writeback-to-redirect control critical path and then validating each smaller timing family with the fast Vivado project flow.

**Architecture:** The implementation reports show WNS `-0.803 ns`, TNS `-466.576 ns`, and 1395 failing endpoints after post-route physical optimization. The dominant paths are not resource-capacity problems; they are wide writeback/forwarding data and `mem_wb_wb_sel` feeding branch/redirect detection, which then drives `id_ex_*` and prefetch CE/R control in the same cycle. The first optimization must cut that combinational control loop by making redirect detect a registered event before it controls pipeline clear/hold.

**Tech Stack:** Verilog RTL, PowerShell check scripts, ModelSim/iverilog regressions, Vivado 2022.2 project timing reports, existing `yunyuan3_rv64.xpr` fast timing scripts.

---

## Evidence Summary

Post-route physopt timing report:

- Report: `D:\Verilog_prj\yunyuan3_rv64\yunyuan3_rv64.runs\impl_1\soc_top_timing_summary_postroute_physopted.rpt`
- WNS/TNS: `WNS=-0.803 ns`, `TNS=-466.576 ns`
- Failing endpoints: `1395 / 24779`
- Hold: clean, `WHS=0.028 ns`, `THS=0.000 ns`
- Only constrained failing group: `clkout0_mmcm`, 100 MHz

Top failing families after post-route physopt:

- `u_core/id_ex_valid_reg/C -> u_core/id_ex_rs1_data_reg[55]/CE`: `-0.803 ns`, 16 logic levels, route 74.0%.
- `u_core/mem_wb_wb_sel_reg[0]_rep__0_replica_11/C -> u_core/id_ex_control_load_resp_dep_reg/R`: `-0.788 ns`, 16 logic levels, route 72.1%.
- `u_core/mem_wb_wb_sel_reg[0]_rep__0_replica_11/C -> u_core/id_ex_valid_reg/R`: `-0.788 ns`, 16 logic levels, route 72.1%.
- `u_core/mem_wb_wb_sel_reg[0]_rep__0_replica_11/C -> u_core/id_ex_rs1_data/id_ex_rs2_data CE`: about `-0.74 ns` to `-0.78 ns`.
- `u_core/mem_wb_mem_data_reg[2]/C -> u_core/ex_mem_alu_result_reg[24]/CE`: `-0.734 ns`, 16 logic levels.

Routed report before post-route physopt:

- WNS/TNS: `WNS=-1.250 ns`, `TNS=-782.753 ns`.
- Dominant path: `mem_wb_mem_data_reg[2] -> ex_mem_alu_result_reg[*]/CE`.
- Methodology DRC `TIMING-16` flags the same family as large setup violations.

Related RTL:

- `rtl/cpu_core.v:251-253`: `wb_data` selects `mem_wb_mem_data`, `mem_wb_pc4`, or `mem_wb_alu_result`.
- `rtl/cpu_core.v:701-708`: `control_forward_*_data` can consume `wb_data`.
- `rtl/cpu_core.v:822-858`: branch compare and redirect detect use forwarded control operands.
- `rtl/cpu_core.v:862-863`: `redirect_register_wait` currently depends on live `redirect_detect`.
- `rtl/cpu_core.v:1406-1422`: `flush || redirect_register_wait` clears `id_ex_*`.
- `rtl/cpu_core.v:1499-1517`: `redirect_register_wait` also holds fetch/IF-ID state.
- `rtl/prefetch.v:61-66`: stall captures skid state, so timing-sensitive stall/CE control reaches prefetch registers.

Non-primary observations:

- Utilization is moderate: LUT 19.6%, FF 7.5%, BRAM 22.9%, DSP 7.3%.
- DRC has DSP `DPOP-1/DPOP-2` and methodology `SYNTH-10` wide multiplier warnings, but the reported critical setup paths are currently redirect/control CE/R paths, not multiplier datapaths.
- DRC `SYNTH-15` says BWWE was not inferred for DMEM BRAMs because address width is 13; this is not the first timing target unless later reports move criticality into DMEM.

---

### Task 1: Add Structural Timing Guards for the Current Critical Path

**Files:**
- Create: `scripts/check_redirect_registered_control_boundary.ps1`
- Modify: `scripts/check_project.ps1`

- [ ] **Step 1: Write the failing structural check**

Create `scripts/check_redirect_registered_control_boundary.ps1` with checks that initially fail on the current RTL. The check must assert:

```powershell
$ErrorActionPreference = "Stop"

$core = Get-Content -Raw "rtl/cpu_core.v"

if ($core -match "assign\s+redirect_register_wait\s*=\s*\(REGISTER_REDIRECT_TO_PC != 0\)\s*&&\s*\(\s*redirect_detect\s*\|\|\s*redirect_stage_valid\s*\)") {
  throw "redirect_register_wait still depends on live redirect_detect; this keeps writeback/forwarding data on ID/EX CE/R timing paths."
}

if ($core -match "if\s*\(\s*flush\s*\|\|\s*redirect_register_wait\s*\)") {
  throw "ID/EX clear still uses redirect_register_wait directly; use a registered redirect-clear event instead."
}

if ($core -notmatch "redirect_flush_pending") {
  throw "Expected a registered redirect flush/hold boundary signal such as redirect_flush_pending."
}

Write-Host "PASS: redirect registered control boundary checks passed."
```

- [ ] **Step 2: Verify RED**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\check_redirect_registered_control_boundary.ps1
```

Expected: FAIL with a message that `redirect_register_wait` still depends on live `redirect_detect`.

- [ ] **Step 3: Wire the check into project checks after GREEN**

After Task 2 passes, add this script to `scripts/check_project.ps1` near the existing timing-risk checks so future edits cannot recreate the path.

---

### Task 2: Split Redirect Detect From Pipeline Clear and Fetch Hold

**Files:**
- Modify: `rtl/cpu_core.v`
- Test: `tb/tb_registered_redirect.v`
- Test: `tb/tb_branch.v`
- Test: `tb/tb_branch_predict.v`
- Test: `tb/tb_load_branch_wrong_path_wb.v`
- Test: `tb/tb_load_branch_same_rd_replay.v`
- Test: `scripts/check_registered_redirect_to_pc.ps1`
- Test: `scripts/check_redirect_registered_control_boundary.ps1`

- [ ] **Step 1: Define the control boundary**

In `rtl/cpu_core.v`, keep `redirect_detect` only as the signal that loads `redirect_stage_*`. Add a registered control event for the following cycle, for example:

```verilog
wire redirect_stage_fire = (REGISTER_REDIRECT_TO_PC != 0) && redirect_stage_valid;
wire redirect_clear_pipe = flush || redirect_stage_fire;
wire redirect_fetch_hold = redirect_stage_fire;
```

Do not let `redirect_detect` feed `id_ex_*` R/CE, `ex_mem_*` CE, or prefetch/IF-ID CE directly.

- [ ] **Step 2: Replace live detect in ID/EX clear**

Change the ID/EX clear branch from:

```verilog
if (flush || redirect_register_wait) begin
```

to a registered-only clear:

```verilog
if (redirect_clear_pipe) begin
```

Expected structural effect: paths ending at `u_core/id_ex_*_reg/R` no longer start from `mem_wb_wb_sel` or `mem_wb_mem_data` through live branch compare.

- [ ] **Step 3: Replace live detect in IF/ID fetch hold**

Change the fetch/IF-ID hold branch from:

```verilog
end else if (redirect_register_wait ||
             pipe_wait || control_conflict_stall ||
             ctrl_pending_conflict_stall ||
             id_load_early_base_wait) begin
```

to:

```verilog
end else if (redirect_fetch_hold ||
             pipe_wait || control_conflict_stall ||
             ctrl_pending_conflict_stall ||
             id_load_early_base_wait) begin
```

This prevents the live branch compare from driving prefetch skid register CE paths.

- [ ] **Step 4: Keep redirect PC commit behavior unchanged**

Keep `flush = branch_mispredict || jump_needs_flush` driven by the committed redirect register. The behavior expected by `tb_registered_redirect` is:

1. live detect cycle: no `flush`;
2. pre-stage cycle: no `flush`;
3. committed redirect cycle: `flush` asserts and PC updates.

- [ ] **Step 5: Run focused behavioral tests**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_modelsim.ps1 -Top tb_registered_redirect
powershell -ExecutionPolicy Bypass -File scripts\run_modelsim.ps1 -Top tb_branch
powershell -ExecutionPolicy Bypass -File scripts\run_modelsim.ps1 -Top tb_branch_predict
powershell -ExecutionPolicy Bypass -File scripts\run_modelsim.ps1 -Top tb_load_branch_wrong_path_wb
powershell -ExecutionPolicy Bypass -File scripts\run_modelsim.ps1 -Top tb_load_branch_same_rd_replay
```

Expected: all focused tests pass. If `run_modelsim.ps1` does not support `-Top`, run the full script and inspect these test names in the output.

- [ ] **Step 6: Run structural checks**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\check_registered_redirect_to_pc.ps1
powershell -ExecutionPolicy Bypass -File scripts\check_redirect_registered_control_boundary.ps1
```

Expected: both checks pass.

- [ ] **Step 7: Run post-synth timing**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_vivado_post_synth_timing.ps1 -Jobs 4
```

Expected: top setup path no longer ends at `id_ex_*_reg/R` or prefetch skid CE through `redirect_detect`. If WNS remains negative, record the new top 10 endpoints before continuing.

---

### Task 3: Remove Writeback Data From Branch/JALR Control When It Cannot Be Needed

**Files:**
- Modify: `rtl/cpu_core.v`
- Test: `tb/tb_branch_conditions.v`
- Test: `tb/tb_load_jalr_one_stall.v`
- Test: `tb/tb_load_jalr_zero_stall.v`
- Test: `tb/tb_ras_return.v`

- [ ] **Step 1: Split branch compare operands from general ALU operands**

Create narrow control operand selection that only evaluates the data needed for active control instructions:

```verilog
wire ctrl_needs_rs1 = ctrl_branch || ctrl_jalr;
wire ctrl_needs_rs2 = ctrl_branch;
wire [XLEN-1:0] ctrl_rs1_data = ctrl_replay_valid ? ctrl_replay_rs1_data :
                                !ctrl_needs_rs1 ? {XLEN{1'b0}} :
                                control_load_resp_dep ? {XLEN{1'b0}} :
                                control_forward_a_data;
wire [XLEN-1:0] ctrl_rs2_data = ctrl_replay_valid ? ctrl_replay_rs2_data :
                                !ctrl_needs_rs2 ? {XLEN{1'b0}} :
                                control_load_resp_dep ? {XLEN{1'b0}} :
                                control_forward_b_data;
```

This keeps non-control instructions from dragging `wb_data` into branch compare and redirect logic.

- [ ] **Step 2: Avoid full 64-bit compare for equality-only cases when possible**

Keep equality/inequality as direct 64-bit comparisons, but ensure unsigned/signed less-than comparators are selected only for `funct3[2]` branch cases. This should keep `BEQ/BNE` away from signed comparator carry chains.

- [ ] **Step 3: Run focused control tests**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_modelsim.ps1 -Top tb_branch_conditions
powershell -ExecutionPolicy Bypass -File scripts\run_modelsim.ps1 -Top tb_load_jalr_one_stall
powershell -ExecutionPolicy Bypass -File scripts\run_modelsim.ps1 -Top tb_load_jalr_zero_stall
powershell -ExecutionPolicy Bypass -File scripts\run_modelsim.ps1 -Top tb_ras_return
```

Expected: all pass.

- [ ] **Step 4: Run post-synth timing**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_vivado_post_synth_timing.ps1 -Jobs 4
```

Expected: fewer `mem_wb_* -> redirect/control` paths and reduced logic levels on branch/JALR paths.

---

### Task 4: Localize Wide Pipeline CE and Reset Control

**Files:**
- Modify: `rtl/cpu_core.v`
- Modify: `rtl/prefetch.v`
- Test: `scripts/check_rtl_timing_risk.ps1`

- [ ] **Step 1: Replace broad CE paths with valid-bit gating where possible**

For wide data registers such as `id_ex_rs1_data`, `id_ex_rs2_data`, `id_ex_imm`, and prefetch skid payloads, prefer unconditional data updates plus registered valid bits where behavior allows. The goal is to avoid a complex live control cone becoming a CE for 64-bit data flops.

- [ ] **Step 2: Keep architectural invalidation in valid/control bits**

When flushing or stalling, clear or hold `*_valid`, `*_reg_write`, `*_mem_read`, `*_mem_write`, `*_branch`, and `*_jump`. Avoid clearing every wide payload unless the payload is externally observable while invalid.

- [ ] **Step 3: Update the RTL timing risk scan**

Extend `scripts/check_rtl_timing_risk.ps1` to warn if `redirect_detect`, `branch_mispredict_raw`, or `jump_needs_flush_raw` appears in wide payload CE/reset conditions.

- [ ] **Step 4: Run behavioral regressions**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_modelsim.ps1
powershell -ExecutionPolicy Bypass -File scripts\check_project.ps1
```

Expected: all regressions pass.

- [ ] **Step 5: Run fast place timing**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_vivado_post_place_timing.ps1 -Jobs 4
```

Expected: with the default `Explore` place directive, post-place WNS improves versus the previous `-0.903 ns` to `-0.990 ns` placement range shown in `runme.log`. Use `-PlaceDirective Quick` only for very rough smoke checks.

---

### Task 5: Triage Remaining Non-Redirect Timing Families

**Files:**
- Modify if needed: `rtl/multiplier.v`
- Modify if needed: `rtl/dmem.v`
- Modify if needed: `rtl/soc_top.v`
- Modify if needed: `constraints/*.xdc`

- [ ] **Step 1: If multiplier paths become top critical, address DSP register warnings**

DRC currently reports `DPOP-1` and `DPOP-2`, and methodology reports `SYNTH-10`. Only act on these if timing reports move top WNS into `u_core/u_multiplier/*`. Possible fixes:

- add explicit DSP-friendly pipeline boundaries in `rtl/multiplier.v`;
- verify post-synth DSP report shows useful `MREG/PREG` inference;
- keep `MUL_STAGES=4` or increase to 5 only if CoreMark CPI remains acceptable.

- [ ] **Step 2: If DMEM paths become top critical, revisit BRAM byte-enable implementation**

Methodology `SYNTH-15` says BWWE was not inferred for 16 DMEM BRAMs. Only act if top WNS moves into `u_dmem/*`. Possible fixes:

- split RV64 DMEM into eight byte-lane memories with simpler write enable;
- reduce board default `DMEM_DEPTH` if current CoreMark image does not need 8192 64-bit entries;
- test with `scripts/check_dmem_bram_read_hold.ps1` and RV64 load/store benches.

- [x] **Step 2a: Cut load-response RF read bypass in timing-safe mode**

Fast post-place after registering `wb_data` moved the top path to:

`u_dmem/gen_bram_friendly.mem_bram_reg_* -> load_resp/shared_wb2 -> regfile second write-port read bypass -> id_ex_rs*_data`

This is the same DMEM BRAM output cone that the original timing-safe load-response mode tried to keep out of EX. The older two-stall timing-safe mode still relied on a same-cycle register-file read bypass from the load-response writeback port, which is too expensive after placement.

Action taken:

- `rtl/regfile.v`: keep the second write port, but add `bypass2_en` and separate `bypass2_data` so same-cycle read bypass can be disabled independently from writeback.
- `rtl/cpu_core.v`: disable second-port read bypass for load responses when `ENABLE_LOAD_RESP_EX_FORWARD=0`; keep mul-response bypass unchanged and keep load-response data out of the RF read-bypass data cone.
- `rtl/hazard_unit.v`: add `load_resp_rf_bypass_stall`, giving timing-safe load-use pairs a third stall so the consumer reads after the register-file write boundary.
- `tb/tb_load_use_timing_safe.v`: update expected timing-safe stall count from 2 to 3.
- `scripts/check_rtl_timing_risk.ps1`: add hard checks for the new RF bypass gate and load-response decode stall.

This supersedes the older two-stall timing-safe expectation for board timing closure. Performance modes with `ENABLE_LOAD_RESP_EX_FORWARD=1` keep the previous one-stall load-use behavior.

- [x] **Step 2b: Preserve the post-place baseline and reject no-benefit experiments**

Fast direct-synth/direct-place checkpoints on 2026-05-27:

- After redirect/WB/register-file timing cuts, post-synth timing is positive (`PROJECT_FAST_TIMING_WORST_SLACK_NS=+0.216` in the fast synth checkpoint).
- The best retained fast post-place Quick checkpoint is `PROJECT_FAST_TIMING_WORST_SLACK_NS=-3.036`.
- The current top family is `u_core/mul_meta_valid_pipe_reg[0]/C -> u_core/if_id_instr_reg[16]_rep*/R` and `u_core/u_prefetch/skid_instr_reg[*]/CE`.
- Data path delay is about `12.312 ns`, with route about `10.926 ns` (`88.7%`) and logic 7 levels. The dominant symptom is high-fanout control placement/routing, not a wide arithmetic datapath.
- QoR suggests `RQS_TIMING-3` on a 154-fanout critical net from `mul_meta_valid_pipe_reg[0]`, plus `RQS_TIMING-59` replication on related critical LUT nets.
- Using the same RTL with `place_design -directive Explore` produced `PROJECT_FAST_TIMING_WORST_SLACK_NS=+0.505`. The placer physical synthesis log replicated `u_core/mul_meta_valid_pipe_reg_n_0_[0]` 10 times and pushed multiplier DSP registers, confirming this family needs physical synthesis/placement effort rather than another broad RTL rewrite.

Rejected experiments:

- Replacing the combinational multiplier outstanding scan with a sequential credit counter worsened fast post-place Quick to about `-4.818 ns`; it was reverted.
- Removing the same-cycle `mul_start` look-ahead from `mul_decode_pipeline_busy` passed static checks and ModelSim, but worsened fast post-place Quick to about `-4.261 ns`. The top path moved to `mul_meta_valid_pipe_reg[1] -> u_prefetch/skid_pc_reg[*]/CE` through `mul_start`, `pipe_wait`, and prefetch CE fanout, so it was reverted.
- Clearing only valid bits for IF/ID and prefetch payloads passed ModelSim but worsened fast post-place Quick to about `-3.859 ns`, moving the top endpoint to `u_core/u_prefetch/current_instr_reg[*]/CE`; it was reverted.
- Adding a broad RTL `max_fanout=32` attribute to `mul_meta_valid_pipe` worsened fast post-place Quick to about `-4.807 ns`; it was reverted. If replication is tried again, use a post-synthesis QoR-driven constraint or a more specific replicated local control signal, not a broad vector attribute.
- A direct post-synth Tcl hook that applied `FORCE_MAX_FANOUT=32` to the post-synth `mul_meta_valid_pipe`/multiplier valid nets was accepted by Vivado but did not change Quick post-place WNS (`-3.036 ns`), so the practical fast-place default is now `Explore`.

Next RTL direction:

- Keep the current RTL baseline intact; the same RTL reaches `+0.505 ns` after `Explore` placement.
- Do not broadly rewrite prefetch/IF-ID flush behavior again without a more local CE split.
- Prefer `Explore` or full implementation strategies that include physical synthesis/replication before attempting more RTL surgery.
- Any next RTL attempt must be judged against both Quick and Explore post-place checkpoints, not post-synth alone.

- [ ] **Step 3: If output-only paths appear, constrain or register IO intentionally**

The timing summary reports `no_input_delay` and `no_output_delay` for board ports, but internal constrained endpoints are the real failing group. Do not mask internal failures with constraints. Add input/output delay constraints only after internal `clkout0_mmcm` paths meet timing.

---

### Task 6: Full Timing Closure Validation

**Files:**
- Read: `D:\Verilog_prj\yunyuan3_rv64\yunyuan3_rv64.runs\impl_1\soc_top_timing_summary_postroute_physopted.rpt`
- Read: `build\vivado_fast_synth\*.rpt`
- Read: `build\vivado_fast_place\*.rpt`
- Modify: `progress.md`

- [x] **Step 1: Run full implementation**

Run the existing full implementation script or Vivado run after the fast checks show a positive trend.

- [x] **Step 2: Compare against baseline**

Baseline:

- post-synth WNS from fast run: `-1.626 ns`;
- routed WNS: `-1.250 ns`;
- post-route physopt WNS: `-0.803 ns`;
- post-route physopt TNS: `-466.576 ns`.

Success target:

- WNS `>= 0.000 ns`;
- TNS `0.000 ns`;
- hold remains clean;
- top 10 setup paths no longer include `mem_wb_* -> id_ex_* CE/R` through redirect logic.

- Result on 2026-05-27 using `Explore + AggressiveExplore + Explore + AggressiveExplore`: post-route WNS `0.076 ns`, TNS `0.000 ns`, setup failing endpoints `0`, hold WHS `0.030 ns`, THS `0.000 ns`.
- Artifact: `build/vivado_impl_soc_top_rv64_explore_20260527/soc_top.bit`.
- Worst setup path after closure is `u_core/if_id_instr_reg[5]/C -> u_core/id_ex_rs1_data_reg[7]/CE`, data path delay `9.475 ns`, logic levels `8`, route `84.063%`.
- The original `mem_wb_* -> id_ex_* CE/R` redirect/control family is no longer the worst reported family.

- [x] **Step 3: Document final result**

Update `progress.md` with:

- exact date and Vivado stage;
- WNS/TNS before and after;
- top path family before and after;
- any CPI or CoreMark impact if redirect latency changes.
