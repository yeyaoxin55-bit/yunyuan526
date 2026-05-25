# 文档审阅计划

## Goal
审阅当前目录下的项目文档，发现可改进处则直接完善；若无需修改，则确认可进入后续工作。

## Phases
- [x] Phase 1: 建立审阅记录并盘点文档
- [x] Phase 2: 阅读设计方案，记录问题和改进点
- [x] Phase 3: 修订文档中明确的问题
- [x] Phase 4: 复核修改并汇总结果
- [x] Phase 5: 按用户新要求改为Zynq-7020性能优先方案
- [x] Phase 6: 创建RTL工程骨架与首轮结构验证
- [x] Phase 7: 接入ModelSim并验证RV32I烟测程序
- [x] Phase 8: 增加RV32I冒险、分支和访存宽度回归并修复基础流水线问题
- [x] Phase 9: 增加RV32I ALU、jump和完整分支条件回归
- [x] Phase 10: 增加LUI/AUIPC/JALR与CSR计数器回归
- [x] Phase 11: 增加RV32M乘除法回归并实现组合功能路径
- [x] Phase 12: 接入真正按位迭代除法器，并用流水线暂停控制通过 ModelSim 全量回归
- [x] Phase 13: 接入两级流水乘法器，覆盖 MUL/MULH/MULHSU/MULHU 单元与程序级回归
- [x] Phase 14: 将IMEM改为同步BRAM语义，并接入prefetch/skid缓冲通过全量回归
- [x] Phase 15: 接入BTB+2-bit分支预测器，覆盖单元与CPU循环预测回归
- [x] Phase 16: 建立官方测试/CoreMark外部hex加载链路与IMEM/DMEM标准地址映射

## Errors Encountered
| Error | Attempt | Resolution |
|-------|---------|------------|
| `git diff`/`git status`失败：当前目录不是Git仓库 | 尝试查看改动摘要 | 改用文件内容扫描与人工复核完成验证 |
| 首次手动 floorplan implementation 命令误用 `-Constraint huoyue_uart` | 得到 WNS 4.040 ns，但这是 50 MHz 约束结果 | 改用 `run_timing_sweep.ps1 -FrequenciesMHz 100` 生成 10 ns 临时 XDC 后重跑，50 MHz 结果不作为 100 MHz 判断 |

## Current Verification Update
- [x] Phase 17: Run applicable official rv32ui/rv32um tests in ModelSim and fix test-environment/DMEM issues
- [ ] Phase 18: Add CoreMark port files, build CoreMark ELF/hex, and run it through the external ModelSim harness

## Phase 29 soc_top Timing/Performance Optimization - In Progress
- Goal: establish repeatable post-route timing baselines, make `soc_top` DMEM infer block RAM instead of distributed RAM, and add a frequency/strategy scan script for 50/75/100 MHz-style experiments.
- Initial finding: `soc_top` synthesis at the Huoyue 50 MHz constraint has wide WNS, but `u_dmem/gen_bram_friendly.mem_reg` maps to distributed RAM (`RAMD64E 5696`) instead of BRAM. This is the first optimization target before deeper pipeline changes.
- Planned verification: QoR report check, full ModelSim regression, CoreMark build, `soc_top` synthesis, and at least one `soc_top` implementation run if runtime permits.
- Current result: DMEM BRAM inference is fixed for active UART-loader `soc_top` by merging loader and CPU writes into one byte-enable write port. `soc_top` 50 MHz default post-route implementation passes with WNS 4.780 ns, 0 setup/hold failing endpoints, LUT 6219, FF 7859, RAMB36 24, DSP48 12, and bitstream generated under `build/timing_sweep_soc_top_smoke3/soc_top_50MHz_default`.
- Added repeatable QoR/timing tooling: `scripts/check_vivado_qor.ps1`, `scripts/run_timing_sweep.ps1`, and `scripts/report_ram_from_checkpoint.tcl`.
- User decision: only run/analyze 100 MHz now; skip 50/75 MHz sweeps to save time.
- 100 MHz `soc_top` default implementation does not close timing: WNS -0.366 ns, TNS -23.243 ns, 153 setup failing endpoints.
- 100 MHz `soc_top` Explore/AggressiveExplore implementation closes timing narrowly: WNS 0.001 ns, TNS 0.000 ns, 0 setup/hold failing endpoints, LUT 6348, FF 7865, RAMB36 24, DSP48 12. Bitstream: `build/timing_sweep_soc_top_100m/soc_top_100MHz_explore/soc_top.bit`.
- QoR remains correct at 100 MHz: DMEM and IMEM use RAMB36E1; remaining RAMD64E=64 is the branch predictor PHT, not DMEM.
- Rejected a replay-only `redirect_from_replay` timing experiment. It improved a temporary 100 MHz explore run to WNS 0.007 ns, but CoreMark external simulation timed out, so the RTL change was reverted.
- Fixed CoreMark harness split after the UART-output addition: `run_coremark.ps1`/ModelSim builds now leave UART output disabled by default, while `prepare_coremark_fpga.ps1` builds board images with `-DCOREMARK_UART_OUTPUT=1`.
- Current next step: keep the current RTL point for board bring-up and avoid speculative small PC/predictor rewrites. Meaningful timing improvement likely needs a deliberate front-end register boundary, not another local mux/control expression tweak.
- Continued 100 MHz-only optimization after user deferred board validation. A refreshed `soc_top` Explore run still passes with WNS 0.001 ns and the same route-dominated replay/redirect path.
- Rejected another small replay-tag rewrite: simulation and CoreMark 50 were unchanged, but 100 MHz Explore implementation failed with WNS -0.385 ns. RTL was restored to the verified baseline.
- Ran two additional 100 MHz implementation strategy variants on the verified RTL baseline. `extra_net_delay` passed at WNS 0.000 ns, WHS 0.029 ns. `alt_spread` is the best current result, passing at WNS 0.013 ns, WHS 0.013 ns, LUT 6369, FF 7865, RAMB36 24, DSP48 12.
- QoR gate passed on `build/vivado_impl_soc_top_100m_alt_spread`: RAMD64E=64, BlockRAM=24, and DMEM is reported as RAMB36E1.
- Current recommended baseline for 100 MHz board bring-up is `build/vivado_impl_soc_top_100m_alt_spread/soc_top.bit`. The margin is still narrow, so further timing work should prioritize implementation/floorplanning or a deliberate register-boundary redesign.
- Added optional floorplan hook support to the implementation flow: `scripts/run_vivado_impl.ps1 -FloorplanTcl`, `scripts/vivado_impl.tcl -floorplan_tcl`, timing-sweep forwarding, `scripts/check_floorplan_hook.ps1`, and `constraints/floorplan_soc_top_light.tcl`.
- Verified the floorplan hook with RED/GREEN script checks and project structure check.
- Ran the correct 100 MHz light floorplan experiment using generated 10 ns XDC plus `alt_spread`. It passes timing and QoR, but WNS is 0.000 ns, worse than the existing no-floorplan `alt_spread` WNS 0.013 ns. Keep the hook for future targeted floorplanning, but do not change the current board baseline.

