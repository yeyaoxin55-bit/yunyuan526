# Load Control Early Replay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an optional zero-hazard-stall replay path for `load -> branch/JALR` consumers without putting load-response data directly on the PC redirect path.

**Architecture:** The decode stage captures a load-dependent branch/JALR into a pending replay record when `ENABLE_LOAD_CONTROL_EARLY_REPLAY=1`. The pending record is completed from the later registered load response and then feeds the existing `ctrl_replay_valid` redirect path. Compatibility defaults remain unchanged.

**Tech Stack:** Verilog RTL, ModelSim, existing PowerShell build/test scripts, Vivado generic overrides.

---

## File Structure

- Modify `rtl/hazard_unit.v`: add `ENABLE_LOAD_CONTROL_EARLY_REPLAY` and suppress only the first `id_ex_load_use` stall for control consumers when the parameter is enabled.
- Modify `rtl/cpu_core.v`: add pending replay registers, early capture logic, pending-to-replay conversion, and pending conflict stalls.
- Modify `rtl/cpu_top.v`, `rtl/fpga_coremark_top.v`, `rtl/soc_top.v`, and `tb/tb_external_program.v`: expose and pass through the new parameter.
- Modify `scripts/run_external_modelsim.ps1`, `scripts/run_coremark.ps1`, and `scripts/run_riscv_suite.ps1`: add `LoadControlEarlyReplay` generic plumbing.
- Create `tb/tb_load_branch_zero_stall.v` and `tb/tb_load_jalr_zero_stall.v`: directed RED/GREEN regressions for the new mode.
- Modify `scripts/run_modelsim.ps1` and `scripts/check_project.ps1`: include the new testbenches.

## Task 1: RED Tests

- [ ] **Step 1: Add zero-stall load-to-branch testbench**

Create `tb/tb_load_branch_zero_stall.v` from `tb/tb_load_branch_one_stall.v`, instantiate `cpu_top` with `.ENABLE_LOAD_CONTROL_EARLY_REPLAY(1)`, and expect `load_use_stall_count == 0`.

- [ ] **Step 2: Add zero-stall load-to-JALR testbench**

Create `tb/tb_load_jalr_zero_stall.v` from `tb/tb_load_jalr_one_stall.v`, instantiate `cpu_top` with `.ENABLE_LOAD_CONTROL_EARLY_REPLAY(1)`, and expect `load_use_stall_count == 0`.

- [ ] **Step 3: Wire tests into the ModelSim regression**

Add both files to `$sources` and both modules to `$tests` in `scripts/run_modelsim.ps1`. Add both file paths to `scripts/check_project.ps1`.

- [ ] **Step 4: Run RED**

Run: `powershell -ExecutionPolicy Bypass -File scripts\run_modelsim.ps1`

Expected: compile/elaboration fails because `ENABLE_LOAD_CONTROL_EARLY_REPLAY` is not yet defined on `cpu_top`.

## Task 2: Parameter Plumbing

- [ ] **Step 1: Add top-level parameters**

Add `ENABLE_LOAD_CONTROL_EARLY_REPLAY = 0` to `cpu_core`, `cpu_top`, `fpga_coremark_top`, `soc_top`, and `tb_external_program`, passing it down to `cpu_core`.

- [ ] **Step 2: Add hazard-unit parameter**

Add `ENABLE_LOAD_CONTROL_EARLY_REPLAY = 0` to `hazard_unit` and pass it from `cpu_core`.

- [ ] **Step 3: Add script generic plumbing**

Add `LoadControlEarlyReplay` parameters to `run_external_modelsim.ps1`, `run_coremark.ps1`, and `run_riscv_suite.ps1`; pass `-gENABLE_LOAD_CONTROL_EARLY_REPLAY=<value>` to ModelSim.

- [ ] **Step 4: Run RED again**

Run: `powershell -ExecutionPolicy Bypass -File scripts\run_modelsim.ps1`

Expected: tests compile, but the two new zero-stall tests fail because the pipeline still performs one hazard stall.

## Task 3: Early Capture Implementation

- [ ] **Step 1: Suppress only the intended first load-use stall**

In `hazard_unit`, make `id_ex_load_use` contribute to `stall` only when the IF/ID consumer is not an early-replay control instruction. Keep all other stalls unchanged.

