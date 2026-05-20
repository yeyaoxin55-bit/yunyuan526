# UART CoreMark Loader Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a board-ready UART download path that can load CoreMark IMEM/DMEM images into FPGA BRAM and then start the existing RV32IM CPU.

**Architecture:** Keep the current CPU datapath and `fpga_coremark_top` performance path intact. Add optional loader write ports to IMEM/DMEM, a small UART RX block, and a hardware `uart_loader` that owns memory writes while CPU reset is held. After a valid `START` packet, `soc_top` releases the CPU to execute from address `0x00000000`.

**Tech Stack:** Verilog RTL, ModelSim testbenches, PowerShell host tooling, Vivado Tcl/PowerShell scripts.

---

### Task 1: Bitstream Output

**Files:**
- Modify: `scripts/vivado_impl.tcl`
- Modify: `scripts/run_vivado_impl.ps1`

- [ ] **Step 1: Add bitstream generation checks before code changes**

Run:

```powershell
Select-String -Path scripts\vivado_impl.tcl -Pattern "write_bitstream"
```

Expected: no matches, proving bitstream output is currently missing.

- [ ] **Step 2: Generate bitstream after post-route reports**

In `scripts/vivado_impl.tcl`, after `report_timing_summary -file [file join $out_dir "timing_summary_post_route.rpt"]`, add:

```tcl
write_bitstream -force [file join $out_dir "${top}.bit"]
puts "IMPL_BITSTREAM=[file join $out_dir "${top}.bit"]"
```

- [ ] **Step 3: Make wrapper verify the bitstream**

In `scripts/run_vivado_impl.ps1`, after checking the utilization report, add:

```powershell
$bitstream = Join-Path $resolvedOutDir "$Top.bit"
if (-not (Test-Path -LiteralPath $bitstream)) {
  throw "Missing bitstream: $bitstream"
}
Write-Host "Bitstream: $bitstream"
```

- [ ] **Step 4: Verify script-level support**

Run:

```powershell
Select-String -Path scripts\vivado_impl.tcl,scripts\run_vivado_impl.ps1 -Pattern "write_bitstream|Missing bitstream|IMPL_BITSTREAM"
```

Expected: matches in both scripts.

### Task 2: UART RX

**Files:**
- Create: `rtl/uart_rx.v`
- Create: `tb/tb_uart_rx.v`
- Modify: `scripts/run_modelsim.ps1`

- [ ] **Step 1: Write failing UART RX regression**

Create `tb/tb_uart_rx.v` that instantiates `uart_rx #(.CLKS_PER_BIT(4))`, drives one byte `8'hA5` on `rx_i`, and expects one-cycle `valid_o` with `data_o == 8'hA5`.

- [ ] **Step 2: Wire test into ModelSim and verify RED**

Add `rtl/uart_rx.v` and `tb/tb_uart_rx.v` to `scripts/run_modelsim.ps1`, and add `tb_uart_rx` to the test list.

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_modelsim.ps1
```

Expected: compile fails because `rtl/uart_rx.v` does not exist.

- [ ] **Step 3: Implement UART RX**

Create `rtl/uart_rx.v` with ports `clk`, `rst`, `rx_i`, `valid_o`, and `data_o`. Sample at the middle of each bit, shift LSB-first, assert `valid_o` for one clock on a valid stop bit.

- [ ] **Step 4: Verify GREEN**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_modelsim.ps1
```

Expected: `tb_uart_rx` passes and existing regressions remain green.

### Task 3: Loader Memory Ports

**Files:**
- Modify: `rtl/imem.v`
- Modify: `rtl/dmem.v`
- Create: `tb/tb_loader_memory_ports.v`
- Modify: `scripts/run_modelsim.ps1`

- [ ] **Step 1: Write failing memory-port regression**

