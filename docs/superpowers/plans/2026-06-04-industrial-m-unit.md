# Industrial M-Unit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an industrial request/response M-unit with a DSP-friendly unified multiplier pipeline, then use it as the path toward replacing `cpu_core`'s fixed-latency multiplier metadata.

**Architecture:** Phase 59A creates and verifies `rtl/m_unit.v` independently. Phase 59B integrates the request/response interface into `cpu_core` and removes multiplier latency guessing. `cpu_core` remains responsible for stalls, flushes, side-effect kill, and writeback arbitration.

**Tech Stack:** Verilog RTL, ModelSim PowerShell scripts, Vivado 2022.2 implementation scripts, existing riscv-tests/CoreMark acceptance harnesses.

---

## File Map

- Create `rtl/m_unit.v`: request/response M-extension unit with unified multiply pipeline and epoch kill.
- Create `tb/tb_m_unit_multiplier.v`: directed RV32/RV64 unit tests for all multiply operations.
- Create `tb/tb_m_unit_pipeline.v`: request throughput, response backpressure, stale epoch, `rd=x0`, and same-rd WAW tests.
- Create `scripts/check_industrial_m_unit_boundary.ps1`: structural guard for the new boundary.
- Modify `scripts/run_modelsim.ps1`: compile and run new M-unit tests.
- Modify `scripts/check_project.ps1`: require new files and structural check.
- Modify `rtl/cpu_core.v` in Phase 59B only: replace `mul_meta_*` and direct multiplier response logic with M-unit request/response scoreboard integration.
- Modify `rtl/cpu_top.v`, `rtl/soc_top.v`, and `rtl/fpga_coremark_top.v` only if a new M-unit parameter must be plumbed to preserve board defaults.

## Task 1: Structural RED Check

**Files:**
- Create: `scripts/check_industrial_m_unit_boundary.ps1`
- Modify: none

- [ ] **Step 1: Write the failing check**

Create `scripts/check_industrial_m_unit_boundary.ps1` with these checks:

```powershell
$ErrorActionPreference = "Stop"

function Require-File($Path) {
  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Missing required file: $Path"
  }
}

function Require-Match($Path, $Pattern, $Description) {
  $text = Get-Content -Raw $Path
  if ($text -notmatch $Pattern) {
    throw "Missing $Description in $Path"
  }
}

function Reject-Match($Path, $Pattern, $Description) {
  $text = Get-Content -Raw $Path
  if ($text -match $Pattern) {
    throw "Rejected $Description in $Path"
  }
}

Require-File "rtl/m_unit.v"
Require-Match "rtl/m_unit.v" "module\s+m_unit\b" "m_unit module"
Require-Match "rtl/m_unit.v" "parameter\s+XLEN\s*=" "XLEN parameter"
Require-Match "rtl/m_unit.v" "req_valid_i" "request valid input"
Require-Match "rtl/m_unit.v" "req_ready_o" "request ready output"
Require-Match "rtl/m_unit.v" "resp_valid_o" "response valid output"
Require-Match "rtl/m_unit.v" "resp_ready_i" "response ready input"
Require-Match "rtl/m_unit.v" "req_epoch_i" "request epoch metadata"
Require-Match "rtl/m_unit.v" "current_epoch_i" "current epoch kill input"
Require-Match "rtl/m_unit.v" "lhs_ext" "unified operand extension"
Require-Match "rtl/m_unit.v" "rhs_ext" "unified operand extension"
Require-Match "rtl/m_unit.v" '\$signed\(lhs_ext\)\s*\*\s*\$signed\(rhs_ext\)' "single signed product"
Reject-Match "rtl/m_unit.v" "product_ss" "parallel signed-signed product"
Reject-Match "rtl/m_unit.v" "product_uu" "parallel unsigned product"
Reject-Match "rtl/m_unit.v" "product_su" "parallel signed-unsigned product"

Write-Host "Industrial M-unit boundary OK"
```

- [ ] **Step 2: Run the check and verify RED**

Run:

```powershell
scripts/check_industrial_m_unit_boundary.ps1
```

Expected: FAIL with `Missing required file: rtl/m_unit.v`.

## Task 2: M-Unit Multiplier Unit Test

**Files:**
- Create: `tb/tb_m_unit_multiplier.v`
- Modify: `scripts/run_modelsim.ps1`

- [ ] **Step 1: Write the failing directed test**