- [ ] **Step 2: Capture pending replay from IF/ID**

In `cpu_core`, detect:

`ENABLE_LOAD_CONTROL_EARLY_REPLAY != 0 && if_id_valid && id_ex_valid && id_ex_mem_read && (dec_branch || (dec_jump && dec_jalr)) && id_ex_rd != 0 && dependency`

Capture PC, immediate, funct3, branch/JALR flags, prediction metadata, decoded rs1/rs2 ids, rf source values, and source-dependency masks into new pending replay registers.

- [ ] **Step 3: Bubble ID/EX on early capture while allowing fetch to advance**

When the early capture fires, clear `id_ex_valid` and side-effecting ID/EX controls for that cycle, but do not hold PC/IF/ID. This removes the `hazard_stall` bubble from the front end.

- [ ] **Step 4: Convert pending replay to existing ctrl replay**

When pending is valid and `load_resp_valid` is high, set `ctrl_replay_valid` and fill rs1/rs2 from either the pending non-load data or `load_resp_data` according to the dependency masks. Clear pending at the same edge.

- [ ] **Step 5: Stall unsafe younger instructions while pending**

Add a pending conflict stall for IF/ID store, CSR, M-extension, branch, and jump instructions while pending is active. Treat it like a decode stall: hold PC/IF/ID and insert/hold a safe bubble instead of letting unsafe side effects advance.

- [ ] **Step 6: Clear pending on reset and flush**

Reset all pending replay registers and clear pending on any older flush.

## Task 4: Functional Verification

- [ ] **Step 1: Run targeted ModelSim**

Run: `powershell -ExecutionPolicy Bypass -File scripts\run_modelsim.ps1`

Expected: all tests pass, including `tb_load_branch_zero_stall` and `tb_load_jalr_zero_stall`.

- [ ] **Step 2: Run official M suite**

Run: `powershell -ExecutionPolicy Bypass -File scripts\run_riscv_suite.ps1 -Suite rv32um -FastMul 0 -MulStages 1 -LoadRespExForward 1 -LoadControlEarlyReplay 1 -BpLocalHistory 1 -BpBhtDepth 64 -BpBhrWidth 2 -BpBtbDepth 64 -MaxCycles 300000`

Expected: `RISCV_SUITE_FAIL=` empty.

- [ ] **Step 3: Run applicable official I suite**

Run the existing applicable `rv32ui` list excluding `fence_i` with the same parameters and `-LoadControlEarlyReplay 1`.

Expected: `RISCV_SUITE_FAIL=` empty.

## Task 5: Performance and Timing

- [ ] **Step 1: Run CoreMark 2**

Run CoreMark 2 with current fastest board-candidate parameters plus `-LoadControlEarlyReplay 1` and `-PerfStats`.

Expected: result is less than the current 699479-cycle quick-screen point for the same predictor profile, or the feature is rejected for performance.

- [ ] **Step 2: Run CoreMark 50**

Run CoreMark 50 with the same parameters.

Expected: compare against 17487089 cycles and the 16666667-cycle 3.0 target.

- [ ] **Step 3: Run Huoyue 100MHz implementation**

Run Vivado with generic overrides:

`ENABLE_LOAD_RESP_EX_FORWARD=1`, `ENABLE_LOAD_CONTROL_EARLY_REPLAY=1`, `BP_LOCAL_HISTORY=1`, `BP_BHT_DEPTH=64`, `BP_BHR_WIDTH=2`, `BP_BTB_DEPTH=64`

Use the previous `ExtraNetDelay_high`, `AggressiveExplore`, `Explore`, and post-route `AggressiveExplore` directives.

Expected: accept only if WNS is nonnegative and QoR reports `BlockRAM=24`.

## Task 6: Records

- [ ] **Step 1: Update planning files**

Record CoreMark, official tests, Vivado timing, resources, rejected candidates, and final decision in `task_plan.md`, `progress.md`, and `findings.md`.

- [ ] **Step 2: Final recommendation**

If timing passes, mark the new bitstream as the fastest candidate. If timing fails, keep the feature optional and retain the current Phase 38 bitstream as the board candidate.

---

## Execution Status 2026-05-06

