# Zynq-7020 RISC-V CPU Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a synthesizable Verilog RV32I-first CPU project for Zynq-7020, with a working simulation loop and an architecture that can be extended to RV32IM/RV64IM/CoreMark.

**Architecture:** Implement a 5-stage Harvard pipeline with parameterized memories, decode/control, ALU, register file, hazard handling, and a simple AXI4-Lite-accessible top-level shell. The first executable milestone targets RV32I integer programs in simulation; M-extension, deeper branch prediction, CSR/exception completeness, and CoreMark bring-up are staged after the base pipeline is proven.

**Tech Stack:** Verilog HDL, PowerShell scripts, Icarus Verilog when available, Vivado-compatible RTL style, hex memory images for simulation.

---

## File Structure

- `rtl/defines.vh`: shared opcodes, funct fields, ALU op constants, CSR constants.
- `rtl/cpu_top.v`: top-level CPU wrapper with parameters and memory/debug-visible interfaces.
- `rtl/cpu_core.v`: 5-stage core wiring and pipeline control.
- `rtl/regfile.v`: 32 x XLEN register file.
- `rtl/alu.v`: integer ALU for RV32I/RV64I common operations.
- `rtl/decoder.v`: instruction decode and immediate generation.
- `rtl/hazard_unit.v`: load-use stalls, flushes, and forwarding selections.
- `rtl/imem.v`: parameterized instruction memory, `$readmemh` capable.
- `rtl/dmem.v`: parameterized byte-write data memory.
- `rtl/prefetch.v`: 4-entry instruction prefetch buffer placeholder integrated after base fetch works.
- `rtl/branch_predictor.v`: local-history branch predictor placeholder integrated after base branch flow works.
- `rtl/multiplier.v`: pipelined multiplier placeholder for M-extension phase.
- `rtl/divider.v`: iterative divider placeholder for M-extension phase.
- `rtl/csr_unit.v`: Machine-mode CSR subset placeholder for CSR/exception phase.
- `rtl/exception.v`: exception routing placeholder for CSR/exception phase.
- `rtl/axi4lite_if.v`: AXI4-Lite debug/load shell placeholder for bus phase.
- `tb/tb_cpu_top.v`: simulation testbench.
- `tb/programs/smoke.hex`: minimal instruction image.
- `scripts/check_project.ps1`: structural verification script that runs before simulator-specific checks.
- `scripts/run_iverilog.ps1`: optional compile/run wrapper for Icarus Verilog.
- `constraints/top_100m.xdc`: Zynq-7020 100MHz baseline timing constraints.
- `constraints/top_125m.xdc`: Zynq-7020 125MHz optimization timing constraints.

## Milestone Scope

The first implementation pass must produce:

- Synthesizable module files with stable interfaces.
- A working RV32I subset sufficient for arithmetic, load/store, branches, jumps, and simple programs.
- A testbench that loads a hex program, runs for a bounded cycle count, and checks a pass flag in DMEM.
- Scripts that verify required files exist and, if `iverilog` is installed, compile the testbench.

The first pass may defer:

- Full RV64I execution.
- Full RV32M/RV64M behavior.
- Full CSR exception semantics.
- Complete AXI4-Lite protocol implementation.
- CoreMark execution.

## Task 1: Create Project Skeleton and Structural Check

**Files:**
- Create: `rtl/defines.vh`
- Create: `scripts/check_project.ps1`
- Create: directories `rtl`, `tb`, `tb/programs`, `scripts`, `constraints`

- [ ] **Step 1: Write structural check first**

Create `scripts/check_project.ps1` with this content:

```powershell
$ErrorActionPreference = "Stop"

$required = @(
  "rtl/defines.vh",
  "rtl/cpu_top.v",
  "rtl/cpu_core.v",
  "rtl/regfile.v",
  "rtl/alu.v",
  "rtl/decoder.v",
  "rtl/hazard_unit.v",
  "rtl/imem.v",
  "rtl/dmem.v",
  "tb/tb_cpu_top.v",
  "tb/programs/smoke.hex",
  "constraints/top_100m.xdc",
  "constraints/top_125m.xdc"
)

$missing = @()
foreach ($path in $required) {
  if (-not (Test-Path -LiteralPath $path)) {
    $missing += $path
  }
}

if ($missing.Count -gt 0) {
  Write-Error ("Missing required files:`n" + ($missing -join "`n"))
}

Write-Host "Project structure OK"
```

- [ ] **Step 2: Run check and verify it fails**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/check_project.ps1
```

Expected: FAIL listing missing RTL/test/constraint files.

- [ ] **Step 3: Create directories and `rtl/defines.vh`**

Create `rtl/defines.vh` with opcode and ALU constants:

```verilog
`ifndef YL3_DEFINES_VH
`define YL3_DEFINES_VH

