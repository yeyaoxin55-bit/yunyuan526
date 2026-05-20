# 进度记录

## 2026-04-27
- 创建本次文档审阅计划文件。
- 盘点目录，发现 1 份 Markdown 设计文档。
- 已阅读全文，记录资源约束、AXI接口角色、RV64M范围、资源估算和中断边界等改进点。
- 已修订设计方案文档，并完成关键词复核；当前目录不是Git仓库，无法生成Git差异。
- 根据用户新要求，将方案改为面向Zynq-7020的性能优先版本，并重命名主设计文档。
- 按CoreMark容量风险调整默认存储配置：IMEM 64KB、DMEM 32KB，并补充64KB/64KB可选说明。
- 创建首轮RTL工程骨架：公共定义、RV32I译码/ALU/寄存器堆、IMEM/DMEM、5级流水核心、顶层、烟测程序、约束和检查脚本。
- 结构检查通过；本机未安装iverilog，仿真脚本已按设计跳过，尚未完成实际RTL仿真。
- 接入ModelSim脚本`scripts/run_modelsim.ps1`，ModelSim编译0错误0警告，smoke程序仿真输出`PASS smoke program completed`。
- 新增ModelSim回归：forwarding、load-use、branch、mem_width；修复MEM级load转发、分支EX冲刷ID/EX、字节/半字load/store扩展。
- 当前基础核心为保证RV32I功能闭环，IMEM采用组合读；后续实现prefetch/同步BRAM前端时需重新验证取指对齐和停顿逻辑。
- 新增ModelSim回归：alu_full、jump、branch_conditions；覆盖RV32I ALU R/I类、JAL链接地址、BNE/BLT/BGE/BLTU/BGEU条件分支。8个testbench全部通过。
- 新增upper_jump回归并修复AUIPC为PC+imm写回，同时覆盖LUI/JALR。
- 新增csr_counter回归，接入最小CSR计数器读路径，支持读取mcycle/minstret用于后续CoreMark计时。
- 加固`scripts/run_modelsim.ps1`，检测`FAIL`输出和非零`Errors:`；当前10个ModelSim testbench全部通过。
- 新增RV32M回归：mul覆盖MUL/MULH/MULHSU/MULHU，div覆盖DIV/DIVU/REM/REMU；当前以组合执行路径实现，12个ModelSim testbench全部通过。
- 将RV32M DIV/DIVU/REM/REMU从组合执行路径替换为按位迭代`rtl/divider.v`，在`cpu_core`中加入DIV/REM等待暂停与EX/MEM空泡注入；`scripts/run_modelsim.ps1`补充编译`rtl/divider.v`后，12个ModelSim testbench全部通过。
- 将RV32M MUL/MULH/MULHSU/MULHU从`cpu_core`组合路径移入`rtl/multiplier.v`两级流水乘法器，CPU使用统一`exec_wait`暂停机制等待乘除法结果；新增`tb/tb_multiplier.v`单元回归并纳入`scripts/run_modelsim.ps1`，当前13个ModelSim testbench全部通过。
- 将`rtl/imem.v`改为同步读BRAM语义，`cpu_core`取指侧拆分请求PC与响应PC/指令，并接入`rtl/prefetch.v`响应缓冲与skid槽处理load-use短暂停和乘除法长暂停；新增`tb/tb_prefetch.v`并纳入ModelSim，当前14个testbench全部通过。
- 实现`rtl/branch_predictor.v`的BTB+2-bit饱和计数器预测；`cpu_core`按预测目标更新PC，预测元数据随prefetch进入流水线，EX阶段仅在分支误预测或跳转时flush并重定向。新增`tb/tb_branch_predictor.v`和`tb/tb_branch_predict.v`，当前16个ModelSim testbench全部通过。
- 暂停Vivado综合方向，转向官方RISC-V测试/CoreMark准备；清理中断后残留Vivado进程。当前未在PATH或常见工程目录找到`riscv*-unknown-elf-*`工具链，但发现本机已有`E:\riscv_cpu\tools\riscv-arch-test-act4`源码目录。
- 为官方测试/CoreMark建立外部加载基础设施：`dmem`增加`DMEM_BASE`地址映射，`cpu_top`透传该参数；新增`tb/tb_external_program.v`、`scripts/run_external_modelsim.ps1`、`scripts/convert_elf_to_hex.ps1`、`scripts/build_baremetal.ps1`、`sw/linker/yl3_rv32im.ld`、`sw/runtime/crt0.S`、`sw/runtime/yl3_platform.h`。已用`tb/programs/external_pass.hex`验证`0x0001_0000` pass标志路径，现有16个ModelSim回归全部通过。

## Official RISC-V Test Update
- Official RISC-V test flow added with xPack GCC 15.2.0 and custom unprivileged sw/riscv-tests-env/riscv_test.h; pass/fail markers moved to 0x00017ff0/0x00017ff4 to avoid signature/data overlap.
- Fixed official-test environment bug: TESTNUM no longer uses gp; gp is initialized to __global_pointer$ so linker-relaxed la sequences address data correctly.
- Fixed DMEM/CPU load-store path for byte-addressed unaligned 1/2/4-byte accesses across word boundaries. Existing 16 ModelSim RTL regressions passed after this change.
- Official applicable rv32ui tests passed in ModelSim: arithmetic/logical/shift/set, branches/jumps, loads/stores, ld_st, st_ld, and ma_data. fence_i is excluded for now because it requires self-modifying code and instruction fetch from DMEM/unified memory, outside the current high-performance Harvard IMEM/DMEM design.
- Official rv32um tests passed in ModelSim: mul,mulh,mulhsu,mulhu,div,divu,rem,remu.

## CoreMark Update
- Added YL3 baremetal CoreMark port in sw/coremark_port and scripts/build_coremark.ps1 / scripts/run_coremark.ps1.
- Moved .rodata/.srodata to DMEM in sw/linker/yl3_rv32im.ld because the current Harvard CPU fetches instructions from IMEM but data loads read DMEM.
- CoreMark TOTAL_DATA_SIZE=1200 ITERATIONS=1 passed ModelSim at cycle 238769.
- CoreMark TOTAL_DATA_SIZE=2000 ITERATIONS=1 passed ModelSim at cycle 573798; build used IMEM 7024 B and DMEM 4104 B, so 64KB IMEM / 32KB DMEM is sufficient for this functional run.
- Re-ran a post-linker-change riscv-tests smoke subset: rv32ui add/beq/lw/sw/ma_data passed, rv32um mul/div passed.
- This is functional validation only; reportable CoreMark scoring still needs a long timed run on hardware or a simulation run long enough to satisfy CoreMark reporting rules.

## CoreMark Profile Update
- Added scripts/profile_coremark.ps1 to run CoreMark across selected TOTAL_DATA_SIZE / ITERATIONS combinations and emit build/coremark/coremark_profile.csv.
- Extended tb/tb_external_program.v and scripts/run_external_modelsim.ps1 with RESULT_ADDR so the harness can print CoreMark measured cycles from 0x00017ff8.
- Updated scripts/run_coremark.ps1 to print COREMARK_SIM_CYCLE and COREMARK_RESULT_CYCLES summary lines.
- Generated build/coremark/coremark_profile.csv: TOTAL_DATA_SIZE=1200 uses 7024 B IMEM / 3304 B DMEM and measured 220749 CoreMark cycles; TOTAL_DATA_SIZE=2000 uses 7024 B IMEM / 4104 B DMEM and measured 542141 CoreMark cycles.
- Project structure check passed and all existing ModelSim RTL regressions passed after the harness changes.

## CoreMark Perf Stats Update
- Added -PerfStats support to scripts/run_external_modelsim.ps1, scripts/run_coremark.ps1, and scripts/profile_coremark.ps1.
- Extended tb/tb_external_program.v to print PERF_STATS counters for retired instructions, loads, stores, branches, jumps, muls, divs, load-use stalls, exec-wait stalls, and flushes.
- Updated profile CSV with CPI and event counters. Current ITERATIONS=1 baseline: TOTAL_DATA_SIZE=1200 CPI 1.409933, retired 156567, load-use stalls 12953, exec-wait stalls 8874, flushes 15781; TOTAL_DATA_SIZE=2000 CPI 1.443327, retired 375619, load-use stalls 29304, exec-wait stalls 31548, flushes 34331.
- Verification passed: CoreMark profile with -PerfStats, project structure check, and full ModelSim RTL regression.

## CoreMark Iteration Sweep Update
- Ran TOTAL_DATA_SIZE=2000 with ITERATIONS=1,2,5,10 and saved build/coremark/coremark_profile_iter_sweep.csv.
- Ran longer ITERATIONS=20,50 and saved build/coremark/coremark_profile_iter_long.csv.
- Cycles per iteration are stable: 542141 at 1 iteration, 542258.3 at 10 iterations, 542329.9 at 50 iterations.
- CPI converges upward as fixed startup/finish work is amortized: 1.443327 at 1 iteration, 1.511777 at 10 iterations, 1.518165 at 50 iterations.
- Normalized long-run event rates at 50 iterations: load-use stalls 80.03/kInstr, exec-wait stalls 79.33/kInstr, flushes 90.14/kInstr, branches 180.78/kInstr, jumps 76.13/kInstr.

## CoreMark 10s Attempt
- Tried official-style CoreMark 10s run with TOTAL_DATA_SIZE=2000, ITERATIONS=1900, MaxCycles=1200000000, and -PerfStats.
- Build and hex conversion succeeded: IMEM 7024 B / 64KB, DMEM 4104 B / 32KB.
- ModelSim RTL simulation did not finish within the 1-hour command window. This is expected from the 50-iteration measured runtime; a 1900-iteration RTL sim likely needs multiple hours.
- Recommendation: run the 1900-iteration command in a standalone terminal for an overnight simulation, or run the official 10s CoreMark on the Zynq-7020 target where wall-clock time is practical.

## JAL Early Redirect Optimization Update
- Split CoreMark perf counters into branch_mispredict_flushes, jump_flushes, jal_flushes, jalr_flushes, and jal_early_redirects.
- Baseline 50-iteration flush split before optimization: flushes 1610096, branch_mispredict_flushes 250258, jump_flushes 1359838, jal_flushes 984115, jalr_flushes 375723.
- Implemented ID-stage early redirect for JAL in rtl/cpu_core.v. JAL still retires through EX/MEM for link writeback, but the frontend redirects before EX-stage jump flush.
- After optimization at TOTAL_DATA_SIZE=2000 ITERATIONS=50: CoreMark cycles 26133650, cycles/iteration 522673, CPI 1.463139, flushes 625981, jump_flushes 375723, jal_flushes 0, jal_early_redirects 984115.
- Compared to the prior 50-iteration baseline of 27116494 cycles / 542329.88 cycles per iteration, this reduces cycles by 982844 total, about 3.62%.
- Verification passed: structure check, full ModelSim RTL regression, CoreMark 2-iteration smoke, CoreMark 50-iteration profile, rv32ui add/beq/jal/jalr/lw/sw/ma_data, and rv32um mul/div.

## JALR Hotspot Analysis Update
- Added JALR_TOP and JALR_PAIR_TOP profiling to tb/tb_external_program.v to identify dynamic JALR source PCs and PC/target pairs.
- Ran CoreMark TOTAL_DATA_SIZE=2000 ITERATIONS=50 after JAL early redirect and saved build/coremark/coremark_jalr_hotspots_50.log. Top JALR PCs: 0x147c count 228801, 0x1460 count 50201, 0x18d4 count 29209, 0x0a94 count 16273.
- Objdump mapping shows 0x147c is the core_state_transition jump-table jr t6, not a return. 0x1460 is a ret in core_state_transition.
- Added JALR last-target predictor simulation in the testbench. On ITERATIONS=10, last-target hits were 23875 and misses were 51578, about 31.6% hit rate.
- Full ModelSim RTL regression and project structure check passed after the profiling additions.

## Load-Use Hotspot Analysis Update
- Added LOAD_USE_TOP and LOAD_USE_PAIR_TOP profiling to tb/tb_external_program.v.
- Ran CoreMark TOTAL_DATA_SIZE=2000 ITERATIONS=50 after JAL early redirect and saved build/coremark/coremark_load_use_50.log.
- Top load-use pairs: 0x144c->0x1450 count 279000, 0x1478->0x147c count 228800, 0x097c->0x0980 count 150100, 0x0980->0x0984 count 150100, 0x0974->0x0978 count 149850, 0x0968->0x096c count 146461, 0x0f44->0x0f48 count 64805.
- Objdump mapping shows the largest hotspots are real adjacent load-use dependencies in core_state_transition, core_list_find, and matrix_sum.

## Zero Load-Use Stall Performance Update
- Added ENABLE_LOAD_USE_STALL parameter to rtl/hazard_unit.v, rtl/cpu_core.v, and rtl/cpu_top.v. Default is 0 for the current performance-oriented asynchronous DMEM read path; setting it to 1 restores conservative load-use stalls for synchronous memory assumptions.
- Current dmem.v is combinational-read, so MEM-stage load data can be forwarded through ex_mem_forward_data into the following EX-stage consumer. The old load-use stall was conservative for this RTL memory model.
- CoreMark TOTAL_DATA_SIZE=2000 ITERATIONS=2 improved from 1045168 cycles after JAL early redirect to 988007 cycles with load-use stalls disabled; load_use_stalls dropped to 0.
- CoreMark TOTAL_DATA_SIZE=2000 ITERATIONS=50 improved from 26133650 cycles after JAL early redirect to 24704859 cycles; cycles/iteration is 494097.18 and CPI is 1.383145.
- Compared to the original pre-JAL/load baseline of 27116494 cycles at 50 iterations, the combined JAL early redirect + zero load-use stall path reduces cycles by 2411635 total, about 8.89%.
- Verification passed: full ModelSim RTL regression, rv32ui load/store/jal/jalr subset, CoreMark 2-iteration smoke, CoreMark 50-iteration profile, and project structure check.

## FPGA CoreMark Bring-up Preparation
- Added CPU_HZ support to the CoreMark port and build/profile scripts so board timing can match the actual FPGA CPU clock.
- Added rtl/fpga_coremark_top.v wrapper exposing pass_o, fail_o, done_o, cycle_o, and led[3:0] for board/ILA observation.
- Added debug_pass_word, debug_fail_word, and debug_cycle_word outputs to cpu_top for pass/fail/cycle result observation.
- Added scripts/prepare_coremark_fpga.ps1, which generated smoke, ten_ms, and ten_sec IMEM/DMEM hex images under build/coremark/fpga.
- Added docs/fpga_coremark_bringup.md with memory map, result addresses, image generation commands, and load-use stall notes.
- Updated Vivado synth scripts to include fpga_coremark_top.v and allow selecting -Top fpga_coremark_top.
- Verification passed: project structure check, full ModelSim RTL regression with 0 warnings, CoreMark 2-iteration simulation, FPGA wrapper ModelSim compile with 0 errors/0 warnings.

