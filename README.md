# YunyuanLegend 3.0 RISC-V CPU

This repository contains a compact RV32IM five-stage pipelined CPU project targeting simulation, CoreMark performance testing, and Xilinx Zynq-7020 FPGA bring-up.

The current working direction prioritizes performance first. Area is still tracked, but FPGA resource usage is treated as a secondary constraint when it conflicts with CoreMark throughput or timing closure.

## Project Status

- ISA target: RV32IM, bare-metal execution
- Main FPGA target: Xilinx Zynq-7020, Huoyue board constraints included
- Main board top: `rtl/soc_top.v`
- Performance top: `rtl/fpga_coremark_top.v`
- Current software flow: RISC-V bare-metal programs loaded as IMEM/DMEM hex files
- External benchmarks/tests:
  - CoreMark is referenced as a Git submodule
  - riscv-tests is referenced as a Git submodule

Large generated outputs are intentionally not tracked. Vivado builds, ModelSim work directories, bitstreams, checkpoints, logs, waves, and the local RISC-V toolchain are excluded by `.gitignore`.

## Repository Layout

```text
constraints/   XDC and floorplanning constraints
coremark/      EEMBC CoreMark upstream submodule
docs/          Bring-up notes and design plans
riscv-tests/   Official RISC-V tests upstream submodule
rtl/           CPU, memory, UART, SoC, and FPGA top RTL
scripts/       Build, simulation, CoreMark, Vivado, and utility scripts
sw/            Bare-metal runtime, linker script, and CoreMark port
tb/            ModelSim testbenches and test program hex files
```

## Clone

Use recursive clone so the external benchmark/test repositories are available:

```powershell
git clone --recursive https://github.com/yeyaoxin55-bit/yunyuan526.git
cd yunyuan526
```

If the repository was cloned without submodules:

```powershell
git submodule update --init --recursive
```

## Required Tools

The scripts are written for Windows PowerShell.

Recommended local tools:

- ModelSim with `vlib`, `vlog`, and `vsim` in `PATH`
- Xilinx Vivado for synthesis/implementation
- xPack RISC-V GCC, expected by default at:

```text
xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-
```

The toolchain directory is not tracked in Git. Install it locally or pass a different `-ToolPrefix` to the build scripts.

## Quick Checks

Run the project structural checks:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\check_project.ps1
```

Run the full local ModelSim regression:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_modelsim.ps1
```

Run the official RISC-V test flow through the provided script:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_riscv_suite.ps1
```

## CoreMark

Short CoreMark simulation example:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_coremark.ps1 `
  -Iterations 2 `
  -TotalDataSize 2000 `
  -MaxCycles 5000000 `
  -OptLevel -O3 `
  -ExtraCFlags "-funroll-loops" `
  -PerfStats
```

Prepare FPGA CoreMark images:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\prepare_coremark_fpga.ps1 -CpuHz 100000000
```

Generated IMEM/DMEM images are written under `build/coremark/`, which is ignored by Git.

## Vivado

Synthesize the Huoyue UART SoC top:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_vivado_synth.ps1 `
  -Top soc_top `
  -Constraint huoyue_uart `
  -OutDir build/vivado_synth_soc_top_huoyue
```

Run implementation:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_vivado_impl.ps1 `
  -Top soc_top `
  -Constraint huoyue_uart `
  -OutDir build/vivado_impl_soc_top_huoyue
```

Implementation artifacts and bitstreams are written under `build/` and are not tracked.

## Huoyue Board Notes

The Huoyue Zynq-7020 UART constraint file is:

```text
constraints/tinyriscv_huoyue_uart.xdc
```

The SoC exposes:

- `sys_clk`
- `sys_rst_n`
- `uart_debug_key_n`
- `uart_rx_pin`
- `uart_tx_pin`
- `over`
- `succ`
- `halted_ind`

See `docs/fpga_coremark_bringup.md` for the current board bring-up flow.

## Git Hygiene

Tracked content should stay focused on reproducible source files:

- RTL
- testbenches
- scripts
- constraints
- software runtime/ports
- documentation

Do not commit generated Vivado/ModelSim outputs, local toolchains, temporary logs, or private working notes.