## Phase 18 CoreMark Functional Bring-up - Completed
- Implemented baremetal CoreMark port and build/run scripts.
- Fixed linker memory placement so data loads can read .rodata/.srodata from DMEM.
- Verified CoreMark ModelSim functional runs for TOTAL_DATA_SIZE=1200 and 2000 with ITERATIONS=1.
- Verified a post-change official riscv-tests smoke subset for RV32UI and RV32UM.
- Next recommended phase: add a measurable performance report path, then run longer CoreMark on target hardware or a longer simulation when practical.

## Phase 19 CoreMark Profile Harness - Completed
- Added a repeatable CoreMark profiling script with CSV output.
- Added RESULT_ADDR support to the external ModelSim harness so performance comparisons use workload-measured cycles.
- Verified the profile flow and full RTL ModelSim regression.
- Next recommended phase: use the new profile baseline to optimize CoreMark hot paths, starting with DIV latency impact, load-use stalls, and branch/prefetch behavior.

## Phase 20 CoreMark Perf Stats Harness - Completed
- Added optional performance event counters to the external ModelSim harness.
- Added parsing and CSV columns for CoreMark CPI and bottleneck counters.
- Next recommended phase: reduce branch/jump flush overhead first, then re-run the same profile CSV to quantify improvement.

## Phase 21 CoreMark Multi-Iteration Sweep - Completed
- Profiled TOTAL_DATA_SIZE=2000 at ITERATIONS=1,2,5,10,20,50.
- Confirmed cycles-per-iteration stability and long-run CPI/event rates.
- Next recommended phase remains branch/jump front-end optimization, using the 50-iteration CSV as the comparison baseline.

## Phase 22 Flush Split and JAL Early Redirect - Completed
- Added split perf counters for branch/jump/JAL/JALR flush behavior.
- Implemented ID-stage early redirect for JAL.
- Verified ISA behavior and CoreMark performance improvement.
- Next recommended phase: choose between JALR target optimization and load-use stall reduction using the updated post-JAL baseline.

## Phase 23 JALR Hotspot Analysis - Completed
- Added dynamic JALR PC and PC/target profiling.
- Mapped top JALR hotspots back to CoreMark disassembly.
- Simulated simple last-target prediction and found limited hit rate.
- Next recommended phase: analyze and reduce load-use stalls before investing in JALR prediction hardware.

## Phase 24 Load-Use Stall Reduction - Completed
- Profiled load-use hotspots and mapped them to CoreMark disassembly.
- Added configurable load-use stall control and disabled it by default for the current performance-oriented async DMEM path.
- Verified functional regressions and measured 50-iteration CoreMark improvement.
- Next recommended phase: profile remaining branch-mispredict and JALR/exec_wait costs on the new baseline.

## Phase 25 FPGA CoreMark Bring-up Prep - Completed
- Prepared configurable CoreMark FPGA images for smoke, 10ms-class, and 10s-class runs.
- Added a simple FPGA wrapper with pass/fail/done/cycle outputs.
- Documented board bring-up flow and verified RTL compile/simulation paths.
- Next recommended phase: map fpga_coremark_top ports to the actual board XDC or integrate pass/fail/cycle into a PS-readable AXI-Lite register block.

## Phase 26 Fast Multiply CoreMark Optimization - Completed
- Added mul/div wait split stats to prove the remaining exec_wait bottleneck.
- Made multiplier latency configurable and added FAST_MUL performance mode.
- Verified official rv32ui applicable tests, full rv32um tests, full ModelSim RTL regression, and CoreMark 50-iteration performance.
- Next recommended phase: run Vivado timing for fpga_coremark_top with FAST_MUL=1. If timing fails, compare FAST_MUL=0/MUL_STAGES=1 against clock target; if timing passes, continue with branch-mispredict/JALR optimization.

## Phase 27 Valid Pipeline and Sync DMEM - Completed
- Added pipeline valid bits and used them to gate writeback, memory side effects, branch predictor updates, branch/jump flushes, and hazard decisions.
- Fixed CSR minstret to count real retirement from MEM/WB valid state.
- Converted DMEM to synchronous-read behavior and added the required MEM load wait handling.
- Updated CoreMark perf stats to track mem_wait_stalls.
- Verified with full ModelSim RTL regression, rv32um full suite, remaining applicable rv32ui tests, CoreMark smoke, CoreMark 50-iteration profile, and project structure check.
- Next recommended phase: start Vivado timing again on fpga_coremark_top with the sync-DMEM/FAST_MUL configuration, then decide whether to keep FAST_MUL=1 or fall back to FAST_MUL=0/MUL_STAGES=1 for Zynq-7020 timing closure.

