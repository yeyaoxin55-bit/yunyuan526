# Phase 60 Industrial M-Unit Backend and CPU Boundary Design

## Goal

Turn the Phase 59 standalone `m_unit` into a signoff-oriented execution block and define a second CPU integration attempt that does not feed the existing redirect/fallthrough critical cone.

Phase 60 is intentionally split into two independently rejectable slices:

1. Phase60A proves the M-unit backend in isolation with ModelSim and Vivado out-of-context synthesis.
2. Phase60B integrates the M-unit into `cpu_core` only after the isolated backend has measurable timing/resource evidence.

## Baseline

The current branch keeps Phase59A and rejects Phase59B:

- `rtl/m_unit.v` exists as a standalone request/response multiplier unit.
- The M-unit is `XLEN` parameterized and supports RV32/RV64 multiply semantics.
- It uses one signed extended product path and a two-stage full-product pipeline before result selection.
- It has response backpressure, stale epoch response kill, `rd=x0` write suppression, and same-rd ordered response coverage.
- `cpu_core` still uses the old fixed-latency `mul_meta_*` pipeline and `mul_fifo_*`.

The best retained hardware timing artifact remains negative:

- Best known physical result: WNS `-1.064 ns`.
- The failing cone repeatedly involves multiplier metadata, forwarding/hazard state, redirect payload, `redirect_fallthrough_pc_q`, and branch predictor update/control state.

Phase59B showed that a direct request/response CPU integration is functionally viable but not physically good enough:

- CoreMark 2 remained below the `682500` screen.
- Full implementation reached WNS `-1.276 ns` after extra product pipelining.
- That still failed to beat `-1.064 ns`, so the CPU integration was reverted.

## Industrial Direction

An industrial-quality next step must avoid treating Vivado implementation as the first debugger. The M-unit backend must become a measurable IP block before it is allowed to disturb the whole CPU.

The design rule for Phase60 is:

> Isolate arithmetic backend proof from CPU control proof.

Phase60A is about the arithmetic block:

- backend selection;
- FPGA synthesis mapping;
- DSP/resource report checks;
- latency metadata;
- focused correctness tests.

Phase60B is about CPU ownership and timing boundaries:

- scoreboard ownership;
- issue gating;
- response arbitration;
- wrong-path kill;
- deliberate removal of M response same-cycle forwarding from redirect/branch/JALR paths.

## Phase60A Backend Architecture

`m_unit` keeps the public request/response interface from Phase 59. Internally, the multiplier backend becomes selectable through a parameter:

```verilog
parameter M_BACKEND = 0
```

Backend values:

```verilog
localparam M_BACKEND_GENERIC = 0;
localparam M_BACKEND_XILINX_DSP = 1;
```

The wrapper remains responsible for:

- request metadata capture;
- response valid/ready behavior;
- stale epoch suppression;
- `rd=x0` write suppression;
- ordered response delivery;
- result selection for architectural operations.

The backend is responsible only for arithmetic:

```verilog
valid_i
op_i
rs1_i
rs2_i
valid_o
result_o
```

The backend must not see PC redirect, CSR state, branch predictor state, or pipeline flush signals. Wrong-path handling remains epoch-based at the wrapper boundary.

### Generic Backend

The generic backend preserves the current portable Verilog behavior:

- one `(XLEN+1) x (XLEN+1)` signed product;
- explicit full-product pipeline;
- RV32/RV64 support;
- ModelSim-friendly implementation.

This backend remains the default for portability and simulation.

### Xilinx DSP Backend

The Xilinx backend is FPGA-specific and may use one of two implementation forms:

1. A Vivado-friendly structural Verilog implementation with synthesis attributes and explicit pipeline stages.
2. A committed Xilinx generated IP or macro wrapper if inference still leaves DSP MREG/PREG warnings.

The first implementation should prefer structural Verilog. A generated IP is allowed only if OOC reports prove the structural version cannot meet the DSP pipeline target.

The Xilinx backend must expose fixed latency to the wrapper through a local parameter or documented invariant. It must not require `cpu_core` to mirror internal stage count.

## OOC Synthesis Contract

Phase60A adds a repeatable OOC synthesis flow for `m_unit`.

The OOC flow must support:

- top `m_unit`;
- `XLEN=32`;
- `XLEN=64` if Vivado accepts the width for the selected backend;
- `M_BACKEND=0` generic;
- `M_BACKEND=1` Xilinx DSP;
- Huoyue part `xc7z020clg400-1`;
- 100 MHz constraint for an apples-to-apples first screen.

The OOC reports must be parsed by a check script. The check script should not claim SoC timing closure. It only decides whether the M-unit backend is worth integrating.

Minimum OOC acceptance:

- synthesis completes;
- utilization report exists;
- timing summary exists;
- DSP utilization report exists when Vivado can generate it;
- worst synthesis timing is not catastrophically negative for a 100 MHz target;
- DSP count is nonzero for the Xilinx backend;
- the report text does not contain known unpipelined DSP warnings for the M-unit backend.

The exact WNS threshold for OOC is not the SoC signoff target. A practical first threshold is:

```text
SYNTH_WORST_SLACK_NS >= 0.000 for M_BACKEND_XILINX_DSP at XLEN=32
```