Create `tb/tb_loader_memory_ports.v`. The test writes `32'h12345678` into IMEM word index 1 through a new loader port, reads address `4`, and expects the new word. It also writes `32'hdeadbeef` into DMEM index 2 through a new loader port, reads address `DMEM_BASE + 8`, and expects the new word.

- [ ] **Step 2: Wire test into ModelSim and verify RED**

Add `tb_loader_memory_ports` to `scripts/run_modelsim.ps1`.

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_modelsim.ps1
```

Expected: compile fails because `imem` and `dmem` do not have loader write ports.

- [ ] **Step 3: Add loader write ports**

Add these ports to `imem`:

```verilog
input wire loader_we,
input wire [31:0] loader_addr,
input wire [31:0] loader_wdata
```

On each clock, if `loader_we` and `loader_addr[31:2] < IMEM_DEPTH`, write `loader_wdata` into `mem[loader_addr[31:2]]`.

Add these ports to `dmem`:

```verilog
input wire loader_we,
input wire [31:0] loader_addr,
input wire [31:0] loader_wdata
```

On each clock, if `loader_we` and the derived word index is in range, write `loader_wdata` into the DMEM array.

- [ ] **Step 4: Update all module instantiations**

Tie loader ports low in existing CPU-only testbenches and tops, except `soc_top` which will connect them in Task 5.

- [ ] **Step 5: Verify GREEN**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_modelsim.ps1
```

Expected: `tb_loader_memory_ports` passes and existing regressions remain green.

### Task 4: UART Loader Protocol

**Files:**
- Create: `rtl/uart_loader.v`
- Create: `tb/tb_uart_loader.v`
- Modify: `scripts/run_modelsim.ps1`

- [ ] **Step 1: Write failing loader regression**

Create `tb/tb_uart_loader.v`. Drive bytes directly into `uart_loader.rx_valid_i/rx_data_i` for these packets:

```text
Magic: 59 4c 33 4c ("YL3L")
CMD_WRITE_IMEM: 01
ADDR: 00000004
WORD_COUNT: 00000001
PAYLOAD: 12345678
CHECKSUM: byte sum of CMD through payload, low byte

Magic: 59 4c 33 4c
CMD_WRITE_DMEM: 02
ADDR: 00010008
WORD_COUNT: 00000001
PAYLOAD: deadbeef
CHECKSUM: byte sum of CMD through payload, low byte

Magic: 59 4c 33 4c
CMD_START: 03
ADDR: 00000000
WORD_COUNT: 00000000
CHECKSUM: byte sum of CMD through word_count, low byte
```

Expected behavior: one-cycle `imem_we_o`, one-cycle `dmem_we_o`, and sticky `start_cpu_o`.

- [ ] **Step 2: Wire test and verify RED**

Add `rtl/uart_loader.v` and `tb/tb_uart_loader.v` to `scripts/run_modelsim.ps1`.

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_modelsim.ps1
```

Expected: compile fails because `rtl/uart_loader.v` does not exist.

- [ ] **Step 3: Implement minimal loader**

Implement a byte-oriented FSM:

```text
WAIT_MAGIC -> CMD -> ADDR[4] -> COUNT[4] -> PAYLOAD words -> CHECKSUM
```

Use big-endian packet fields for host readability. Convert each payload word to 32-bit memory data. Write consecutive words at `addr + word_index * 4`. On checksum mismatch, increment `error_count_o` and return to `WAIT_MAGIC`.

- [ ] **Step 4: Verify GREEN**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_modelsim.ps1
```

Expected: `tb_uart_loader` passes and existing regressions remain green.

### Task 5: SoC Download Integration

**Files:**
- Modify: `rtl/soc_top.v`
- Create: `tb/tb_soc_uart_loader.v`
- Modify: `scripts/run_modelsim.ps1`

- [ ] **Step 1: Write failing SoC download regression**

Create `tb/tb_soc_uart_loader.v`. Instantiate `soc_top #(.UART_CLKS_PER_BIT(4), .IMEM_INIT_FILE(""))`, send UART packets that write a tiny IMEM program and DMEM data, send `START`, then expect `succ=1` and `over=1`.