## FPGA Manifest Fix
- Fixed scripts/prepare_coremark_fpga.ps1 so manifest.csv contains only image metadata, not build log arrays.
- Regenerated build/coremark/fpga/manifest.csv with smoke=2 iterations, ten_ms=2 iterations, and ten_sec=1900 iterations.
- Re-ran project structure check after the fix: PASS.

## Fast Multiply CoreMark Optimization
- Added split perf counters for mul_wait_stalls and div_wait_stalls in tb/tb_external_program.v, scripts/run_coremark.ps1, and scripts/profile_coremark.ps1.
- Confirmed on CoreMark TOTAL_DATA_SIZE=2000 ITERATIONS=2 that exec_wait_stalls were dominated by multiply: 56949 mul_wait_stalls vs 2871 div_wait_stalls.
- Added configurable MUL_STAGES parameter through cpu_core/cpu_top and set the performance default to 1 stage. This reduced 50-iteration CoreMark cycles from 24704859 to 24233659.
- Added FAST_MUL parameter, enabled by default, to compute MUL/MULH/MULHSU/MULHU in the EX-stage combinational path while leaving DIV/REM iterative. This reduced 50-iteration CoreMark cycles to 23291259, cycles/iteration to 465825.18, and CPI to 1.304002.
- Current 50-iteration fast-multiply stats: mul_wait_stalls 0, div_wait_stalls 2871, exec_wait_stalls 2871, load_use_stalls 0.
- Compared with the original pre-JAL/load-use baseline of 27116494 cycles, the combined optimization path is now 3825235 cycles lower, about 14.11%.
- Verification passed: CoreMark 2-iteration smoke, CoreMark 50-iteration profile, rv32um full suite, applicable rv32ui suite excluding fence_i, full ModelSim RTL regression, and project structure check.

## Valid Pipeline and Sync DMEM Update
- Stopped the in-progress Vivado synthesis run so RTL correctness work could continue cleanly.
- Added id_ex/ex_mem/mem_wb valid tracking and gated reg_write, dmem write/read side effects, branch predictor update, branch/jump flushes, and hazard inputs with valid/pipeline wait state.
- Fixed CSR minstret accounting to use real MEM/WB retirement validity instead of a constant retire signal. The CSR counter regression now checks 0 < minstret < mcycle.
- Changed dmem.v to synchronous-read behavior and restored ENABLE_LOAD_USE_STALL=1 for the FPGA/BRAM-oriented path.
- Added mem_wait stall handling for one-cycle synchronous load return and added mem_wait_stalls to CoreMark perf stats and CSV output.
- Verification passed: full ModelSim RTL regression, rv32um full suite, the remaining rv32ui ld_st/st_ld/ma_data tests after the earlier long rv32ui run timed out, CoreMark 2-iteration smoke, CoreMark 50-iteration profile, and project structure check.
- New sync-DMEM CoreMark TOTAL_DATA_SIZE=2000 ITERATIONS=50 result: 28015450 CoreMark cycles, 560309 cycles/iteration, CPI 1.568495, load_use_stalls 1586888, mem_wait_stalls 3297838, mul_wait_stalls 0, div_wait_stalls 2871.

## Vivado 100MHz Synthesis Update
- First fpga_coremark_top synthesis attempt with sync DMEM exposed that DMEM was still mapping to distributed RAM because the RAM output was not in a BRAM-friendly template.
- Added SUPPORT_MISALIGNED_DMEM so simulation/default CPU can keep official misaligned access support, while fpga_coremark_top uses a CoreMark/BRAM-friendly single-word synchronous DMEM path.
- Changed the FPGA DMEM path to register the BRAM read word directly and shift with the registered byte offset outside the RAM output register.
- Updated scripts/vivado_synth.tcl to tolerate Vivado 2022.2 not having report_dsp_utilization.
- Verification after the memory-template change passed: full ModelSim RTL regression and CoreMark 2-iteration smoke.
- Vivado 2022.2 synthesis for fpga_coremark_top at 100MHz now completes and maps memories into BRAM: LUT 4456, FF 6624, BRAM36 24, DSP48 12, distributed RAM 0.
- Timing is not met at 100MHz in out-of-context synthesis: WNS -7.088 ns, TNS -5794.543 ns. Worst path is from DMEM BRAM output to ex_mem_alu_result through a 21-level path including CARRY4 and DSP48E1 logic.
- Changed fpga_coremark_top default to FAST_MUL=0 / MUL_STAGES=1 and reran 100MHz synthesis into build/vivado_synth_fpga_coremark_100m_slowmul.
- Slow-multiply synthesis still does not meet 100MHz: WNS -6.545 ns, TNS -5771.848 ns, LUT 4455, FF 6690, BRAM36 24, DSP48 12.
- Worst slow-multiply path is from DMEM BRAM output to u_multiplier/result_pipe_reg through 20 logic levels including CARRY4 and DSP48E1, so simply disabling FAST_MUL is not enough while MUL_STAGES=1 still captures the multiply result in the first multiplier stage.

## Pipelined Multiplier and Load Forward Timing Update
- Reworked rtl/multiplier.v so FAST_MUL=0 captures multiplier operands/funct3 first, then computes the product from registered operands in the following cycle. This lets Vivado absorb DSP AREG/BREG/MREG registers for the FPGA multiplier path.
- Strengthened tb/tb_multiplier.v to reject same-cycle valid output for MUL_STAGES=1, and changed tb/tb_mul.v to exercise the FAST_MUL=0 / MUL_STAGES=1 CPU path.
- 100MHz synthesis after the multiplier pipeline improved WNS from -6.545 ns to -4.718 ns, but timing still failed. The new worst path moved from the multiplier DSP path to a DMEM-load-forwarded branch/PC update path.
- Cut the FPGA synchronous-DMEM load forwarding path in rtl/cpu_core.v: when ENABLE_LOAD_USE_STALL is enabled, EX/MEM no longer forwards unregistered load data, so load consumers use the registered MEM/WB result instead. The old direct load forwarding remains available when ENABLE_LOAD_USE_STALL is disabled.
- Verification after the load-forward cut passed: full ModelSim RTL regression, CoreMark 2-iteration smoke, and full rv32um suite.
- 100MHz synthesis after the load-forward cut improved WNS to -2.813 ns and reduced failing setup endpoints from 5192 to 712 versus the post-multiplier run. Resources are LUT 4483, FF 6694, BRAM36 24, DSP48 12, distributed RAM 0.
- Timing still does not meet 100MHz. The current worst path is now id_ex_rs2_reg -> branch compare / flush / PC update -> pc_reg, so the next timing tradeoff is branch redirect timing versus branch penalty.

## Local BHR Branch Predictor Update
- Added a true local-history direction predictor in rtl/branch_predictor.v: per-PC BHR table, PHT of 2-bit counters indexed by PC index plus local history, and the existing BTB for target prediction.
- Kept the old per-PC BHT as the fallback direction predictor. The local PHT only overrides the base BHT when its counter is strongly taken or strongly not-taken, avoiding regressions on short phase changes.
- Added a unit regression in tb/tb_branch_predictor.v for an alternating branch pattern that the old per-PC 2-bit predictor could not learn.
- Tuned the CPU predictor to BHR_WIDTH=4. A BHR_WIDTH=6 experiment improved CoreMark slightly more but made synthesis impractical with the first resettable-PHT implementation.
- Changed PHT to an initialized, no-reset table so Vivado infers distributed RAM instead of thousands of resettable flops. Vivado maps the 2048x2 PHT to RAM128X1D x32.
- CoreMark TOTAL_DATA_SIZE=2000 ITERATIONS=50 with BHR_WIDTH=4: 27932114 cycles, CPI 1.563829, branch_mispredict_flushes 229336, flushes 605059. Compared with the previous sync-DMEM baseline of 28015450 cycles and 250258 branch mispredict flushes, this saves 83336 cycles and 20922 branch mispredict flushes.
- Final smoke/ISA verification passed after PHT RAM inference: full ModelSim RTL regression, CoreMark 2-iteration smoke, full rv32um suite, and project structure check.
- 100MHz synthesis completes with local BHR but still fails timing: WNS -2.835 ns, LUT 4993, LUTRAM 128, FF 7220, BRAM36 24, DSP48 12. The worst path remains id_ex_rs2_reg -> branch compare / flush / PC update -> pc_reg, so local BHR is a performance improvement but not a timing-closure fix.

## Registered Redirect Timing Update
- Added a registered EX redirect path in rtl/cpu_core.v. Branch/JALR redirect detection now latches redirect_pc_q plus redirect type flags, then flushes and updates PC on the following cycle instead of driving PC directly from the EX compare result.
- Added tb/tb_registered_redirect.v and wired it into scripts/run_modelsim.ps1 to check that EX redirect detection does not assert flush until the next cycle.
- Fixed the delayed-redirect wrong-path hazard found by rv32ui/beq: while redirect_valid is pending, wrong-path ID/EX branch/jump instructions are prevented from scheduling a second redirect before they are flushed.
- Verification passed after the redirect change: full ModelSim RTL regression, rv32um full suite, CoreMark TOTAL_DATA_SIZE=2000 ITERATIONS=2, CoreMark TOTAL_DATA_SIZE=2000 ITERATIONS=50, and project structure check. The 2-iteration smoke result is 1141538 measured cycles, CPI 1.506967.
- CoreMark TOTAL_DATA_SIZE=2000 ITERATIONS=50 after registered redirect: 28532090 measured cycles, CPI 1.545151, branch_mispredict_flushes 228482, flushes 604205. Compared with the local-BHR result before registered redirect, this costs 600976 cycles but improves synthesis timing.
- Full rv32ui now passes through branch tests but still times out at fence_i, which remains unsupported for the current Harvard IMEM/DMEM design because the test requires self-modifying instruction fetch visibility.
- 100MHz synthesis with the registered redirect improved timing substantially versus local BHR: WNS -1.383 ns, TNS -47.799 ns, failing endpoints 47. Resources are LUT 5060, LUTRAM 128, FF 7255, BRAM36 24, DSP48 12.
- The previous branch-compare-to-PC path is cut, but timing still fails. The new worst path is id_ex_rs2_reg -> branch compare/control -> redirect_pc_q_reg[0]/CE, so the next timing step should remove the compare result from the redirect_pc_q clock-enable path, for example by always latching candidate redirect_pc_q and only registering a narrower redirect_valid/type decision.

## Redirect Candidate Split Timing Update
- Split EX redirect target capture from redirect-valid/type capture in rtl/cpu_core.v. Candidate taken target, fallthrough PC, and taken bit are latched for every valid EX branch/JALR candidate, while the narrower redirect_valid and redirect type flags still use the compare/mispredict decision.
- Fixed the PC update path to use the new redirect_pc mux, so not-taken branch mispredicts redirect to the captured fallthrough PC instead of the taken target.
- Verification passed after the split: rv32ui/beq external test, full ModelSim RTL regression, CoreMark TOTAL_DATA_SIZE=2000 ITERATIONS=2, full rv32um suite, CoreMark TOTAL_DATA_SIZE=2000 ITERATIONS=50, project structure check, and fpga_coremark_top 100MHz synthesis.
- CoreMark 50-iteration result is unchanged from the prior registered-redirect baseline: 28532090 measured cycles, CPI 1.545151, branch_mispredict_flushes 228482, flushes 604205.
- 100MHz synthesis improved from WNS -1.383 ns / TNS -47.799 ns / 47 failing endpoints to WNS -0.576 ns / TNS -3.502 ns / 15 failing endpoints.
- Resource use is LUT 5058, LUTRAM 128, FF 7289, BRAM36 24, DSP48 12.
- Timing still does not meet 100MHz. The current worst path is id_ex_rs2_reg[0] -> redirect_branch_mispredict_reg/D through the branch compare/control cone, with 10.569 ns data path delay and 16 logic levels. The next timing step should target the remaining redirect valid/type control cone rather than redirect PC data capture.

## Branch Mispredict Boolean Rewrite Update
- Rewrote branch_mispredict_raw in rtl/cpu_core.v from a full actual-next-PC versus predicted-next-PC compare into an equivalent taken/not-taken form: taken branches check predicted-taken plus target match, while not-taken branches only check predicted-taken.
- This removes the branch redirect control path from the worst setup path. 100MHz synthesis improved from WNS -0.576 ns / TNS -3.502 ns / 15 failing endpoints to WNS -0.457 ns / TNS -2.358 ns / 13 failing endpoints.
- Resource use is LUT 5002, LUTRAM 128, FF 7289, BRAM36 24, DSP48 12.
- CoreMark 50-iteration result is unchanged: 28532090 measured cycles, CPI 1.545151, branch_mispredict_flushes 228482, flushes 604205.
- Verification passed: rv32ui/beq external test, CoreMark 2-iteration smoke, full ModelSim RTL regression, full rv32um suite, CoreMark 50-iteration profile, project structure check, and fpga_coremark_top 100MHz synthesis.
- Timing still does not meet 100MHz. The new worst path is inside the pipelined multiplier, from DSP48E1 product_ss__1/CLK to u_multiplier/result_pipe_reg[0][30]/D, with 10.450 ns data path delay and 16 logic levels. The next timing step should focus on the multiplier result accumulation/output register path rather than branch redirect.

## Multiplier Output Pipeline Timing Closure Update
- Strengthened tb_multiplier.v to require an explicit output pipeline stage after the product register. The old multiplier failed this regression with "valid asserted before output pipeline stage", then passed after the RTL change.
- Added product_valid, product_funct3_q, and registered signed/unsigned product stages in rtl/multiplier.v. The result select now reads registered product values, so the DSP product path is split from result_pipe[0].
- Updated tb_external_program.v plus scripts/run_external_modelsim.ps1 and scripts/run_coremark.ps1 with optional MUL_STAGES and FAST_MUL generics. Defaults remain MUL_STAGES=1 / FAST_MUL=1 for the performance exploration path; FPGA-like runs can now use -FastMul 0 -MulStages 1.
- Vivado reports DSP PREG use after the change. fpga_coremark_top 100MHz synthesis now meets timing in out-of-context synthesis: WNS 0.091 ns, TNS 0.000 ns, 0 failing endpoints.
- Resource use is LUT 5008, LUTRAM 128, FF 7365, BRAM36 24, DSP48 12.
- The new worst met path is id_ex_rs2_reg[0] -> branch_predictor PHT write-enable, with 9.297 ns data path delay and 11 logic levels.
- Verification passed: full ModelSim RTL regression, full rv32um suite, default CoreMark 2-iteration smoke, FPGA-like CoreMark 2-iteration smoke with FAST_MUL=0, FPGA-like CoreMark 50-iteration profile with FAST_MUL=0, project structure check, and fpga_coremark_top 100MHz synthesis.
- Default FAST_MUL=1 CoreMark 2-iteration smoke remains 1141538 measured cycles, CPI 1.506967.
- FPGA-like FAST_MUL=0 / MUL_STAGES=1 CoreMark 50-iteration result is 30416890 measured cycles, CPI 1.647223, mul_wait_stalls 1885351, div_wait_stalls 2871. Compared with the default fast-multiply 50-iteration result of 28532090 cycles, timing closure costs 1884800 cycles on this workload.

