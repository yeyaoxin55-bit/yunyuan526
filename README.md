# YunyuanLegend 3.0 RISC-V CPU

This repository contains a compact RV32IM/RV64IM-parameterized five-stage pipelined CPU project targeting simulation, CoreMark performance testing, and Xilinx Zynq-7020 FPGA bring-up.

The current working direction prioritizes performance first. Area is still tracked, but FPGA resource usage is treated as a secondary constraint when it conflicts with CoreMark throughput or timing closure.

## Project Status

- ISA target: RV64IM by default, with RV32IM still available through explicit `XLEN=32` overrides in legacy tests and scripts
- Address map: current SoC/loader/MMIO integration keeps 32-bit addresses while CPU integer registers, ALU, CSR counters, DMEM data, and M-extension operands/results scale with `XLEN`
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
- RISC-V GCC. CoreMark scripts default to `riscv64-unknown-elf-` in `PATH`; pass `-ToolPrefix` for a local xPack or other bare-metal toolchain.

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

The ModelSim regression includes directed RV64I/RV64M tests (`tb_rv64i_basic` and `tb_rv64m_basic`) plus explicit `XLEN=32` legacy RV32IM tests.

Run the official RISC-V test flow through the provided script:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_riscv_suite.ps1
```

## CoreMark

Short CoreMark simulation example:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_coremark.ps1 `
  -XLEN 64 `
  -Iterations 2 `
  -TotalDataSize 2000 `
  -MaxCycles 5000000 `
  -OptLevel -O3 `
  -ExtraCFlags "-funroll-loops" `
  -PerfStats
```

Prepare FPGA CoreMark images:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\prepare_coremark_fpga.ps1 -XLEN 64 -CpuHz 100000000
```

Generated IMEM/DMEM images are written under `build/coremark/`, which is ignored by Git.
The UART download protocol still transfers 32-bit payload words. For default RV64 images, `scripts/send_uart_image.ps1` reads 64-bit DMEM hex rows and sends each row as low-32 then high-32 chunks, while the FPGA DMEM loader merges those chunks into the addressed 64-bit word. Pass `-DMemWordBytes 4` only when sending RV32-format DMEM images.

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

---

# YunyuanLegend 3.0 RISC-V CPU 中文说明

本仓库是一个面向仿真验证、CoreMark 性能测试和 Xilinx Zynq-7020 FPGA 上板验证的 RV32IM 五级流水线 CPU 工程。

当前优化方向以性能优先。资源占用仍会持续关注，但当资源和 CoreMark 性能、时序收敛发生冲突时，优先保证性能和关键路径优化空间。

## 项目状态

- 指令集目标：RV32IM
- 运行环境：裸机程序
- 主要 FPGA 目标：Xilinx Zynq-7020，已包含野火皓月开发板约束
- 上板 SoC 顶层：`rtl/soc_top.v`
- CoreMark 性能验证顶层：`rtl/fpga_coremark_top.v`
- 软件加载方式：将裸机程序转换为 IMEM/DMEM hex 文件后运行
- 外部测试/基准：
  - `coremark/` 使用官方 EEMBC CoreMark 仓库 submodule
  - `riscv-tests/` 使用官方 RISC-V tests 仓库 submodule

Vivado 综合实现结果、ModelSim 工作目录、bitstream、checkpoint、日志、波形文件和本地 RISC-V 工具链都不会提交到 GitHub，相关内容已由 `.gitignore` 排除。

## 目录结构

```text
constraints/   XDC 约束和 floorplan 约束
coremark/      EEMBC CoreMark 官方 submodule
docs/          上板说明、设计计划和阶段记录
riscv-tests/   官方 RISC-V tests submodule
rtl/           CPU、存储器、UART、SoC 和 FPGA 顶层 RTL
scripts/       构建、仿真、CoreMark、Vivado 和辅助脚本
sw/            裸机运行时、链接脚本和 CoreMark 移植代码
tb/            ModelSim testbench 和测试程序 hex
```

## 克隆仓库

建议使用递归克隆，自动拉取 CoreMark 和 riscv-tests：

```powershell
git clone --recursive https://github.com/yeyaoxin55-bit/yunyuan526.git
cd yunyuan526
```

如果已经普通克隆，可以再初始化 submodule：

```powershell
git submodule update --init --recursive
```

## 工具依赖

脚本默认在 Windows PowerShell 下运行。

建议安装并配置：

- ModelSim，并确保 `vlib`、`vlog`、`vsim` 可在 `PATH` 中找到
- Xilinx Vivado，用于综合、实现和生成 bitstream
- xPack RISC-V GCC，默认工具链前缀为：

```text
xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-
```

本地工具链目录不会提交到 GitHub。可以放在默认路径，也可以通过脚本参数 `-ToolPrefix` 指定其他路径。

## 基础检查

运行工程结构检查：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\check_project.ps1
```

运行完整本地 ModelSim 回归：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_modelsim.ps1
```

运行官方 RISC-V 测试脚本：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_riscv_suite.ps1
```

## CoreMark

短轮数 CoreMark 仿真示例：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_coremark.ps1 `
  -Iterations 2 `
  -TotalDataSize 2000 `
  -MaxCycles 5000000 `
  -OptLevel -O3 `
  -ExtraCFlags "-funroll-loops" `
  -PerfStats
```

生成 FPGA 上板用 CoreMark 镜像：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\prepare_coremark_fpga.ps1 -CpuHz 100000000
```

生成的 IMEM/DMEM hex 文件位于 `build/coremark/` 下，该目录不会被 Git 跟踪。

## Vivado

综合皓月开发板 UART SoC 顶层：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_vivado_synth.ps1 `
  -Top soc_top `
  -Constraint huoyue_uart `
  -OutDir build/vivado_synth_soc_top_huoyue
```

运行实现：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_vivado_impl.ps1 `
  -Top soc_top `
  -Constraint huoyue_uart `
  -OutDir build/vivado_impl_soc_top_huoyue
```

实现结果和 bitstream 默认写入 `build/`，不会提交到 Git。

## 皓月开发板说明

皓月 Zynq-7020 UART 上板约束文件：

```text
constraints/tinyriscv_huoyue_uart.xdc
```

SoC 顶层主要端口：

- `sys_clk`
- `sys_rst_n`
- `uart_debug_key_n`
- `uart_rx_pin`
- `uart_tx_pin`
- `over`
- `succ`
- `halted_ind`

当前上板流程见：

```text
docs/fpga_coremark_bringup.md
```

## Git 维护规则

仓库只跟踪可复现的源码和说明文件：

- RTL
- testbench
- 脚本
- 约束
- 裸机软件运行时和移植代码
- 文档

不要提交 Vivado/ModelSim 生成结果、本地工具链、临时日志、波形文件或私人工作记录。
