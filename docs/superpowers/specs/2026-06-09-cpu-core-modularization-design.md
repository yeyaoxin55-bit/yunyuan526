# Phase62 CPU Core Modularization Design

## Context

`rtl/cpu_core.v` has become the main integration point for nearly every CPU concern:

- PC and frontend sequencing.
- IF/ID, ID/EX, EX/MEM, and MEM/WB pipeline registers.
- Decode-side hazards and CSR-state stalls.
- Load response, early load forwarding, load-control replay, and pending replay capture.
- Fixed-latency multiplier metadata, multiply FIFO, divider command issue, and shared writeback.
- CSR reads, normal CSR commits, trap entry commits, and MRET commits.
- Branch/JAL/JALR redirect detection, redirect payload capture, and frontend flush.
- Branch predictor update and RAS side effects.
- Retire counting and side-effect kill rules.

This is no longer an industrial-quality ownership boundary. The file is not only large; it also lets timing-critical domains feed each other directly. The repeated Phase54-61 timing failures show that small local rewrites often preserve simulation but move the worst path to another endpoint in the same broad redirect/control cone.

Current retained baseline:

- Branch: `新增CSR`.
- Functional baseline: CSR phase acceptance passes.
- CoreMark 2 baseline: `649893` cycles, CPI `1.110978`.
- Best known physical artifact: WNS `-1.064 ns`.
- Phase60A M-unit backend/OOC split is retained.
- Phase60B CPU M-unit integration and Phase61 prefetch valid-only flush were rejected and reverted.

## Goal

Convert `cpu_core` from a monolithic control/data implementation into a small top-level pipeline orchestrator with explicit submodule contracts, while preserving the retained functional and physical baseline at every retained step.

## Non-Goals

This phase does not implement RTL extraction. It defines the industrial modularization target and the order of future implementation phases.

Out of scope for this design phase:

- Changing CSR/trap architectural behavior.
- Reattempting M-unit CPU request/response integration.
- Adding PMP, MMU, CLINT, PLIC, debug CSRs, or asynchronous interrupt response.
- Rewriting the branch predictor algorithm.
- Replacing the multiplier with explicit DSP48 primitives.
- Converting the whole design to SystemVerilog interfaces in one step.

## Design Principles

### Preserve the Hardware Baseline

Every retained refactor must pass the same gates as a functional feature:

- `scripts/check_project.ps1`
- full ModelSim or CSR phase acceptance
- `scripts/run_csr_phase_acceptance.ps1 -SkipVivado`
- CoreMark 2 under `682500` cycles
- Huoyue `soc_top` QoR with `RAMD64E=0` and `BlockRAM=24`
- physical WNS no worse than the current retained artifact for timing-sensitive cuts

If a refactor is functionally clean but physically worse than WNS `-1.064 ns`, reject and revert the RTL while keeping the finding.

### Make `cpu_core` the Orchestrator

Long term, `cpu_core` should instantiate units and own only the final pipeline sequencing contract:

- which stage advances;
- which younger stages are killed;
- which redirect target is selected;
- which architectural side effects commit.

Detailed local policy should move into named modules with narrow interfaces.

### Extract Low-Risk Boundaries First

The first extraction must not be the redirect datapath. Redirect PC/payload CE has been the dominant physical failure region across Phase54-61. Start with modules whose outputs already feed committed boundaries and are easier to prove equivalent.

Recommended first retained extraction:

1. `writeback_arb.v`
2. `commit_side_effect_gate.v`
3. `retire_counter_ctrl.v`

Redirect, frontend flush, predictor update, load replay, and M-scoreboard extraction should wait until the low-risk boundaries prove the extraction method and checks.

### Keep Parameterization Honest

Every new RTL module must be parameterized for the architectural data width:

- `parameter XLEN = 32`
- use `[XLEN-1:0]` for register/ALU/CSR data
- keep instruction fields explicitly 32-bit in the first-stage non-C design
- avoid new hard-coded `32'h...` datapath constants except instruction NOPs, RV32-only legacy wrappers, or documented PC reset values

For PC values, use `PC_WIDTH` only if the design explicitly separates PC width from `XLEN`; otherwise use `XLEN` consistently in newly extracted modules. This prevents RV64 support from being blocked by new RV32-only helper modules.

### Use Plain Verilog Contracts First

The current repo uses `.v` RTL and existing ModelSim/Vivado scripts already compile it successfully. The first modularization phase should use explicit Verilog module ports instead of a broad SystemVerilog interface migration. A later style phase may introduce typedefs or interfaces if the tool flow and source lists are ready.