## Vivado Implementation and Predictor Update Timing Closure
- Added scripts/vivado_impl.tcl and scripts/run_vivado_impl.ps1 to run synth/opt/place/route/post-route phys_opt and emit timing/utilization reports for fpga_coremark_top.
- The first 100MHz implementation after synthesis timing closure failed post-route timing: WNS -0.263 ns, TNS -51.127 ns, 473 failing endpoints. The worst path was ex_mem_rd_reg -> branch_predictor PHT write-enable, with 9.470 ns data path delay dominated by routing.
- Registered the branch predictor update path in rtl/branch_predictor.v. PHT/BHT/BHR/BTB training now happens one cycle after update_i, cutting the EX/MEM forwarding and branch-taken cone from the PHT write-enable path.
- Updated tb_branch_predictor.v to account for the one-cycle delayed training update.
- The second 100MHz implementation passes post-route timing after route and post-route phys_opt: WNS 0.007 ns, TNS 0.000 ns, failing endpoints 0; hold timing also passes with WHS 0.054 ns and THS 0.000 ns.
- Post-route resources are LUT 4982, LUTRAM 128, FF 7452, BRAM36 24, DSP48 12, and IOB 41 on xc7z020clg400-1.
- The new worst met setup path is branch_predictor bhr_reg[43][1] -> pc_reg[21], with 9.889 ns data path delay and 13 logic levels. This is close to the 100MHz limit but positive after phys_opt.
- Verification passed after the predictor update: project structure check, rv32ui/beq external test, full ModelSim RTL regression, full rv32um suite, FPGA-like CoreMark 2-iteration smoke, FPGA-like CoreMark 50-iteration profile, and 100MHz Vivado implementation.
- FPGA-like FAST_MUL=0 / MUL_STAGES=1 CoreMark 50 remains stable at 30416890 measured CoreMark cycles, CPI 1.647223, mul_wait_stalls 1885351, div_wait_stalls 2871.
- This implementation flow is not yet a board-ready bitstream flow because real board pin constraints and any PS/AXI integration still need to be added.

## Pipelined Synchronous Load Response Update
- Added tb/tb_mem_pipeline.v plus tb/programs/mem_pipeline.hex. The new regression checks that independent synchronous-DMEM loads do not create global mem_wait stalls. It first failed on the old RTL with mem_wait_count=2, then passed after the load-response pipeline change.
- Reworked rtl/cpu_core.v so synchronous loads no longer freeze the whole pipeline through mem_wait. A load request records rd/funct3/reg_write metadata in a load-response side channel, while normal ALU/store instructions continue through MEM/WB.
- Added a second regfile write port in rtl/regfile.v for the delayed load response. Normal MEM/WB writeback has priority over the load-response port if both target the same architectural register.
- Updated rtl/csr_unit.v so minstret can increment by a 2-bit retire_count when normal MEM/WB and a load response retire in the same cycle.
- The first aggressive implementation forwarded dmem_rdata directly into EX from the load-response path. It improved CoreMark 50 to 27121490 cycles, but failed 100MHz post-route timing at WNS -0.114 ns because the new path ran from DMEM BRAM output through EX logic.
- The final implementation removes same-cycle load-response EX forwarding and instead extends load-use interlock to cover EX/MEM loads. Independent instructions still proceed without mem_wait, but true load consumers wait until the regfile/read bypass can supply the load result without a BRAM-to-EX critical path.
- To recover final post-route margin, reduced the CPU local-history predictor from BHR_WIDTH=4 to BHR_WIDTH=3. This cuts the PHT from 2048x2 to 1024x2 and reduces LUTRAM from 128 to 64.
- Final FPGA-like FAST_MUL=0 / MUL_STAGES=1 CoreMark 50 result is 28843256 measured cycles, CPI 1.561506, mem_wait_stalls 0, load_use_stalls 3156654, mul_wait_stalls 1885351, div_wait_stalls 2871.
- Compared with the prior timing-clean baseline of 30416890 cycles, this saves 1573634 cycles, about 5.17%, while preserving 100MHz post-route timing.
- Final 100MHz post-route implementation passes with WNS 0.000 ns, TNS 0.000 ns, 0 failing endpoints, WHS 0.110 ns, and THS 0.000 ns. Resources are LUT 5577, LUTRAM 64, FF 7291, BRAM36 24, DSP48 12, and IOB 41.
- Verification passed: new mem-pipeline regression, full ModelSim RTL regression, rv32ui/beq external test, full rv32um suite, FPGA-like CoreMark 2, FPGA-like CoreMark 50, project structure check, and 100MHz Vivado implementation.

## Vivado Strategy Timing Margin Update
- Added optional implementation strategy directive arguments to scripts/vivado_impl.tcl and scripts/run_vivado_impl.ps1: place, phys_opt, route, and post-route phys_opt directives can now be selected from the PowerShell wrapper.
- Fixed scripts/run_vivado_impl.ps1 so benign Vivado stderr messages do not become PowerShell NativeCommandError failures before the wrapper can inspect LASTEXITCODE and generated reports.
- Reran fpga_coremark_top 100MHz implementation with Place=Explore, PhysOpt=AggressiveExplore, Route=Explore, and PostRoutePhysOpt=AggressiveExplore.
- The directed implementation passes post-route timing with WNS 0.090 ns, TNS 0.000 ns, 0 failing setup endpoints, WHS 0.087 ns, and THS 0.000 ns.
- Resource use is essentially unchanged: LUT 5579, LUTRAM 64, FF 7291, BRAM36 24, DSP48 12, and IOB 41.
- This is the better current implementation flow than the default strategy because it recovers a small but useful timing margin without changing RTL or CoreMark behavior.

## Multiplier Output Visibility Update
- Tightened tb/tb_multiplier.v so MUL_STAGES=1 now requires valid_o/result_o to become visible directly from the output pipeline stage. The old multiplier failed this regression by one cycle.
- Updated rtl/multiplier.v so valid_o/result_o are continuous outputs from the last valid/result pipeline registers instead of being registered for one extra cycle. The DSP/product/output pipeline is still preserved; the multiplier combinational product path is not moved back into EX.
- Added FastMul/MulStages parameters to scripts/run_riscv_test.ps1 and scripts/run_riscv_suite.ps1, so official RISC-V tests can cover the FPGA-like FAST_MUL=0 path directly.
- Verification passed: full ModelSim RTL regression, rv32um suite with FAST_MUL=0 / MUL_STAGES=1, FPGA-like CoreMark 2, FPGA-like CoreMark 50, project structure check, and 100MHz post-route Vivado implementation.
- FPGA-like FAST_MUL=0 / MUL_STAGES=1 CoreMark 50 improves from 28843256 to 28372056 measured cycles, saving 471200 cycles. Dynamic muls are 471335, so this is the expected one-cycle-per-MUL improvement.
- New CoreMark 50 CPI is 1.535996. mul_wait_stalls drop from 1885351 to 1414016; div_wait_stalls remain 2871 and load_use_stalls remain 3156654.
- 100MHz directed post-route implementation still passes with WNS 0.020 ns, TNS 0.000 ns, 0 failing setup endpoints, WHS 0.040 ns, and THS 0.000 ns.
- Post-route resources are LUT 5589, LUTRAM 64, FF 7258, BRAM36 24, DSP48 12, and IOB 41.

## Selective Load-Response Forwarding Update
- Added tb/tb_load_use_one_stall.v and wired it into scripts/run_modelsim.ps1. The new regression checks a true lw-to-consumer dependency and requires only one load-use hazard stall while preserving the correct result.
- The old conservative RTL failed this regression with load_use_stall_count=2, proving the test caught the intended behavior.
- Added a load-response forwarding source to rtl/hazard_unit.v and rtl/cpu_core.v. Ordinary ALU/store consumers can now advance after the first load-use stall and receive the registered load response through the EX forwarding mux.
- Rejected the unrestricted version that allowed branch/jump/M-extension consumers to use the same path. It improved CoreMark 50 to 26679765 cycles but failed/timed out in Vivado implementation, with route timing around WNS -0.365 ns before post-route phys_opt and DMEM-to-divider/front-end paths becoming critical.
- The final kept version uses a conservative second stall for branch, jump, and M-extension load consumers. This avoids pulling load-response data into PC redirect or multiply/divide control paths.
- Verification passed: new one-stall load-use regression, full ModelSim RTL regression, FPGA-like rv32um suite, FPGA-like CoreMark 2, FPGA-like CoreMark 50, project structure check, and 100MHz directed post-route Vivado implementation.
- FPGA-like FAST_MUL=0 / MUL_STAGES=1 CoreMark 50 improves from 28372056 to 27729615 measured cycles, saving 642441 cycles. CPI improves from 1.535996 to 1.501216.
- load_use_stalls drop from 3156654 to 2513677. mem_wait_stalls remain 0, mul_wait_stalls remain 1414016, and div_wait_stalls remain 2871.
- 100MHz directed post-route implementation passes with WNS 0.006 ns, TNS 0.000 ns, 0 failing setup endpoints, WHS 0.043 ns, and THS 0.000 ns.
- Post-route resources are LUT 5740, LUTRAM 64, FF 7253, BRAM36 24, DSP48 12, and IOB 41.

## Front-End Timing Experiment Update
- Tested disabling the local-history PHT path by setting the CPU branch predictor LOCAL_HISTORY parameter to 0. This was rejected: CoreMark 2 worsened from 1109160 to 1112095 measured cycles and branch_mispredict_flushes increased from 9780 to 10494, while directed 100MHz implementation did not improve timing margin.
- Tested changing branch_predictor predict_target_o to output the raw BTB target and letting cpu_core perform the only next-PC mux. ModelSim and CoreMark 2 still passed with unchanged cycles, but the directed 100MHz post-route implementation failed timing at WNS -0.271 ns.
- Reverted both front-end experiments. The current kept RTL remains the selective load-response forwarding point with LOCAL_HISTORY=1, BHR_WIDTH=3, and predict_target_o returning the actual predicted next PC.
- The failed raw-target experiment moved/expanded critical pressure across PC prediction, load-response/DMEM, and EX forwarding paths. The next useful optimization should target the DMEM/load-response-to-EX cone or create timing margin before adding more performance logic.

## Load-Use Hotspot Classification Update
- Fixed tb_external_program.v load-use pair reporting so second-cycle conservative stalls attribute the pair to the true EX/MEM load PC instead of the temporary ID/EX bubble/consumer PC.
- Reran current FPGA-like CoreMark 50 with FAST_MUL=0 / MUL_STAGES=1 and the fixed statistics. Architectural/performance results are unchanged: 27729615 measured cycles, CPI 1.501216, load_use_stalls 2513677.
- The current top load-use pairs are dominated by PC/control consumers, not ordinary ALU consumers:
  - 0000144c lbu -> 00001450 beqz: 559041 stalls
  - 00001478 lw -> 0000147c jr: 457601 stalls
  - 00000974 lw -> 00000978 beqz: 310000 stalls
  - 00000980 lh -> 00000984 bne: 300200 stalls
  - 00000968 lbu -> 0000096c bne: 292933 stalls
- Category totals across the 32 reported hotspot entries are branch 1609869, indirect/direct jump 460808, load-as-consumer 214954, simple ALU 206047, multiply 16211, and store 5788 stalls.
- This confirms that the remaining load-use performance headroom is mostly in load-to-branch/jump dependencies. Directly forwarding load_resp_data into those consumers was already rejected by post-route timing, so the next RTL optimization needs a real registered control-path redesign rather than another forwarding whitelist tweak.

## CoreMark Compiler Performance Update
- Added OptLevel and ExtraCFlags parameters to scripts/build_coremark.ps1 and scripts/run_coremark.ps1, then propagated the same parameters into scripts/prepare_coremark_fpga.ps1 and the FPGA image manifest.
- Benchmarked CoreMark compiler options on the current FPGA-like CPU configuration. The best tested option was -O3 -funroll-loops; 2-iteration CoreMark improved from the -Os baseline of 1109160 cycles to 769466 cycles.
- Made -O3 -funroll-loops the default CoreMark build configuration. The old size-oriented flow remains available by passing -OptLevel -Os -ExtraCFlags "".
- Reran 50-iteration CoreMark with the new default. The measured result is 19228682 cycles, CPI 1.341955, load_use_stalls 1772819, mul_wait_stalls 1409703, div_wait_stalls 33, and mem_wait_stalls 0.
- Compared with the prior -Os 50-iteration result of 27729615 cycles, this saves 8500933 cycles, about 30.66%, without changing CPU RTL.
- The new image remains well within the current memory parameters: IMEM 25576 bytes of 64KB and DMEM 3948 bytes of 32KB.
- Regenerated build/coremark/fpga smoke, ten_ms, and ten_sec images with -O3 -funroll-loops. The manifest records opt_level and extra_cflags for each image.
- Verification passed: default CoreMark 2, default CoreMark 50, project structure check, full ModelSim RTL regression, FPGA image preparation, and directed fpga_coremark_top 100MHz post-route implementation.
- Directed 100MHz post-route implementation still passes with WNS 0.006 ns, TNS 0.000 ns, 0 failing setup endpoints, WHS 0.043 ns, and THS 0.000 ns. Resources remain LUT 5740, LUTRAM 64, FF 7253, BRAM36 24, DSP48 12, and IOB 41.

## Registered Load-to-Control Replay Update
- Added directed regressions for load-to-branch and load-to-JALR one-stall behavior, then wired them into scripts/run_modelsim.ps1.
- Implemented a registered control replay path in rtl/cpu_core.v. Branch/JALR instructions that depend on a load response capture the resolved operands into replay registers and make the redirect decision from registered operands on the next cycle.
- Kept ordinary ALU/store load-response forwarding separate from control forwarding. The control compare path no longer directly consumes load_resp_data in the non-replay path.
- Added redirect_from_replay/replay_flush gating so replay-triggered wrong-path EX/MEM side effects are suppressed, while ordinary JAL/JALR link writes are preserved.
- Rejected the earlier conservative replay-stall variant because it recovered timing but erased the CoreMark cycle gain.
- Verification passed: full ModelSim RTL regression and CoreMark 50 with -O3 -funroll-loops.
- Current CoreMark 50 result is 18431390 measured cycles, CPI 1.280799, load_use_stalls 908368, branch_mispredict_flushes 174500, jump_flushes 67905, and jalr_flushes 5.
- Compared with the previous -O3/-funroll baseline of 19228682 measured cycles, this saves 797292 cycles, about 4.15%.
- Synthesis-only timing on fpga_coremark_top at 100MHz still reports WNS -0.908 ns. The remaining worst path is no longer load-to-control replay; it is DMEM BRAM output through normal load-response forwarding into ALU/ex_mem_alu_result.