## Phase 28 Vivado Synthesis Bring-up - In Progress
- Fixed the fpga_coremark_top synthesis script for Vivado 2022.2 report command compatibility.
- Split DMEM behavior so default simulation keeps misaligned access support while fpga_coremark_top uses a BRAM-friendly single-word synchronous path.
- Confirmed fpga_coremark_top 100MHz synthesis completes and maps IMEM/DMEM into BRAM.
- Current 100MHz synthesis timing fails with WNS -7.088 ns under FAST_MUL=1.
- Added/selects a FAST_MUL=0 FPGA top configuration and reran 100MHz synthesis.
- FAST_MUL=0 / MUL_STAGES=1 still fails 100MHz with WNS -6.545 ns because the first multiplier stage still contains the full combinational multiply.
- Pipelined the multiplier operand/product path and confirmed DSP AREG/BREG/MREG use; 100MHz WNS improved to -4.718 ns.
- Cut direct EX/MEM load-data forwarding for the synchronous-DMEM configuration; full ModelSim, CoreMark smoke, rv32um, and Vivado synthesis completed, with WNS improved to -2.813 ns.
- Added a local BHR/PHT branch predictor and mapped its PHT to distributed RAM; CoreMark 50-iteration cycles improved to 27932114 and branch mispredict flushes dropped to 229336.
- Local BHR synthesis completes but still fails 100MHz with WNS -2.835 ns, so it is a performance improvement rather than a timing fix.
- Registered the EX redirect and added a regression for the one-cycle delayed flush behavior.
- Fixed the delayed-redirect wrong-path hazard by blocking new redirect detection while redirect_valid is pending.
- Verified full ModelSim RTL regression, rv32um full suite, CoreMark 2-iteration smoke, CoreMark 50-iteration profile, and project structure check after the redirect change.
- CoreMark 50-iteration measured cycles are now 28532090, trading performance for timing improvement.
- 100MHz synthesis improved to WNS -1.383 ns, TNS -47.799 ns, failing endpoints 47. The direct pc_reg endpoint is gone; the remaining worst path is id_ex_rs2_reg -> redirect_pc_q_reg CE.
- Split redirect target/fallthrough capture from redirect-valid/type capture, verified rv32ui/beq, full ModelSim, rv32um, CoreMark 2/50, project structure, and Vivado synthesis.
- CoreMark 50 remains 28532090 measured cycles, CPI 1.545151.
- 100MHz synthesis improved to WNS -0.576 ns, TNS -3.502 ns, failing endpoints 15. Resources are LUT 5058, LUTRAM 128, FF 7289, BRAM36 24, DSP48 12.
- Rewrote branch_mispredict_raw into an equivalent taken/not-taken boolean form, removing branch redirect control from the worst setup path without changing CoreMark 50 performance.
- 100MHz synthesis improved to WNS -0.457 ns, TNS -2.358 ns, failing endpoints 13. Resources are LUT 5002, LUTRAM 128, FF 7289, BRAM36 24, DSP48 12.
- Added an explicit multiplier product/output pipeline stage, with a regression that first failed on the old early-valid behavior and passed after the change.
- Added FAST_MUL/MUL_STAGES generics to the external CoreMark simulation path so the default fast path and FPGA-like slow path can be measured separately.
- fpga_coremark_top 100MHz out-of-context synthesis now meets timing: WNS 0.091 ns, TNS 0.000 ns, failing endpoints 0. Resources are LUT 5008, LUTRAM 128, FF 7365, BRAM36 24, DSP48 12.
- FPGA-like FAST_MUL=0 CoreMark 50 measured 30416890 cycles, CPI 1.647223, with 1885351 mul_wait_stalls.
- Added Vivado implementation/place-and-route scripts and ran fpga_coremark_top at 100MHz.
- First post-route implementation failed timing with WNS -0.263 ns because the branch predictor PHT write-enable path became route-dominated.
- Registered the branch predictor update path and adjusted the predictor unit test for one-cycle delayed training.
- Post-route implementation now passes 100MHz: WNS 0.007 ns, TNS 0.000 ns, failing endpoints 0, WHS 0.054 ns. Resources are LUT 4982, LUTRAM 128, FF 7452, BRAM36 24, DSP48 12.
- Verified project structure, rv32ui/beq, full ModelSim RTL regression, rv32um full suite, FPGA-like CoreMark 2, FPGA-like CoreMark 50, and Vivado implementation.
- Added a mem-pipeline regression and verified it failed on the old global-mem_wait RTL before the optimization.
- Implemented synchronous load-response pipelining with a second regfile write port and 2-bit CSR retire_count support.
- Rejected the aggressive dmem_rdata-to-EX forwarding version because it improved CoreMark but failed post-route timing.
- Kept the timing-safe version: independent loads no longer create global mem_wait stalls, while true load consumers wait through an EX/MEM load-use interlock.
- Reduced CPU BHR_WIDTH from 4 to 3 to recover post-route timing margin after the load-response datapath change.
- Final FPGA-like CoreMark 50 is 28843256 cycles, CPI 1.561506, mem_wait_stalls 0, load_use_stalls 3156654.
- Final post-route implementation passes 100MHz: WNS 0.000 ns, TNS 0.000 ns, failing endpoints 0, WHS 0.110 ns. Resources are LUT 5577, LUTRAM 64, FF 7291, BRAM36 24, DSP48 12.
- Verified project structure, rv32ui/beq, full ModelSim RTL regression, rv32um full suite, FPGA-like CoreMark 2, FPGA-like CoreMark 50, and Vivado implementation.
- Added optional Vivado implementation directives to the Tcl/PowerShell flow and fixed the wrapper so Vivado stderr notices do not cause false NativeCommandError failures.
- Reran 100MHz implementation with Place=Explore, PhysOpt=AggressiveExplore, Route=Explore, and PostRoutePhysOpt=AggressiveExplore.
- Directed post-route implementation improves timing margin to WNS 0.090 ns, TNS 0.000 ns, failing endpoints 0, WHS 0.087 ns. Resources remain effectively unchanged at LUT 5579, LUTRAM 64, FF 7291, BRAM36 24, DSP48 12.
- Removed one avoidable multiplier output cycle by exposing the last valid/result pipeline stage directly. This preserves the DSP/product pipeline but lets the CPU observe the result one cycle earlier.
- Added FastMul/MulStages parameters to the RISC-V test scripts, then verified rv32um with FAST_MUL=0 / MUL_STAGES=1.
- CoreMark 50 improves to 28372056 cycles, CPI 1.535996, with mul_wait_stalls reduced to 1414016.
- Directed post-route implementation still passes 100MHz after this RTL change: WNS 0.020 ns, TNS 0.000 ns, failing endpoints 0, WHS 0.040 ns. Resources are LUT 5589, LUTRAM 64, FF 7258, BRAM36 24, DSP48 12.
- Added tb_load_use_one_stall and verified the old conservative load-use interlock failed with two stalls.
- Added selective load-response forwarding: ordinary ALU/store consumers can use the registered load response after one stall, while branch/jump/M-extension consumers keep the conservative second stall.
- Tested and rejected unrestricted load-response forwarding because it improved CoreMark more but failed implementation timing.
- Final selective-forwarding CoreMark 50 is 27729615 cycles, CPI 1.501216, with load_use_stalls reduced to 2513677.
- Directed post-route implementation still passes 100MHz: WNS 0.006 ns, TNS 0.000 ns, failing endpoints 0, WHS 0.043 ns. Resources are LUT 5740, LUTRAM 64, FF 7253, BRAM36 24, DSP48 12.
- Verification passed: full ModelSim RTL regression, FPGA-like rv32um, FPGA-like CoreMark 2/50, project structure check, and 100MHz directed Vivado implementation.
- Next recommended phase: stop adding direct EX datapath optimizations until there is more timing margin. The current best next step is front-end/PC-select timing cleanup or board-specific bitstream integration.
- Tried two front-end timing cleanup experiments and rejected both: disabling LOCAL_HISTORY worsened CoreMark and did not improve directed implementation, while raw-BTB-target predict_target_o preserved simulation behavior but failed post-route timing at WNS -0.271 ns.
- Next recommended phase: keep the current selective-forwarding RTL as the best verified point, then investigate DMEM/load-response/EX critical cones or board integration instead of more small predictor mux rewrites.
- Fixed the CoreMark load-use hotspot attribution in tb_external_program.v and reran current FPGA-like CoreMark 50.
- Current load-use hotspot categories show branch and jump consumers dominate the remaining stalls: branch 1609869, jump 460808, load 214954, simple ALU 206047, mul 16211, store 5788 across the top 32 pairs.
- Next recommended phase: either accept the current timing-clean selective-forwarding RTL for FPGA bring-up, or design a registered load-to-branch/jump handling path. Expanding direct load_resp forwarding to branch/jump is not recommended because it already failed post-route timing in the unrestricted experiment.
- Added CoreMark compiler option controls to the build/run/FPGA image scripts and benchmarked -O2/-O3 variants.
- Made -O3 -funroll-loops the default CoreMark build because it improves the 50-iteration FPGA-like run from 27729615 to 19228682 cycles without RTL changes.
- Regenerated FPGA CoreMark images with the optimized flags; the largest default image footprint remains within the current 64KB IMEM / 32KB DMEM configuration at 25576 bytes IMEM and 3948 bytes DMEM.
- Verified the optimized default with CoreMark 2/50, full ModelSim regression, project structure check, FPGA image preparation, and directed 100MHz post-route Vivado implementation.
- Next recommended phase: keep this optimized CoreMark flow for board measurement, while treating the current RTL as timing-fragile because directed post-route margin is still only WNS 0.006 ns.
- Added Huoyue UART SoC bring-up path: `soc_top`, `uart_tx`, UART hello firmware, board XDC, ModelSim UART/SoC tests, and Vivado `huoyue_uart` constraint support.
- Verified the SoC bring-up path with project structure check, full ModelSim RTL regression, and synthesis-only `soc_top` run at 50MHz. Synthesis WNS is 8.442 ns with 0 setup/hold failures.
- Next recommended phase: generate a bitstream for `soc_top`, program the Huoyue board, and confirm the USB-UART prints `HI` while `succ/over` LEDs assert.
- Reran directed 100MHz implementation for the current registered load-to-control replay CoreMark RTL. Post-route timing passes with WNS 0.015 ns, TNS 0.000 ns, WHS 0.011 ns, LUT 5867, FF 7427, BRAM36 24, DSP48 12.
- The current worst post-route setup path is front-end PC/predictor selection (`pc_reg` to `pc_reg`), dominated by routing, not the synthesis-only DMEM load-response path.
- Next recommended phase: keep the current RTL and improve timing margin first, preferably through implementation strategy/placement exploration or a deliberate front-end register boundary design. Do not implement registered load-response-to-EX replay unless a later post-route run fails.