The test instantiates `m_unit` twice, once with `XLEN=32` and once with `XLEN=64`. It sends one request at a time and checks `MUL`, `MULH`, `MULHSU`, and `MULHU` results.

Key expected cases:

```verilog
// RV32
MUL    32'hffff_ffff * 32'h0000_0002 -> 32'hffff_fffe
MULH   32'hffff_ffff * 32'h0000_0002 -> 32'hffff_ffff
MULHSU 32'hffff_ffff * 32'h0000_0002 -> 32'hffff_ffff
MULHU  32'hffff_ffff * 32'h0000_0002 -> 32'h0000_0001

// RV64
MUL    64'hffff_ffff_ffff_ffff * 64'h2 -> 64'hffff_ffff_ffff_fffe
MULH   64'hffff_ffff_ffff_ffff * 64'h2 -> 64'hffff_ffff_ffff_ffff
MULHSU 64'hffff_ffff_ffff_ffff * 64'h2 -> 64'hffff_ffff_ffff_ffff
MULHU  64'hffff_ffff_ffff_ffff * 64'h2 -> 64'h0000_0000_0000_0001
```

- [ ] **Step 2: Run compile/test and verify RED**

Run:

```powershell
scripts/run_modelsim.ps1
```

Expected before implementation: FAIL because `m_unit` is not defined.

## Task 3: Implement Standalone `m_unit`

**Files:**
- Create: `rtl/m_unit.v`

- [ ] **Step 1: Add the request/response module**

Implement these ports:

```verilog
module m_unit #(
    parameter XLEN = 32,
    parameter MUL_PIPE_STAGES = 3,
    parameter EPOCH_WIDTH = 2
) (
    input wire clk,
    input wire rst,
    input wire req_valid_i,
    output wire req_ready_o,
    input wire [2:0] req_op_i,
    input wire [XLEN-1:0] req_rs1_i,
    input wire [XLEN-1:0] req_rs2_i,
    input wire [4:0] req_rd_i,
    input wire req_reg_write_i,
    input wire [EPOCH_WIDTH-1:0] req_epoch_i,
    input wire [EPOCH_WIDTH-1:0] current_epoch_i,
    output wire resp_valid_o,
    input wire resp_ready_i,
    output wire [4:0] resp_rd_o,
    output wire [XLEN-1:0] resp_result_o,
    output wire resp_reg_write_o,
    output wire [EPOCH_WIDTH-1:0] resp_epoch_o
);
```

For Phase 59A, `req_ready_o` may be low only when the final response register is occupied and `resp_ready_i` is low. The unit must not drop valid responses under backpressure.

- [ ] **Step 2: Use one unified product path**

Use a single product expression:

```verilog
wire lhs_signed = (stage_op == 3'b001) || (stage_op == 3'b010);
wire rhs_signed = (stage_op == 3'b001);
wire signed [XLEN:0] lhs_ext = lhs_signed ? {stage_rs1[XLEN-1], stage_rs1} : {1'b0, stage_rs1};
wire signed [XLEN:0] rhs_ext = rhs_signed ? {stage_rs2[XLEN-1], stage_rs2} : {1'b0, stage_rs2};
wire signed [(2*XLEN)+1:0] product = $signed(lhs_ext) * $signed(rhs_ext);
```

Select low/high result from the registered product.

- [ ] **Step 3: Run GREEN checks**

Run:

```powershell
scripts/check_industrial_m_unit_boundary.ps1
scripts/run_modelsim.ps1
```

Expected: both pass.

## Task 4: Pipeline Behavior Test

**Files:**
- Create: `tb/tb_m_unit_pipeline.v`
- Modify: `scripts/run_modelsim.ps1`

- [ ] **Step 1: Add back-to-back and backpressure tests**

The test must prove:

- two consecutive requests produce two ordered responses;
- `resp_ready_i=0` holds the response stable;
- a request with stale `req_epoch_i` does not assert a response writeback after `current_epoch_i` changes;
- `rd=x0` may produce a response, but `resp_reg_write_o` must be zero;
- same-rd back-to-back requests return in order.

- [ ] **Step 2: Run RED before implementing any missing behavior**

If Task 3's minimal module lacks any behavior above, run:

```powershell
scripts/run_modelsim.ps1
```

Expected: FAIL in `tb_m_unit_pipeline`.

- [ ] **Step 3: Implement the missing behavior in `rtl/m_unit.v`**