## Huoyue UART SoC Bring-up Update
- Added a standalone UART TX module and a minimal `soc_top` for board bring-up. `soc_top` instantiates `cpu_core`, `imem`, `dmem`, and `uart_tx` directly, with DMEM at `0x0001_0000` and UART/status/pass/fail/cycle MMIO at `0x0002_0000` onward.
- Added `sw/uart_hello/uart_hello.hex` as the default `soc_top` IMEM image. The firmware polls UART ready, transmits `HI\n`, writes the pass register, and loops.
- Added `tb/tb_uart_tx.v` and `tb/tb_soc_uart_hello.v`, then wired them into `scripts/run_modelsim.ps1`.
- Added `constraints/tinyriscv_huoyue_uart.xdc` using the provided Huoyue board pins, and added `-Constraint huoyue_uart` support to synthesis/implementation wrappers.
- Verification passed: project structure check, full ModelSim RTL regression including the new UART/SoC tests, and synthesis-only Vivado run for `soc_top` with the Huoyue 50MHz XDC.
- Vivado synthesis result for `build/vivado_synth_soc_top_huoyue`: WNS 8.442 ns, WHS 0.189 ns, 0 failing setup/hold endpoints. Resources are LUT 5972, FF 7533, RAMB36 24, DSP48 12.

## Current CoreMark 100MHz Implementation Update
- Reran directed 100MHz implementation for `fpga_coremark_top` after the registered load-to-control replay optimization, using Place=Explore, PhysOpt=AggressiveExplore, Route=Explore, and PostRoutePhysOpt=AggressiveExplore.
- Implementation passed timing: post-route WNS 0.015 ns, TNS 0.000 ns, 0 failing setup endpoints, WHS 0.011 ns, and PW slack 3.750 ns.
- Post-route resources are LUT 5867, FF 7427, BRAM36 24, and DSP48 12.
- The worst setup path is now `u_cpu_top/u_core/pc_reg[2]_rep__4/C` to `u_cpu_top/u_core/pc_reg[3]_rep/D`, not the synthesis-only DMEM load-response path. It has 9.811 ns data path delay, 12 logic levels, and 6.753 ns routing delay.
- Decision: do not start registered load-response-to-EX replay at this checkpoint. Current RTL closes 100MHz post-route, and that replay would likely reduce the CoreMark gain from one-stall ALU load forwarding.

## soc_top Timing/Performance Optimization Update
- Added `scripts/check_vivado_qor.ps1` to gate Vivado memory QoR. The gate allows the small branch-predictor LUTRAM but requires DMEM to be reported as RAMB36E1 and total block RAM to stay at or above the expected threshold.
- Confirmed the old `soc_top` reports fail the QoR gate: `build/vivado_synth_soc_top_huoyue_bram3` reports `RAMD64E=5696`.
- Reworked the BRAM-friendly branch of `rtl/dmem.v` so active UART loader writes and CPU stores share one byte-enable write template. This fixed the DMEM inference issue for `soc_top`.
- Added `scripts/run_timing_sweep.ps1` for frequency/strategy sweeps with generated temporary XDC files and CSV output, plus `scripts/report_ram_from_checkpoint.tcl` to generate RAM utilization reports from an existing checkpoint.
- Updated Vivado wrappers to support absolute output paths and custom `-XdcPath`. Updated implementation Tcl to emit RAM utilization reports at post-synth and post-route.
- Verified current RTL/scripts with project structure check, full ModelSim regression, QoR gate on the post-route implementation, and a 50 MHz `soc_top` timing sweep smoke run.
- The 50 MHz `soc_top` default implementation generated `build/timing_sweep_soc_top_smoke3/soc_top_50MHz_default/soc_top.bit`. CSV result: WNS 4.780 ns, TNS 0.000 ns, setup failures 0, hold failures 0, LUT 6219, FF 7859, RAMB36 24, DSP48 12.

## soc_top 100MHz-Only Update
- User narrowed timing work to 100 MHz only; no more 50/75 MHz sweeps were run.
- Ran `soc_top` at 100 MHz for default and Explore/AggressiveExplore strategies. Default fails timing with WNS -0.366 ns, TNS -23.243 ns, and 153 setup failing endpoints. Explore passes with WNS 0.001 ns, TNS 0.000 ns, and 0 setup/hold failing endpoints.
- The current usable 100 MHz `soc_top` bitstream is `build/timing_sweep_soc_top_100m/soc_top_100MHz_explore/soc_top.bit`.
- Patched `scripts/run_timing_sweep.ps1` so future CSV rows mark negative WNS or nonzero setup/hold failures as `timing_fail` instead of `pass`.
- Tested a small `redirect_from_replay` timing split in `rtl/cpu_core.v`; full ModelSim passed and a temporary 100 MHz Explore implementation improved WNS to 0.007 ns, but CoreMark external simulation timed out, so the RTL change was reverted.
- Root-caused the CoreMark timeout to UART polling at `0x00020004` in the external `cpu_top` harness. Added `COREMARK_UART_OUTPUT` so simulation builds do not touch UART MMIO, while FPGA images still print CoreMark summaries over UART.
- Verification after the CoreMark UART split passed: `scripts/check_project.ps1`, full `scripts/run_modelsim.ps1`, `scripts/run_coremark.ps1 -Iterations 2 -TotalDataSize 2000 -MaxCycles 5000000 -FastMul 0 -MulStages 1 -PerfStats`, and `scripts/prepare_coremark_fpga.ps1 -CpuHz 100000000 -SmokeIterations 2 -TenMsIterations 2 -TenSecIterations 1900`.
- The repaired CoreMark 2 FPGA-like simulation result is 737581 measured cycles, CPI 1.250023. FPGA UART-output images build with `-DCOREMARK_UART_OUTPUT=1`; smoke/ten_ms IMEM is 32356 B and ten_sec IMEM is 32384 B, still within 64 KB.

## soc_top Timing Optimization Continuation
- Reran the current `soc_top` 100 MHz Explore/AggressiveExplore implementation after the CoreMark UART output split. Timing still passes narrowly with WNS 0.001 ns, TNS 0.000 ns, 0 setup/hold failing endpoints, LUT 6348, FF 7865, RAMB36 24, DSP48 12.
- The current worst setup path is `u_core/ex_mem_rd_reg[1]` to `u_core/redirect_from_replay_reg/D`, with 9.924 ns data path delay, 14 logic levels, and 70.767% route delay.
- Tried replacing `redirect_from_replay <= redirect_detect && ctrl_replay_valid` with `redirect_from_replay <= ctrl_replay_valid`. Functional checks passed (`check_project`, full ModelSim, CoreMark 2, CoreMark 50), and CoreMark 50 stayed at 18431390 cycles / CPI 1.280797.
- Rejected that replay-tag timing experiment because the 100 MHz Explore implementation failed timing: WNS -0.385 ns, TNS -28.114 ns, 133 setup failing endpoints. The worst path moved to branch predictor update control (`ex_mem_rd_reg[2]` to `update_taken_q_reg_rep__5/D`), also route dominated.
- Reverted `rtl/cpu_core.v` back to the verified baseline assignment `redirect_from_replay <= redirect_detect && ctrl_replay_valid`.

## soc_top 100MHz Strategy Update
- Checked two newer 100 MHz implementation strategy outputs on the restored RTL baseline.
- `build/vivado_impl_soc_top_100m_extra_net_delay` passes post-route timing with WNS 0.000 ns, TNS 0.000 ns, WHS 0.029 ns, LUT 6360, FF 7868, RAMB36 24, DSP48 12. Its worst setup path is `u_dmem/gen_bram_friendly.mem_bram_reg_2_0/CLKBWRCLK` to `u_core/u_divider/quotient_reg[17]/R`, with 9.448 ns data path delay and 7 logic levels.
- `build/vivado_impl_soc_top_100m_alt_spread` is the better current 100 MHz result: WNS 0.013 ns, TNS 0.000 ns, WHS 0.013 ns, LUT 6369, FF 7865, RAMB36 24, DSP48 12.
- The `alt_spread` worst setup path is `u_dmem/gen_bram_friendly.mem_bram_reg_0_1/CLKBWRCLK` to `u_core/ex_mem_alu_result_reg[0]/D`, with 9.947 ns data path delay, 12 logic levels, and 56.459% route delay.
- Ran the QoR gate on `alt_spread`: `QoR OK: TOP=soc_top RAMD64E=64 BlockRAM=24`. RAM utilization confirms IMEM and DMEM use RAMB36E1; the remaining RAMD64E=64 is the branch predictor LUTRAM.
- Current 100 MHz board candidate bitstream is `build/vivado_impl_soc_top_100m_alt_spread/soc_top.bit`. This is better than the previous Explore WNS 0.001 ns bitstream, but the timing margin remains fragile.

## soc_top Floorplan Hook Update
- Added a small implementation plan at `docs/superpowers/plans/2026-05-05-soc-top-floorplan-hook.md`.
- Added a RED/GREEN hook check in `scripts/check_floorplan_hook.ps1`. The RED run failed as expected because `scripts/run_vivado_impl.ps1` did not yet expose `-FloorplanTcl`.
- Implemented optional floorplan hook plumbing through `scripts/run_vivado_impl.ps1`, `scripts/vivado_impl.tcl`, and `scripts/run_timing_sweep.ps1`. The floorplan Tcl is sourced after `opt_design` and before `place_design`.
- Added `constraints/floorplan_soc_top_light.tcl`, a broad pblock experiment for `u_core` and `u_dmem` that derives legal site ranges from the target device.
- Verification passed for the hook itself: `scripts/check_floorplan_hook.ps1` prints `Floorplan hook OK`, and `scripts/check_project.ps1` prints `Project structure OK`.
- A first manual floorplan implementation command used `-Constraint huoyue_uart`, which is the 50 MHz board XDC. Its WNS 4.040 ns result is ignored for 100 MHz analysis.
- Reran through `scripts/run_timing_sweep.ps1 -FrequenciesMHz 100 -Strategies alt_spread -FloorplanTcl constraints\floorplan_soc_top_light.tcl` so the generated XDC uses a 10 ns clock.
- Correct 100 MHz floorplan run: `build/timing_sweep_soc_top_100m_floorplan_light/soc_top_100MHz_alt_spread`. Timing passes but only at WNS 0.000 ns, TNS 0.000 ns, WHS 0.043 ns, LUT 6360, FF 7860, RAMB36 24, DSP48 12.
- The floorplan run worst setup path is `u_core/ex_mem_rd_reg[1]` to `u_core/ex_mem_alu_result_reg[0]/D`, with 9.997 ns data path delay, 11 logic levels, and 76.493% route delay.
- QoR gate passed on the floorplan run: `QoR OK: TOP=soc_top RAMD64E=64 BlockRAM=24`.
- Decision: keep the hook infrastructure, but do not replace the current board baseline. The no-floorplan `build/vivado_impl_soc_top_100m_alt_spread/soc_top.bit` remains better at WNS 0.013 ns.

## Load Response EX Boundary Update
- Wrote the design spec at `docs/superpowers/specs/2026-05-05-load-response-ex-boundary-design.md` and implementation plan at `docs/superpowers/plans/2026-05-05-load-response-ex-boundary.md`.
- Added `tb/tb_load_use_timing_safe.v` and wired it into `scripts/run_modelsim.ps1`. The RED run failed at elaboration with `Module parameter 'ENABLE_LOAD_RESP_EX_FORWARD' not found for override`, proving the timing-safe boundary was not implemented yet.
- Added `ENABLE_LOAD_RESP_EX_FORWARD` through `rtl/cpu_core.v`, `rtl/cpu_top.v`, `rtl/fpga_coremark_top.v`, and `rtl/soc_top.v`. `cpu_top` keeps default performance mode at 1; FPGA-oriented `fpga_coremark_top` and `soc_top` default to timing-safe mode 0.
- Updated `rtl/hazard_unit.v` so ordinary EX consumers take a second stall when load-response EX forwarding is disabled, while branch/JALR consumers still use the registered load-to-control replay path.
- Split ordinary EX forwarding from replay-capture forwarding in `rtl/cpu_core.v`. With the parameter disabled, `load_resp_data` no longer feeds the ordinary ALU/M/DIV/store/ex_mem result path, but it can still be captured into control replay registers.
- Added `LoadRespExForward` pass-through to CoreMark and RISC-V external simulation scripts.
- Verification passed: project structure check, full ModelSim RTL regression, rv32um with `FastMul=0 MulStages=1 LoadRespExForward=0`, and rv32ui applicable tests excluding unsupported `fence_i` with `LoadRespExForward=0`.
- CoreMark timing-safe 2-iteration result: 760135 measured cycles, CPI 1.288246, load_use_stalls 60483.
- CoreMark timing-safe 50-iteration result: 18995096 measured cycles, CPI 1.319969, load_use_stalls 1482544, branch_mispredict_flushes 174490, jump_flushes 67905, jalr_flushes 5.
- Compared with the previous load-to-control replay performance point of 18431390 cycles, the timing-safe EX boundary costs 563706 cycles, about 3.06%, while preserving the control replay improvement.
- 100 MHz `soc_top` `alt_spread` implementation passes with WNS 0.022 ns, TNS 0.000 ns, 0 setup failures, WHS 0.019 ns, LUT 6271, FF 7858, RAMB36 24, DSP48 12. Bitstream: `build/timing_sweep_soc_top_100m_loadresp_boundary/soc_top_100MHz_alt_spread/soc_top.bit`.
- QoR gate passed on the new implementation: `QoR OK: TOP=soc_top RAMD64E=64 BlockRAM=24`.
- The new worst setup path is `u_core/mem_wb_rd_reg[2]/C` to `u_core/u_branch_predictor/update_taken_q_reg_rep__5/D`, with data path delay 9.883 ns, route 7.193 ns, and 13 logic levels. The previous DMEM BRAM to `ex_mem_alu_result` worst path is no longer the top path.