## Phase 30 Load Response EX Boundary - Completed
- Implemented the deliberate RTL load-response-to-EX register boundary as a parameterized timing-safe mode. `ENABLE_LOAD_RESP_EX_FORWARD=0` is now the default for FPGA-oriented `fpga_coremark_top` and `soc_top`, while generic `cpu_top` keeps default performance mode at 1.
- Verification passed for the new timing-safe boundary: `check_project`, full ModelSim, rv32um with `LoadRespExForward=0`, applicable rv32ui excluding unsupported `fence_i`, CoreMark 2/50 with `FastMul=0 MulStages=1 LoadRespExForward=0`, QoR gate, and `soc_top` 100 MHz `alt_spread` implementation.
- Current timing-safe CoreMark 50 result is 18995096 measured cycles, CPI 1.319969. This costs about 3.06% versus the previous 18431390-cycle performance point.
- Current best 100 MHz board candidate is now `build/timing_sweep_soc_top_100m_loadresp_boundary/soc_top_100MHz_alt_spread/soc_top.bit`: WNS 0.022 ns, TNS 0.000 ns, WHS 0.019 ns, LUT 6271, FF 7858, RAMB36 24, DSP48 12. QoR remains correct with `RAMD64E=64 BlockRAM=24`.
- The previous DMEM BRAM to `ex_mem_alu_result` worst path is no longer the top path. The new worst path is branch-predictor update control from `mem_wb_rd_reg[2]` to `update_taken_q_reg_rep__5`, so the next optimization should target predictor/update control or a registered ordinary ALU/store replay path if we want to recover the 3.06% performance loss without restoring the DMEM-to-EX critical cone.

## Phase 31 Branch Predictor Resource Profile - Completed
- Goal: satisfy the new hard constraints of `LUT < 5000` and CoreMark/MHz `> 2.5` by trimming low-return predictor resources first.
- Implemented predictor sizing parameters and made FPGA-oriented tops default to local-history disabled, `BHT=64`, `BTB=32`.
- Verified the resource profile with static checks, full RTL regression, applicable official RISC-V tests, CoreMark 2/50, QoR gate, and a 100 MHz `soc_top` implementation.
- Result: `soc_top` 100 MHz `alt_spread` passes timing at WNS 0.203 ns with 4740 LUT, and CoreMark 50 measures 19341937 cycles, about 2.585 CoreMark/MHz at 100 MHz.
- Next recommended phase: keep this trimmed predictor as the board baseline. Only consider further LUT cuts after board integration adds enough logic to threaten the 5000-LUT budget again.

## Phase 32 BHT/BTB Parameter Scan - Completed
- Goal: test whether nearby BHT/BTB sizes can improve performance or resource margin without violating `LUT < 5000` and CoreMark/MHz `> 2.5`.
- Added Vivado generic override support so timing sweeps can test parameter combinations without editing RTL defaults.
- CoreMark tested `64/16`, `64/32`, `64/64`, and `128/32` with local history disabled.
- Vivado implementation tested the two useful endpoints: `64/16` as a resource-saving fallback and `64/64` as a performance candidate.
- Result: `64/64` is faster but rejected because it uses 5313 LUT. `64/16` is valid and small at 4327 LUT but slower. Keep `64/32` as default; keep `64/16` as fallback for future board-integration LUT pressure.