- Implemented `ENABLE_LOAD_CONTROL_EARLY_REPLAY` through RTL tops, ModelSim harnesses, CoreMark scripts, and RISC-V suite scripts.
- Added strict directed tests:
  - `tb_load_branch_zero_stall` using `tb/programs/load_branch_strict.hex`
  - `tb_load_jalr_zero_stall` using `tb/programs/load_jalr_strict.hex`
- Added bug regressions found during implementation:
  - `tb_load_branch_same_rd_replay`
  - `tb_load_branch_wrong_path_wb`
- Fixed the same-`rd` pending replay hazard by forcing the captured replay to wait for a later matching load response instead of consuming a response already visible in the capture cycle.
- Fixed replay-flush wrong-path side effects by gating MEM/WB and load-response writeback/retire on replay-triggered flush.
- Rejected a broad `ctrl_replay_valid` front-end conflict stall because it hurt CoreMark; restored the narrower original `control_conflict_stall`.
- Verification passed:
  - `scripts/run_modelsim.ps1`
  - `scripts/check_project.ps1`
  - full `rv32um` with `LoadControlEarlyReplay=1`
  - applicable `rv32ui` excluding `fence_i` with `LoadControlEarlyReplay=1`
- CoreMark 2 A/B after the final stall revert:
  - disabled: 704487 cycles
  - enabled: 696597 cycles
- CoreMark 50 A/B after the final stall revert:
  - disabled: 17612289 cycles
  - enabled: 17414991 cycles
  - improvement: 197298 cycles, about 1.12%
  - previous accepted Phase 38 board candidate: 17487089 cycles
  - new simulation candidate gain over Phase 38: 72098 cycles, about 0.41%
- Huoyue 100MHz implementation attempts:
  - `ExtraNetDelay_high`: failed timing at WNS -0.011 ns, TNS -0.016 ns, 2 setup endpoints. QoR passed with `RAMD64E=16 BlockRAM=24`, LUT 6341, FF 7679, BRAM36 24, DSP48 12.
  - `AltSpreadLogic_high`: failed timing at WNS -0.086 ns, TNS -0.363 ns, 8 setup endpoints.
  - A small `redirect_from_replay` tag-boundary experiment passed `check_project`, full ModelSim, and CoreMark 2, but worsened `ExtraNetDelay_high` implementation to WNS -0.220 ns; it was reverted.
- Decision so far: keep the feature as a simulation-proven optional performance candidate. Do not replace the Phase 38 timing-clean board bitstream unless a targeted timing rescue passes.

## Execution Status 2026-05-11

- Targeted timing rescue attempts after the first Phase 39 failure did not work:
  - `constraints/floorplan_soc_top_replay_focus.tcl` focused replay/redirect-related cells, but worsened 100MHz implementation to WNS -0.173 ns, TNS -4.037 ns.
  - A plain `Explore` implementation without the focused pblock also failed at WNS -0.156 ns, TNS -4.271 ns.
- A parameter-only `MUL_STAGES=2` screen was rejected for performance. CoreMark 2 with early replay measured 710637 cycles versus 696597 cycles for `MUL_STAGES=1`, so the extra multiplier stage would erase the early-replay gain.
- Added a source-register-use mask at the decode/hazard boundary so load-use and multiplier scoreboarding compare only real source operands. This fixes false dependencies from U/J/immediate encodings where `instr[19:15]` or `instr[24:20]` is not a source register.
- Added RED/GREEN regression:
  - `tb/tb_load_false_dep_no_stall.v`
  - `tb/programs/load_false_dep.hex`
  The old RTL failed with one false load-use stall after `lw` followed by `lui`; the fixed RTL passes with zero stalls.
- Verification after the source-use mask:
  - `scripts/run_modelsim.ps1`: pass.
  - `scripts/check_project.ps1`: pass.
  - full `rv32um` with early replay enabled: pass.
  - applicable `rv32ui` excluding `fence_i` with early replay enabled: pass. A first command accidentally included `fence_i`; it failed as expected for the known unsupported Harvard self-modifying-code case, then the correct excluded list passed.