## Branch Predictor Resource Profile Update
- Added branch predictor resource parameters through `cpu_core`, `cpu_top`, `soc_top`, `fpga_coremark_top`, `tb_external_program`, and the CoreMark/RISC-V simulation scripts.
- FPGA-oriented tops now default to `BP_LOCAL_HISTORY=0`, `BP_BHT_DEPTH=64`, `BP_BHR_WIDTH=2`, and `BP_BTB_DEPTH=32`. Generic `cpu_top` keeps the larger local-history predictor as an optional performance configuration.
- Reworked `branch_predictor.v` so the BHR/PHT local-history tables are not instantiated when `LOCAL_HISTORY=0`.
- Added `scripts/check_bp_resource_profile.ps1` to guard the intended resource profile.
- Verification passed: branch-predictor resource profile check, project structure check, full ModelSim RTL regression, full rv32um suite with FPGA-like parameters, applicable rv32ui suite excluding unsupported `fence_i`, CoreMark 2/50, QoR gate, and `soc_top` 100 MHz `alt_spread` implementation.
- CoreMark 50 with the resource profile is 19341937 measured cycles, CPI 1.337589. At 100 MHz and 50 iterations this is about 2.585 CoreMark/MHz, above the 2.5 target.
- `soc_top` 100 MHz `alt_spread` now passes with WNS 0.203 ns, TNS 0.000 ns, LUT 4740, FF 5210, RAMB36 24, DSP48 12. Bitstream: `build/timing_sweep_soc_top_100m_bp_resource/soc_top_100MHz_alt_spread/soc_top.bit`.
- This is the first verified point that satisfies both current hard constraints: LUT below 5000 and CoreMark/MHz above 2.5.

## Branch Predictor Parameter Scan Update
- Added generic override support to `scripts/run_vivado_impl.ps1`, `scripts/vivado_impl.tcl`, and `scripts/run_timing_sweep.ps1`, with `scripts/check_vivado_generic_override.ps1` guarding the interface. This allows Vivado runs to override top parameters without editing RTL defaults.
- CoreMark 50 scan with local history disabled:
  - `BHT=64 BTB=16`: 19500682 measured cycles, about 2.564 CoreMark/MHz.
  - `BHT=64 BTB=32`: 19341937 measured cycles, about 2.585 CoreMark/MHz.
  - `BHT=64 BTB=64`: 19192242 measured cycles, about 2.605 CoreMark/MHz.
  - `BHT=128 BTB=32`: 19354447 measured cycles, about 2.583 CoreMark/MHz.
- 100 MHz `soc_top` `alt_spread` implementation candidates:
  - `BHT=64 BTB=16`: passes timing, WNS 0.186 ns, LUT 4327, FF 4167, RAMB36 24, DSP48 12.
  - `BHT=64 BTB=64`: passes timing, WNS 0.089 ns, LUT 5313, FF 7316, RAMB36 24, DSP48 12, but violates the current LUT < 5000 constraint.
- Decision: keep the current default `BHT=64 BTB=32` as the best balance. Use `BHT=64 BTB=16` only if later board integration consumes more LUT and threatens the 5000-LUT budget.

## CoreMark Compiler Flag Scan Update
- Continued the zero-RTL-risk compiler flag scan on the accepted resource profile: `FAST_MUL=0`, `MUL_STAGES=1`, `ENABLE_LOAD_RESP_EX_FORWARD=0`, `BP_LOCAL_HISTORY=0`, `BHT=64`, `BTB=32`.
- A first attempt to run multiple CoreMark flag variants in parallel was discarded because `run_coremark.ps1` shares `build/coremark` outputs. The accepted results below were rerun sequentially.
- 2-iteration quick-screen results:
  - default `-O3 -funroll-loops`: 773627 measured cycles, IMEM 25592 B, DMEM 3948 B.
  - `-Ofast -funroll-loops`: 773627 measured cycles, IMEM 25592 B, DMEM 3948 B.
  - `-O3 -funroll-loops -frename-registers`: 773627 measured cycles, IMEM 25592 B, DMEM 3948 B.
  - `-O3 -funroll-loops -fweb -frename-registers`: 773627 measured cycles, IMEM 25592 B, DMEM 3948 B.
  - `-O3 -funroll-loops -falign-functions=16 -falign-loops=16 -falign-jumps=16 -falign-labels=16`: 835912 measured cycles, IMEM 29692 B, DMEM 3948 B.
- Decision: keep the existing default `-O3 -funroll-loops`. No candidate beat it in the quick screen, so no extra 50-iteration run was needed.
- Verification after the scan passed: `scripts/check_project.ps1`, `scripts/check_bp_resource_profile.ps1`, and `scripts/check_vivado_generic_override.ps1`.

## soc_top Real 100MHz Board Clock Update
- Added `docs/superpowers/plans/2026-05-05-soc-top-mmcm-100mhz.md` to track the board-clock implementation steps.
- Added `scripts/check_soc_board_clock.ps1`. Its RED run failed as expected because `rtl/clk_gen_50m_to_100m.v` did not exist yet.
- Added `rtl/clk_gen_50m_to_100m.v`, which bypasses in RTL simulation and instantiates `MMCME2_BASE` plus BUFGs in synthesis to generate 100MHz from the 50MHz Huoyue `sys_clk`.
- Updated `rtl/soc_top.v` to use the generated 100MHz clock, hold reset until `clk_locked`, and default `UART_CLKS_PER_BIT` to 868 for 115200 baud at 100MHz.
- Updated ModelSim and Vivado source lists, added clock reports to Vivado Tcl output, and added the new files to `scripts/check_project.ps1`.
- Verification passed: `scripts/check_soc_board_clock.ps1`, `scripts/check_project.ps1`, and full `scripts/run_modelsim.ps1`.
- Real board-XDC Vivado implementation passed: `build/vivado_impl_soc_top_huoyue_100m_mmcm/soc_top.bit` with WNS 0.236 ns, TNS 0.000 ns, WHS 0.018 ns, LUT 4741, FF 5210, BRAM36 24, DSP48 12, BUFG 2, MMCME2_ADV 1.
- Clock report confirms `sys_clk` at 20.000 ns / 50MHz and generated `clkout0_mmcm` at 10.000 ns / 100MHz.
- QoR gate passed after correcting the command parameter name: `QoR OK: TOP=soc_top RAMD64E=0 BlockRAM=24`.

## UART Download Reset-Start Update
- Added `tb/programs/soc_fail.hex` and `tb/tb_soc_uart_reset_start.v` to reproduce the board issue. The RED run failed with `CPU ran while UART download key was active`, proving the old SoC ignored the download key and could run before the terminal was open.
- Changed `soc_top` startup control: `BOOT_FROM_INIT` defaults to 1 for normal reset boot, `uart_debug_key_n=0` clears `run_armed_q`, and START is consumed only as a rising pulse outside download mode.
- Changed `scripts/send_uart_image.ps1` so it defaults to sending IMEM/DMEM only. It now prints instructions to open the serial terminal, release `uart_debug_key_n`, and press reset. The old behavior is kept behind `-StartAfterDownload`.
- Added `scripts/check_soc_reset_start_flow.ps1` and updated `scripts/check_soc_board_clock.ps1` for the new `run_armed_q` reset gate.
- Verification passed: targeted GREEN run of `tb_soc_uart_reset_start`, `check_project`, `check_soc_board_clock`, `check_soc_reset_start_flow`, and full `run_modelsim`.
- Reran real Huoyue board-XDC implementation after the reset-start change. Final bitstream: `build/vivado_impl_soc_top_huoyue_100m_mmcm_reset_start/soc_top.bit`.
- Final timing/resource result: WNS 0.018 ns, TNS 0.000 ns, WHS 0.032 ns, LUT 4750, FF 5212, BRAM36 24, DSP48 12, BUFG 2, MMCME2_ADV 1.
- Final clock report still confirms `sys_clk` 50MHz and generated `clkout0_mmcm` 100MHz. QoR gate passed with `RAMD64E=0 BlockRAM=24`.

## Nonblocking Slow Multiplier Update
- Explored FAST_MUL=1 first. It improves CoreMark 50 to 17932537 cycles on the resource profile, but the Huoyue 100MHz implementation fails timing badly at WNS -3.774 ns, so it is not an acceptable board path.
- Added `tb/tb_mul_nonblocking.v` and `tb/programs/mul_nonblocking.hex`. The RED run on old behavior failed with `mul_wait_count=3`; the GREEN implementation now passes with zero wait in that regression.
- Implemented a single in-flight nonblocking slow multiplier in `rtl/cpu_core.v`, with new hazard inputs in `rtl/hazard_unit.v`.
- Reworked the first implementation to avoid a third regfile write port: `rtl/regfile.v` is back to two write ports, and multiplier response shares the load-response writeback port through `shared_wb2_*`.
- Verification passed after the shared writeback refactor:
  - `scripts/run_modelsim.ps1`
  - `scripts/run_riscv_suite.ps1 -Suite rv32um -FastMul 0 -MulStages 1 -LoadRespExForward 0 -BpLocalHistory 0 -BpBhtDepth 64 -BpBhrWidth 2 -BpBtbDepth 32`
  - applicable `rv32ui` list excluding `fence_i` with the same FPGA resource parameters
  - CoreMark 2: 734747 measured cycles, CPI 1.239172, mul_wait_stalls 145
  - CoreMark 50: 18369937 measured cycles, CPI 1.270371, mul_wait_stalls 3601
  - static checks: project, BP resource profile, board clock, reset-start
  - Vivado implementation and QoR on `build/vivado_impl_soc_top_huoyue_100m_nonblocking_mul_shared_wb`
- 100MHz Huoyue implementation result: WNS 0.106 ns, TNS 0.000 ns, WHS 0.035 ns, LUT 5444, FF 5278, BRAM36 24, DSP48 12, BUFG 2, MMCME2_ADV 1.
- QoR result: `QoR OK: TOP=soc_top RAMD64E=0 BlockRAM=24`.
- Current bitstream: `build/vivado_impl_soc_top_huoyue_100m_nonblocking_mul_shared_wb/soc_top.bit`.

## Load Response EX Forward Candidate Update
- Re-tested the existing performance-mode load-response EX forwarding as a parameter-only candidate on top of the accepted nonblocking slow multiplier and trimmed predictor profile. No RTL default was changed.
- CoreMark 2 with `ENABLE_LOAD_RESP_EX_FORWARD=1` measured 712193 cycles, CPI 1.201134, load_use_stalls 54191, and mul_wait_stalls 145.
- CoreMark 50 measured 17806231 cycles, CPI 1.231388, load_use_stalls 1342523, mul_wait_stalls 3601, branch_mispredict_flushes 243973, and jump_flushes 67905.
- This is about 2.808 CoreMark/MHz at 100MHz. It improves Phase 36 by 563706 cycles, about 3.07%, but still needs roughly another 1.14M cycles of reduction on the 50-iteration run to reach 3.0.
- Functional regression passed for this parameter set: full `rv32um` and applicable `rv32ui` excluding unsupported `fence_i`.
- A Huoyue 100MHz `AltSpreadLogic_high` implementation generated a bitstream but failed setup timing at WNS -0.041 ns, so it is rejected.
- A Huoyue 100MHz `ExtraNetDelay_high` implementation passed timing: WNS 0.013 ns, TNS 0.000 ns, WHS 0.034 ns, LUT 5513, FF 5288, BRAM36 24, DSP48 12, BUFGCTRL 4, MMCME2_ADV 1.
- QoR passed on the accepted implementation: `QoR OK: TOP=soc_top RAMD64E=0 BlockRAM=24`.
- Current fastest measured candidate bitstream: `build/vivado_impl_soc_top_huoyue_100m_nonblocking_mul_loadresp_exfwd_extra_net_delay/soc_top.bit`.

## LR1 Branch Predictor Capacity Scan Update
- Restored project context from the planning files. `session-catchup.py` could not run because this machine reported `python.exe` cannot be accessed by the system; the planning files themselves were readable and current.
- Ran a parameter-only CoreMark quick screen on top of the LR1 nonblocking-multiplier candidate. No RTL default was changed.
- 2-iteration quick-screen results:
  - `LOCAL_HISTORY=0 BHT=64 BHR=2 BTB=64`: 706166 cycles, branch_mispredict_flushes 9019.
  - `LOCAL_HISTORY=1 BHT=64 BHR=2 BTB=32`: 705536 cycles, branch_mispredict_flushes 8884.
  - `LOCAL_HISTORY=1 BHT=64 BHR=2 BTB=64`: 699479 cycles, branch_mispredict_flushes 7615.
  - `LOCAL_HISTORY=1 BHT=128 BHR=3 BTB=64`: 698701 cycles, branch_mispredict_flushes 7391.
- 50-iteration result for the small local-history candidate `LOCAL_HISTORY=1 BHT=64 BHR=2 BTB=64`: 17487089 cycles, CPI 1.214696, branch_mispredict_flushes 180058, jump_flushes 67905. This is about 2.859252 CoreMark/MHz.
- 50-iteration result for the large local-history candidate `LOCAL_HISTORY=1 BHT=128 BHR=3 BTB=64`: 17459390 cycles, CPI 1.213253, branch_mispredict_flushes 174490, jump_flushes 67905. This is about 2.863788 CoreMark/MHz.
- Both local-history candidates still miss the 3.0 target. The accepted small candidate needs 820422 fewer cycles, about another 4.692%, on the 50-iteration run.
- Official tests passed for the large local-history candidate, but its Huoyue 100MHz implementation failed timing: WNS -0.093 ns, TNS -1.389 ns, 38 setup failing endpoints. Worst setup path was `u_core/ex_mem_rd_reg[2]/C` to `u_core/u_divider/result_o_reg[8]/CE`, with 9.788 ns data path delay and 83.940% route delay. This candidate is rejected.
- The first Vivado command for the large candidate used repeated `-Generic` parameters and failed before Vivado started. Re-ran with the script-supported array syntax.
- The small local-history candidate passed Huoyue 100MHz implementation with `ExtraNetDelay_high`: WNS 0.004 ns, TNS 0.000 ns, WHS 0.035 ns, LUT 6332, FF 7499, BRAM36 24, DSP48 12.
- QoR passed for the small local-history candidate: `QoR OK: TOP=soc_top RAMD64E=16 BlockRAM=24`. The clock report confirms `sys_clk=20 ns` and generated `clkout0_mmcm=10 ns`.
- The small candidate's worst setup path is `u_dmem/gen_bram_friendly.mem_bram_reg_3_0/CLKBWRCLK` to `u_core/ex_mem_alu_result_reg[0]/D`, with 9.875 ns data path delay, 8 logic levels, 39.139% logic delay, and 60.861% route delay.
- Official tests passed for the accepted small local-history candidate: full `rv32um` and applicable `rv32ui` excluding unsupported `fence_i`.
- Current fastest timing-clean bitstream: `build/vivado_impl_soc_top_huoyue_100m_nonblocking_mul_loadresp_exfwd_localhist64_btb64/soc_top.bit`.

