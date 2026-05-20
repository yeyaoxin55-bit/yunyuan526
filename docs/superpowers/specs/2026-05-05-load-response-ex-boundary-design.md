# Load Response EX Boundary Design

## Goal

Improve 100 MHz FPGA timing margin by adding a real RTL boundary between synchronous DMEM load responses and the ordinary EX datapath, while keeping the existing load-to-branch/JALR replay optimization available.

## Background

The current `soc_top` 100 MHz no-floorplan baseline closes timing narrowly at WNS 0.013 ns. Recent timing reports show the worst paths moving between front-end control and DMEM/EX cones. The latest `alt_spread` path is from DMEM BRAM output toward `ex_mem_alu_result`, and `cpu_core` still allows `load_resp_data` to feed the ordinary EX forwarding mux when `forward_sel == 2'd3`.

The existing registered load-to-control replay path should remain. It handles branch and JALR consumers without directly pulling load data into the PC redirect decision in the same cycle.

## Chosen Approach

Add a parameterized switch for ordinary load-response EX forwarding:

- `ENABLE_LOAD_RESP_EX_FORWARD=1`: preserve the current performance behavior. Ordinary ALU/store/load-address consumers can use `load_resp_data` after one load-use stall.
- `ENABLE_LOAD_RESP_EX_FORWARD=0`: timing-safe FPGA mode. Ordinary EX consumers take a second load-use stall and read the loaded value through a register-file/writeback boundary before entering EX.

Branch and JALR load consumers keep using the registered control replay path in both modes. M-extension consumers remain conservative because forwarding load data into multiply/divide control was already a timing risk.

## RTL Boundaries

The timing-safe mode must not use `load_resp_data` in the ordinary ALU, multiplier, divider, store-data, or `ex_mem_alu_result` path.

The only retained direct use of `load_resp_data` in timing-safe mode is the existing control replay capture register for load-to-branch/JALR. That path captures data into replay registers before branch/JALR redirect decision.

## Test Plan

Add a directed ModelSim regression that instantiates `cpu_top` with `ENABLE_LOAD_RESP_EX_FORWARD=0`, runs the existing load-use program, checks the correct result, and expects two hazard stalls instead of one.

Keep the existing `tb_load_use_one_stall` behavior for `ENABLE_LOAD_RESP_EX_FORWARD=1`.

Run after implementation:

- `scripts\check_project.ps1`
- `scripts\run_modelsim.ps1`
- `scripts\run_riscv_suite.ps1 -Suite rv32um -FastMul 0 -MulStages 1 -LoadRespExForward 0`
- `scripts\run_coremark.ps1 -Iterations 2 -TotalDataSize 2000 -MaxCycles 5000000 -FastMul 0 -MulStages 1 -LoadRespExForward 0 -PerfStats`
- `scripts\run_coremark.ps1 -Iterations 50 -TotalDataSize 2000 -MaxCycles 60000000 -FastMul 0 -MulStages 1 -LoadRespExForward 0 -PerfStats`
- `scripts\run_timing_sweep.ps1 -Top soc_top -FrequenciesMHz 100 -Strategies alt_spread ...`

## Expected Tradeoff

The timing-safe mode should reduce pressure on the DMEM-to-EX critical cone. It will likely increase CoreMark load-use stalls versus the current one-stall ordinary forwarding point. If timing margin improves but performance loss is too large, the next design should be a registered ordinary ALU/store replay path rather than re-enabling direct load-response EX forwarding.
