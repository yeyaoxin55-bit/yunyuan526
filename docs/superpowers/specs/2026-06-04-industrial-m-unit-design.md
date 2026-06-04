# Industrial M-Unit Design

## Goal

Build an industrial-style M-extension execution boundary that can host a DSP-friendly multiplier pipeline now and a divider pipeline later, while keeping `cpu_core` responsible for architectural control: stalls, flush, redirect, side-effect kill, and retirement.

## Current Baseline

The retained CSR branch RTL is the Phase 54/55 clean baseline. It passes CSR functional acceptance, but Huoyue/Zynq-7020 100 MHz timing remains blocked. The current best physical artifact is still timing-negative at WNS `-1.064 ns`.

The existing multiplier path has two structural problems for an industrial implementation:

- `cpu_core` predicts multiplier latency with parallel `mul_meta_*` pipes. This couples CPU hazard logic to the exact multiplier latency.
- `rtl/multiplier.v` computes `product_ss`, `product_uu`, and `product_su` in parallel. This is easy to verify, but it spends DSP resources and makes DSP input/output pipelining harder to control.

## Scope

Phase 59 focuses on synchronous M-extension execution only.

In scope:

- `XLEN=32` and `XLEN=64` parameterization.
- A new `m_unit` request/response interface.
- A unified signed-extended multiplier product path.
- Back-to-back request acceptance when the multiplier pipeline can accept one request per cycle.
- Epoch-based response kill so wrong-path M responses cannot write the regfile.
- A response FIFO boundary so shared writeback pressure does not corrupt M results.
- Tests for directed RV32/RV64 multiply cases, back-to-back operation, response backpressure, stale-epoch kill, `rd=x0`, and same-rd WAW behavior.

Out of scope for the first implementation slice:

- Replacing the divider with the same interface.
- Adding async interrupts, PMP, MMU, S/U mode, CLINT, or PLIC.
- Retuning branch/CSR redirect policy.
- Claiming timing closure without a fresh Vivado implementation run.

## Architecture

`cpu_core` will eventually issue M-extension work as a transaction:

```verilog
req_valid_i
req_ready_o
req_op_i
req_rs1_i
req_rs2_i
req_rd_i
req_reg_write_i
req_epoch_i
```

The M-unit returns completed architectural responses:

```verilog
resp_valid_o
resp_ready_i
resp_rd_o
resp_result_o
resp_reg_write_o
resp_epoch_o
```

The request carries all metadata needed for writeback. `cpu_core` no longer mirrors multiplier latency with a separate `mul_meta_*` pipe after Phase 59B.

Flush handling is epoch-based. `cpu_core` increments an M epoch whenever an older redirect/trap/MRET flush invalidates younger work. The M-unit may continue computing stale requests, but its response is discarded if its epoch is stale. This keeps the multiplier pipeline local and avoids broad kill/reset cones through DSP stages.

## Multiplier Product Semantics

The multiplier uses one signed product path of width `(XLEN+1) x (XLEN+1)`.

Operand extension:

```verilog
lhs_signed = (op == MULH) || (op == MULHSU);
rhs_signed = (op == MULH);
lhs_ext = lhs_signed ? {rs1[XLEN-1], rs1} : {1'b0, rs1};
rhs_ext = rhs_signed ? {rs2[XLEN-1], rs2} : {1'b0, rs2};
product = $signed(lhs_ext) * $signed(rhs_ext);
```

Result selection:

```verilog
MUL    -> product[XLEN-1:0]
MULH   -> product[(2*XLEN)-1:XLEN]
MULHSU -> product[(2*XLEN)-1:XLEN]
MULHU  -> product[(2*XLEN)-1:XLEN]
```

For `MUL`, signedness does not change the low `XLEN` result bits.

## Pipeline Shape

The first accepted implementation should use explicit register boundaries:

1. Request capture.
2. Operand extension and metadata capture.
3. DSP product register.
4. Result select register.
5. Response register or response FIFO enqueue.

This is allowed to add latency. The acceptance criterion is not zero-cycle multiply. The acceptance criterion is a clean, scalable boundary that gives Vivado real DSP pipeline registers and removes CPU latency guessing.

## CPU Integration Policy

Phase 59A adds and verifies `m_unit` independently. It does not change `cpu_core`.

Phase 59B replaces the `cpu_core` multiplier integration:

- Remove `mul_meta_valid_pipe`, `mul_meta_rd_pipe`, and `mul_meta_reg_write_pipe`.
- Track outstanding M writes with a scoreboard keyed by `rd`.
- Stall consumers while a needed M result is outstanding, unless a same-cycle response forward is explicitly available.
- Stall or queue requests when the M-unit cannot accept a new request.
- Gate request issue with existing older-flush, trap, and redirect kill rules.
- Gate response writeback with epoch validity, `rd != x0`, and shared writeback availability.

The CPU remains the owner of architectural control. The M-unit does not decide PC redirect, CSR state, or retirement.

## Acceptance

A Phase 59A candidate can be kept only if:

- The structural RED check fails on the old baseline and passes after the new files are added.
- The new `m_unit` unit test passes for RV32 and RV64 directed cases.
- Existing multiplier unit regressions still pass.
- `scripts/check_project.ps1` passes after adding the new required files.

A Phase 59B candidate can be kept only if:

- Focused CPU M-extension tests pass.
- Full `rv32um` passes with `FAST_MUL=0`.
- CSR phase acceptance without Vivado passes.
- CoreMark 2 stays below `682500` cycles for the first screen.
- A Huoyue `soc_top` 100 MHz implementation beats the current best physical WNS `-1.064 ns`; otherwise the CPU integration candidate is rejected even if simulation is clean.

## Stop Rules

- If a candidate worsens timing versus `-1.064 ns`, revert RTL and keep only the experiment record.
- If a candidate requires broad frontend clear/reset fan-in similar to Phase 58, stop and redesign before another Vivado run.
- If a candidate only changes local expressions around redirect or predictor payloads, reject it before implementation. That path family is exhausted.