## Load Control Early Replay Update
- Implemented optional `ENABLE_LOAD_CONTROL_EARLY_REPLAY` to capture `load -> branch/JALR` consumers into a pending replay record and complete them from a later registered load response.
- Added parameter plumbing through `hazard_unit`, `cpu_core`, `cpu_top`, `fpga_coremark_top`, `soc_top`, `tb_external_program`, and CoreMark/RISC-V scripts.
- Added strict and bug-regression tests: `tb_load_branch_zero_stall`, `tb_load_jalr_zero_stall`, `tb_load_branch_same_rd_replay`, and `tb_load_branch_wrong_path_wb`.
- Found and fixed two correctness bugs during RED/GREEN testing:
  - same-`rd` pending replay could consume an older visible `load_resp_data`; fixed by forcing the pending replay to wait for a later matching response.
  - replay flush could allow a wrong-path MEM/WB write to commit; fixed by gating MEM/WB and load-response writeback/retire on replay-triggered flush.
- Rejected a broad control replay front-end conflict stall after it hurt CoreMark; restored the original narrower `control_conflict_stall`.
- Verification passed:
  - `scripts/run_modelsim.ps1`
  - `scripts/check_project.ps1`
  - `scripts/run_riscv_suite.ps1 -Suite rv32um ... -LoadControlEarlyReplay 1`
  - applicable `rv32ui` excluding `fence_i` with `LoadControlEarlyReplay 1`
- CoreMark 2 after final revert: disabled `704487` cycles, enabled `696597` cycles.
- CoreMark 50 after final revert: disabled `17612289` cycles, enabled `17414991` cycles. The feature improves this RTL point by `197298` cycles, about `1.12%`.
- Compared with the Phase 38 accepted small local-history candidate (`17487089` cycles), the new simulation candidate saves `72098` cycles, about `0.41%`.
- Huoyue 100MHz implementation attempts:
  - `build/vivado_impl_soc_top_huoyue_100m_nonblocking_mul_loadresp_exfwd_localhist64_btb64_lctrl_early_replay` with `ExtraNetDelay_high` generated a bitstream but failed timing: WNS -0.011 ns, TNS -0.016 ns, 2 setup failing endpoints. QoR passed with `RAMD64E=16 BlockRAM=24`, LUT 6341, FF 7679, BRAM36 24, DSP48 12.
  - `build/vivado_impl_soc_top_huoyue_100m_nonblocking_mul_loadresp_exfwd_localhist64_btb64_lctrl_early_replay_alt_spread` failed timing worse: WNS -0.086 ns, TNS -0.363 ns, 8 setup failing endpoints.
  - A small `redirect_from_replay` tag-boundary experiment passed `check_project`, full ModelSim, and CoreMark 2, but worsened implementation to WNS -0.220 ns, so the RTL change was reverted.
- Current next step: try a targeted floorplan around replay/redirect-related cells. If it fails, do not replace the Phase 38 timing-clean bitstream.

## Source Operand Hazard Mask Update
- Targeted Phase 39 timing rescue attempts did not close timing. The replay-focused pblock failed at WNS -0.173 ns, and the no-pblock Explore run failed at WNS -0.156 ns.
- Tested `MUL_STAGES=2` as a parameter-only timing candidate, but rejected it because CoreMark 2 worsened to 710637 cycles versus 696597 cycles for `MUL_STAGES=1`.
- Found a real false load-use stall source: hazard comparisons used raw `instr[19:15]`/`instr[24:20]` even for instructions that do not read rs1/rs2.
- Added `tb_load_false_dep_no_stall` and `tb/programs/load_false_dep.hex`. The old RTL failed with one false stall after `lw` followed by `lui`; the new RTL passes with zero false stalls.
- Implemented decode-side source-use masking in `rtl/cpu_core.v` for load-use, early control replay dependency checks, and multiplier scoreboard dependency checks.
- Verification passed: full `scripts/run_modelsim.ps1`, `scripts/check_project.ps1`, full `rv32um`, and applicable `rv32ui` excluding `fence_i`.
- CoreMark with early replay enabled improved modestly:
  - 2 iterations: 696597 -> 695145 cycles.
  - 50 iterations: 17414991 -> 17378691 cycles.
  - New estimated score at 100MHz/50 iterations is about 2.877 CoreMark/MHz.
- Added `scripts/vivado_route_from_place.tcl` and used it to resume the timed-out early-replay implementation from `post_place.dcp`.
- The resumed early-replay + source-mask Huoyue 100MHz implementation generated a bitstream but failed timing at WNS -0.376 ns, TNS -32.883 ns. QoR passed with `RAMD64E=16 BlockRAM=24`, so this is a timing failure, not a memory inference issue.
- Current accepted board bitstream remains Phase 38. The source-use mask is functionally and performance-positive, but a timing-clean board build must be established separately before replacing the accepted bitstream.

## Current RTL No-Early-Replay Timing Fallback Update
- Built the current source tree with early replay disabled and the Phase 38-style performance parameters: `FAST_MUL=0`, `MUL_STAGES=1`, `ENABLE_LOAD_RESP_EX_FORWARD=1`, `ENABLE_LOAD_CONTROL_EARLY_REPLAY=0`, `BP_LOCAL_HISTORY=1`, `BP_BHT_DEPTH=64`, `BP_BHR_WIDTH=2`, `BP_BTB_DEPTH=64`.
- `ExtraNetDelay_high` generated a bitstream but failed setup narrowly: WNS -0.026 ns, TNS -0.160 ns, 7 failing endpoints. QoR was correct with `RAMD64E=16 BlockRAM=24`, LUT 6312, FF 7529, BRAM36 24, DSP48 12.
- `AltSpreadLogic_high` passed timing: WNS 0.000 ns, TNS 0.000 ns, WHS 0.037 ns, LUT 6337, FF 7537, BRAM36 24, DSP48 12. QoR was correct with `RAMD64E=16 BlockRAM=24`.
- Timing-clean current-source bitstream: `build/vivado_impl_soc_top_huoyue_100m_srcmask_no_lctrl_alt_spread/soc_top.bit`.
- CoreMark 50 with early replay disabled on the current source tree measured 17575989 cycles. At 100MHz and 50 iterations this is about 2.84479 CoreMark/MHz.
- This current-source fallback is functionally useful, but it is slower than the older Phase 38 accepted artifact by 88900 cycles. The fastest measured timing-clean board bitstream therefore remains `build/vivado_impl_soc_top_huoyue_100m_nonblocking_mul_loadresp_exfwd_localhist64_btb64/soc_top.bit` unless the latest RTL itself is required.

## CoreMark Hotspot Attribution Update
- Fixed simulation-only hotspot accounting in `tb/tb_external_program.v`. The old top-table replacement path incorrectly incremented the evicted slot's count for a new PC; it now resets new entries to count 1. Load-use hotspot capacity was expanded to 256 entries.
- Added branch and jump flush PC hotspot tables in `tb/tb_external_program.v`.
- Added `scripts/run_coremark_hotspots.ps1`. It wraps `run_coremark.ps1 -PerfStats`, writes raw logs and sorted CSVs, and annotates PCs with function names from `riscv-none-elf-nm`.
- Generated current hotspot outputs:
  - `build/coremark/hotspots/iter2_lctrl1_bht64_bhr2_btb64.summary.txt`
  - `build/coremark/hotspots/iter2_lctrl0_bht64_bhr2_btb64.summary.txt`
  - matching `.load_use.csv`, `.load_use_pair.csv`, `.jalr.csv`, `.jalr_pair.csv`, `.branch_mispredict.csv`, and `.jump_flush.csv` files.
- 2-iteration early-replay enabled result: 695145 cycles, 45060 load-use stalls, 7615 branch-mispredict flushes, 5255 jump flushes, 5 JALR flushes.
- 2-iteration early-replay disabled result: 703035 cycles, 55017 load-use stalls, 7615 branch-mispredict flushes, 5255 jump flushes, 5 JALR flushes.
- Top early-replay load-use pairs:
  - `core_bench_list+0x134 -> +0x138`: 5978
  - `core_bench_list+0x7c -> +0x80`: 5946
  - `core_bench_list+0x6c -> +0x70`: 5942
  - `core_bench_list+0x140 -> +0x144`: 5800
  - `core_state_transition+0xd4 -> +0xd8`: 3144
  - `matrix_test+0xa24/+0xa1c/+0xa2c -> +0xa28/+0xa20/+0xa30`: 2592 each
- Top branch/jump flush PCs are mostly in `core_state_transition`, but their total counts are far smaller than load-use stalls. Even perfect branch/jump cleanup would not close the remaining 3.0 target gap by itself.
- Verification after these changes:
  - `scripts/check_project.ps1`: pass.
  - `scripts/run_coremark_hotspots.ps1 -Iterations 2 -LoadControlEarlyReplay 1`: pass.
  - `scripts/run_coremark_hotspots.ps1 -Iterations 2 -LoadControlEarlyReplay 0`: pass.
- full `scripts/run_modelsim.ps1`: pass.

## ID Load Early Read Update
- Implemented optional `ENABLE_ID_LOAD_EARLY_READ` and parameter plumbing through CPU tops and ModelSim/CoreMark/RISC-V scripts. The feature defaults off.
- Added `tb_load_use_zero_stall_early_read` and `tb_load_use_zero_stall_early_read_width`. The width regression covers early-read `lh` sign extension and `lbu` zero extension with zero load-use stalls.
- Fixed the early-read path to avoid stale reads behind older memory operations and to format byte/halfword early data before EX/MEM forwarding.
- Verification passed:
  - targeted `tb_load_use_zero_stall_early_read_width`
  - `scripts/check_project.ps1`
  - full `scripts/run_modelsim.ps1`
  - full `rv32um` with `IdLoadEarlyRead=1`
  - applicable `rv32ui` excluding `fence_i` with `IdLoadEarlyRead=1`
  - `scripts/check_vivado_generic_override.ps1`
  - `scripts/check_vivado_qor.ps1` on the synthesis report
- CoreMark 2 with early replay + ID early read measured `682305` cycles, reducing load-use stalls from `45060` to `29833` versus the previous 2-iteration early-replay point.
- CoreMark 50 measured `17057625` cycles, CPI `1.203214`, load-use stalls `734275`, branch-mispredict flushes `180058`, jump flushes `130505`. At 100 MHz this is about `2.931 CoreMark/MHz`.
- Added generic override support to `run_vivado_synth.ps1` and `vivado_synth.tcl`; the static check first failed on the missing synth generic path and then passed after the fix.
- Synthesis-only Huoyue `soc_top` screen for the candidate completed with LUT `6682`, FF `7727`, BRAM36 `24`, DSP48 `12`, WNS `-4.199 ns`. RAM QoR remains correct with `RAMD64E=16 BlockRAM=24`. Worst synth path is DMEM BRAM output to `mmio_rdata_q_reg[10]/R`.
- Decision: do not run post-route yet. The next useful step is to isolate or register the SoC MMIO/debug readback path so the early-read candidate is not blocked by a board-only readback cone.

## ID Early Read Timing Rescue Update
- Added `tb_load_base_from_load_resp_no_early` and `tb/programs/load_base_from_load_resp_no_early.hex` to guard the load-response base-register corner.
- Added static checks:
  - `scripts/check_id_load_early_read_boundary.ps1`
  - `scripts/check_id_load_early_addr_boundary.ps1`
  - `scripts/check_id_load_early_enable_boundary.ps1`
  - `scripts/check_soc_mmio_registered_read_hold.ps1`
- Added raw regfile read ports and changed ID early-read address generation to avoid pulling same-cycle `load_resp_data` into `dmem_addr`.
- Lightened `id_load_early_read` enable gating by removing global `hazard_stall`, `pipe_wait`, `control_conflict_stall`, and `ctrl_pending_conflict_stall` from the DMEM read-enable cone.
- Restored safe MMIO read-hold behavior in `soc_top`: reset and unsupported MMIO reads still drive zero, while non-MMIO cycles hold the private readback register.
- Verification passed:
  - static boundary checks above
  - `scripts/check_project.ps1`
  - targeted ModelSim: `tb_load_use_zero_stall_early_read`, `tb_load_use_zero_stall_early_read_width`, `tb_load_base_from_load_resp_no_early`
  - SoC ModelSim: `tb_soc_uart_hello`, `tb_soc_uart_loader`, `tb_soc_uart_reset_start`
  - CoreMark 2 with early replay + ID early read: `687953` measured cycles, CPI `1.183453`
- Synth-only timing trend for the same Huoyue 100MHz generic set:
  - pre-boundary ID early read: WNS `-4.199 ns`
  - stable address source: WNS `-2.994 ns`
  - lighter early-read enable: WNS `-2.689 ns`
  - safe MMIO hold: WNS `-2.608 ns`
  - explicit `dmem_read_early` SoC/MMIO boundary: WNS `-2.349 ns`
- Added `dmem_read_early` from `cpu_core`, connected it through `cpu_top`, and used it in `soc_top` to define `cpu_dmem_arch_read = cpu_dmem_read && !cpu_dmem_read_early`.
- Added `scripts/check_soc_early_read_mmio_boundary.ps1`; it failed before the RTL port/boundary change and passes afterward.
- Additional verification passed after the explicit read qualifier:
  - `tb_load_use_zero_stall_early_read`
  - `tb_load_use_zero_stall_early_read_width`
  - `tb_load_base_from_load_resp_no_early`
  - `tb_soc_uart_hello`
  - `tb_soc_uart_loader`
  - `tb_soc_uart_reset_start`
  - `scripts/check_project.ps1`
  - CoreMark 2 with early replay + ID early read: still `687953` measured cycles
- Current state: still not suitable for full implementation/post-route. The remaining synth path now ends at DMEM BRAM `ENARDEN` rather than MMIO readback, so the next target is the early-read address/range/enable cone into DMEM.

## Current ID Early-Read Baseline and MMIO Hold-Only Update
- Reran the latest high-performance ID early-read configuration for a full CoreMark 50 baseline:
  - `COREMARK_RESULT_CYCLES=17198825`
  - CPI `1.213560`
  - load-use stalls `875475`
  - branch-mispredict flushes `180058`
  - jump flushes `130505`
  - estimated score at 100MHz and 50 iterations is about `2.907 CoreMark/MHz`.
- Tested a DMEM BRAM-friendly narrow-index/read-enable cleanup, but rejected it. Although short ModelSim behavior stayed correct, synthesis WNS worsened to `-2.590 ns` and the worst path moved back to `mmio_rdata_q_reg[10]/R`. The RTL experiment and its static check were removed.
- Kept a smaller SoC MMIO readback cleanup: unsupported MMIO reads now hold `mmio_rdata_q` instead of using address-dependent clear logic. Reset still clears the register, and `mmio_read_q` still controls whether the CPU sees MMIO data.
- Verification after the kept MMIO cleanup:
  - `scripts/check_soc_mmio_registered_read_hold.ps1`
  - `scripts/check_soc_early_read_mmio_boundary.ps1`
  - `scripts/check_project.ps1`
  - `tb_soc_uart_hello`
  - `tb_soc_uart_loader`
  - `tb_soc_uart_reset_start`
  - full `scripts/run_modelsim.ps1`
  - CoreMark 2 with early replay + ID early read: `COREMARK_RESULT_CYCLES=687953`
