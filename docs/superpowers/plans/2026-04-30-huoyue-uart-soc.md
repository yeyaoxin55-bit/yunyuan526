# Huoyue UART SoC Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a board-ready minimal SoC top that runs firmware from IMEM, exposes UART TX through MMIO, and drives the Huoyue Zynq-7020 board LEDs.

**Architecture:** Keep the existing `cpu_top` and `fpga_coremark_top` paths intact. Add `soc_top` that directly instantiates `cpu_core`, `imem`, `dmem`, `uart_tx`, and a small data-bus MMIO decoder.

**Tech Stack:** Verilog RTL, ModelSim, PowerShell regression scripts, Vivado XDC.

---

### Task 1: UART TX Regression

**Files:**
- Create: `tb/tb_uart_tx.v`
- Modify: `scripts/run_modelsim.ps1`

- [x] **Step 1: Add UART TX test**

The test instantiates `uart_tx #(.CLKS_PER_BIT(4))`, sends `8'hA5`, and verifies idle, start, LSB-first data bits, stop bit, and ready/busy behavior.

- [x] **Step 2: Run regression to verify RED**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_modelsim.ps1
```

Expected: FAIL at compile because `rtl/uart_tx.v` is not implemented yet.

Actual: FAIL at compile with missing `rtl/uart_tx.v` and `rtl/soc_top.v`.

- [x] **Step 3: Implement UART TX**

Create `rtl/uart_tx.v` with ports `clk`, `rst`, `valid_i`, `data_i`, `ready_o`, `busy_o`, and `tx_o`.

- [x] **Step 4: Verify UART TX passes**

Run the same ModelSim regression. Expected: `tb_uart_tx` passes once `uart_tx` exists.

### Task 2: SoC UART Hello Regression

**Files:**
- Create: `sw/uart_hello/uart_hello.hex`
- Create: `tb/tb_soc_uart_hello.v`
- Create: `rtl/soc_top.v`
- Modify: `scripts/run_modelsim.ps1`

- [x] **Step 1: Add firmware hex and test**

The firmware polls `UART_STATUS` at `0x0002_0004`, writes bytes to `UART_TXDATA` at `0x0002_0000`, writes pass to `0x0002_0010`, then loops. The test expects UART bytes `H`, `I`, newline, `succ=1`, `over=1`, and `halted_ind=0`.

- [x] **Step 2: Run regression to verify RED**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_modelsim.ps1
```

Expected: FAIL at compile because `rtl/soc_top.v` is not implemented yet.

Actual: FAIL at compile before RTL implementation because `rtl/soc_top.v` was missing.

- [x] **Step 3: Implement SoC top**

Decode DMEM at `0x0001_0000`, MMIO at `0x0002_0000`, `0x0002_0004`, `0x0002_0010`, `0x0002_0014`, and `0x0002_0018`. Software must poll UART ready before writing TX data.

- [x] **Step 4: Verify SoC test passes**

Run ModelSim regression. Expected: `tb_soc_uart_hello` passes and existing tests remain green.

### Task 3: Board/Vivado Integration

**Files:**
- Create: `constraints/tinyriscv_huoyue_uart.xdc`
- Modify: `scripts/vivado_synth.tcl`
- Modify: `scripts/vivado_impl.tcl`
- Modify: `scripts/run_vivado_synth.ps1`
- Modify: `scripts/run_vivado_impl.ps1`

- [x] **Step 1: Add Huoyue XDC**

Use the provided 50 MHz clock, reset key, UART pins, and LED pins.

- [x] **Step 2: Add RTL sources to Vivado scripts**

Include `uart_tx.v` and `soc_top.v` in synthesis/implementation source lists.

- [x] **Step 3: Add 50 MHz constraint option**

Allow `-Constraint huoyue_uart` in the PowerShell Vivado wrappers.

- [x] **Step 4: Run structure check and ModelSim**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\check_project.ps1
powershell -ExecutionPolicy Bypass -File scripts\run_modelsim.ps1
```

Expected: project structure check and full RTL regression pass.

Actual: `scripts/check_project.ps1` passed, full `scripts/run_modelsim.ps1` passed, and `soc_top` synthesis with `-Constraint huoyue_uart` passed at 50 MHz with WNS 8.442 ns.