## Target Module Boundaries

### `writeback_arb.v`

Responsibility:

- Choose final writeback port 0 from MEM/WB.
- Choose shared writeback port 1 from load response versus multiply response.
- Apply `rd != x0` and valid/write-enable gates.
- Present a clear pair of writeback records back to `cpu_core`.

Allowed inputs:

- MEM/WB retire valid, `rd`, `reg_write`, `wb_sel`, ALU data, memory data, PC+4.
- Load response retire valid, `rd`, `reg_write`, load data.
- Multiply response retire valid, `rd`, `reg_write`, multiply data.

Forbidden inputs:

- `redirect_*`
- `csr_trap_*`
- `csr_mret_*`
- branch predictor update signals
- RAS signals
- frontend flush signals

Rationale:

This is the safest first extraction because it should be mostly combinational selection. It reduces local clutter without changing redirect or pipeline sequencing.

### `commit_side_effect_gate.v`

Responsibility:

- Compute which side effects are allowed to commit in the current cycle.
- Centralize gates for register write, load writeback, multiply writeback, DMEM write, CSR write, trap entry, MRET restore, predictor update, RAS update, divider/multiplier issue, replay capture, and retire count.

Allowed inputs:

- stage valid bits;
- trap/MRET/redirect detect and committed flush state;
- replay flush state;
- per-side-effect raw request bits.

Outputs:

- named allow/kill bits for each side-effect class.

Forbidden behavior:

- no payload computation;
- no CSR state storage;
- no PC target computation;
- no branch target arithmetic.

Rationale:

The CSR phase already depends on correct side-effect kill ordering. Making this an explicit module gives the project a single place to audit architectural precision.

### `retire_counter_ctrl.v`

Responsibility:

- Compute `retire_count`, `retire_valid`, and related performance counter retire classifications.
- Keep explicit priority between ordinary CSR counter writes and implicit counter increments by feeding the existing `csr_unit` contract cleanly.

Allowed inputs:

- MEM/WB retire valid.
- Load response retire valid.
- Multiply response retire valid.
- Divider retire valid if present.
- replay/flush kill bits already resolved by `commit_side_effect_gate`.

Forbidden inputs:

- raw branch target signals;
- frontend prediction payloads;
- CSR read data.

### `load_replay_ctrl.v`

Responsibility:

- Own control-load replay capture and pending load-control replay state.
- Convert load-response availability into a replay packet.
- Keep wrong-path replay capture killed by side-effect gates.

Extraction risk:

Medium. Previous timing paths often involve load/control replay. Do this after writeback and side-effect gating have proved the extraction style.

### `redirect_ctrl.v`

Responsibility:

- Arbitrate trap, MRET, branch mispredict, JAL, JALR, replay redirect, and ID-stage early redirect.
- Own redirect valid, redirect target payload, fallthrough payload, redirect cause, and frontend flush cause.

Extraction risk:

High. This domain contains the current worst physical paths. Do not extract first. When extracted, use a RED structural check that proves no M response or load-response payload directly enters redirect PC/fallthrough payload computation.

### `bp_update_ctrl.v`

Responsibility:

- Compute branch predictor update valid, PC, target, taken, and unconditional update class.
- Separate side-effect valid gating from payload loading.

Extraction risk:

Medium-high. Prior predictor-payload experiments were functionally clean but physically worse. Extract only after side-effect gating is explicit.

### `ras_ctrl.v`

Responsibility:

- Own RAS stack, push/pop request capture, top target, and stack count.
- Accept a side-effect allow/kill bit instead of raw global flush expressions.

Extraction risk:

Medium. RAS CE appeared as a timing endpoint in earlier phases, so this should be extracted only with focused RAS tests and physical screening.

### `m_scoreboard.v`

Responsibility:

- Future M-unit outstanding request tracking.
- Pending destination scoreboard.
- Epoch or wrong-path token management.
- Response ordering and stale-response kill.

Extraction risk:

High until redirect/side-effect boundaries are cleaner. Phase59B and Phase60B proved functionality is feasible, but physical timing is not retainable with current CPU integration.

## Repository Organization Target

Keep the existing folders, but separate signoff and experiments more clearly:

- `rtl/`: synthesizable RTL only.
- `tb/`: Verilog testbenches and test programs.
- `scripts/`: repeatable build, simulation, synthesis, implementation, and structural checks.
- `docs/superpowers/specs/`: approved design specs.
- `docs/superpowers/plans/`: executable implementation plans.
- `docs/signoff/`: future retained baseline summaries, one file per accepted phase.
- `docs/experiments/`: future rejected experiment summaries when they become too large for `findings.md`.

