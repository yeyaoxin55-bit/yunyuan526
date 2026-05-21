# RV64IM Parameterization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the existing RV32IM CPU parameterizable to RV64IM through `XLEN=64` while preserving RV32IM as the default.

**Architecture:** Keep the SoC address map 32-bit and widen integer data paths to `XLEN`. Add internal `word_op` decode/execute semantics for RV64 W-class ALU and M instructions instead of adding a new external feature parameter.

**Tech Stack:** Verilog RTL, ModelSim/iverilog simulation scripts, existing PowerShell test harnesses, directed Verilog testbenches.

---

### Task 1: Add RV64 Directed Tests

**Files:**
- Create: `tb/tb_rv64i_basic.v`
- Create: `tb/tb_rv64m_basic.v`
- Modify: `scripts/run_modelsim.ps1`
- Modify: `scripts/run_iverilog.ps1`

- [ ] **Step 1: Write failing tests**

Create two testbenches that instantiate `cpu_top #(.XLEN(64))`, directly initialize `dut.u_imem.mem`, and check `dut.u_dmem.mem` for expected RV64 results. RV64I must cover W-class ALU semantics plus `SD/LD/LWU`. RV64M must cover `MULW/DIVW/DIVUW/REMW/REMUW`.

- [ ] **Step 2: Run tests and verify RED**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_iverilog.ps1
```

Expected: the RV64 test compile or simulation fails because the RTL still has fixed 32-bit paths and does not decode RV64-only opcodes.

### Task 2: Parameterize Core Data Signals

**Files:**
- Modify: `rtl/cpu_core.v`
- Modify: `rtl/cpu_top.v`
- Modify: `rtl/fpga_coremark_top.v`
- Modify: `rtl/soc_top.v`

- [ ] **Step 1: Replace core architectural data widths**

In `cpu_core.v`, convert register operands, immediates, ALU results, forwarding data, CSR data, memory data, multiply/divide data, and writeback data from `[31:0]` to `[XLEN-1:0]`. Keep PC and external addresses `[31:0]`.

- [ ] **Step 2: Pass `.XLEN(XLEN)`**

Replace hard-coded `.XLEN(32)` instantiations for `regfile`, `alu`, `csr_unit`, `multiplier`, and `divider` with `.XLEN(XLEN)`.

- [ ] **Step 3: Run focused compile**

Run the iverilog script. Expected: compilation progresses to missing decoder/DMEM RV64 behavior rather than fixed-width connection errors.

### Task 3: Add RV64I Decode and ALU Word Semantics

**Files:**
- Modify: `rtl/defines.vh`
- Modify: `rtl/decoder.v`
- Modify: `rtl/alu.v`
- Modify: `rtl/cpu_core.v`

- [ ] **Step 1: Add RV64 opcodes and `word_op`**

Define `OPCODE_OP_IMM_32` and `OPCODE_OP_32`. Parameterize `decoder` with `XLEN`, widen `imm`, and emit `word_op`.

- [ ] **Step 2: Add ALU W behavior**

Add an ALU `word_op` input. For `word_op`, execute low-32 operations and sign-extend the 32-bit result to `XLEN`. Normal shifts use 6-bit shift amounts only when `XLEN == 64`.

- [ ] **Step 3: Connect `word_op` through the pipeline**

Add `id_ex_word_op` and use it when selecting ALU and M-extension behavior.

- [ ] **Step 4: Run RV64I test**

Run the focused RV64I test. Expected: RV64I ALU W behavior passes or the remaining failure points to DMEM load/store width.

### Task 4: Parameterize DMEM for 32/64-bit Data

**Files:**
- Modify: `rtl/dmem.v`
- Modify: `rtl/cpu_top.v`
- Modify: `rtl/cpu_core.v`
- Modify: `rtl/soc_top.v`

- [ ] **Step 1: Add `XLEN` to DMEM**

Make `dmem` memory words `[XLEN-1:0]`, byte enables `[XLEN/8-1:0]`, and read windows `2*XLEN` wide.

- [ ] **Step 2: Add RV64 load/store formatting**

In `cpu_core.v`, support `LD`, `SD`, and `LWU` when `XLEN == 64`. Existing byte/half/word sign and zero extension must still work for RV32 and RV64.

- [ ] **Step 3: Run RV64I test**

Expected: `tb_rv64i_basic` passes.

### Task 5: Add RV64M W-Class Semantics

**Files:**
- Modify: `rtl/cpu_core.v`
- Modify: `rtl/decoder.v`

- [ ] **Step 1: Decode `OP_32 + funct7=0000001` as M word operations**

Set both `m_ext` and `word_op` for RV64M W instructions.

- [ ] **Step 2: Implement W multiply/divide/remainder result path**

For `word_op && m_ext`, operate on `rs1[31:0]` and `rs2[31:0]` and sign-extend the 32-bit result. Preserve full-width M behavior for non-word operations.

- [ ] **Step 3: Run RV64M test**

Expected: `tb_rv64m_basic` passes.

### Task 6: Regression and Documentation

**Files:**
- Modify: `README.md`
- Modify: `progress.md`

- [ ] **Step 1: Run RV32 regression**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_iverilog.ps1
```

If ModelSim is available, run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_modelsim.ps1
```

- [ ] **Step 2: Update docs**

Document that RV64IM is available through `XLEN=64`, with 64-bit integer data semantics and the current 32-bit SoC address map.

- [ ] **Step 3: Review diff**

Run:

```powershell
git diff --stat
git diff -- rtl tb scripts docs README.md progress.md
```

Confirm changes match the design and do not include unrelated edits.