## Phase 33 CoreMark Compiler Flag Scan - Completed
- Goal: check whether extra GCC flags can improve CoreMark without touching RTL or increasing FPGA resource usage.
- Sequentially tested `-Ofast`, `-frename-registers`, `-fweb`, and 16-byte alignment variants against the accepted `-O3 -funroll-loops` default.
- Result: no candidate improved over the default 773627-cycle 2-iteration result. The alignment variant was worse at 835912 cycles and larger code size.
- Decision: keep `-O3 -funroll-loops` as the CoreMark default and move the next optimization back to hardware/clocking/board validation.

## Phase 34 soc_top Real 100MHz Board Clock - Completed
- Goal: make the Huoyue board build run the CPU domain at a real 100MHz from the 50MHz PL input instead of only constraining `sys_clk` as if it were 100MHz.
- Added `rtl/clk_gen_50m_to_100m.v`, using `MMCME2_BASE` plus BUFG in synthesis and a ModelSim bypass in RTL simulation.
- Updated `soc_top` so CPU/IMEM/DMEM/UART use the generated 100MHz clock, reset is held until MMCM lock, and default UART divisor is 868 for 100MHz/115200 baud.
- Verification passed: clocking static check, project structure check, full ModelSim regression, real board-XDC Vivado implementation, and QoR gate.
- Result: Vivado reports `sys_clk=50MHz` and generated `clkout0_mmcm=100MHz`; the first MMCM implementation passed with WNS 0.236 ns. This bitstream was superseded by Phase 35 after the reset-start behavior fix.

## Phase 35 UART Download Reset-Start Flow - Completed
- Goal: prevent downloaded programs from running and finishing before the user opens the serial terminal.
- Added a reset-start gate in `soc_top`: `uart_debug_key_n=0` holds the CPU stopped and clears `run_armed_q`; START packets are sampled by rising edge only outside download mode; releasing the key alone does not start execution.
- Changed `scripts/send_uart_image.ps1` so the default behavior downloads IMEM/DMEM without START. `-StartAfterDownload` is available for the old immediate-run behavior.
- Added `tb/tb_soc_uart_reset_start.v` and `scripts/check_soc_reset_start_flow.ps1` to guard this behavior.
- Verification passed: RED/GREEN reset-start regression, project/clock/start static checks, full ModelSim regression, real board-XDC Vivado implementation, and QoR gate.
- Result: final board bitstream is `build/vivado_impl_soc_top_huoyue_100m_mmcm_reset_start/soc_top.bit`; post-route WNS 0.018 ns, LUT 4750, FF 5212, BRAM36 24, DSP48 12, BUFG 2, MMCME2_ADV 1.

## Phase 36 Nonblocking Slow Multiplier - Completed

## Phase 42 ID Early-Read Timing Rescue - In Progress
- Current exact latest-RTL CoreMark 50 baseline: `17198825` cycles, about `2.907 CoreMark/MHz` at 100MHz.
- Rejected DMEM narrow-index/read-enable experiment because synthesis worsened to WNS `-2.590 ns`.
- Kept SoC MMIO hold-only cleanup; synthesis improved to WNS `-2.196 ns` with LUT `6532`, FF `7714`, BRAM36 `24`, DSP48 `12`.
- Current blocker remains the early-read request/address path into DMEM BRAM `ENARDEN`.
- Next planned work: add a deliberate registered early-read request/address boundary or otherwise split the `id_load_early_addr/id_load_early_read -> dmem_sel/mem_read -> RAMB36 ENARDEN` cone, then re-run targeted ModelSim, CoreMark smoke, and Vivado synthesis.
- Goal: improve CoreMark performance without using the timing-failing single-cycle FAST_MUL path, accepting a moderate LUT increase.
- Implemented a single in-flight nonblocking slow multiplier issue path. Independent instructions can continue while a slow multiply is pending; true dependencies, WAW hazards, CSR ordering, and multiplier structural hazards are held by the hazard unit.
- Added a regression `tb_mul_nonblocking` with `tb/programs/mul_nonblocking.hex`. The test requires an independent ALU/store chain after MUL to finish without `mul_wait`.
- Removed the temporary third regfile write port and shared the existing load-response writeback port with multiplier response. If load response and multiplier response collide, the multiplier result is held one cycle in `mul_resp_*`.
- Verification passed: full ModelSim RTL regression, full `rv32um`, applicable `rv32ui` excluding unsupported `fence_i`, CoreMark 2/50, static checks, Huoyue 100MHz Vivado implementation, and QoR gate.
- CoreMark 50 with the resource profile is 18369937 measured cycles, about 2.722 CoreMark/MHz at 100MHz. This is a 5.025% cycle reduction versus the prior 19341937-cycle resource baseline.
- Huoyue 100MHz `soc_top` implementation passes timing with WNS 0.106 ns, WHS 0.035 ns, LUT 5444, FF 5278, BRAM36 24, DSP48 12, BUFG 2, MMCME2_ADV 1. Bitstream: `build/vivado_impl_soc_top_huoyue_100m_nonblocking_mul_shared_wb/soc_top.bit`.
- QoR remains correct: `RAMD64E=0 BlockRAM=24`; IMEM and DMEM both map to RAMB36E1.
- Result: this is the new best verified board candidate if moderate LUT overage is acceptable. It improves performance but does not reach the 3.0 CoreMark/MHz target by itself.

## Phase 37 Load Response EX Forward Parameter Scan - Completed
- Goal: check whether the existing `ENABLE_LOAD_RESP_EX_FORWARD=1` performance mode can be combined with the accepted nonblocking slow multiplier and trimmed predictor profile.
- No RTL default was changed in this phase. The candidate was evaluated through generic overrides: `FAST_MUL=0`, `MUL_STAGES=1`, `ENABLE_LOAD_RESP_EX_FORWARD=1`, `BP_LOCAL_HISTORY=0`, `BP_BHT_DEPTH=64`, `BP_BHR_WIDTH=2`, `BP_BTB_DEPTH=32`.
- CoreMark 2 measured 712193 cycles, CPI 1.201134, with 54191 load-use stalls.
- CoreMark 50 measured 17806231 cycles, CPI 1.231388. At 100MHz this is about 2.808 CoreMark/MHz, a 3.07% cycle reduction versus the Phase 36 18369937-cycle baseline.
- Official tests passed with this parameter set: full `rv32um` and applicable `rv32ui` excluding unsupported `fence_i`.
- The first Huoyue 100MHz implementation attempt with `AltSpreadLogic_high` failed timing at WNS -0.041 ns, so it is rejected.
- The second implementation with `ExtraNetDelay_high` passed timing and generated `build/vivado_impl_soc_top_huoyue_100m_nonblocking_mul_loadresp_exfwd_extra_net_delay/soc_top.bit`: WNS 0.013 ns, WHS 0.034 ns, LUT 5513, FF 5288, BRAM36 24, DSP48 12, BUFGCTRL 4, MMCME2_ADV 1.
- QoR remains correct: `RAMD64E=0 BlockRAM=24`; IMEM and DMEM still map to block RAM.
- Result: this is the fastest verified board candidate so far, but the timing margin is only 0.013 ns and the score is still below the 3.0 target. Treat it as suitable for board measurement, not as a stable base for blindly adding more combinational performance logic.