The pre-existing untracked file `docs/superpowers/plans/2026-06-04-csr-late-redirect-commit.md` should be reviewed separately before any cleanup. Do not silently delete or commit it as part of CPU modularization.

## Implementation Order

### Phase62A: Documentation and Baseline Contract

Deliverables:

- this design spec;
- updated `task_plan.md`, `findings.md`, and `progress.md`;
- no RTL edits.

Acceptance:

- documentation self-check passes;
- `git diff --check` passes;
- branch stays synchronized after push.

### Phase62B: Writeback Arbiter Extraction

Create:

- `rtl/writeback_arb.v`
- `tb/tb_writeback_arb.v`
- `scripts/check_writeback_arb_boundary.ps1`

Modify:

- `rtl/cpu_core.v`
- `scripts/run_modelsim.ps1`
- `scripts/check_project.ps1`
- Vivado source lists if needed

Retain only if:

- focused test passes;
- full ModelSim passes;
- CSR acceptance passes;
- CoreMark is unchanged or below the first screen;
- physical WNS is not worse than the retained baseline.

### Phase62C: Commit Side-Effect Gate Extraction

Create:

- `rtl/commit_side_effect_gate.v`
- focused tests proving kill/allow behavior for trap, MRET, redirect, replay, load response, multiply response, CSR write, DMEM write, predictor update, RAS update, and retire count.

Retain only if:

- existing CSR precision tests pass;
- focused trap/kill programs pass;
- physical WNS is not worse.

### Phase62D: Retire Counter Control Extraction

Create:

- `rtl/retire_counter_ctrl.v`
- focused counter tests including `minstret` precision interactions.

Retain only if:

- official `rv32mi/instret_overflow` acceptance remains passing;
- CSR acceptance and CoreMark remain within baseline limits.

### Later Phases

After low-risk extractions prove stable:

1. `load_replay_ctrl.v`
2. `ras_ctrl.v`
3. `bp_update_ctrl.v`
4. `redirect_ctrl.v`
5. `m_scoreboard.v`

Do not combine these into one large branch.

## Structural Check Policy

Every extracted module must have a companion PowerShell structural check. The check should verify:

- required file exists;
- module name exists;
- required parameters exist, including `XLEN` when data width is used;
- forbidden cross-domain signal names are absent;
- the module is instantiated exactly once from `cpu_core` unless documented otherwise;
- `scripts/check_project.ps1` invokes the check.

Example forbidden coupling rules:

- `writeback_arb.v` must not mention `redirect`, `trap`, `mret`, `bp_update`, or `ras`.
- `m_scoreboard.v` must not mention `branch_target`, `redirect_pc`, `redirect_fallthrough`, or `bp_update_target`.
- backend arithmetic modules must not mention CPU control terms such as `csr`, `trap`, `mret`, `redirect`, or `fallthrough`.

## Acceptance Gates for Future RTL Extractions

Minimum functional gate:

```powershell
scripts/check_project.ps1
scripts/run_modelsim.ps1
scripts/run_csr_phase_acceptance.ps1 -SkipVivado
git diff --check
```

Physical gate for timing-sensitive or retained baseline candidates:

```powershell
scripts/run_vivado_impl.ps1 -Top soc_top -Constraint huoyue_uart -OutDir build\<phase-name> -Jobs 4 -PlaceDirective ExtraNetDelay_high -PhysOptDirective AggressiveExplore -RouteDirective Explore -PostRoutePhysOptDirective AggressiveExplore
scripts/check_vivado_qor.ps1 -ReportDir build\<phase-name> -Top soc_top -RequireDmemBlockRam
scripts/check_vivado_timing.ps1 -ReportDir build\<phase-name>
```

Retention rule:

- Reject any RTL refactor that breaks CSR acceptance.
- Reject any RTL refactor with CoreMark 2 above `682500` cycles.
- Reject timing-sensitive refactors that are worse than WNS `-1.064 ns`.
- Keep failed experiment conclusions in docs, not failed RTL.

## Review Questions Before Implementation

Before writing a Phase62B plan, confirm:

- whether `writeback_arb.v` is accepted as the first extraction target;
- whether the physical no-regression rule should be strict for Phase62B or whether an intermediate documentation-only commit may precede the physical run;
- whether to add `docs/signoff/` in Phase62B or wait until the first retained RTL extraction.