Keep response ordering in the pipeline. Hold the output response until `resp_ready_i` is high. Drop stale-epoch responses before asserting `resp_valid_o`.

- [ ] **Step 4: Run GREEN**

Run:

```powershell
scripts/check_industrial_m_unit_boundary.ps1
scripts/run_modelsim.ps1
scripts/check_project.ps1
```

Expected: all pass.

## Task 5: CPU Integration RED Tests

**Files:**
- Create or modify focused CPU tests under `tb/` and `tb/programs/`
- Modify: `scripts/run_modelsim.ps1`

- [ ] **Step 1: Write wrong-path M response test**

Create a program where a multiply is issued on a path that is killed by an older redirect/trap. The test must fail if the multiply response writes its destination register or memory-visible result.

- [ ] **Step 2: Write M scoreboard dependency test**

Create a program with:

```asm
mul x5, x1, x2
add x6, x5, x3
sw  x6, 0(x0)
```

Expected: `sw` stores the value using the multiply result, not the old `x5`.

- [ ] **Step 3: Verify RED**

Run the focused tests before changing `cpu_core`.

Expected: at least one test fails because `cpu_core` still uses the legacy `multiplier`/`mul_meta_*` integration and has no M-unit epoch boundary.

## Task 6: CPU Integration

**Files:**
- Modify: `rtl/cpu_core.v`
- Modify: top-level parameter plumbing only if needed

- [ ] **Step 1: Instantiate `m_unit`**

Replace the standalone `multiplier` instantiation used in the `FAST_MUL=0` path with `m_unit`.

- [ ] **Step 2: Remove fixed multiplier metadata**

Remove CPU logic that assumes multiplier latency:

```verilog
mul_meta_valid_pipe
mul_meta_rd_pipe
mul_meta_reg_write_pipe
mul_early_forward_valid
mul_early_forward_rd
```

Keep or replace `mul_fifo_*` only if it remains the shared writeback response queue. Prefer the M-unit response register/FIFO as the owning queue.

- [ ] **Step 3: Add M scoreboard**

Track pending destination registers for issued M requests. Decode stalls when `rs1`, `rs2`, or a younger WAW `rd` conflicts with a pending M write. Clear the scoreboard entry when a valid non-stale response is accepted into writeback.

- [ ] **Step 4: Add epoch issue/response kill**

Increment the M epoch on older redirect/trap/MRET flush. Send the current epoch with each M request. Drop responses whose epoch differs from the current epoch.

- [ ] **Step 5: Run focused GREEN**

Run:

```powershell
scripts/run_modelsim.ps1
scripts/run_riscv_suite.ps1 -Suite rv32um
scripts/run_csr_phase_acceptance.ps1 -SkipVivado
```

Expected: all pass. CoreMark 2 must stay below `682500` measured cycles for the first screen.

## Task 7: Vivado Timing Screen

**Files:**
- Modify none unless timing scripts need a new parameter passthrough

- [ ] **Step 1: Run the current best Huoyue implementation strategy**

Run:

```powershell
scripts/run_vivado_impl.ps1 -Top soc_top -Constraint huoyue_uart -OutDir build\vivado_impl_soc_top_phase59_m_unit_extra_net_delay_100m -Jobs 4 -PlaceDirective ExtraNetDelay_high -PhysOptDirective AggressiveExplore -RouteDirective Explore -PostRoutePhysOptDirective AggressiveExplore
```

- [ ] **Step 2: Gate QoR and timing**

Run:

```powershell
scripts/check_vivado_qor.ps1 -Checkpoint build\vivado_impl_soc_top_phase59_m_unit_extra_net_delay_100m\post_route.dcp -Top soc_top
scripts/check_vivado_timing.ps1 -TimingSummary build\vivado_impl_soc_top_phase59_m_unit_extra_net_delay_100m\timing_summary.rpt
```

Expected acceptance: timing must beat WNS `-1.064 ns` at minimum before keeping the CPU integration candidate. Non-negative WNS is required before claiming hardware timing closure.

## Self-Review

- Spec coverage: the plan covers standalone M-unit, unified product path, RV32/RV64 tests, epoch kill, CPU integration, CoreMark screen, and Vivado timing screen.
- Gap scan: no vague steps are left. Each phase has concrete files, behavior, commands, and expected outcomes.
- Type consistency: request/response signal names are consistent across the spec and tasks.