## Phase 38 LR1 Branch Predictor Capacity Scan - Completed
- Goal: recover more CoreMark performance on top of Phase 37 by spending LUTs on BTB capacity and optional local history, without changing RTL defaults.
- Quick CoreMark 2 screens, all with `FAST_MUL=0`, `MUL_STAGES=1`, and `ENABLE_LOAD_RESP_EX_FORWARD=1`:
  - `LOCAL_HISTORY=0 BHT=64 BHR=2 BTB=64`: 706166 cycles.
  - `LOCAL_HISTORY=1 BHT=64 BHR=2 BTB=32`: 705536 cycles.
  - `LOCAL_HISTORY=1 BHT=64 BHR=2 BTB=64`: 699479 cycles.
  - `LOCAL_HISTORY=1 BHT=128 BHR=3 BTB=64`: 698701 cycles.
- CoreMark 50 confirmed the two useful local-history candidates:
  - Small local-history candidate `BHT=64 BHR=2 BTB=64`: 17487089 cycles, about 2.859252 CoreMark/MHz.
  - Large local-history candidate `BHT=128 BHR=3 BTB=64`: 17459390 cycles, about 2.863788 CoreMark/MHz.
- The large local-history candidate passed official tests but failed Huoyue 100MHz implementation: WNS -0.093 ns, TNS -1.389 ns, 38 setup failing endpoints. It is rejected despite being the fastest simulation result.
- The small local-history candidate passed official tests and Huoyue 100MHz implementation. Final bitstream: `build/vivado_impl_soc_top_huoyue_100m_nonblocking_mul_loadresp_exfwd_localhist64_btb64/soc_top.bit`.
- Accepted small-candidate implementation result: WNS 0.004 ns, TNS 0.000 ns, WHS 0.035 ns, LUT 6332, FF 7499, BRAM36 24, DSP48 12. QoR passed with `RAMD64E=16 BlockRAM=24`.
- Result: this is now the fastest timing-clean board candidate, but timing is extremely fragile and the score is still below 3.0. At 50 iterations it still needs 820422 fewer cycles, about another 4.69% cycle reduction, to reach 3.0 CoreMark/MHz at 100MHz.

## Phase 39 Load Control Early Replay - In Progress
- Goal: reduce remaining load-use stalls for `load -> branch/JALR` without putting `load_resp_data` directly on the PC/redirect combinational path.
- Implemented optional `ENABLE_LOAD_CONTROL_EARLY_REPLAY` through RTL tops and simulation scripts. Defaults remain compatibility-oriented; the performance candidate enables it by generic override.
- Added strict directed regressions for zero-stall load-to-branch and load-to-JALR, plus same-`rd` replay and wrong-path writeback bug regressions.
- Verification passed after the final RTL point: full ModelSim RTL regression, project structure check, full `rv32um`, and applicable `rv32ui` excluding unsupported `fence_i`.
- CoreMark 50 A/B on the same RTL point: disabled `17612289` cycles, enabled `17414991` cycles. This is about a 1.12% gain from the feature.
- The enabled result is faster than the Phase 38 accepted bitstream simulation point `17487089` by `72098` cycles, but still short of the 3.0 target of `16666667` cycles for 50 iterations at 100MHz.
- Huoyue 100MHz implementation did not close timing. `ExtraNetDelay_high` failed narrowly at WNS -0.011 ns; `AltSpreadLogic_high` failed at WNS -0.086 ns. QoR was correct on the narrow failure.
- Tried and reverted a small `redirect_from_replay` tag-boundary timing experiment because it worsened implementation to WNS -0.220 ns despite passing `check_project`, full ModelSim, and CoreMark 2.
- Current decision: keep this as a simulation-proven optional performance candidate, but do not replace the Phase 38 timing-clean board bitstream until timing is rescued.
- Additional Phase 39 timing rescue attempts were rejected. Focused replay/redirect floorplanning failed at WNS -0.173 ns, a plain Explore implementation failed at WNS -0.156 ns, and a resumed routed implementation after a source-use-mask RTL cleanup failed at WNS -0.376 ns despite correct QoR.
- Added source-register-use masking for hazard/scoreboard comparisons to remove false load-use stalls on instructions that do not actually read rs1/rs2. New regression `tb_load_false_dep_no_stall` failed on old RTL and passes after the fix.
- Source-use mask verification passed: full ModelSim regression, project structure check, full rv32um, and applicable rv32ui excluding fence_i.
- Source-use mask performance is a small improvement: early-replay CoreMark 50 moved from 17414991 to 17378691 cycles, about 0.21%. This is still short of the 16666667-cycle target for 3.0 CoreMark/MHz at 100MHz.
- Added `scripts/vivado_route_from_place.tcl` so interrupted/timed-out implementation runs can resume from `post_place.dcp`.
- Also tested the current RTL with `ENABLE_LOAD_CONTROL_EARLY_REPLAY=0` after the source-use mask, to establish a timing-clean fallback from the latest source tree.
- No-early-replay CoreMark 50 on current RTL measured 17575989 cycles, about 2.84479 CoreMark/MHz at 100MHz. This improves versus the Phase 39 disabled same-RTL point, but is slower than the older Phase 38 accepted 17487089-cycle artifact by 88900 cycles.
- No-early-replay Huoyue 100MHz implementation:
  - `ExtraNetDelay_high` failed narrowly: WNS -0.026 ns, TNS -0.160 ns, 7 setup endpoints. QoR passed with `RAMD64E=16 BlockRAM=24`, LUT 6312, FF 7529, BRAM36 24, DSP48 12.
  - `AltSpreadLogic_high` passed exactly at the boundary: WNS 0.000 ns, TNS 0.000 ns, WHS 0.037 ns, LUT 6337, FF 7537, BRAM36 24, DSP48 12. QoR passed with `RAMD64E=16 BlockRAM=24`.
