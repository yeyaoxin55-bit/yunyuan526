# RV64 Default CoreMark Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make RV64IM the default project target and validate a small RV64 CoreMark ModelSim run.

**Architecture:** Keep the RTL parameterized while changing default top-level XLEN values to 64. Parameterize the CoreMark software and hex conversion flow so RV64 is the default and RV32 remains selectable.

**Tech Stack:** Verilog RTL, ModelSim, PowerShell build scripts, bare-metal RISC-V GCC, CoreMark.

---

### Task 1: Make RV64 the default top-level target

**Files:**
- Modify: `rtl/cpu_top.v`
- Modify: `rtl/soc_top.v`
- Modify: `rtl/fpga_coremark_top.v`
- Modify: `tb/tb_soc_uart_hello.v`
- Modify: `tb/tb_soc_uart_loader.v`
- Modify: `tb/tb_soc_uart_reset_start.v`

- [ ] Change top-level `parameter XLEN = 32` defaults to `parameter XLEN = 64`.
- [ ] Add explicit `.XLEN(32)` overrides to SOC UART testbenches that still use RV32 images.
- [ ] Run `powershell -ExecutionPolicy Bypass -File scripts\run_modelsim.ps1` after later tasks are complete.

### Task 2: Parameterize external program simulation

**Files:**
- Modify: `tb/tb_external_program.v`
- Modify: `scripts/run_external_modelsim.ps1`

- [ ] Add `parameter XLEN = 64` to `tb_external_program`.
- [ ] Pass `.XLEN(XLEN)` into `cpu_top`.
- [ ] Replace direct `dut.u_dmem.mem[index]` pass/fail/result reads with a helper that returns a 32-bit little-endian word from byte address.
- [ ] Add `-XLEN` to `run_external_modelsim.ps1` and pass `-gXLEN=$XLEN` to `vsim`.

### Task 3: Parameterize CoreMark build and metadata

**Files:**
- Create: `sw/linker/yl3_rv64im.ld`
- Modify: `scripts/build_coremark.ps1`
- Modify: `scripts/run_coremark.ps1`
- Modify: `sw/coremark_port/core_portme.h`

- [ ] Add `-XLEN` to the CoreMark build and run scripts.
- [ ] For `XLEN=64`, use `-march=rv64im_zicsr_zifencei`, `-mabi=lp64`, and `sw/linker/yl3_rv64im.ld`.
- [ ] For `XLEN=32`, preserve `-march=rv32im_zicsr_zifencei`, `-mabi=ilp32`, and `sw/linker/yl3_rv32im.ld`.
- [ ] Update CoreMark compiler metadata strings using `__riscv_xlen`.

### Task 4: Parameterize DMEM hex width

**Files:**
- Modify: `scripts/convert_elf_to_hex.ps1`
- Modify: `scripts/run_coremark.ps1`

- [ ] Add `-DMemWordBytes` to `convert_elf_to_hex.ps1`.
- [ ] Keep IMEM output at 4-byte words.
- [ ] Emit RV64 DMEM as 8-byte little-endian hex lines when `-DMemWordBytes 8`.
- [ ] Emit one byte-lane file per DMEM byte lane.
- [ ] Pass `-DMemWordBytes ($XLEN / 8)` from `run_coremark.ps1`.

### Task 5: Verify RV64 CoreMark smoke and regressions

**Files:**
- Modify: `README.md`
- Modify: `progress.md`
- Modify: `scripts/check_project.ps1`

- [ ] Run `powershell -ExecutionPolicy Bypass -File scripts\run_coremark.ps1 -XLEN 64 -Iterations 1 -TotalDataSize 1200 -MaxCycles 2000000`.
- [ ] Run focused RV64 directed tests.
- [ ] Run full ModelSim regression if runtime permits.
- [ ] Run `powershell -ExecutionPolicy Bypass -File scripts\check_project.ps1`.
- [ ] Run `git diff --check`.
