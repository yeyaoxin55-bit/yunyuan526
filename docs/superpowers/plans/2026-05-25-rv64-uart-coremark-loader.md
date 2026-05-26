# RV64 UART CoreMark Loader Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the UART download path capable of loading default RV64 CoreMark images into FPGA DMEM without corrupting 64-bit memory words.

**Architecture:** Keep the UART wire protocol as 32-bit payload words so existing IMEM and RV32 flows remain compatible. Split 64-bit DMEM hex rows into two 32-bit UART writes in the host script, and make `dmem` merge each loader write into the selected 4-byte half of the addressed `XLEN` memory word.

**Tech Stack:** Verilog RTL, PowerShell UART/image scripts, ModelSim regression, RV64 CoreMark image generation.

---

### Task 1: Add RV64 Loader Regression

**Files:**
- Create: `tb/tb_dmem_loader_rv64.v`
- Modify: `scripts/run_modelsim.ps1`
- Modify: `scripts/check_project.ps1`

- [x] Add a ModelSim test that writes `0x55667788` to `DMEM_BASE + 0` and `0x11223344` to `DMEM_BASE + 4` through the loader port of an `XLEN=64`, BRAM-friendly `dmem`.
- [x] Read back at `DMEM_BASE + 0` and expect `64'h1122334455667788`.
- [x] Read back at `DMEM_BASE + 4` and expect the low 32 bits to be `32'h11223344`.
- [x] Add the test to the full ModelSim source and test lists.
- [x] Add the test file to project structure checks.

### Task 2: Merge 32-bit Loader Writes Into RV64 DMEM Words

**Files:**
- Modify: `rtl/dmem.v`

- [x] In the misaligned-memory generate branch, replace full-word loader assignment with byte-wise writes at `loader_addr - DMEM_BASE`.
- [x] In the BRAM-friendly generate branch, compute loader byte enable from the loader byte offset and shift the 32-bit loader word into the selected half.
- [x] Preserve RV32 behavior as a normal 4-byte full-word write.
- [x] Keep debug 32-bit word updates consistent with byte-addressed loader writes.

### Task 3: Send RV64 DMEM Hex As 32-bit UART Chunks

**Files:**
- Modify: `scripts/send_uart_image.ps1`

- [x] Add `-DMemWordBytes` with valid values `4` and `8`, defaulting to `8` for the RV64 project default.
- [x] Keep IMEM reading fixed at 4-byte words.
- [x] For `DMemWordBytes=8`, parse each 16-hex-digit row as `UInt64` and append low 32 bits then high 32 bits to the UART payload list.
- [x] Keep UART packet format and address stepping at 4 bytes per payload word.
- [x] Print the selected DMEM word width in the completion message.

### Task 4: Document Scheme C

**Files:**
- Modify: `README.md`
- Modify: `docs/fpga_coremark_bringup.md`
- Modify: `progress.md`

- [x] Document that RV64 FPGA/CoreMark UART download uses the unchanged 32-bit UART packet protocol while the host script splits 64-bit DMEM rows.
- [x] Document `-DMemWordBytes 4` as the compatibility override for RV32 images.
- [x] Record the verification commands and results.

### Task 5: Verify

**Files:**
- No source files.

- [x] Run `powershell -ExecutionPolicy Bypass -File scripts\check_project.ps1`.
- [x] Run full `powershell -ExecutionPolicy Bypass -File scripts\run_modelsim.ps1`.
- [x] Run `powershell -ExecutionPolicy Bypass -File scripts\prepare_coremark_fpga.ps1 -XLEN 64 -CpuHz 100000000 -SmokeIterations 1 -TenMsIterations 1 -TenSecIterations 1`.
- [x] Run `git diff --check`.