If this threshold fails, Phase60A does not proceed to CPU integration.

## Phase60B CPU Boundary Architecture

The next CPU integration must not repeat Phase59B's shape.

Phase59B replaced fixed latency with request/response state, but the resulting scoreboard still fed the broad forwarding/redirect/fallthrough control cone. Phase60B must introduce a narrower CPU boundary.

Recommended CPU-side split:

1. `m_issue` boundary in or near EX:
   - forms one M request;
   - owns request valid/ready;
   - assigns current epoch;
   - does not generate PC redirect.
2. `m_scoreboard` boundary in decode/hazard:
   - tracks only outstanding architectural destinations;
   - exposes registered `rs1_pending`, `rs2_pending`, and WAW/order pending bits;
   - does not expose full response data to ID redirect logic.
3. `m_wb` boundary at shared writeback2:
   - arbitrates load response versus M response;
   - writes regfile through existing writeback2 path;
   - clears scoreboard entries only when writeback is accepted or explicitly discarded.

### No Same-Cycle Control-Path Forwarding

The first Phase60B candidate must deliberately remove M response same-cycle forwarding from:

- branch compare inputs;
- JALR base target calculation;
- redirect payload calculation;
- branch predictor update payload;
- RAS push/pop decisions;
- CSR/trap redirect classification.

If an instruction in ID/EX needs an outstanding M result for a control-flow decision, it stalls until the M writeback has crossed a registered boundary. This may cost cycles, but it should reduce timing risk.

Same-cycle M forwarding may be reintroduced later only if timing is already clean.

### Epoch and Kill Policy

`cpu_core` remains the owner of architectural control:

- exception priority;
- redirect valid;
- PC target selection;
- pipeline flush;
- younger side-effect kill;
- CSR commit/trap/MRET commit;
- branch predictor update;
- RAS update;
- retire count.

The M-unit receives only epoch metadata. On older redirect/trap/MRET flush, the CPU increments the M epoch or otherwise marks younger M work stale. The M backend is not reset or cleared by frontend flush.

Wrong-path M responses must be discarded before regfile writeback and before scoreboard clear that could unblock a wrong dependency.

### Scoreboard Policy

The scoreboard is architectural, not physical-latency based.

It tracks:

- `rd`;
- valid;
- epoch;
- whether writeback is required.

It does not track:

- multiplier internal stage index;
- product pipe state;
- redirect/fallthrough payload state;
- branch predictor payload state.

Consumer stalls are conservative in the first candidate:

- if `rs1` or `rs2` matches any outstanding M destination, stall;
- if a younger M write targets an already outstanding destination, stall or preserve ordered issue;
- if shared writeback2 is busy, hold the response at `m_wb` and keep the scoreboard entry valid.

## Acceptance Gates

### Phase60A Keep Gate

Keep the backend slice only if all pass:

- `scripts/check_industrial_m_unit_boundary.ps1`;
- `tb_m_unit_multiplier`;
- `tb_m_unit_pipeline`;
- full `scripts/run_modelsim.ps1` or equivalent focused plus full regression evidence;
- OOC synth for `m_unit` generic backend;
- OOC synth for `m_unit` Xilinx backend;
- OOC report check for DSP usage and warning screen.

### Phase60B Keep Gate

Keep CPU integration only if all pass:

- focused structural check proves `cpu_core` no longer uses `mul_meta_*` for M response tracking;
- focused structural check proves no M response same-cycle forward path feeds redirect/fallthrough control;
- full ModelSim regression;
- `scripts/run_riscv_suite.ps1 -Suite rv32um -FastMul 0 -MulStages 1`;
- `scripts/run_csr_phase_acceptance.ps1 -SkipVivado`;
- CoreMark 2 result cycles stay below `682500`;
- Huoyue `soc_top` implementation beats WNS `-1.064 ns` before any retention decision;
- final target remains WNS `>= 0.000 ns`, setup endpoints `0`, hold endpoints `0`, and QoR OK.

## Rejection Rules

Reject immediately if any candidate:

- modifies `cpu_core` before Phase60A OOC backend evidence exists;
- reintroduces direct M response data into branch/JALR redirect target paths;
- requires frontend global reset/clear fan-in similar to Phase58;
- leaves `mul_meta_valid_pipe`, `mul_meta_rd_pipe`, or `mul_meta_reg_write_pipe` as active CPU M response tracking after Phase60B;
- worsens physical WNS versus `-1.064 ns` after a full Huoyue implementation;
- passes simulation but fails the CoreMark first screen.

## Non-Goals

Phase 60 does not implement:

- divider request/response migration;
- S/U mode;
- PMP;
- MMU;
- CLINT/PLIC;
- timer/software/external interrupts;
- compressed instruction support;
- branch predictor redesign;
- debug CSR support.

## Expected Outcome

The ideal Phase60 result is not merely "a faster multiplier." The intended result is a reusable M execution boundary with measurable isolated synthesis evidence and a CPU integration shape that reduces timing fan-in instead of moving the same route-heavy cone to a new endpoint.

If Phase60A passes but Phase60B fails timing, keep Phase60A and reject Phase60B. That still leaves the project with a cleaner M-unit backend ready for a later CPU control redesign.