- Current-source timing-clean bitstream: `build/vivado_impl_soc_top_huoyue_100m_srcmask_no_lctrl_alt_spread/soc_top.bit`.
- Decision update: the latest source tree now has a timing-clean no-early-replay build, but it does not replace the older Phase 38 artifact as the fastest measured board candidate. Keep Phase 38 for fastest board measurement; use the current-source bitstream when the exact latest RTL is required.

## Phase 40 CoreMark Hotspot Attribution - Completed
- Goal: stop guessing which performance source is large enough for the 3.0 target by attributing CoreMark stalls/flushes back to PCs and symbols.
- Fixed the simulation-only hotspot tables in `tb/tb_external_program.v`: replacement entries now reset count to 1 instead of inheriting the evicted count, load-use table capacity was raised to 256 entries, and branch/jump flush PC tables were added.
- Added `scripts/run_coremark_hotspots.ps1`, which runs CoreMark with `-PerfStats`, saves a raw log, parses hotspot lines, annotates PCs through `nm`, and writes sorted CSVs under `build/coremark/hotspots`.
- Ran 2-iteration A/B with current local-history 64/64 parameters:
  - early replay enabled: 695145 cycles, 45060 load-use stalls, 7615 branch-mispredict flushes, 5255 jump flushes, 5 JALR flushes.
  - early replay disabled: 703035 cycles, 55017 load-use stalls, 7615 branch-mispredict flushes, 5255 jump flushes, 5 JALR flushes.
- Hotspot conclusion: early replay saves about 9957 load-use stalls and 7890 result cycles in the 2-iteration run, but the remaining loss is still dominated by ordinary adjacent load-to-consumer pairs.
- Top remaining load-use pairs with early replay enabled are concentrated in `core_bench_list`, `core_state_transition`, and `matrix_test`; branch/jump flushes are much smaller and mostly in `core_state_transition`.
- Verification passed after the testbench/script changes: `scripts/check_project.ps1`, both hotspot CoreMark runs, and full `scripts/run_modelsim.ps1`.
- Decision: branch predictor/JALR work is not the next highest-leverage route to 3.0. The next RTL performance work should target ordinary load-use dependency cost or a broader registered replay/issue boundary, because predictor/flush work cannot close the remaining 50-iteration gap alone.

## Phase 41 ID Load Early Read - In Progress
- Goal: reduce ordinary adjacent load-use stalls by optionally issuing a safe ID-stage early DMEM read when a load's base register is already available.
- Implemented `ENABLE_ID_LOAD_EARLY_READ`, default off, with CPU hierarchy and script parameter plumbing.
- Added directed zero-stall regressions for word loads and byte/halfword formatted early-read forwarding.
- Verification passed: targeted width regression, project structure check, full ModelSim regression, full `rv32um`, and applicable `rv32ui` excluding `fence_i`.
- CoreMark 50 result with early replay + local-history 64/64 + ID early read is `17057625` measured cycles, about `2.931 CoreMark/MHz` at 100 MHz. This is the fastest simulation point so far, but still misses 3.0 by `390958` cycles.
- Added generic override support to the synth-only Vivado flow so parameterized candidates can be screened without place/route.
- Synthesis-only Huoyue `soc_top` screen completed with correct QoR (`RAMD64E=16 BlockRAM=24`) and resources LUT `6682`, FF `7727`, BRAM36 `24`, DSP48 `12`, but WNS is `-4.199 ns`.
- Current next step: register or decouple the SoC MMIO/debug readback path from DMEM BRAM output before attempting post-route, because the worst synth path is `u_dmem/.../CLKBWRCLK` to `mmio_rdata_q_reg[10]/R`.
- Continued timing rescue for the ID early-read candidate:
  - Added a load-response base dependency guard so an ID-stage early-read load does not use the same-cycle load response as its address base.
  - Added raw regfile read outputs and changed `id_load_early_addr` to use a stable base source that excludes `load_resp_data`; this cut the synth-only WNS from about `-4.21 ns` to `-2.994 ns`.
  - Removed global `hazard_stall` / pipe-control stall gating from `id_load_early_read`; this preserved CoreMark 2 at `687953` cycles and improved synth WNS to `-2.689 ns`.
  - Reintroduced the safe SoC MMIO read-hold boundary: reset and unsupported MMIO reads still clear `mmio_rdata_q`, but non-MMIO cycles no longer clear it every clock. SoC UART directed tests passed and synth WNS improved to `-2.608 ns`.
  - Added an explicit `dmem_read_early` qualifier from `cpu_core` and used it in `soc_top` so MMIO readback only responds to architectural MEM-stage reads. Short CoreMark stayed at `687953` cycles and synth WNS improved to `-2.349 ns`.
  - Current decision: this is a real timing improvement but still not route-ready. The next architectural timing step should target the remaining `id_load_early_addr -> DMEM BRAM ENARDEN` path, likely by simplifying/relocating the DMEM range check or adding a registered early-read request boundary.

## Phase 42 ID Early-Read Timing Rescue - In Progress
- Goal: decide whether the remaining DMEM BRAM `ENARDEN` synth failure can be rescued without giving up the ID early-read CoreMark gain.
- Completed and rejected a fast DMEM select experiment:
  - high-bit `dmem_sel` plus trusted DMEM address range
  - simulation and short CoreMark remained correct
  - synth-only WNS worsened to `-2.680 ns` versus the `-2.196 ns` MMIO hold-only baseline
  - experiment was reverted and its static check removed
- Tried light floorplanning on the MMIO hold-only baseline. It produced a bitstream but failed timing at WNS `-1.339 ns`; the worst endpoint was DMEM BRAM `RSTRAMB`.
- Added and kept a DMEM BRAM read-hold cleanup:
  - `read_word_q/read_offset_q` now hold on non-read cycles in the BRAM-friendly DMEM path
  - new static check: `scripts/check_dmem_bram_read_hold.ps1`
  - CoreMark 2 remains `687953` cycles
  - applicable `rv32ui` and full `rv32um` pass
  - post-route without floorplan improves the failure shape to WNS `-1.131 ns`, worst path `redirect_from_replay -> DMEM ENARDEN`
- Current accepted RTL state for this phase keeps MMIO hold-only plus DMEM BRAM read-hold. It is still not timing-clean for the high-performance ID early-read configuration.
- Next planned decision:
  - stop floorplan-only rescue for this candidate;
  - design a true registered read-enable/request boundary for `redirect/load-replay/id-early-read -> dmem_read -> BRAM ENARDEN`, then measure CoreMark loss or gain immediately.