`define OPCODE_LUI      7'b0110111
`define OPCODE_AUIPC    7'b0010111
`define OPCODE_JAL      7'b1101111
`define OPCODE_JALR     7'b1100111
`define OPCODE_BRANCH   7'b1100011
`define OPCODE_LOAD     7'b0000011
`define OPCODE_STORE    7'b0100011
`define OPCODE_OP_IMM   7'b0010011
`define OPCODE_OP       7'b0110011
`define OPCODE_MISC_MEM 7'b0001111
`define OPCODE_SYSTEM   7'b1110011

`define ALU_ADD  5'd0
`define ALU_SUB  5'd1
`define ALU_SLL  5'd2
`define ALU_SLT  5'd3
`define ALU_SLTU 5'd4
`define ALU_XOR  5'd5
`define ALU_SRL  5'd6
`define ALU_SRA  5'd7
`define ALU_OR   5'd8
`define ALU_AND  5'd9
`define ALU_PASS 5'd10

`endif
```

- [ ] **Step 4: Re-run check**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/check_project.ps1
```

Expected: still FAIL, but `rtl/defines.vh` is no longer missing.

## Task 2: Implement Core Leaf Modules

**Files:**
- Create: `rtl/regfile.v`
- Create: `rtl/alu.v`
- Create: `rtl/decoder.v`
- Create: `rtl/imem.v`
- Create: `rtl/dmem.v`

- [ ] **Step 1: Add leaf RTL modules**

Implement:

- `regfile.v`: two async read ports, one sync write port, x0 hardwired to zero.
- `alu.v`: RV32I ALU ops using `defines.vh`.
- `decoder.v`: RV32I decode for LUI/AUIPC/JAL/JALR/BRANCH/LOAD/STORE/OP-IMM/OP/FENCE/SYSTEM-as-NOP.
- `imem.v`: word-addressed instruction memory with `IMEM_INIT_FILE`.
- `dmem.v`: byte-write data memory.

- [ ] **Step 2: Run structural check**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/check_project.ps1
```

Expected: leaf files no longer missing; top/core/test/constraints still missing.

## Task 3: Implement RV32I Pipeline Skeleton

**Files:**
- Create: `rtl/hazard_unit.v`
- Create: `rtl/cpu_core.v`
- Create: `rtl/cpu_top.v`

- [ ] **Step 1: Add hazard unit**

Implement forwarding from EX/MEM and MEM/WB to EX operands, plus one-cycle load-use stall.

- [ ] **Step 2: Add `cpu_core.v`**

Implement RV32I five-stage pipeline:

- IF: fetch from IMEM, PC update.
- ID: decode, regfile read, immediate generation.
- EX: ALU, branch/jump resolution.
- MEM: load/store.
- WB: writeback.

- [ ] **Step 3: Add `cpu_top.v`**

Expose clock/reset, halted/pass debug outputs, and instantiate IMEM/DMEM/core.

## Task 4: Add Simulation Smoke Test

**Files:**
- Create: `tb/programs/smoke.hex`
- Create: `tb/tb_cpu_top.v`
- Create: `scripts/run_iverilog.ps1`

- [ ] **Step 1: Add hex program**

Program behavior:

- Set `x1 = 5`
- Set `x2 = 7`
- Compute `x3 = 12`
- Store `x3` to DMEM address `0`
- Store pass marker `1` to DMEM address `4`
- Loop forever

- [ ] **Step 2: Add testbench**

Testbench behavior:

- Clock at 100MHz equivalent.
- Release reset.
- Run bounded cycles.
- Check DMEM word 1 equals `1`.
- Stop with PASS/FAIL message.

- [ ] **Step 3: Add Icarus wrapper**

`scripts/run_iverilog.ps1` checks `iverilog` availability, compiles all RTL and testbench, and runs `vvp`.

## Task 5: Add Constraints and Run Verification

**Files:**
- Create: `constraints/top_100m.xdc`
- Create: `constraints/top_125m.xdc`
- Modify: `progress.md`

- [ ] **Step 1: Add XDC files**

Add clock constraints:

```tcl
create_clock -period 10.000 [get_ports clk]
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets clk]
```

and:

```tcl
create_clock -period 8.000 [get_ports clk]
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets clk]
```

- [ ] **Step 2: Run structural check**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/check_project.ps1
```

Expected: `Project structure OK`.

- [ ] **Step 3: Run simulator if available**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_iverilog.ps1
```

Expected if Icarus is installed: PASS from testbench.

Expected if unavailable: script reports missing `iverilog` without modifying RTL.

## Self-Review Notes

- This plan intentionally scopes the first code pass to RV32I plus a smoke simulation. Full CoreMark is not credible until base instruction execution, memory, CSR timers, and toolchain loading are verified.
- The architecture leaves named files for M-extension, CSR, exception, prefetch, branch prediction, and AXI4-Lite so later phases can extend without renaming the project.
- No Git commit steps are included because the current directory is not a Git repository.
