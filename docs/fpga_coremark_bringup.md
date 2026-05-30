# FPGA CoreMark Bring-up Notes

## Memory map

- IMEM: `0x00000000`, 64 KiB
- DMEM: `0x00010000`, 32 KiB
- pass marker: `0x00017ff0`
- fail marker: `0x00017ff4`
- CoreMark cycle result: `0x00017ff8`

## Generate FPGA hex images

```powershell
powershell -ExecutionPolicy Bypass -File scripts\prepare_coremark_fpga.ps1 -CpuHz 100000000
```

This creates:

- `build/coremark/fpga/coremark_o1.imem.hex`
- `build/coremark/fpga/coremark_o1.dmem.hex`
- `build/coremark/fpga/coremark_o2.imem.hex`
- `build/coremark/fpga/coremark_o2.dmem.hex`
- `build/coremark/fpga/coremark_o3.imem.hex`
- `build/coremark/fpga/coremark_o3.dmem.hex`
- `build/coremark/fpga/manifest.csv`

All three generated images default to `ITERATIONS=2200`, which is intended to exceed the 10 second CoreMark validation window at 100 MHz after the timing-safe load-use fix. The `o3` image is the default UART download target.

## FPGA top

Use `rtl/fpga_coremark_top.v` as a simple bring-up wrapper. It exposes:

- `pass_o`
- `fail_o`
- `done_o`
- `cycle_o[31:0]`
- `led[3:0] = {done_o, fail_o, pass_o, cycle_o[0]}`

For Zynq bring-up, connect these outputs to LEDs, ILA, or a small AXI-readable register block.

## UART SoC download flow

`rtl/soc_top.v` now uses the Huoyue 50 MHz PL clock to generate a real 100 MHz CPU clock with an MMCM. For UART download, hold `uart_debug_key_n` low so the CPU stays in reset while IMEM/DMEM are written.

The `soc_top` default IMEM image is intentionally empty for manual Vivado projects. This avoids GUI synthesis warnings from repository-relative `$readmemh` paths and matches the UART download flow, where IMEM and DMEM are loaded after bitstream configuration.

```powershell
powershell -ExecutionPolicy Bypass -File scripts\prepare_coremark_fpga.ps1 -CpuHz 100000000
powershell -ExecutionPolicy Bypass -File scripts\run_vivado_impl.ps1 -Top soc_top -Constraint huoyue_uart -OutDir build/vivado_impl_soc_top_huoyue_100m_mmcm_reset_start -PlaceDirective AltSpreadLogic_high -PhysOptDirective AggressiveExplore -RouteDirective Explore -PostRoutePhysOptDirective AggressiveExplore
powershell -ExecutionPolicy Bypass -File scripts\send_uart_image.ps1 -PortName COMx -BaudRate 115200 -DMemWordBytes 8
```

The default send script downloads `coremark_o3.*`, writes IMEM and DMEM, and does not send START. This prevents CoreMark from finishing before the terminal is open. To run another optimization level, pass explicit image paths, for example `-IMemHex build/coremark/fpga/coremark_o2.imem.hex -DMemHex build/coremark/fpga/coremark_o2.dmem.hex`. After the image is sent:

1. Open the serial terminal at 115200 baud.
2. Release `uart_debug_key_n`.
3. Press/release `sys_rst_n`.

The loaded image then starts after reset and prints the normal CoreMark log plus a compact board summary:

```text
YL3 CoreMark summary
CPU_HZ=100000000
CPU_MHZ=100.000
ITERATIONS=...
CYCLES=...
COREMARK_PER_SEC=...
COREMARK_PER_MHZ=...
RESULT=PASS
```

For the old immediate-run behavior, pass `-StartAfterDownload` to `scripts/send_uart_image.ps1` and do not hold the UART download key low.

The UART packet protocol remains 32-bit-word based for compatibility with the existing loader. With RV64 images, `coremark_o*.dmem.hex` contains 64-bit little-endian DMEM rows; `scripts/send_uart_image.ps1 -DMemWordBytes 8` splits each row into low-32 then high-32 UART chunks. The FPGA-side DMEM loader merges those chunks by byte address into the selected 64-bit memory word. Use `-DMemWordBytes 4` only for legacy RV32 DMEM hex files.

## Clock frequency

CoreMark timing uses `CPU_HZ`. The current `soc_top` board bitstream runs the CPU domain at 100 MHz through the MMCM. If you change the clock later, regenerate images with the actual clock:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\prepare_coremark_fpga.ps1 -CpuHz 100000000
```

For official-style 10 second validation at 100 MHz, the prepared `coremark_o1`, `coremark_o2`, and `coremark_o3` images use `ITERATIONS=2200`.

## Load-use stall setting

The current performance RTL uses combinational DMEM read and defaults `ENABLE_LOAD_USE_STALL=0`. If DMEM is later converted to true synchronous BRAM read, set `ENABLE_LOAD_USE_STALL=1` or redesign the load-data timing path.

## RV64 timing note

The `soc_top` board default disables multiply early forwarding with `ENABLE_MUL_EARLY_FORWARD=0` and multiply complete forwarding with `ENABLE_MUL_COMPLETE_FORWARD=0`. This keeps the RV64M multiplier result out of the same-cycle EX operand forwarding paths that have shown up as the worst 100 MHz routed timing paths. Generic `cpu_top` simulations can still enable these forwarding paths explicitly when measuring performance tradeoffs.