Tiny program:

```text
00000000: 000100b7  lui x1,0x10
00000004: 00100113  addi x2,x0,1
00000008: 0020a823  sw x2,16(x1)  ; DMEM pass marker path for this test program
0000000c: 0000006f  jal x0,0
```

- [ ] **Step 2: Verify RED**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_modelsim.ps1
```

Expected: test fails because `soc_top` does not yet instantiate `uart_rx`/`uart_loader` or hold CPU reset until `START`.

- [ ] **Step 3: Integrate UART RX and loader**

In `soc_top`, instantiate `uart_rx` on `uart_rx_pin`, feed it to `uart_loader`, connect loader write ports to IMEM/DMEM, and define:

```verilog
wire cpu_rst = rst || !loader_start_cpu;
```

Use `cpu_rst` for `cpu_core`, while UART RX/TX and loader use board reset only.

- [ ] **Step 4: Preserve hello default**

Add parameter `BOOT_FROM_INIT = 1`. When set, initialize `loader_start_cpu` as active after reset so existing `uart_hello` behavior remains unchanged. In loader-download tests set `BOOT_FROM_INIT = 0`.

- [ ] **Step 5: Verify GREEN**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_modelsim.ps1
```

Expected: both `tb_soc_uart_hello` and `tb_soc_uart_loader` pass.

### Task 6: Host Download Script and Documentation

**Files:**
- Create: `scripts/send_uart_image.ps1`
- Modify: `docs/fpga_coremark_bringup.md`
- Modify: `scripts/check_project.ps1`

- [ ] **Step 1: Add script structure check**

Add `scripts/send_uart_image.ps1` to `scripts/check_project.ps1`, then run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\check_project.ps1
```

Expected: FAIL because the script does not exist.

- [ ] **Step 2: Implement host script**

Create `scripts/send_uart_image.ps1` with parameters:

```powershell
param(
  [Parameter(Mandatory=$true)][string]$PortName,
  [string]$IMemHex = "build/coremark/fpga/coremark.imem.hex",
  [string]$DMemHex = "build/coremark/fpga/coremark.dmem.hex",
  [int]$BaudRate = 115200
)
```

It reads Verilog hex word files, emits `WRITE_IMEM`, `WRITE_DMEM`, and `START` packets, and closes the serial port.

- [ ] **Step 3: Document board flow**

Update `docs/fpga_coremark_bringup.md` with:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\prepare_coremark_fpga.ps1 -CpuHz 50000000
powershell -ExecutionPolicy Bypass -File scripts\run_vivado_impl.ps1 -Top soc_top -Constraint huoyue_uart -OutDir build/vivado_impl_soc_top_huoyue
powershell -ExecutionPolicy Bypass -File scripts\send_uart_image.ps1 -PortName COMx -BaudRate 115200
```

- [ ] **Step 4: Verify structure**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\check_project.ps1
```

Expected: PASS.

### Task 7: Final Verification

**Files:**
- Modify: `task_plan.md`
- Modify: `findings.md`
- Modify: `progress.md`

- [ ] **Step 1: Full ModelSim regression**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_modelsim.ps1
```

Expected: PASS for all testbenches.

- [ ] **Step 2: Project structure check**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\check_project.ps1
```

Expected: PASS.

- [ ] **Step 3: Vivado implementation check when available**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_vivado_impl.ps1 -Top soc_top -Constraint huoyue_uart -OutDir build/vivado_impl_soc_top_huoyue
```

Expected: post-route timing passes and `soc_top.bit` exists. If Vivado is unavailable or runtime is too long for this session, record the exact blocker and keep the script-level checks plus ModelSim evidence.

- [ ] **Step 4: Update planning files**

Add Phase 29 entries describing bitstream output and UART CoreMark loader status. Record verification commands and results.