- CoreMark after the source-use mask:
  - early replay enabled, 2 iterations: 695145 cycles, down from 696597.
  - early replay enabled, 50 iterations: 17378691 cycles, down from 17414991.
  - remaining 3.0 target gap at 50 iterations: 712024 cycles versus the 16666667-cycle target.
  - early replay disabled, 2 iterations: 703035 cycles, down from 704487.
- Added `scripts/vivado_route_from_place.tcl` to resume a timed-out implementation from `post_place.dcp` and avoid repeating synthesis/place.
- Huoyue 100MHz implementation of early replay plus source-use mask still failed timing:
  - initial run reached post-place before timeout; post-place WNS was -0.150 ns.
  - resumed route/post-route physopt completed and generated a bitstream, but timing failed at WNS -0.376 ns, TNS -32.883 ns.
  - QoR was correct: `RAMD64E=16 BlockRAM=24`, BRAM36 24, DSP48 12.
- Decision: keep the source-use mask because it fixes a real false-stall bug and gives a small CoreMark gain, but early replay is still not an accepted board candidate. The fastest timing-clean board bitstream remains the Phase 38 small-local-history candidate until a no-early-replay build with the source mask is implemented and passes timing, or a larger RTL register-boundary redesign is done.

## Execution Status 2026-05-11 Current-Source Fallback

- Established a timing-clean fallback from the latest source tree by disabling early replay:
  - `FAST_MUL=0`
  - `MUL_STAGES=1`
  - `ENABLE_LOAD_RESP_EX_FORWARD=1`
  - `ENABLE_LOAD_CONTROL_EARLY_REPLAY=0`
  - `BP_LOCAL_HISTORY=1`
  - `BP_BHT_DEPTH=64`
  - `BP_BHR_WIDTH=2`
  - `BP_BTB_DEPTH=64`
- `ExtraNetDelay_high` failed narrowly: WNS -0.026 ns, TNS -0.160 ns, 7 setup endpoints. QoR passed with `RAMD64E=16 BlockRAM=24`, LUT 6312, FF 7529, BRAM36 24, DSP48 12.
- `AltSpreadLogic_high` passed timing and generated `build/vivado_impl_soc_top_huoyue_100m_srcmask_no_lctrl_alt_spread/soc_top.bit`: WNS 0.000 ns, TNS 0.000 ns, WHS 0.037 ns, LUT 6337, FF 7537, BRAM36 24, DSP48 12. QoR passed with `RAMD64E=16 BlockRAM=24`.
- CoreMark 50 with early replay disabled on the latest source tree measured 17575989 cycles, about 2.84479 CoreMark/MHz at 100MHz.
- This current-source fallback is not a new fastest candidate. It is slower than the older Phase 38 accepted artifact by 88900 cycles. The fastest timing-clean board bitstream for performance measurement remains `build/vivado_impl_soc_top_huoyue_100m_nonblocking_mul_loadresp_exfwd_localhist64_btb64/soc_top.bit`; the current-source fallback is useful when the board image must match the latest RTL exactly.

## Execution Status 2026-05-11 Hotspot Attribution

- Added a reproducible hotspot script: `scripts/run_coremark_hotspots.ps1`.
- Fixed the simulation-only hotspot replacement counters in `tb/tb_external_program.v`, expanded load-use hotspot capacity to 256 entries, and added branch/jump flush PC tables.
- Early-replay enabled 2-iteration hotspot run:
  - summary: `build/coremark/hotspots/iter2_lctrl1_bht64_bhr2_btb64.summary.txt`
  - cycles: 695145
  - load-use stalls: 45060
  - branch-mispredict flushes: 7615
  - jump flushes: 5255
  - JALR flushes: 5
- Early-replay disabled 2-iteration hotspot run:
  - summary: `build/coremark/hotspots/iter2_lctrl0_bht64_bhr2_btb64.summary.txt`
  - cycles: 703035
  - load-use stalls: 55017
  - branch-mispredict flushes: 7615
  - jump flushes: 5255
  - JALR flushes: 5
- Hotspot conclusion: early replay removes about 9957 load-use stalls in the 2-iteration run, but the remaining 45060 stalls are ordinary load-to-consumer pairs in `core_bench_list`, `matrix_test`, and `core_state_transition`.
- Verification passed after these testbench/tooling changes: `check_project`, both hotspot CoreMark runs, and full ModelSim regression.