## Phase 43 JAL BTB + ID Early-Read Timing Closure - In Progress
- Goal: preserve the fastest current simulation point, including JAL unconditional BTB prediction and ID load early-read, while reducing Huoyue 100MHz post-route timing failure.
- Accepted RTL changes so far:
  - trim `id_load_early_read` control fan-in by removing `ctrl_replay_valid` and `flush` from the read-enable expression;
  - predecode IF/ID load `rs1` and load immediate for early-read address/dependency checks;
  - wrap fast-multiply combinational products in a `generate if (FAST_MUL != 0)` boundary. This is a hygiene cleanup; synthesis showed no WNS change in the current `FAST_MUL=0` build.
- Rejected or not selected:
  - multiplier operand gating: behavior unchanged, synth WNS worsened;
  - predecode `NoTimingRelaxation` route-only result: QoR OK but worse than full impl;
  - `MoreGlobalIterations` route from the ExtraNetDelay placement: QoR OK but WNS worsened to `-0.341 ns`.
- Current best candidate:
  - `build/vivado_route_soc_top_huoyue_jal_uncond_fastmulgen_btb32_extra_net_delay_route_explore/soc_top.bit`
  - WNS `-0.099 ns`, TNS `-1.072 ns`, 21 setup failing endpoints, WHS `0.043 ns`
  - resources LUT/FF/BRAM/DSP `6454 / 5782 / 24 / 12`
  - QoR passed with `RAMD64E=16 BlockRAM=24`
  - CoreMark 2 remains `678919` cycles, CPI `1.164976`
- Current next step: either try one more targeted route/placement variant from the promising ExtraNetDelay placement, or move to an RTL boundary for the new worst path `ex_mem_rd -> redirect_branch_mispredict`.
- Latest attempted RTL path, control forwarding selector duplication, was rejected:
  - synth improved, but post-route worsened to WNS `-0.498 ns`;
  - RTL and temporary check script were reverted;
  - current accepted source is back to the fast-mul-generate/JAL/predecode baseline.
- Next preferred step: run one controlled implementation-side experiment from the current best placement before attempting a larger redirect boundary rewrite.
- That controlled route experiment is complete and rejected: `AdvancedSkewModeling + AggressiveExplore` reached only WNS `-0.277 ns`.
- Updated next preferred step: design a narrow RTL boundary or simplification specifically for `redirect_branch_mispredict` registration, but require immediate ModelSim/CoreMark and post-route comparison against the `-0.099 ns` baseline.
- Dependency-stall boundary attempt is complete and rejected:
  - broad branch/JALR EX/MEM wait was too slow;
  - less-than-only wait still worsened CoreMark and synth WNS;
  - source is reverted to the prior accepted baseline.
- Next preferred step: keep same-cycle forwarding and try a compare-cone rewrite that separates equality branches from less-than branches without adding stalls.
- Compare-cone split is also complete and rejected:
  - behavior/CoreMark unchanged, but post-route WNS worsened to `-0.572 ns`;
  - source is reverted again to the prior accepted baseline;
  - retained `scripts/vivado_impl_from_opt.tcl` as a useful implementation resume helper.
- Next preferred step: stop local branch RTL micro-edits for now. The better next target is either a controlled floorplan/placement constraint around the current `ex_mem_rd -> redirect_branch_mispredict` region, or a larger redirect boundary redesign only if willing to pay more verification time.

## Phase 44 Repository Backup and GitHub Initialization - In Progress
- Goal: create a clean source-controlled project snapshot without committing Vivado/ModelSim generated outputs or the local RISC-V toolchain.
- Local backup policy:
  - keep a source backup under `.project_backups/`;
  - exclude `.project_backups/` from the Git repository.
- Git repository policy:
  - track RTL, testbenches, scripts, constraints, software support files, and project documentation;
  - ignore `build/`, `.Xil/`, `work/`, simulator logs/waves, Vivado logs/checkpoints/bitstreams, local toolchains, and transient preview files;
  - keep `coremark` and `riscv-tests` as official upstream submodule references rather than copying their internal Git metadata into this repository.
- Next step: commit the cleaned initial import, then add a GitHub remote and push after the remote URL is available.

## Phase 45 CoreMark 3.2 Timing/Resource Optimization - In Progress
- Goal: reach or approach CoreMark 3.2 while keeping the design plausible for Huoyue/Zynq-7020 timing.
- Completed in this phase:
  - tested BHR/local-history removal by setting `BP_LOCAL_HISTORY=0`;
  - added optional `BP_INIT_TAKEN` predictor cold-start generic with default off;
  - verified default predictor behavior and init-taken behavior with ModelSim unit tests;
  - measured no-BHR CoreMark and synthesis/resource tradeoffs.
- Current finding:
  - no-BHR reduces predictor complexity but does not reach 3.2; best observed no-BHR CoreMark 2 is `630043` cycles;
  - reasonable no-BHR synth still has WNS `-2.348 ns` and the same DMEM-to-redirect class of worst path;
  - oversized no-BHR BTB/BHT is not viable.
- Next preferred step:
  - stop increasing no-BHR predictor size;
  - target the remaining load-use/redirect datapath while keeping no-BHR as a fallback/resource configuration.

## Phase 46 CoreMark 3.0 Hard-Target Closure - Complete
- Goal: meet the revised hard targets at the same time:
  - CoreMark/MHz >= 3.0 at 100 MHz
  - Slice LUTs < 9000
  - Huoyue/Zynq-7020 post-route 100 MHz timing clean
- Selected implementation configuration:
  - `FAST_MUL=0`, `MUL_STAGES=1`
  - `ENABLE_LOAD_RESP_EX_FORWARD=1`
  - `ENABLE_LOAD_CONTROL_EARLY_REPLAY=0`
  - `ENABLE_ID_LOAD_EARLY_READ=0`
  - `BP_LOCAL_HISTORY=1`
  - `BP_BHT_DEPTH=64`, `BP_BHR_WIDTH=2`, `BP_BTB_DEPTH=64`
  - `BP_INIT_TAKEN=0`
- Selected artifact:
  - `build/vivado_physopt_soc_top_coremark30_lhr64_bhr2_btb64_lctrl0_idread0_adv_skew_pass2/soc_top_physopt.bit`
- Verification result:
  - CoreMark 2 cycles: `650534`, about `3.074 CoreMark/MHz`
  - Vivado post-route physopt timing: WNS `0.000 ns`, TNS `0.000 ns`, failing setup endpoints `0`
  - Utilization: LUT `6800`, FF `8278`, RAMB36 `24`, DSP `12`, RAMD64E `16`
- Current status:
  - The hard targets are met, but timing margin is exactly 0 ps. The next optimization should first increase timing margin before trying to recover more CoreMark performance.