- Huoyue 100MHz synthesis for the same ID early-read generic set improved from the prior explicit-boundary `-2.349 ns` to `-2.196 ns`. LUT/FF/BRAM/DSP are `6532 / 7714 / 24 / 12`.
- The current worst synth path is again `u_core/mul_resp_rd_reg[0]` to `u_dmem/gen_bram_friendly.mem_bram_reg_0_0/ENARDEN`, with data path delay `11.523 ns`, 18 logic levels, and about 61% route delay.
- Current next step: keep the MMIO hold-only cleanup, do not keep the DMEM narrow-index experiment, and target the actual `id_load_early_addr/id_load_early_read -> dmem_sel/mem_read -> BRAM ENARDEN` cone with a more explicit register or request boundary.

## Fast DMEM Select Experiment Rejected
- Tested a more aggressive SoC/DMEM range-check simplification: derive `dmem_sel` from a high-bit DMEM window and add a `TRUST_ADDR_RANGE` DMEM parameter so the BRAM-friendly read path could skip the internal `word_index < DMEM_DEPTH` check.
- Behavior was clean before synthesis:
  - static fast-select check passed
  - `scripts/check_project.ps1` passed
  - targeted ModelSim passed for `tb_soc_uart_hello`, `tb_soc_uart_loader`, `tb_soc_uart_reset_start`
  - targeted ModelSim passed for `tb_load_use_zero_stall_early_read`, `tb_load_use_zero_stall_early_read_width`, `tb_load_base_from_load_resp_no_early`
  - CoreMark 2 stayed unchanged at `687953` cycles
- Synthesis rejected the change. Huoyue 100MHz synth-only WNS worsened from the MMIO hold-only baseline `-2.196 ns` to `-2.680 ns`; resources were LUT/FF/BRAM/DSP `6534 / 7714 / 24 / 12`.
- The worst path remained `u_core/mul_resp_rd_reg[0]` to `u_dmem/gen_bram_friendly.mem_bram_reg_0_0/ENARDEN`, now with data path delay `12.007 ns`. This shows the expression rewrite did not remove the real timing problem and made Vivado mapping worse.
- Reverted the fast-select RTL and removed its static check from the project. Kept only the previously beneficial SoC MMIO hold-only cleanup.
- Post-revert verification passed:
  - no remaining `DMEM_ADDR_LSB`, `TRUST_ADDR_RANGE`, or `check_soc_dmem_fast_select` references under `rtl/` and `scripts/`
  - `scripts/check_project.ps1`
  - `scripts/check_soc_mmio_registered_read_hold.ps1`
  - `scripts/check_soc_early_read_mmio_boundary.ps1`
  - ModelSim targeted checks: `tb_load_use_zero_stall_early_read`, `tb_load_use_zero_stall_early_read_width`, `tb_load_base_from_load_resp_no_early`, `tb_soc_uart_hello`, `tb_soc_uart_reset_start`, `tb_soc_uart_loader`
- Current direction: stop spending time on local SoC/DMEM Boolean rewrites for this path. The next serious optimization should either use implementation/floorplanning on the `-2.196 ns` MMIO hold-only point or add a real registered early-read request/replay boundary with expected CoreMark tradeoff measured immediately.

## Floorplan and DMEM BRAM Read-Hold Update
- Ran Huoyue 100MHz implementation for the current ID early-read/MMIO hold-only point with light floorplan and `ExtraNetDelay_high/AggressiveExplore/Explore/AggressiveExplore`.
- Result: implementation completed and produced a bitstream, but timing failed at WNS `-1.339 ns`, TNS `-338.360 ns`, with 714 failing setup endpoints. QoR passed with `RAMD64E=16 BlockRAM=24`; resources were LUT/FF/BRAM/DSP `6632 / 7762 / 24 / 12`.
- The floorplanned worst path hit DMEM BRAM `RSTRAMB`: `u_core/redirect_jump_flush_reg_replica` to `u_dmem/gen_bram_friendly.mem_bram_reg_1_0/RSTRAMB`, 18 logic levels and data delay `10.967 ns`.
- Added `scripts/check_dmem_bram_read_hold.ps1` and changed the BRAM-friendly DMEM read output to hold its value on non-read cycles instead of clearing to zero. This removes the non-read clear/reset path into the BRAM output register. The check first failed on old RTL and passes after the change.
- Behavior/performance verification after the read-hold change:
  - `scripts/check_dmem_bram_read_hold.ps1`
  - `scripts/check_project.ps1`
  - `scripts/check_soc_mmio_registered_read_hold.ps1`
  - `scripts/check_soc_early_read_mmio_boundary.ps1`
  - targeted ModelSim: `tb_load_use_zero_stall_early_read`, `tb_load_use_zero_stall_early_read_width`, `tb_load_base_from_load_resp_no_early`, `tb_soc_uart_hello`, `tb_soc_uart_reset_start`, `tb_soc_uart_loader`
  - CoreMark 2 unchanged: `COREMARK_RESULT_CYCLES=687953`, CPI `1.183453`
  - official `rv32ui` excluding unsupported `fence_i`: pass
  - full `rv32um`: pass
- Synth-only timing after the read-hold change worsened from `-2.196 ns` to `-2.485 ns`; the worst synth path remains `u_core/mul_resp_rd_reg[0]` to DMEM BRAM `ENARDEN`.
- Post-route implementation without floorplan improved versus the light-floorplan attempt but still failed timing: WNS `-1.131 ns`, TNS `-310.402 ns`, 612 failing setup endpoints. QoR passed with `RAMD64E=16 BlockRAM=24`; resources were LUT/FF/BRAM/DSP `6695 / 7792 / 24 / 12`.
- The new post-route worst path is `u_core/redirect_from_replay_reg` to `u_dmem/gen_bram_friendly.mem_bram_reg_0_1/ENARDEN`, 18 logic levels, data delay `10.666 ns`. This confirms the next blocker is the replay/early-read control cone into DMEM BRAM enable, not BRAM output reset.
- Current decision: keep the DMEM BRAM read-hold cleanup because it preserves behavior, removes the `RSTRAMB` timing endpoint, and improves the routed failure shape. Do not use the light floorplan for this candidate. Next RTL step should register or otherwise break the `redirect/load-replay/id-early-read -> dmem_read -> BRAM ENARDEN` control path.

## Load-Forward Duplication Timing Update
- Rejected two timing experiments:
  - Multiplier operand gating preserved behavior and CoreMark 2 (`694006` cycles) but worsened post-route WNS to `-0.683 ns`, so it was reverted.
  - Moving load byte/half formatting into `dmem` preserved behavior and CoreMark 2, but broke BRAM inference for DMEM (`RAM128X1D x2048`, BRAM dropped to 16) and worsened synth WNS to `-3.699 ns`, so it was reverted.
- Kept the useful low-risk change: duplicate a `load_resp_forward_data` formatting network for EX/replay forwarding, while writeback keeps the original `load_resp_data`.
- Behavior and performance after the kept change:
  - targeted load/width ModelSim passed
  - full `scripts/run_modelsim.ps1` passed
  - official load subset `rv32ui/lb,lbu,lh,lhu,lw` passed with the BTB32 high-performance generics
  - full `rv32um` passed with the same generics
  - CoreMark 2 unchanged: `COREMARK_RESULT_CYCLES=694006`, `COREMARK_CPI=1.191230`
- Vivado results for `build/vivado_impl_soc_top_huoyue_loadfwddup_btb32_extra_net_delay`:
  - post-route WNS improved from the divcmd baseline `-0.531 ns` to `-0.505 ns`
  - resources: LUT `6433`, FF `5742`, BRAM `24`, DSP `12`
  - worst path is still DMEM BRAM output to `u_core/ex_mem_alu_result_reg[0]/D`, but the duplicated forward network reduced the route/fanout shape enough to give a small positive routed gain.
- Current baseline to beat: BTB32 high-performance generics with redirect replay boundary, divider command operand boundary, and load-response forward duplication; CoreMark 2 `694006` cycles; post-route WNS `-0.505 ns`.

## Route-From-Place Timing Rescue Update
- Inspected the stronger `AltSpreadLogic_high/AggressiveExplore/Explore/AggressiveExplore` implementation for the load-forward duplication RTL:
  - `build/vivado_impl_soc_top_huoyue_loadfwddup_btb32_alt_spread`
  - WNS `-0.445 ns`, TNS `-8.188 ns`, 37 failing setup endpoints
  - resources: LUT/FF/BRAM/DSP `6442 / 5745 / 24 / 12`
  - worst path: `if_id_instr_reg[13]` to DMEM BRAM `ENARDEN`, data delay `9.817 ns`, 11 logic levels
- Tried simplifying ID early-read load-base dependency checks to use direct `dec_rs1` instead of the generic `dec_hazard_rs1` source mask. It preserved behavior:
  - `scripts/check_project.ps1`
  - full `scripts/run_modelsim.ps1`
  - CoreMark 2 unchanged: `COREMARK_RESULT_CYCLES=694006`, `COREMARK_CPI=1.191230`
  - `rv32ui/lb,lbu,lh,lhu,lw` passed
  - full `rv32um` passed
  - synth WNS remained `-1.809 ns`
  - post-route WNS worsened to `-0.462 ns`
  - Reverted this RTL change.
- Tried a `soc_top`-only DMEM BRAM read-always mode to remove the BRAM read-enable control path. It preserved SoC directed simulations and kept BRAM inference, and synth WNS improved to `-1.679 ns`; however post-route worsened to WNS `-0.516 ns` and TNS `-58.402 ns`, with the worst path moving to redirect control. Reverted this RTL change.
- Added `-jobs` support to `scripts/vivado_route_from_place.tcl` and reused the known-good `post_place.dcp` from the current best RTL.
- New best implementation result:
  - `build/vivado_route_soc_top_huoyue_loadfwddup_btb32_no_timing_relax/soc_top.bit`
  - route directive `NoTimingRelaxation`, post-route physopt `AggressiveExplore`
  - WNS `-0.204 ns`, TNS `-3.023 ns`, 29 failing setup endpoints
  - resources: LUT/FF/BRAM/DSP `6457 / 5745 / 24 / 12`
  - worst path: DMEM BRAM output to `u_core/ex_mem_alu_result_reg[0]/D`, data delay `10.096 ns`, 10 logic levels
- Tried the same route with post-route `AlternateFlowWithRetiming`; it worsened to WNS `-0.272 ns`, so the retained best remains `NoTimingRelaxation + AggressiveExplore`.
- Current best bitstream is still not timing-clean at 100 MHz, but the remaining gap is now only `0.204 ns`. Next meaningful RTL target is the DMEM load-response-to-ALU path, not the BRAM enable path.

## Load/EX Physical Rescue Follow-up
- Tested an A/B split of `load_resp_forward_data` into separate A/B formatting copies. It preserved short behavior and CoreMark 2 (`COREMARK_RESULT_CYCLES=694006`, CPI `1.191230`), but synthesis worsened versus the accepted single-forward-copy baseline:
  - accepted `loadfwddup` synth: WNS `-1.809 ns`, LUT/FF/BRAM/DSP `6307 / 5732 / 24 / 12`
  - A/B split synth: WNS `-1.929 ns`, LUT/FF/BRAM/DSP `6341 / 5746 / 24 / 12`
  - worst path stayed DMEM BRAM output to `u_core/ex_mem_alu_result_reg[0]/D`
  - Reverted the A/B split and re-verified `scripts/check_project.ps1` plus targeted load/width ModelSim tests.
- Tried a focused load/EX floorplan pblock around the current routed path. It completed implementation but worsened timing to WNS `-0.330 ns`, TNS `-5.757 ns`; the worst path moved to replay/JALR redirect (`ex_mem_rd_reg[2]` to `redirect_pc_q_reg[29]`), and DRC reported RAMB36 over-utilization inside the pblock. The floorplan Tcl was removed.
- Tried route-from-place with `HigherDelayCost` plus post-route `AggressiveExplore` from the same best placed checkpoint. It worsened to WNS `-0.338 ns`, TNS `-7.356 ns`.
- Decision: keep the current best artifact as `build/vivado_route_soc_top_huoyue_loadfwddup_btb32_no_timing_relax/soc_top.bit` with WNS `-0.204 ns`. The rejected A/B, focused pblock, and `HigherDelayCost` route do not replace it.
- Current next direction: stop local duplication/floorplan tweaks on the same load-response path. The remaining gap likely needs an architectural boundary, such as a registered ordinary load-to-ALU replay path or another performance/timing tradeoff that removes `dmem_rdata` from the EX result cone.

## JAL BTB Prediction Performance Update
- Implemented and rejected an optional registered ordinary load-to-ALU replay experiment. It passed directed load-use tests, but CoreMark 2 worsened from `694006` to `750355` cycles and synth WNS worsened to `-2.238 ns`, so the replay RTL/test/script parameter was removed. Kept the independent `tb_external_program` plumbing fix for `ENABLE_ID_LOAD_EARLY_READ`.
- Added JAL target learning through the existing branch predictor path. The first version trained JAL as a normal taken branch and improved CoreMark 2 to `680627` cycles, but it polluted conditional branch history.
- Refined the predictor with a BTB `unconditional` bit and `update_uncond_i`, so JAL targets can be predicted without updating BHT/PHT/BHR. A new `tb_jal_predict` regression shows repeated same-PC JAL ID redirects drop from 4 to 1.
- Current high-performance simulation point with BTB32/local-history generics:
  - `COREMARK_RESULT_CYCLES=678919`
  - `COREMARK_CPI=1.164976`
  - improvement versus previous accepted simulation baseline `694006`: `15087` cycles, about `2.17%`
- Verification passed:
  - `scripts/check_project.ps1`
  - targeted ModelSim: `tb_jal_predict`, jump/upper-jump, branch predictor/core branch tests, load-branch/jalr, load-use, mem-width
  - official `rv32ui` excluding unsupported `fence_i`: pass
  - full `rv32um`: pass
- Vivado synth screen for `build/vivado_synth_soc_top_huoyue_jal_uncond_btb32`:
  - `SYNTH_WORST_SLACK_NS=-2.033`
  - BRAM/DSP inference remains correct: BRAM36 `24`, DSP48 `12`, PHT still `RAM128X1D x4`
  - cell usage includes FDRE `5673`, FDSE `84`; LUT count increased versus the current route-best RTL, so this needs post-route validation before replacing the bitstream.
- Current decision under performance priority: keep the JAL unconditional BTB change as the active RTL candidate. Next step is a post-route run from implementation directives to see whether the `2.17%` CoreMark gain can be accepted on the Huoyue 100 MHz target.

