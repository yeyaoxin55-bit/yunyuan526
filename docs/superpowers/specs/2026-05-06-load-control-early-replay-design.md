# Load Control Early Replay Design

## Goal

Reduce CoreMark load-use/control stalls by removing the first decode-stage stall for `load -> branch` and `load -> JALR` pairs, while keeping `load_resp_data` out of the same-cycle PC/redirect combinational path.

## Background

The current fastest timing-clean board candidate uses `ENABLE_LOAD_RESP_EX_FORWARD=1`, local history enabled with `BHT=64`, `BHR=2`, and `BTB=64`. It reaches 17487089 CoreMark cycles for 50 iterations, about 2.859252 CoreMark/MHz at 100MHz, but timing margin is only WNS 0.004 ns.

The current control replay path already handles `load -> branch/JALR` without directly pulling `load_resp_data` into PC redirect. The remaining cost is the mandatory first `id_ex_load_use` stall when the load is in ID/EX and the control consumer is still in IF/ID.

## Chosen Approach

Add a parameterized early replay mode:

- `ENABLE_LOAD_CONTROL_EARLY_REPLAY=0`: default compatibility mode. Existing behavior is preserved; directed `load_branch_one_stall` and `load_jalr_one_stall` tests still expect one hazard stall.
- `ENABLE_LOAD_CONTROL_EARLY_REPLAY=1`: performance mode. A branch or JALR in IF/ID that depends on an ID/EX load is captured into a new pending replay register instead of causing the first hazard stall.

The pending replay stores PC, immediate, funct3, prediction metadata, and the non-load source operand. It also records whether rs1 and/or rs2 must be filled from the later load response. When `load_resp_data` is valid, the pending record is converted into the existing `ctrl_replay_valid` register. Redirect detection still happens from registered replay data, not directly from DMEM output.

## Safety Rules

While a load-control pending replay is active, younger instructions may proceed only if they cannot commit an unsafe side effect before the older branch/JALR resolves.

The implementation must stall younger stores, CSR instructions, M-extension instructions, branches, and jumps while a pending replay is active. Younger ALU and load instructions may proceed because their register writes or load responses are killed by the existing replay flush path if the older control instruction redirects.

The pending replay is cleared on reset and any older flush. It must not overwrite an existing pending or active control replay.

## Interfaces

Expose `ENABLE_LOAD_CONTROL_EARLY_REPLAY` through:

- `rtl/cpu_core.v`
- `rtl/cpu_top.v`
- `rtl/fpga_coremark_top.v`
- `rtl/soc_top.v`
- `tb/tb_external_program.v`
- CoreMark and RISC-V suite scripts

The FPGA-oriented defaults should remain conservative at `0`. Performance candidates can enable the mode through simulation and Vivado generic overrides.

## Test Plan

Add RED tests before implementation:

- `tb_load_branch_zero_stall`: run `tb/programs/load_branch_strict.hex` with `ENABLE_LOAD_CONTROL_EARLY_REPLAY=1`; expect correct result and zero `hazard_stall` cycles.
- `tb_load_jalr_zero_stall`: run `tb/programs/load_jalr_strict.hex` with `ENABLE_LOAD_CONTROL_EARLY_REPLAY=1`; expect correct result and zero `hazard_stall` cycles.
- `tb_load_branch_same_rd_replay`: guard against consuming an older load response when the pending replay load has the same `rd`.
- `tb_load_branch_wrong_path_wb`: guard against a replay redirect allowing a wrong-path MEM/WB register write to commit.

Keep existing compatibility tests:

- `tb_load_branch_one_stall`
- `tb_load_jalr_one_stall`
- `tb_load_use_one_stall`
- `tb_load_use_timing_safe`

After GREEN:

- `scripts\check_project.ps1`
- `scripts\run_modelsim.ps1`
- full `rv32um`
- applicable `rv32ui` excluding unsupported `fence_i`
- CoreMark 2/50 with the current best performance parameters plus `LoadControlEarlyReplay=1`
- Huoyue 100MHz Vivado implementation and QoR gate

Current ModelSim result, 2026-05-06:

- Full RTL regression passed after adding the strict and bug-regression tests.
- Full `rv32um` passed with `LoadControlEarlyReplay=1`.
- Applicable `rv32ui` excluding unsupported `fence_i` passed with `LoadControlEarlyReplay=1`.
- CoreMark 50 improved from 17612289 cycles with the feature disabled to 17414991 cycles with the feature enabled on the same RTL point.
- The enabled result is faster than the previous timing-clean board candidate at 17487089 cycles, but still below the 3.0 CoreMark/MHz target. Vivado timing remains pending for this candidate.

## Expected Tradeoff

This should reduce load-use stalls for branch/JALR consumers without adding a direct DMEM-to-PC timing path. It may still be timing-fragile because the design already has only 0.004 ns margin. If post-route timing fails, keep the feature as an optional simulation-proven parameter and do not replace the current board bitstream.