## JAL BTB Post-Route Timing Update
- Ran Huoyue 100MHz implementation for the JAL unconditional BTB candidate with the current high-performance generics:
  `FAST_MUL=0,MUL_STAGES=1,ENABLE_LOAD_RESP_EX_FORWARD=1,ENABLE_LOAD_CONTROL_EARLY_REPLAY=1,ENABLE_ID_LOAD_EARLY_READ=1,BP_LOCAL_HISTORY=1,BP_BHT_DEPTH=64,BP_BHR_WIDTH=2,BP_BTB_DEPTH=32`.
- `build/vivado_impl_soc_top_huoyue_jal_uncond_btb32_alt_spread`:
  - directives: `AltSpreadLogic_high/AggressiveExplore/Explore/AggressiveExplore`
  - bitstream generated, but timing failed: WNS `-0.521 ns`, TNS `-14.308 ns`, 58 failing setup endpoints
  - resources: LUT `6456`, FF `5775`, BRAM `24`, DSP `12`
  - QoR check passed: `RAMD64E=16`, `BlockRAM=24`
  - worst path: `u_core/redirect_valid_reg/C` to DMEM BRAM `ENARDEN`, 11 logic levels, data path `9.808 ns`
- Route-from-place rescue from the same `post_place.dcp`:
  - `build/vivado_route_soc_top_huoyue_jal_uncond_btb32_no_timing_relax`
  - directives: route `NoTimingRelaxation`, post-route physopt `AggressiveExplore`
  - worsened to WNS `-0.684 ns`, TNS `-18.368 ns`, 50 failing setup endpoints
  - worst path: `if_id_instr_reg[13]` to DMEM BRAM `ENARDEN`, 11 logic levels, data path `9.973 ns`
- Independent `ExtraNetDelay_high/AggressiveExplore/Explore/AggressiveExplore` implementation:
  - `build/vivado_impl_soc_top_huoyue_jal_uncond_btb32_extra_net_delay`
  - bitstream generated, but timing failed: WNS `-0.726 ns`, TNS `-23.249 ns`, 126 failing setup endpoints
  - QoR check passed: `RAMD64E=16`, `BlockRAM=24`
  - worst path returned to DMEM BRAM output to `u_core/ex_mem_alu_result_reg[0]/D`, data path `10.412 ns`
- Decision: do not replace the current best bitstream `build/vivado_route_soc_top_huoyue_loadfwddup_btb32_no_timing_relax/soc_top.bit` yet. The JAL unconditional BTB candidate is the fastest simulation point so far, but post-route timing is not acceptable at 100MHz.
- Next RTL direction: keep the JAL predictor behavior, but reduce the new control timing cost. The immediate target is the ID/JAL redirect and branch-predictor update cone feeding fetch/early-read/DMEM enable control, because the best JAL placement fails on `redirect_valid -> dmem ENARDEN` rather than on the predictor table memories themselves.

## ID Early-Read Cone Trim and Predecode Update
- Kept two timing cleanups on top of JAL unconditional BTB:
  - `id_load_early_read` no longer depends on global `ctrl_replay_valid` or `flush`; speculative reads are safe because capture/commit remain qualified.
  - IF/ID now carries predecoded load `rs1` and load immediate fields, so the ID early-read address/dependency path does not re-enter the generic decode/hazard source selection cone.
- Rejected a multiplier operand-gating experiment. It preserved CoreMark 2 (`678919` cycles) but worsened synth WNS from `-1.668 ns` to `-2.037 ns`, so the RTL and static check were removed.
- Verification for the accepted predecode point passed:
  - `scripts/check_id_early_read_control_cone.ps1`
  - `scripts/check_id_load_early_predecode_boundary.ps1`
  - `scripts/check_project.ps1`
  - targeted ModelSim load/control/JAL/branch/mem-width regressions
  - CoreMark 2 unchanged at `COREMARK_RESULT_CYCLES=678919`, `COREMARK_CPI=1.164976`
  - applicable `rv32ui` excluding unsupported `fence_i`: pass
  - full `rv32um`: pass
- Vivado synthesis and implementation trend:
  - control-cone-only synth improved the JAL candidate from `-2.033 ns` to `-1.668 ns`
  - predecode synth was `-1.723 ns`, slightly worse than control-cone-only but still better than original JAL
  - full `AltSpreadLogic_high/AggressiveExplore/Explore/AggressiveExplore` implementation is the new best candidate: `build/vivado_impl_soc_top_huoyue_jal_uncond_idread_predecode_btb32_alt_spread/soc_top.bit`
  - post-route result: WNS `-0.176 ns`, TNS `-1.798 ns`, 22 failing endpoints, LUT/FF/BRAM/DSP `6484 / 5784 / 24 / 12`, QoR OK with `RAMD64E=16`, `BlockRAM=24`
  - worst path: DMEM BRAM output to `u_core/ex_mem_alu_result_reg[0]/D`
- Route-from-place `NoTimingRelaxation + AggressiveExplore` on the predecode placement was rejected. It worsened to WNS `-0.317 ns`, TNS `-4.536 ns`, 31 failing endpoints, with worst path `u_core/redirect_valid_reg/C` to DMEM BRAM `ENBWREN`. QoR remained correct.
- Current best artifact is therefore the full implementation, not the route-only result:
  `build/vivado_impl_soc_top_huoyue_jal_uncond_idread_predecode_btb32_alt_spread/soc_top.bit`.
- Current next direction: the JAL/predecode candidate is fastest and also beats the prior route-best timing, but still misses 100MHz by `0.176 ns`. The next target should reduce the DMEM BRAM output to `ex_mem_alu_result` cone without reintroducing the earlier registered ordinary load-to-ALU replay regression.

## Fast-Mul Generate Boundary and Route Sweep Update
- Added `scripts/check_fast_mul_generate_boundary.ps1` and wrapped the fast-multiply combinational products in `generate if (FAST_MUL != 0)`. This keeps the `FAST_MUL=0` board configuration from carrying explicit fast-mul product expressions in RTL.
- Verification after the RTL cleanup:
  - static fast-mul generate check passed
  - `scripts/check_project.ps1` passed
  - targeted ModelSim passed for `tb_load_use_zero_stall_early_read`, `tb_jal_predict`, and `tb_mem_width`
  - CoreMark 2 with the current high-performance generics stayed unchanged at `COREMARK_RESULT_CYCLES=678919`, `COREMARK_CPI=1.164976`
- Synth-only Huoyue result for the cleanup was unchanged at WNS `-1.723 ns`; resource cells also stayed effectively identical. This means Vivado was already optimizing the inactive fast-mul branch for the current generic set, so the cleanup is not a timing win by itself.
- Started an `ExtraNetDelay_high/AggressiveExplore/Explore/AggressiveExplore` full implementation for the current source. It timed out after placement, but produced a useful `post_place.dcp`.
  - post-place setup WNS was `0.002 ns`, with hold still negative at placement
  - placement resources were LUT/FF/BRAM/DSP `6448 / 5782 / 24 / 12`
- Reused that placement with route-only experiments:
  - `NoTimingRelaxation + AggressiveExplore`: WNS `-0.133 ns`, TNS `-1.075 ns`, 21 setup endpoints, QoR OK
  - `Explore + AggressiveExplore`: WNS `-0.099 ns`, TNS `-1.072 ns`, 21 setup endpoints, QoR OK
  - `MoreGlobalIterations + AggressiveExplore`: WNS `-0.341 ns`, QoR OK, rejected
- New best candidate artifact:
  - `build/vivado_route_soc_top_huoyue_jal_uncond_fastmulgen_btb32_extra_net_delay_route_explore/soc_top.bit`
  - WNS `-0.099 ns`, TNS `-1.072 ns`, WHS `0.043 ns`
  - resources LUT/FF/BRAM/DSP `6454 / 5782 / 24 / 12`
  - QoR OK with `RAMD64E=16`, `BlockRAM=24`
  - worst setup path moved from DMEM BRAM output to `ex_mem_alu_result` into `u_core/ex_mem_rd_reg[0]/C -> u_core/redirect_branch_mispredict_reg/D`, 15 logic levels and 72.7% route delay
- Current decision: keep the `Route=Explore` result as the current best artifact, but it is still not timing-clean. The remaining 0.099 ns gap now points at branch-mispredict/redirect registration rather than the load-response ALU datapath.

## Control Forward Selector Duplication Rejection
- Tried duplicating the forwarding selector only for the branch/control compare path to reduce fanout from the shared `forward_a_sel/forward_b_sel` nets into `redirect_branch_mispredict`.
- The candidate passed the local static check, `scripts/check_project.ps1`, targeted ModelSim control/load/JAL regressions, and preserved CoreMark 2 at `COREMARK_RESULT_CYCLES=678919`, `COREMARK_CPI=1.164976`.
- Synth-only timing improved from the current screen near `-1.723 ns` to `SYNTH_WORST_SLACK_NS=-1.229`, but post-route timing got substantially worse:
  - artifact: `build/vivado_impl_soc_top_huoyue_jal_uncond_ctrlfwddup_btb32_extra_net_delay/soc_top.bit`
  - route-only from `post_place.dcp`, directives `Explore + AggressiveExplore`
  - WNS `-0.498 ns`, TNS `-7.030 ns`, 52 setup failing endpoints, WHS `0.074 ns`
  - worst setup path became DMEM BRAM output to `u_core/ex_mem_alu_result_reg[0]/D`
- Decision: rejected and reverted. The temporary local selector RTL and `scripts/check_control_forward_select_dup.ps1` were removed. Current best remains:
  `build/vivado_route_soc_top_huoyue_jal_uncond_fastmulgen_btb32_extra_net_delay_route_explore/soc_top.bit` at WNS `-0.099 ns`.
- Revert verification:
  - `scripts/check_project.ps1`: pass
  - `scripts/check_fast_mul_generate_boundary.ps1`: pass
  - full `scripts/run_modelsim.ps1`: pass
  - CoreMark 2 high-performance generics: `COREMARK_RESULT_CYCLES=678919`, `COREMARK_CPI=1.164976`

## ExtraNetDelay Route Variant Rejection
- Reused the current best `post_place.dcp` in a separate directory and tried route directive `AdvancedSkewModeling` with post-route physopt `AggressiveExplore`.
- Result was not competitive:
  - artifact: `build/vivado_route_soc_top_huoyue_jal_uncond_fastmulgen_btb32_extra_net_delay_adv_skew/soc_top.bit`
  - WNS `-0.277 ns`, worse than current best `-0.099 ns`
  - worst path remained `u_core/ex_mem_rd_reg[0]/C -> u_core/redirect_branch_mispredict_reg/D`
  - data path delay `10.243 ns`, with route `7.988 ns` / `77.985%`
  - QoR check passed: `RAMD64E=16`, `BlockRAM=24`
- Decision: rejected. The current best stays `Route=Explore + AggressiveExplore` from the same placement.

## Branch Less-Than EX/MEM Wait Rejection
- Tried a narrow RTL boundary for the current worst path by stalling only branch comparisons that both:
  - are less-than class branches (`id_ex_funct3[2]`), and
  - need a result from the immediately previous EX/MEM instruction.
- A broader first version that stalled all branch/JALR EX/MEM dependencies was immediately rejected on performance: CoreMark 2 regressed from `678919` to `703217` cycles.
- The narrowed less-than-only version passed:
  - structural check while active
  - targeted ModelSim: registered redirect, branch, branch predict, JAL predict, load-branch, load-JALR
- Performance and timing screen were both worse:
  - CoreMark 2: `684543` cycles, `COREMARK_CPI=1.174627`, about `0.83%` slower than the `678919` baseline
  - synth-only Huoyue WNS: `-1.809 ns`, worse than the current source screen around `-1.723 ns`
  - resources stayed in the same shape, with BRAM/DSP inference correct in synth output
- Decision: rejected and reverted. The temporary `control_ex_mem_forward_wait` RTL and `scripts/check_branch_exmem_forward_wait.ps1` were removed.

## Branch Compare Split Rejection
- Tried rewriting the branch compare cone so equality branches and less-than branches used explicit split signals instead of a single `case` with inline comparisons.
- Behavior and performance were preserved while active:
  - targeted ModelSim branch/condition/predict/registered-redirect/JAL tests passed
  - CoreMark 2 stayed at `COREMARK_RESULT_CYCLES=678919`, `COREMARK_CPI=1.164976`
- Synth-only timing was not improved:
  - `build/vivado_synth_soc_top_huoyue_jal_uncond_branchcmp_split_btb32`
  - `SYNTH_WORST_SLACK_NS=-1.723`, effectively same as baseline
  - cell count was slightly lower in parts of the compare cone, so it was allowed one post-route trial
- Added a reusable resume helper `scripts/vivado_impl_from_opt.tcl` to continue place/route from an existing `post_opt.dcp`.
- Post-route trial was worse than the current best:
  - `build/vivado_impl_soc_top_huoyue_jal_uncond_branchcmp_split_btb32_extra_net_delay/soc_top.bit`
  - WNS `-0.572 ns`, versus current best `-0.099 ns`
  - QoR/bitstream generation completed, but it is not selected
- Decision: rejected and reverted. The branch compare RTL and temporary `scripts/check_branch_compare_split.ps1` were removed. The generic `vivado_impl_from_opt.tcl` helper is retained.
- Revert verification:
  - `scripts/check_project.ps1`: pass
  - `scripts/check_fast_mul_generate_boundary.ps1`: pass
  - targeted branch/JAL ModelSim: pass
  - CoreMark 2 high-performance generics: `COREMARK_RESULT_CYCLES=678919`, `COREMARK_CPI=1.164976`

## Repository Backup and Git Initialization
- Created a clean source backup at `.project_backups/source_backup_20260520_165915`.
  - Backup contains 954 files, about 7.96 MB.
  - It intentionally excludes generated Vivado/ModelSim outputs and the local RISC-V toolchain.
- Initialized the project root as a Git repository on branch `main`.
- Added cleanup metadata:
  - `.gitignore` excludes `build/`, `.Xil/`, `work/`, `.project_backups/`, Vivado logs/checkpoints/bitstreams, simulator waves/logs, local toolchain, and transient preview files.
  - `.gitattributes` pins RTL/Tcl/XDC/scripts/docs line endings to stable LF handling.
  - `.gitmodules` records official upstream sources for `coremark` and `riscv-tests`.
- Staging preview confirmed the repository candidate contains source, tests, scripts, constraints, software support files, docs, and submodule references; large generated artifacts are ignored.
- After the initial commit, `coremark` reported an untracked legacy `riscv_port/` directory. The active build scripts use `sw/coremark_port/`, so `.gitmodules` was adjusted to ignore untracked files inside the `coremark` submodule rather than adding stale local port files to the repository.
- Added GitHub remote `origin = https://github.com/yeyaoxin55-bit/yunyuan526.git`.
- Pushed `main` to GitHub. Current remote-tracking state after push: `b4654af (HEAD -> main, origin/main) Initial project import`.
