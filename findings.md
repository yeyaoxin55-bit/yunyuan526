# 文档审阅发现

## 文档清单
- `RISC-V RV32I_RV64I面向Zynq-7020高性能CPU架构设计方案.md`

## 发现
- 资源目标中“相比PicoRV32同等功能配置LUT降低20%以上”与后文`~5200 LUT`、PicoRV32 `~1500 LUT`的对比表矛盾；应改为相对ibex降低资源，并强调性能/资源效率。
- AXI4-Lite表述为“主从接口”不够准确。当前交付模块是CPU侧调试/加载用AXI4-Lite从接口，CPU核本身不作为AXI主设备。
- RV64模式下若启用M扩展，应明确支持RV64M的W后缀乘除法指令，避免只写“RV32M”造成范围不清。
- 分支预测器资源估算：BHT 256位 + PHT 2048位 + BTB 1664位 = 3968位，约0.5KB，不是4KB。
- 预取缓存资源按`XLEN`变化，原文固定写32位时只适用于RV32。
- CSR列出`mie/mip`且正文提到中断，但异常章节未说明中断支持边界，需要补充默认最小实现与可选中断入口。
- 用户后续将目标改为性能优先并指定部署在Zynq-7020上，文档需从“低资源/低功耗”转为“Zynq-7020性能优先”，资源改为预算参考。
- CoreMark默认运行更稳妥的片上存储配置为IMEM 64KB + DMEM 32KB；32KB IMEM对启动代码、轻量运行库和输出代码可能偏紧。

## Official Test Findings
- Official rv32ui/fence_i requires executing code placed in .data and observing self-modified instructions after fence.i; current Harvard IMEM/DMEM design does not fetch from DMEM, so this is an unsupported architecture feature rather than a normal RV32I execution failure.
- The custom riscv-tests harness must not use gp as TESTNUM, because modern RISC-V toolchains relax some la instructions to gp-relative addressing. gp must be initialized and preserved for official tests and CoreMark-style C code.

## CoreMark Findings
- The official CoreMark tree is present under coremark and contains the expected source files and ports.
- CoreMark needs read-only constants/jump tables accessible through the CPU data-load path. In the current Harvard memory layout, .rodata/.srodata must reside in DMEM, not IMEM.
- With TOTAL_DATA_SIZE=2000 and ITERATIONS=1, the current baremetal CoreMark image uses IMEM 7024 B and DMEM 4104 B. The configured 64KB IMEM / 32KB DMEM has ample margin.
- CoreMark functional validation passes in ModelSim, but official scoring is not claimed until a >=10 second timed run is done on hardware or an equivalently long timing run.

## Performance Measurement Findings
- The external harness now distinguishes simulator completion cycle from workload-measured CoreMark cycles. CoreMark cycles are read from 0x00017ff8 and should be used for performance comparison.
- For ITERATIONS=1, TOTAL_DATA_SIZE=1200 measured 220749 CoreMark cycles; TOTAL_DATA_SIZE=2000 measured 542141 CoreMark cycles.
- The generated CSV is a functional profiling baseline, not an official CoreMark score.

## CoreMark Bottleneck Snapshot
- The measured CPI baseline is about 1.41 for TOTAL_DATA_SIZE=1200 and 1.44 for TOTAL_DATA_SIZE=2000.
- Flush count is high relative to retired instructions, so branch/jump front-end behavior is a likely optimization target.
- Load-use stalls are also significant; improving load forwarding/use latency or scheduling-sensitive code paths should be evaluated.
- DIV count is low in the 1200/2000 functional runs, so divider latency is measurable but probably not the first CoreMark bottleneck compared with branch flushes and load-use stalls.

## CoreMark Multi-Iteration Findings
- Multi-iteration runs confirm the workload is stable around 542.3k CoreMark cycles per iteration for TOTAL_DATA_SIZE=2000.
- At 50 iterations, CPI is 1.518165 and normalized flush rate is 90.14/kInstr. Branch/jump front-end behavior remains a primary optimization target.
- Load-use stalls and exec-wait stalls are both around 80/kInstr in the long run; they are secondary targets after reducing avoidable flush cost.
- DIV instruction count remains fixed at 87 across iteration counts, so these runs do not justify prioritizing divider latency for CoreMark yet.

## CoreMark 10s Practicality Finding
- At the current 100MHz timing model, official 10s CoreMark needs roughly 1844+ iterations. ITERATIONS=1900 gives margin above 1e9 mcycle ticks.
- ModelSim RTL simulation of this workload is too long for the interactive 1-hour command window. Use long-run extrapolated 50-iteration data for design optimization, and use FPGA execution for official score collection.

## JAL Early Redirect Findings
- The 50-iteration CoreMark baseline showed jump flushes dominate flush cost: 1359838 of 1610096 flushes, with 984115 from JAL and 375723 from JALR.
- ID-stage JAL early redirect eliminated JAL flushes in the measured CoreMark run and reduced 50-iteration CoreMark cycles from 27116494 to 26133650.
- Remaining jump flushes are JALR-only. JALR optimization is more complex because the target depends on rs1 forwarding; it should be considered separately after evaluating load-use and branch-mispredict cost.
- Branch mispredict flushes are now 250258 at 50 iterations, much smaller than pre-optimization jump flush cost but still a visible target.

## JALR Optimization Finding
- The dominant remaining JALR flush source is 0x147c in core_state_transition, which is a multi-target jump-table dispatch. It is not suitable for a simple return-address stack optimization.
- A simple per-PC last-target predictor has only about 31.6% hit rate on the 10-iteration CoreMark run, so a generic JALR target cache is unlikely to be the highest-return next optimization.
- The better next target is load-use behavior, because long-run load-use stalls remain around 80/kInstr and are comparable in scale to remaining JALR flush pressure.

## Load-Use Optimization Finding
- Load-use stalls were mostly adjacent load-consumer pairs in core_state_transition, core_list_find, and matrix_sum.
- Because dmem.v currently has combinational read behavior, these dependencies can use existing MEM-to-EX forwarding instead of forcing a bubble.
- Disabling load-use stalls is a performance win for the current RTL model, but if DMEM is later changed to true synchronous BRAM read, ENABLE_LOAD_USE_STALL should be set back to 1 or a load-data bypass/late-EX timing solution must be designed.
- After this change the next remaining major CoreMark costs are JALR flushes, branch mispredict flushes, and exec_wait stalls from M-extension operations.

## FPGA Bring-up Finding
- CoreMark FPGA images are ready under build/coremark/fpga. The default coremark.imem.hex/coremark.dmem.hex currently point to the smoke image.
- For board timing correctness, regenerate images with -CpuHz equal to the actual CPU clock if not running at 100MHz.
- fpga_coremark_top is a minimal observation wrapper. For a Zynq PS workflow, the next practical integration is an AXI-Lite readable result register block for pass/fail/cycle rather than relying only on LEDs or ILA.

## FPGA Image Manifest
- build/coremark/fpga/manifest.csv now lists the generated smoke, ten_ms, and ten_sec CoreMark images and their ELF/hex paths. Use smoke first for board bring-up, then replace the default coremark.*.hex files with ten_ms or ten_sec when ready.

## Fast Multiply Finding
- After JAL early redirect and zero load-use stalls, CoreMark exec_wait stalls were almost entirely multiply-related: 56949 mul_wait_stalls and 2871 div_wait_stalls in a 2-iteration run.
- Reducing the multiplier pipeline from 2 stages to 1 stage saved about one cycle per dynamic multiply, improving 50-iteration CoreMark from 24704859 to 24233659 cycles.
- Enabling FAST_MUL removes multiply wait cycles entirely for the current pipeline by computing MUL/MULH/MULHSU/MULHU combinationally in EX. The 50-iteration run improved further to 23291259 cycles.
- The tradeoff is FPGA timing risk: the EX path now includes forwarding muxes plus a 32x32 multiply/high-half select. Keep FAST_MUL enabled for performance experiments, but if Vivado timing fails on Zynq-7020, use FAST_MUL=0 and MUL_STAGES=1 as the next fallback.

## Sync DMEM / Valid Pipeline Finding
- The valid-bit cleanup is necessary before deeper optimization: without id_ex/ex_mem/mem_wb valid tracking, flushed bubbles can still affect reg_write, memory side effects, branch predictor training, or CSR minstret accounting.
- CSR minstret must count real retired instructions, not cycles. The strengthened CSR regression catches the old retire_i=1 behavior by requiring minstret to be positive but lower than mcycle.
- A true FPGA BRAM-oriented DMEM should use synchronous read semantics. This requires a MEM wait cycle for loads and conservative load-use interlock unless a later timing-aware bypass scheme is designed.
- Sync DMEM changes the performance baseline materially: CoreMark TOTAL_DATA_SIZE=2000 ITERATIONS=50 moved from the fast async-DMEM result of 23291259 cycles to 28015450 cycles, mainly from 3297838 mem_wait_stalls and 1586888 load_use_stalls.
- The next performance target should be reducing the synchronous load penalty without returning to non-BRAM-friendly combinational RAM. Candidate directions are MEM-stage load-data bypass timing review, a small data-side prefetch/cache, or instruction scheduling in the CoreMark build; verify each against rv32ui/rv32um and CoreMark.

## Vivado Synthesis Finding
- For Zynq-7020 synthesis, DMEM must use a strict BRAM inference template. A registered rdata alone is not enough if the RAM output feeds variable shifting or debug combinational reads in a way Vivado cannot map to block RAM.
- The FPGA CoreMark top now maps 64KB IMEM plus 32KB DMEM to 24 RAMB36E1 blocks with no distributed RAM, which is the correct memory implementation direction.
- The current FAST_MUL=1 configuration does not meet 100MHz after synthesis. Worst setup slack is -7.088 ns and the reported path runs from DMEM BRAM output into ex_mem_alu_result through DSP-heavy execute logic.
- The highest-return timing experiment is to synthesize a FAST_MUL=0 / MUL_STAGES=1 FPGA configuration. If that closes or improves timing strongly, keep FAST_MUL only for simulation/performance exploration and use the pipelined multiplier on FPGA.
- FAST_MUL=0 / MUL_STAGES=1 improves WNS only slightly to -6.545 ns. The multiplier module still computes product combinationally before result_pipe[0], so the critical load-to-multiply path remains.
- The next timing fix should change the multiplier microarchitecture, not just the top-level FAST_MUL switch: register multiplier operands/funct3 first, compute product in the following cycle, then return valid. This will add one multiply latency cycle but should break the DMEM/forwarding-to-DSP critical path.
- Registering multiplier operands/funct3 works as intended: Vivado reports DSP AREG/BREG/MREG usage and WNS improves to -4.718 ns. The multiplier is no longer the worst path.
- Cutting direct EX/MEM load-data forwarding in the synchronous-DMEM configuration improves WNS further to -2.813 ns and keeps all memories in BRAM. This is functionally safe with ENABLE_LOAD_USE_STALL=1 because load consumers use MEM/WB registered load data.
- The remaining 100MHz synthesis bottleneck is the EX-stage branch compare/redirect path from id_ex_rs2 to pc_reg. Closing this likely requires either a registered branch redirect stage, simplified branch-mispredict/redirect logic, or a lower initial clock target such as 75MHz before place-and-route.

## Local BHR Predictor Finding
- A true local-history predictor is functional and gives a measurable CoreMark improvement, but the improvement is modest on the current synchronous-DMEM baseline.
- BHR_WIDTH=4 with a 2048x2 PHT reduces 50-iteration CoreMark from 28015450 to 27932114 cycles and branch_mispredict_flushes from 250258 to 229336.
- The PHT should not be reset synchronously. A resettable PHT caused impractical synthesis time; an initialized no-reset PHT maps cleanly to distributed RAM.
- The local predictor should remain a performance option/default, but it does not address the current 100MHz timing bottleneck. The worst path remains EX-stage branch compare/redirect into pc_reg.

## Registered Redirect Finding
- Registering the EX redirect breaks the direct branch-compare-to-PC update path and improves 100MHz synthesis from WNS -2.835 ns to WNS -1.383 ns.
- The change costs one additional cycle on branch mispredict/JALR redirects. CoreMark 2-iteration smoke still passes with CPI 1.506967, and the 50-iteration run measures 28532090 cycles with CPI 1.545151 on the current synchronous-DMEM/local-BHR baseline.
- Delayed redirects need explicit suppression of wrong-path redirect detection while redirect_valid is pending. Without that gate, rv32ui/beq can schedule a second redirect from a wrong-path branch before the pending flush clears it.
- The remaining worst path is now the redirect capture enable: id_ex_rs2_reg -> compare/control -> redirect_pc_q_reg CE. The next timing optimization should latch redirect_pc_q without using the full redirect_detect cone as a wide clock enable, then keep only the small valid/type decision on the critical control path.

## Redirect Candidate Split Finding
- Splitting redirect target/fallthrough capture from redirect_valid/type capture removes the compare result from the wide redirect_pc_q enable path and improves 100MHz synthesis from WNS -1.383 ns to WNS -0.576 ns.
- This timing improvement has no measurable CoreMark performance cost versus the registered-redirect baseline: the 50-iteration measured cycle count remains 28532090 with CPI 1.545151.
- The current worst path is now the branch compare/control cone into redirect_branch_mispredict_reg, not PC data capture. Closing the remaining 0.576 ns likely requires simplifying or further registering the redirect valid/type decision, accepting another branch redirect penalty only if the simpler control cleanup is insufficient.

## Branch Mispredict Boolean Rewrite Finding
- Rewriting branch_mispredict_raw as a taken/not-taken boolean expression is behavior-equivalent and avoids a full actual-next-PC versus predicted-next-PC compare for not-taken branches.
- This removes branch redirect control from the worst 100MHz setup path and improves synthesis to WNS -0.457 ns, TNS -2.358 ns, and 13 failing endpoints.
- The next timing bottleneck is now the multiplier DSP/result accumulation path, not branch redirect. Since CoreMark has 471346 dynamic MULs in the 50-iteration run, any added multiplier latency must be weighed against 100MHz closure; using an additional DSP/output pipeline register is the likely next experiment.

## Multiplier Output Pipeline Finding
- Adding an explicit product/output pipeline stage lets Vivado use DSP PREG and closes fpga_coremark_top out-of-context 100MHz synthesis at WNS 0.091 ns with no setup violations.
- The cost is real on CoreMark when using the FPGA-like FAST_MUL=0 path: 50 iterations measure 30416890 cycles versus 28532090 cycles on the default FAST_MUL=1 performance path, with 1885351 mul_wait_stalls.
- This is a good FPGA bring-up point because timing is finally positive at synthesis and resources remain modest: 5008 LUTs, 7365 FFs, 24 RAMB36, and 12 DSP48. The next step should be place-and-route/implementation timing, not more speculative RTL changes.

## Implementation Timing Closure Finding
- Out-of-context synthesis timing was not sufficient: the first routed 100MHz implementation failed with WNS -0.263 ns because routing delay made the branch predictor PHT write-enable path critical.
- Registering the branch predictor update is a low-risk timing fix. It delays predictor training by one cycle but does not change architectural execution state, and the measured CoreMark 50 result stayed stable.
- Post-route 100MHz timing now passes after phys_opt with WNS 0.007 ns and no setup/hold violations. The margin is small, so board pin constraints, different placement, or extra debug logic could still require another timing pass.
- The current next bottleneck is again front-end/redirect related: the worst met path runs from a BHR register through predictor/PC selection logic into pc_reg. If timing regresses after board integration, the next candidates are further registering predictor read/PC select logic or lowering the first board clock target.

## Pipelined Load Response Finding
- Eliminating global mem_wait for synchronous loads is the highest-return resource-for-performance optimization so far. The final timing-clean CoreMark 50 run drops from 30416890 to 28843256 cycles, mainly by replacing 3297838 global mem_wait stalls with dependency-only load-use stalls.
- Directly forwarding BRAM load data into EX is too aggressive for the current 100MHz Zynq-7020 target. It gives better CoreMark cycles but creates a DMEM-to-EX critical path and failed post-route timing.
- The safer structure is a delayed load-response writeback plus dependency-only interlock. It preserves BRAM-friendly memory inference, avoids a BRAM-to-ALU path, and still lets independent instructions continue while a load response is pending.
- BHR_WIDTH=3 is the better current FPGA point after this change. It loses some branch prediction accuracy versus BHR_WIDTH=4, but cuts PHT LUTRAM in half and gives just enough post-route timing margin with the new load-response datapath.
- Current 100MHz timing margin is exactly 0.000 ns after phys_opt. Treat this as timing-clean but fragile; board constraints, ILA insertion, or AXI status integration may require either a small frequency reduction, more front-end pipelining, or placement/strategy tuning.

## Vivado Strategy Finding
- The Explore/AggressiveExplore implementation strategy improves the final 100MHz post-route margin from WNS 0.000 ns to WNS 0.090 ns on the current fpga_coremark_top design.
- The improvement is placement/routing driven, not RTL driven: CoreMark behavior does not change and resource use stays effectively the same.
- Keep this strategy for the current performance-oriented FPGA build while evaluating the next RTL optimization. A 0.090 ns margin is still modest, so larger additions such as a data cache or deeper predictor should be guarded by immediate post-route timing checks.

## Multiplier Output Visibility Finding
- The prior pipelined multiplier had one avoidable cycle after the output pipeline register: valid_o/result_o were registered again before the CPU could observe them.
- Exposing the last result_pipe/valid_pipe stage directly saves essentially one cycle per dynamic MUL without reintroducing a DSP/product critical path.
- This is a good resource-neutral performance tradeoff for the current FPGA build: CoreMark 50 saves 471200 cycles and post-route timing still passes at 100MHz.
- The remaining 100MHz margin is only WNS 0.020 ns. Further performance work should first target either non-critical registered control paths or a small instruction/data locality optimization, not a wider EX-stage combinational path.

## Selective Load-Response Forwarding Finding
- Reducing load-use stalls is possible without returning to asynchronous DMEM, but unrestricted load-response forwarding is too aggressive for the current 100MHz Zynq-7020 target.
- Allowing every consumer type to use load_resp_data in EX creates critical paths from DMEM BRAM output toward divider/front-end control and did not close post-route timing.
- The timing-safe compromise is selective forwarding: ordinary ALU/store consumers use the registered load response after one stall, while branch/jump/M-extension consumers keep the conservative second stall.
- This recovers a meaningful part of the load-use penalty while preserving 100MHz post-route timing. CoreMark 50 saves 642441 cycles versus the previous timing-clean multiplier-output baseline, but WNS is now only 0.006 ns.
- Treat the current point as performance-improved but very timing-fragile. The next RTL performance change should first create front-end timing margin or be guarded by immediate post-route implementation.

## Front-End Timing Experiment Finding
- Removing local-history prediction is not a good tradeoff on this design. It slightly worsens CoreMark and did not recover useful post-route margin, so the BHR/PHT predictor should stay enabled at the current BHR_WIDTH=3 setting.
- Simplifying predict_target_o to a raw BTB target is also not worth keeping. Although it preserves RTL behavior in simulation when cpu_core stores predicted_next_pc, route timing became worse and failed at WNS -0.271 ns under the directed 100MHz implementation flow.
- The current margin problem is no longer just a single visible mux in the branch predictor. Placement and routing now couple the PC-select, DMEM/load-response, forwarding, and EX cones. Future performance changes should either add a real register boundary or reduce a known critical cone; small combinational rewrites are not reliable enough at the present 100MHz margin.

## Load-Use Hotspot Classification Finding
- After fixing the profiling attribution for second-cycle conservative stalls, the current CoreMark 50 hotspot distribution shows that most remaining load-use stalls are intentional control-path stalls.
- Branch consumers account for 1609869 of the 32 reported hotspot stall counts, and jump consumers account for another 460808. Simple ALU consumers account for only 206047, which means the existing selective load-response forwarding already captures most of the safe ALU-side benefit.
- The largest remaining single pair is in core_state_transition: lbu at 0000144c followed by beqz at 00001450. The next largest is a jump-table style lw at 00001478 followed by jr at 0000147c.
- Therefore, further significant CoreMark improvement requires handling load-to-branch/jump dependencies. Letting those consume load_resp_data directly would reintroduce the timing problem previously seen in the unrestricted forwarding experiment. A useful hardware direction would need to register or delay the branch/jump decision path cleanly, not just expand forwarding.

## CoreMark Compiler Optimization Finding
- Compiler scheduling and inlining are a high-return, low-hardware-risk optimization for this CPU. Moving CoreMark from -Os to -O3 -funroll-loops improves 50-iteration cycles from 27729615 to 19228682, a 30.66% reduction, while preserving the 100MHz post-route result.
- The improvement comes from fewer retired instructions, fewer branches/jumps, fewer branch flushes, and fewer load-use stalls. It does not require wider forwarding or new CPU datapaths.
- -fno-jump-tables was not useful in the tested combinations. It reduced some indirect jump behavior but increased total cycles compared with the corresponding -O2/-O3 runs.
- The memory cost is acceptable for the current FPGA parameters: the optimized CoreMark image uses 25576 bytes of IMEM and 3948 bytes of DMEM, still far below the 64KB/32KB limits.
- For board bring-up and performance measurement, use the new default -O3 -funroll-loops CoreMark images. For apples-to-apples comparison with older logs, rerun with -OptLevel -Os and an empty ExtraCFlags value.

## Registered Load-to-Control Replay Finding
- Registering load-to-branch/JALR consumers is a real CoreMark win when the replay cycle does not globally stall the front end. The kept design reduces 50-iteration CoreMark from 19228682 to 18431390 measured cycles.
- The critical correctness detail is that replay-triggered redirects must kill only younger wrong-path side effects. A global flush kill on MEM/WB also kills ordinary JAL/JALR link writes; the retained fix tracks redirect_from_replay and gates side effects only for replay flushes.
- The replay redesign successfully moves the worst timing path away from branch/JALR redirect and predictor update. Synthesis-only timing now reports the worst path as DMEM BRAM output through normal load-response forwarding into the ALU result register.
- The remaining WNS -0.908 ns in synthesis-only mode is the price of keeping one-stall load-to-ALU forwarding. Removing or registering that path would likely improve timing, but it would give back a meaningful part of the load-use performance gain.
- Next timing work should target the normal load-response-to-ALU path directly, or run implementation to see whether placement/routing plus phys_opt can close the remaining synthesis-estimated deficit.

## Current 100MHz Implementation Timing Finding
- Directed post-route implementation closed the current load-to-control replay RTL at 100MHz without further RTL changes: WNS 0.015 ns, TNS 0.000 ns, WHS 0.011 ns.
- The synthesis-only deficit was pessimistic for this checkpoint. After placement/routing and post-route phys_opt, the DMEM-to-EX path is no longer the reported worst setup path.
- The new worst setup path is a front-end path from pc_reg[2] through prediction/PC-select logic into pc_reg[3], with 9.811 ns data path delay, 12 logic levels, and 68.8% route delay.
- Because timing now closes, do not implement registered load-response-to-EX replay yet. That change would likely give back CoreMark load-use performance to solve a path that implementation currently closes.
- Treat this checkpoint as usable but fragile. The next timing work should either improve implementation margin or add a real front-end register boundary; small predictor mux rewrites have already been unreliable.

## soc_top Timing and BRAM QoR Finding
- `soc_top` originally met 50 MHz synthesis timing but wasted LUTRAM: DMEM mapped to distributed RAM (`RAMD64E=5696`), leaving only IMEM in BRAM.
- Splitting DMEM into four byte-lane RAM arrays did not help. Vivado still inferred distributed RAM, even with `ram_style="block"` and direct byte-lane `$readmemh` initialization.
- The root cause was the active UART loader write path combined with a separate CPU byte-write path. When loader writes and CPU writes were expressed as different write styles, Vivado chose LUTRAM for the 8K x 32 DMEM.
- Merging loader and CPU writes into a single byte-enable write port fixed inference. Loader writes are now represented as `byte_en=4'b1111` on the same RAM write template.
- Current `soc_top` post-route 50 MHz baseline passes: WNS 4.780 ns, TNS 0.000 ns, WHS 0.023 ns, no setup/hold failing endpoints, LUT 6219, FF 7859, RAMB36 24, DSP48 12.
- Post-route RAM utilization confirms IMEM uses 16 RAMB36 and DMEM uses 8 RAMB36. The remaining 64 LUTMs as distributed RAM are the branch predictor PHT (`RAM128X1D`), not DMEM.
- The worst 50 MHz setup path is DMEM BRAM output toward divider quotient reset/control logic, with 14.395 ns data path delay and heavy routing. This has enough 50 MHz margin but is the first path to watch if pushing `soc_top` beyond the board default clock.

## soc_top 100MHz-Only Timing Finding
- Per user direction, the current timing target is only 100 MHz; 50/75 MHz sweeps are intentionally skipped.
- `soc_top` default post-route implementation at 100 MHz fails timing: WNS -0.366 ns, TNS -23.243 ns, 153 setup failing endpoints, 0 hold failing endpoints.
- `soc_top` Explore/AggressiveExplore post-route implementation at 100 MHz passes narrowly: WNS 0.001 ns, TNS 0.000 ns, 0 setup/hold failing endpoints, LUT 6348, FF 7865, RAMB36 24, DSP48 12.
- The usable 100 MHz bitstream is `build/timing_sweep_soc_top_100m/soc_top_100MHz_explore/soc_top.bit`.
- The earlier default worst path was `u_core/ex_mem_rd_reg[1]` to branch predictor update control. The Explore run moved the worst path to `u_core/ex_mem_rd_reg[1]` to `u_core/redirect_from_replay_reg`, with 70.8% routing delay.
- A small replay-only `redirect_from_replay` cleanup was tested and rejected. It generated a temporary passing bitstream with WNS 0.007 ns, but the CoreMark external run timed out, showing the rewrite was not behavior-safe for long programs.
- The next timing optimization should target a real front-end PC/predictor register boundary or floorplanning/implementation strategy, not another local expression rewrite. The design is currently timing-clean but fragile.

## CoreMark UART Output Split Finding
- Adding UART printing to the CoreMark port made external `cpu_top` ModelSim runs hang because the simulation harness does not implement `soc_top` UART MMIO at `0x00020004`.
- Trace confirmed the timeout loop at PC 0x5f60 was polling UART status, not a CPU execution deadlock.
- `COREMARK_UART_OUTPUT` now controls whether CoreMark touches UART MMIO. Simulation builds default to `0`; FPGA image generation passes `-DCOREMARK_UART_OUTPUT=1`.
- This keeps board-visible CoreMark summary output while preserving fast external ModelSim profiling.

## Replay Tag Timing Experiment Finding
- The refreshed 100 MHz `soc_top` Explore implementation after the UART/CoreMark split still passes only narrowly: WNS 0.001 ns. The worst path is `ex_mem_rd_reg[1]` to `redirect_from_replay_reg/D`, with about 70.8% routing delay.
- A seemingly equivalent replay-tag simplification, `redirect_from_replay <= ctrl_replay_valid`, was functionally safe in simulation but failed post-route timing badly at WNS -0.385 ns. The failing path moved into branch predictor update control and remained route dominated.
- This confirms that local replay/redirect expression rewrites are not reliable timing fixes at the current margin. The safer next route is implementation strategy/floorplanning exploration or a deliberate front-end/register-boundary redesign.

## soc_top 100MHz Strategy Selection Finding
- Additional implementation strategy exploration found a slightly better 100 MHz `soc_top` baseline without RTL changes.
- `extra_net_delay` closes timing but only at WNS 0.000 ns. Its worst path moves back to DMEM BRAM output feeding divider reset/control.
- `alt_spread` is the current best board candidate: WNS 0.013 ns, TNS 0.000 ns, WHS 0.013 ns, LUT 6369, FF 7865, RAMB36 24, DSP48 12.
- The `alt_spread` critical setup path is DMEM BRAM output to `ex_mem_alu_result_reg[0]`, not the replay tag path. This reinforces that the design is timing-fragile across several route-dominated cones rather than limited to one local Boolean expression.
- QoR gate passes on `alt_spread`; DMEM remains RAMB36E1 and the only distributed RAM is the intended 64 LUTRAM branch predictor PHT.
- Use `build/vivado_impl_soc_top_100m_alt_spread/soc_top.bit` as the current 100 MHz board bring-up bitstream. Further margin improvement should come from implementation/floorplanning or a real register boundary, not speculative local RTL rewrites.

## Light Floorplan Experiment Finding
- The Vivado flow now has a reusable floorplan hook, so future pblock experiments do not require modifying the main implementation Tcl again.
- The first broad `u_core` + `u_dmem` pblock is not a better 100 MHz solution. The correct 100 MHz run closes timing at WNS 0.000 ns, which is worse than the no-floorplan `alt_spread` WNS 0.013 ns.
- The light pblock changed the critical path to `ex_mem_rd_reg[1]` -> `ex_mem_alu_result_reg[0]` and increased route share to 76.493%. This suggests the broad pblock constrained placement enough to hurt the load/EX cone.
- Keep `constraints/floorplan_soc_top_light.tcl` as a test vehicle, not as the current board constraint. Future floorplanning should be more targeted, probably driven by placed-cell reports around DMEM BRAM, ALU/load-response, and predictor/update registers.
- The current best board bitstream remains `build/vivado_impl_soc_top_100m_alt_spread/soc_top.bit`.

## Load Response EX Boundary Finding
- A parameterized timing-safe mode is now implemented with `ENABLE_LOAD_RESP_EX_FORWARD=0`. It prevents `load_resp_data` from feeding the ordinary EX datapath, while keeping load-to-branch/JALR registered replay active.
- The directed tests prove both modes: `tb_load_use_one_stall` keeps the performance-mode one-stall ordinary load-use behavior, and `tb_load_use_timing_safe` requires two stalls when the EX boundary is enabled.
- The boundary moves the `soc_top` 100 MHz `alt_spread` worst setup path away from DMEM BRAM to `ex_mem_alu_result`. The new worst path is branch-predictor update control from `mem_wb_rd_reg[2]` to `update_taken_q_reg_rep__5`, with WNS 0.022 ns.
- The timing improvement is modest but real versus the prior no-floorplan `alt_spread` WNS 0.013 ns. Resource use also drops slightly from LUT 6369 / FF 7865 to LUT 6271 / FF 7858, while BRAM and DSP remain unchanged at 24 RAMB36 and 12 DSP48.
- The performance cost is also modest: CoreMark 50 moves from 18431390 to 18995096 measured cycles, a 563706-cycle increase, about 3.06%. Most of the cost is expected from load_use_stalls increasing from 908368 to 1482544.
- The current better board candidate is now `build/timing_sweep_soc_top_100m_loadresp_boundary/soc_top_100MHz_alt_spread/soc_top.bit`, because it has slightly more timing margin and removes the DMEM-to-EX path as the top critical path. If more performance is needed later, the next RTL direction should be a registered ordinary ALU/store replay path rather than restoring direct load-response EX forwarding.

## Branch Predictor Resource Profile Finding
- The local-history predictor is no longer worth keeping in the default FPGA resource profile under the new hard `LUT < 5000` target.
- Disabling local history and shrinking the predictor to `BHT=64` and `BTB=32` reduces the 100 MHz `soc_top` implementation from the prior 6271 LUT timing-safe point to 4740 LUT, while preserving BRAM-based IMEM/DMEM and 12 DSP48 multiplier usage.
- The performance cost is modest on optimized CoreMark: the 50-iteration measured cycles move from 18995096 to 19341937, about a 1.83% slowdown.
- At 100 MHz with 50 iterations, the resource-profile result is still about 2.585 CoreMark/MHz, so it satisfies the current `> 2.5` score target with margin.
- Keep local BHR/PHT as an optional experiment, but the board/resource default should be the trimmed predictor profile unless a later workload proves the predictor accuracy loss matters more than the LUT budget.

## BHT/BTB Scan Finding
- CoreMark is more sensitive to BTB capacity than BHT capacity in the current trimmed predictor profile. Increasing BHT from 64 to 128 with BTB fixed at 32 did not improve the 50-iteration result.
- Increasing BTB from 32 to 64 does improve CoreMark from 19341937 to 19192242 cycles, but the implemented `soc_top` uses 5313 LUT and violates the hard 5000-LUT target.
- Reducing BTB from 32 to 16 saves substantial resources, down to 4327 LUT, while still meeting performance at about 2.564 CoreMark/MHz. This is a good fallback if board integration adds more logic.
- The current default `BHT=64 BTB=32` remains the best accepted baseline because it stays under 5000 LUT and has better performance than the `BTB=16` fallback.

## CoreMark Compiler Flag Scan Finding
- The current `-O3 -funroll-loops` default is still the best accepted CoreMark compiler setting among the tested zero-hardware-risk variants.
- `-Ofast`, `-frename-registers`, and `-fweb` did not change the 2-iteration measured cycle count versus the default on the accepted FPGA resource profile.
- 16-byte function/loop/jump/label alignment is harmful for this CPU/CoreMark point: it increases IMEM from 25592 B to 29692 B and worsens 2-iteration cycles from 773627 to 835912.
- Keep compiler defaults unchanged. The next performance work should return to hardware/microarchitecture or board-clock bring-up rather than adding more GCC flags without a specific hypothesis.

## Real 100MHz Board Clock Finding
- The previous 100MHz `soc_top` timing runs proved the logic could meet 10ns, but the Huoyue board XDC still supplied a 50MHz `sys_clk`. Without a clock generator the board would physically run at 50MHz.
- The new MMCM path fixes that distinction: `sys_clk` remains constrained at 20ns from pin N18, and Vivado auto-derives a generated `clkout0_mmcm` clock with a 10ns period for the CPU domain.
- The final real board-XDC implementation after reset-start gating passes timing with WNS 0.018 ns on `clkout0_mmcm`, no setup/hold failing endpoints, and LUT remains below the 5000 target at 4750.
- UART default `CLKS_PER_BIT=868` now matches 100MHz / 115200 baud. Testbenches still override the divisor to small values and use the simulation clock bypass, so ModelSim does not require Xilinx unisim libraries.

## UART Download Reset-Start Finding
- The old UART flow sent START immediately after downloading, so short programs could finish before the user opened the serial terminal.
- Using `uart_debug_key_n` as a real download-mode gate fixes the board workflow. When the key is held low, CPU execution is held off even if the loader receives START. Releasing the key alone is not enough; a subsequent reset is required to arm normal boot.
- `send_uart_image.ps1` now defaults to no START. The intended board sequence is: hold download key low, send image, open serial terminal, release download key, press reset.
- The old immediate-run behavior remains available with `-StartAfterDownload` when the user explicitly wants it.

## Nonblocking Slow Multiplier Finding
- Single-cycle FAST_MUL is the wrong board tradeoff at 100MHz: it reduces CoreMark 50 to 17932537 cycles, but the implemented Huoyue build fails timing with WNS -3.774 ns.
- A nonblocking slow multiplier is a better timing/performance compromise. It removes nearly all long global MUL waits while preserving the registered multiplier datapath that closes timing on Zynq-7020.
- Sharing multiplier response with the existing load-response writeback port is worthwhile. It avoids the large LUT cost of a third regfile write port, at the cost of rare one-cycle multiplier response holds when load writeback has priority.
- The accepted shared-writeback result is 18369937 CoreMark cycles for 50 iterations, or about 2.722 CoreMark/MHz at 100MHz. This improves the previous resource baseline by 5.025%, but it is not enough for the 3.0 target.
- The cost is moderate resource growth: `soc_top` moves from the previous 4750 LUT reset-start baseline to 5444 LUT. This is a 694 LUT increase, and still closes 100MHz with WNS 0.106 ns.
- The next path to 3.0 needs a larger performance source than multiplier scheduling alone. The most promising hardware directions are load-use/control replay reduction, BTB/local-history capacity if LUT budget allows, or a small instruction/data locality structure; each must be checked immediately with post-route timing.

## Load Response EX Forward Candidate Finding
- Re-enabling ordinary load-response EX forwarding is a real performance win on the current nonblocking multiplier baseline. CoreMark 50 drops from 18369937 to 17806231 measured cycles, about a 3.07% cycle reduction.
- The cost is timing fragility. One 100MHz implementation strategy failed at WNS -0.041 ns, while `ExtraNetDelay_high` closed only at WNS 0.013 ns. The candidate is usable for board measurement but leaves almost no margin for further combinational logic.
- The accepted implementation resources are LUT 5513, FF 5288, BRAM36 24, DSP48 12, with `RAMD64E=0`, so the moderate LUT overage buys performance without breaking the BRAM mapping.
- The score is now about 2.808 CoreMark/MHz at 100MHz. For a 50-iteration CoreMark target of 3.0, the run must be no more than 16666667 cycles; the current candidate still needs about 1139564 fewer cycles, roughly another 6.4% cycle reduction.
- The new worst accepted setup path is route dominated and ends in divider control (`mem_wb_rd_reg[2]` to `u_divider/quotient_reg[22]`). CoreMark barely uses division, so optimizing divider latency will not move the score much; this path matters mainly as a timing-margin limiter.
- The next performance step should first use cheap parameter scans on this LR1 candidate, especially BTB capacity or optional local history, then only keep a candidate if it survives official tests and post-route timing. For RTL work, avoid feeding new long combinational paths into PC/redirect/load-response; register-boundary designs are safer than direct forwarding expansion.

## LR1 Branch Predictor Capacity Finding
- Spending resources on both local history and a 64-entry BTB helps CoreMark, but the gain is not large enough to reach 3.0 by itself. The best timing-clean point is `LOCAL_HISTORY=1 BHT=64 BHR=2 BTB=64` at 17487089 cycles, or about 2.859252 CoreMark/MHz.
- The larger `LOCAL_HISTORY=1 BHT=128 BHR=3 BTB=64` predictor is not worth keeping for the board path. It improves 50-iteration CoreMark by only 27699 cycles versus the small local-history candidate, but it fails 100MHz implementation at WNS -0.093 ns.
- The accepted small local-history candidate is now the fastest verified board bitstream, but it has almost no margin: WNS 0.004 ns. Any further performance logic on the load-response, EX, redirect, or predictor-update cone is likely to break timing unless it adds a clean register boundary.
- Resource cost is significant compared with the trimmed predictor baseline: the accepted local-history board candidate uses 6332 LUT and 7499 FF. This is acceptable only under the current relaxed resource direction, not under the earlier 5000-LUT limit.
- The accepted worst setup path is back in the load-response to EX result cone, from DMEM BRAM clock to `ex_mem_alu_result_reg[0]/D`. This confirms that direct LR1 load-response forwarding is again the timing limiter after predictor capacity is increased.
- Branch prediction capacity still leaves the design about 820422 cycles short of 3.0 on the 50-iteration run. The next score improvement needs a larger source than BHT/BTB sizing, most likely reducing remaining load-use/control stalls through a registered design or improving effective frequency after strengthening the multiplier/DSP timing boundary.

## Load Control Early Replay Finding
- Registered load-to-control early replay is functionally viable and gives a measurable CoreMark win without reintroducing a direct DMEM-to-PC redirect path.
- The useful implementation is narrow: only suppress the first hazard stall for the exact IF/ID branch or JALR that depends on the ID/EX load, then complete the pending control operation from a later registered load response.
- A broad stall on every `ctrl_replay_valid` cycle was counterproductive. It preserved functionality but worsened CoreMark, so the final candidate keeps the original narrower control-conflict condition.
- Correctness requires two non-obvious guards:
  - pending replay must not consume a stale same-`rd` load response visible in the capture cycle;
  - replay-triggered flush must kill wrong-path MEM/WB and load-response writes that would otherwise commit before the corrected control flow takes effect.
- Final ModelSim data shows the feature reduces CoreMark 50 from `17612289` to `17414991` cycles on the same RTL point, a `197298` cycle gain or about `1.12%`.
- This beats the previous Phase 38 simulation point by only `72098` cycles, about `0.41%`, so it is a useful incremental improvement but not enough for 3.0. At 100MHz and 50 iterations, the 3.0 target remains `16666667` cycles, leaving `748324` cycles to remove after this candidate.
- Because the Phase 38 board margin was only WNS `0.004 ns`, this candidate had to pass Huoyue 100MHz implementation before replacing the current fastest bitstream. It did not: `ExtraNetDelay_high` failed by 11 ps and `AltSpreadLogic_high` failed by 86 ps.
- The narrow `ExtraNetDelay_high` failure still had correct QoR (`RAMD64E=16`, `BlockRAM=24`), so the blocker is timing rather than memory inference or gross resource growth.
- A small attempt to simplify the replay flush tag moved timing in the wrong direction (`WNS=-0.220 ns`) and was reverted. This matches earlier experience: local replay/redirect Boolean rewrites are not reliable enough at the current route-dominated margin.
- Current accepted board bitstream remains the Phase 38 small-local-history candidate. The next timing rescue should be targeted placement/floorplanning around the replay/load-response cone, not another one-line control expression tweak.

## Source Operand Hazard Mask Finding
- The hazard unit was comparing raw rs1/rs2 instruction fields for every IF/ID instruction. That creates false load-use and multiplier-scoreboard dependencies for U-type, J-type, and immediate encodings where those bit fields are not real source registers.
- A minimal regression using `lw` followed by `lui` with an immediate field aliasing the load destination caught the issue: old RTL inserted one false load-use stall, while the corrected RTL inserts zero.
- Masking unused source operands at the `cpu_core` decode/hazard boundary is low risk because it does not add data to the EX/load/redirect critical path. It only prevents hazard comparisons from seeing non-source fields.
- The CoreMark gain is real but small: early-replay CoreMark 50 improved from 17414991 to 17378691 cycles. The new result is about 2.877 CoreMark/MHz at 100MHz and still misses the 3.0 target by 712024 cycles on the 50-iteration run.
- Timing did not improve for the early-replay board candidate. The resumed Huoyue 100MHz implementation failed at WNS -0.376 ns even though BRAM QoR was correct. This means the source mask should be kept as a correctness/performance cleanup, but it does not rescue Phase 39 timing.
- `scripts/vivado_route_from_place.tcl` is now available for future long Vivado runs that time out after placement; it can resume route/post-route phys_opt from `post_place.dcp`.

## Current RTL Timing-Clean Fallback Finding
- The latest source tree can still produce a Huoyue 100MHz timing-clean bitstream if `ENABLE_LOAD_CONTROL_EARLY_REPLAY=0` is used. The successful build is `build/vivado_impl_soc_top_huoyue_100m_srcmask_no_lctrl_alt_spread/soc_top.bit`.
- The successful `AltSpreadLogic_high` result has no slack margin to spend: WNS 0.000 ns, TNS 0.000 ns, WHS 0.037 ns. Resources are LUT 6337, FF 7537, BRAM36 24, DSP48 12, with expected QoR `RAMD64E=16 BlockRAM=24`.
- The same current-source no-early-replay configuration is slower than the older Phase 38 accepted artifact: CoreMark 50 is 17575989 cycles versus 17487089 cycles. It is therefore a latest-RTL compatibility fallback, not the fastest board candidate.
- The early-replay source-mask candidate remains the fastest simulation point at 17378691 cycles, but timing failure keeps it off the board path. The 3.0 target still needs a larger architectural performance source than BHT/BTB sizing or false-stall cleanup.

## CoreMark Hotspot Attribution Finding
- The remaining CoreMark bottleneck is ordinary load-use latency, not JALR, multiplier waits, or branch predictor capacity.
- With early replay enabled, 2-iteration CoreMark still has 45060 load-use stalls versus only 7615 branch-mispredict flushes, 5255 jump flushes, and 5 JALR flushes.
- Disabling early replay raises load-use stalls to 55017 while branch/jump flush counts stay unchanged. This confirms early replay is working on a narrow load-to-control class, but the remaining loss is dominated by ordinary load-to-consumer pairs.
- The hottest pairs are simple adjacent producer/consumer instruction pairs in CoreMark's main kernels:
  - `core_bench_list` pointer/data loads immediately consumed by branch or compare logic.
  - `matrix_test` halfword loads immediately consumed by multiply/add chains.
  - `core_state_transition` byte/word loads immediately consumed by classify/update control.
- Branch and jump flush PCs are mostly in `core_state_transition`; eliminating all of them would be useful but still not enough to reach 3.0 because the 50-iteration early-replay gap is about 712024 cycles.
- A next high-leverage RTL experiment should therefore target ordinary load-use cost. A small predictor tweak, larger BHT/BTB, or JALR-only optimization is lower priority unless it is nearly free in timing.

## ID Load Early Read Finding
- ID-stage early load read is a high-return performance direction for this CPU because many CoreMark hot pairs are adjacent load consumers whose base register is already available.
- The safe version must not issue early reads behind older ID/EX or EX/MEM memory operations. Without that guard, a load can observe stale data before an older store commits.
- Early-read forwarded data must be formatted by load width and signedness before being carried into EX/MEM. Forwarding raw DMEM word data breaks byte/halfword consumers and CoreMark validation.
- The current implementation reduces CoreMark 50 from the previous best simulated early-replay/source-mask point `17378691` cycles to `17057625` cycles. That is a `321066` cycle improvement, about `1.85%`.
- Against the fastest timing-clean Phase 38 board bitstream result `17487089`, the new simulation point saves `429464` cycles, about `2.46%`.
- The 3.0 CoreMark/MHz target at 100 MHz and 50 iterations requires `16666667` cycles or less. The current `17057625` cycle result is about `2.931 CoreMark/MHz`, still `390958` cycles short, about another `2.29%`.
- Synthesis-only timing shows the next blocker is not just CPU execution logic. The worst Huoyue `soc_top` path is DMEM BRAM output to `mmio_rdata_q`, so board/debug readback muxing needs to be registered or decoupled before spending time on full post-route for this candidate.
- The first timing rescue confirmed the real loop is broader than MMIO readback: `load_resp_data` can feed the regfile read bypass, then `id_load_early_addr`, then DMEM/MMIO address decode. A same-cycle load response must not be an ID early-read address source.
- Exposing raw regfile read data and building a stable early-read base source is worthwhile. It preserved short CoreMark performance while improving synth WNS by about `1.2 ns`.
- The `id_load_early_read` enable should not depend on global stall cones. For this design, a speculative read during a held IF/ID cycle is safe as long as it is not captured as a valid early load and does not conflict with a real MEM-stage DMEM access.
- SoC MMIO readback should hold its private read data register on non-MMIO cycles. Clearing it every clock creates an unnecessary address-dependent reset/enable cone from CPU early-read address logic into the SoC readback register.
- Adding an explicit `dmem_read_early` qualifier is a good boundary: it preserved short CoreMark performance and moved synth WNS from `-2.608 ns` to `-2.349 ns`. It also moved the worst endpoint away from MMIO readback and back to DMEM BRAM enable.
- Even after these cleanups, the ID early-read candidate is still timing-negative in synthesis. The next rescue should focus on the `id_load_early_addr -> dmem word_index/range check -> RAMB36 ENARDEN` path. Small SoC/MMIO Boolean rewrites are now giving diminishing returns.

## MMIO Hold-Only Timing Cleanup Finding
- The latest exact high-performance simulation baseline is `17198825` cycles for CoreMark 50, about `2.907 CoreMark/MHz` at 100MHz. This is below the earlier `17057625` best ID early-read simulation point, but above the fastest timing-clean Phase 38 bitstream result.
- A DMEM narrow-index/read-enable rewrite is not worth keeping. It removed a full read compare from the BRAM-friendly DMEM path, but synthesis WNS worsened to `-2.590 ns` and reintroduced an MMIO readback reset endpoint. This confirms that Vivado's local mapping of this cone is sensitive, and simple address-index rewrites are not automatically helpful.
- Removing the unsupported-MMIO-read address-dependent clear is a useful small cleanup. It preserves UART/loader/reset-start behavior and improves the same synthesis screen to `-2.196 ns`.
- The true remaining blocker is still the early-read request/address cone into DMEM BRAM enable: source `u_core/mul_resp_rd_reg[0]`, destination `u_dmem/gen_bram_friendly.mem_bram_reg_0_0/ENARDEN`. The path still includes carry-chain address arithmetic and read-enable selection, so the next meaningful RTL change should create a cleaner registered request boundary rather than another local MMIO or DMEM expression rewrite.

## Fast DMEM Select Rejection Finding
- A high-bit DMEM window compare plus trusted DMEM range parameter passed simulation and preserved the short CoreMark result, but synthesis WNS worsened from `-2.196 ns` to `-2.680 ns`.
- The endpoint stayed at DMEM BRAM `ENARDEN`, and the data delay increased to `12.007 ns`. This means removing visible range checks in RTL did not make Vivado build a shorter physical path.
- This result reinforces the earlier narrow-index experiment: small SoC/DMEM address-expression rewrites are now low-confidence for timing rescue. Treat them as rejected unless a later placed/routed result proves otherwise.
- The next RTL route should be a genuine pipeline boundary for early-read request/data replay, not another combinational simplification. If the priority is lower risk, first try floorplanning/implementation strategies on the current MMIO hold-only baseline before changing architecture.

## DMEM BRAM Read-Hold Finding
- The light floorplan experiment did not close timing. It failed at WNS `-1.339 ns` and exposed a BRAM `RSTRAMB` endpoint caused by clearing the DMEM BRAM read output registers on every non-read cycle.
- Holding the BRAM read output on non-read cycles is functionally safe for the tested CPU/SoC paths because committed load data is qualified by the pipeline, MMIO reads are selected through `mmio_read_q`, and official tests/CoreMark do not depend on non-read DMEM data being zero.
- The change passed directed ModelSim, SoC tests, CoreMark 2, applicable `rv32ui`, and full `rv32um`. CoreMark 2 stayed exactly at `687953` cycles.
- The change does not solve timing by itself. Synth-only WNS worsened to `-2.485 ns`, but post-route without floorplan reached `-1.131 ns` and removed the `RSTRAMB` endpoint. The remaining routed worst path is now `redirect_from_replay -> DMEM ENARDEN`.
- Conclusion: keep this as a cleanup that clarifies the real failing path, but do not spend more time on floorplan-only rescue. The next meaningful optimization is a registered boundary for the DMEM read-enable path, especially around load-control replay and ID early-read arbitration.

## Load-Response Forward Duplication Finding
- Duplicating the load-response formatting network only for EX/replay forwarding is a worthwhile small timing cleanup. It keeps the zero-stall load-use behavior and preserves CoreMark cycles, while reducing the shared fanout pressure of the original load writeback/forwarding data path.
- The routed gain is modest but real on the current BTB32 high-performance board build: WNS moved from `-0.531 ns` to `-0.505 ns`; CoreMark 2 stayed at `694006` cycles.
- The change is safer than moving formatting into `dmem`. Pushing formatting into the synchronous memory output made Vivado infer the 8Kx32 DMEM as distributed RAM instead of BRAM, which is unacceptable for this design.
- The worst path remains the same class: DMEM BRAM output through load-response forwarding and ALU logic into `ex_mem_alu_result`. This means the next meaningful improvement likely needs either a real load-use pipeline/issue change or physical placement help; pure expression rewrites are only giving small gains.

## Route-From-Place Timing Finding
- Reusing the best placed design and changing only route/post-route optimization is currently the highest-return timing step.
- `NoTimingRelaxation` routing plus post-route `AggressiveExplore` improved the current load-forward-duplication board build from WNS `-0.445 ns` / TNS `-8.188 ns` to WNS `-0.204 ns` / TNS `-3.023 ns`.
- The best artifact is `build/vivado_route_soc_top_huoyue_loadfwddup_btb32_no_timing_relax/soc_top.bit`. It is not timing-clean yet, but it is the best 100 MHz Huoyue result for this RTL.
- The route-only result uses normal BRAM inference: resources are LUT `6457`, FF `5745`, BRAM `24`, DSP `12`, with `RAMD64E=16`.
- `AlternateFlowWithRetiming` did not help this placed design. It worsened WNS to `-0.272 ns`, so retiming should not be the default post-route rescue for this point.
- Two RTL attempts were rejected:
  - direct `dec_rs1` for ID early-read load-base dependency checks preserved behavior but worsened routed WNS to `-0.462 ns`;
  - SoC-only DMEM read-always mode improved synth but worsened routed WNS/TNS to `-0.516 ns` / `-58.402 ns`.
- The current remaining critical path is DMEM BRAM output through load-response forwarding and ALU logic into `ex_mem_alu_result`. Future RTL work should reduce that data path or give it a physical/register boundary; BRAM enable control is no longer the best immediate target after the route rescue.

## Load/EX Rescue Rejection Finding
- Splitting the load-response forward formatting into separate rs1/rs2 copies is not beneficial on this design point. It keeps CoreMark unchanged, but synthesis WNS worsens from `-1.809 ns` to `-1.929 ns` and resource use rises, while the same DMEM-to-EX path remains worst.
- A narrow-looking load/EX pblock can still hurt unrelated control timing because post-synth names and optimized cones overlap with branch predictor/replay/JALR logic. The attempted pblock moved the worst path to redirect target generation and reported RAMB36 over-utilization, so it should not be reused.
- Router-only search is also not uniformly helpful. `HigherDelayCost` performed worse than `NoTimingRelaxation` on the same placed checkpoint, ending at WNS `-0.338 ns` versus the current best `-0.204 ns`.
- The best retained timing artifact remains `NoTimingRelaxation + AggressiveExplore` from the known-good `post_place.dcp`. More progress probably requires changing the microarchitectural timing boundary, not more expression duplication or hand pblocks around this path.

## JAL BTB Prediction Finding
- Registered ordinary load-to-ALU replay is not a good tradeoff for this project. It reduces some load-use stall accounting, but it serializes enough useful work that CoreMark 2 regresses from `694006` to `750355` cycles and synthesis also worsens.
- Predicting unconditional `JAL` targets is a worthwhile performance optimization. It does not touch the DMEM load-response-to-ALU data path, and CoreMark 2 improves to `678919` cycles with the current high-performance BTB32/local-history generics.
- JAL should not be trained as a normal conditional branch. Doing so improves cycles, but also perturbs BHT/PHT/local history. A separate BTB unconditional bit keeps JAL target prediction independent from conditional branch direction learning.
- The new predictor behavior is covered by `tb_branch_predictor` for unconditional BTB hits and `tb_jal_predict` for repeated JAL redirect reduction.
- Synthesis is not free: the current JAL unconditional candidate has synth WNS `-2.033 ns`, worse than the pre-JAL `-1.809 ns` synth screen. Because the performance gain is about `2.17%`, this remains a valid performance-priority candidate, but it must be judged by post-route timing before becoming the board bitstream.
- Post-route confirms the candidate cannot replace the board bitstream yet. The best JAL unconditional implementation tested is `AltSpreadLogic_high/AggressiveExplore/Explore/AggressiveExplore` at WNS `-0.521 ns`; both route-from-place `NoTimingRelaxation` and `ExtraNetDelay_high` are worse.
- The JAL performance gain is worth preserving in simulation, but the added ID/JAL prediction and update logic has made control-to-DMEM-enable timing fragile again. The next useful RTL work is not more route directive search; it is reducing or registering the `redirect/id_jal/predictor_update -> early-read/dmem_read -> BRAM ENARDEN` cone while keeping JAL predicted-hit behavior.

## ID Early-Read Predecode Finding
- Removing `ctrl_replay_valid` and `flush` from `id_load_early_read` is safe in this pipeline and useful for timing. The read can be speculative because pipeline valid/flush logic still decides whether the read result is captured and retired.
- Predecoding only the load base register and load immediate into IF/ID is a better boundary than reusing the generic hazard/decode source selection for early-read address generation. It reduces the fetch/decode/control fan-in visible to the DMEM request path without changing CoreMark cycles.
- The accepted predecode point keeps the JAL unconditional BTB performance result: CoreMark 2 remains `678919` cycles and CPI `1.164976`, with full `rv32um` and applicable `rv32ui` passing.
- The post-route gain is enough to make this the current best artifact: WNS improves from the previous best `-0.204 ns` route-only load-forward build to `-0.176 ns` on the JAL/predecode full implementation, while also preserving the faster JAL simulation point.
- The `NoTimingRelaxation` route-from-place rescue is not universally helpful. On this placement it worsened timing to WNS `-0.317 ns`, so the full implementation artifact should be kept instead.
- Multiplier operand gating is not a useful timing cleanup here. It adds enough operand mux/control cost to worsen synthesis WNS, and CoreMark does not improve.
- The remaining critical path has returned to DMEM BRAM output feeding `ex_mem_alu_result`. Further progress should target the load-response-to-EX result cone or a nearby register/placement boundary; more early-read control expression tweaks are lower confidence now.

## Fast-Mul Generate and ExtraNetDelay Route Finding
- Wrapping fast-mul products in a `generate if (FAST_MUL != 0)` block is a safe RTL hygiene improvement, but it did not change the current `FAST_MUL=0` Huoyue synthesis WNS or resource shape. Vivado was already pruning the inactive fast-mul result path for this generic set.
- The useful improvement came from implementation, not RTL: the `ExtraNetDelay_high` placement plus route-only `Explore` recovered additional margin and moved the best WNS from `-0.176 ns` to `-0.099 ns`.
- `NoTimingRelaxation` is no longer the best route directive for this placement. On the same `post_place.dcp`, `Explore` reached `-0.099 ns`, `NoTimingRelaxation` reached `-0.133 ns`, and `MoreGlobalIterations` fell back to `-0.341 ns`.
- The new worst path is `ex_mem_rd -> redirect_branch_mispredict`, not DMEM output to ALU. That means the remaining timing problem has shifted toward branch/redirect control and route placement, so the next RTL optimization should be aimed at that registered branch-mispredict boundary if another route attempt cannot close the last 0.1 ns.

## Control Forward Selector Duplication Finding
- Duplicating forwarding select logic for the branch/control path is misleading in this design point. It improves synthesis WNS, but worsens post-route timing from the current best `-0.099 ns` to `-0.498 ns`.
- The regression indicates Vivado used the extra duplicated compare/mux logic in a way that disturbed the DMEM-to-EX physical path, even though the targeted control path looked better before routing.
- Treat synth-only improvement on this late-stage design as insufficient evidence. For the remaining 0.1 ns closure problem, accept only changes that improve post-route timing from the known ExtraNetDelay placement or from a full implementation.
- Next higher-confidence directions are physical implementation variants from the current best placement, or a real architectural/register boundary around redirect/branch-mispredict generation. More local duplication in already dense EX/control cones is low-confidence.
- An `AdvancedSkewModeling` route from the current best placement also failed to improve timing, ending at WNS `-0.277 ns`.
- The worst path stayed `ex_mem_rd -> redirect_branch_mispredict` and became even more route dominated. This reinforces that the remaining problem is not likely to be solved by another generic router directive alone.

## Branch EX/MEM Wait Finding
- Stalling branch/JALR consumers of EX/MEM results is too expensive for CoreMark. The broad version adds about `24k` cycles in a 2-iteration run, which is unacceptable.
- Restricting the stall to less-than class branches reduces the loss but still regresses CoreMark 2 by `5624` cycles and worsens synthesis WNS to `-1.809 ns`.
- This means the current `ex_mem_rd -> redirect_branch_mispredict` path should not be solved by inserting dependency stalls. The timing gain is not even visible at synth, and performance moves in the wrong direction.
- Future attempts should preserve same-cycle ALU-to-branch forwarding and instead simplify the physical/logic cone, for example by changing branch compare structure or placement attributes, not by serializing branch consumers.

## Branch Compare Split Finding
- Splitting the branch compare RTL into explicit equality and less-than cones preserves behavior and CoreMark, but it does not improve timing in practice.
- The synth screen stayed at `-1.723 ns`, and the full post-route trial worsened to WNS `-0.572 ns`.
- The rejected result indicates Vivado's placement/routing around the current branch/redirect cone is very sensitive. Small stylistic compare rewrites are not reliable closure moves at this point.
- Keep the new `vivado_impl_from_opt.tcl` helper; it successfully resumed from `post_opt.dcp` and avoided re-running synthesis during implementation experiments.

## No-BHR Predictor Finding
- Disabling local history/BHR removes the PHT/BHR structures, but CoreMark loses about 5k-10k cycles compared with the best local-history points.
- `BP_INIT_TAKEN=1` is worth keeping as an optional generic. With no BHR, it improves CoreMark 2 by roughly 3k cycles because learned BTB targets become taken sooner, while the default remains unchanged for baseline regressions.
- The best no-BHR performance found so far is `BHT1024/BTB1024/init_taken=1` at `630043` cycles, still short of the `625000` cycle requirement for 3.2 CoreMark/MHz.
- A reasonable no-BHR point, `BHT512/BTB256/init_taken=1`, uses fewer predictor features but synthesizes to WNS `-2.348 ns`; the worst path is still DMEM BRAM output to `redirect_valid`, not the BHR/PHT cone.
- Oversizing the no-BHR BTB/BHT is counterproductive. `BHT1024/BTB1024/init_taken=1` only improves cycles to `630043`, but explodes to LUT `31383`, FF `74727`, and WNS `-3.323 ns`.
- Recommendation: use no-BHR as a resource/timing fallback, not the 3.2 performance path. For 3.2 with timing, keep the predictor moderate and move the next optimization to the load-use/redirect datapath.

## CoreMark 3.0 Hard-Target Closure Finding
- A fully no-BHR predictor is not the best final answer for the revised target. It can reduce predictor structure, but practical no-BHR configurations either do not keep enough performance margin or still fail timing/resource screens when the BHT/BTB is enlarged.
- A very small local-history predictor is the better compromise:
  - `BHT64/BHR2/BTB64`
  - `RAMD64E=16`
  - LUT `6800`
  - CoreMark 2 `650534` cycles, about `3.074 CoreMark/MHz`
  - post-route physopt WNS `0.000 ns`
- The high-risk performance features for this hard target are still ID load early read and load-control early replay. They help cycles, but have repeatedly exposed DMEM/redirect timing paths that are too expensive for a clean 100 MHz board candidate.
- The current selected bitstream meets all revised hard targets, but has no setup slack margin. Treat it as timing-clean but fragile. The next useful optimization should add margin on the current multiplier-to-EX/MEM result path before increasing predictor size or re-enabling aggressive load-use features.

## Slow-Multiply EX-Result Cut Finding
- Cutting `FAST_MUL=0` slow `mul_result` out of `m_result/ex_result` is functionally safe for the tested paths, but it is not a useful timing optimization for this design point.
- The path reappears physically through multiplier completion forwarding into a following instruction's EX result, or the implementation falls back to a DMEM-to-EX/MEM path. In both cases post-route timing is worse than the selected baseline.
- Reject this direction unless the multiplier forwarding protocol is redesigned more deeply. A one-line `m_result` mux cut is not enough to create timing margin.

## BTB128 Parameter Trial Finding
- The next simple performance knob after the selected `BHT64/BHR2/BTB64` point is BTB capacity. Increasing only BHT to 128 barely helps (`650534 -> 650164` cycles), while increasing BTB to 128 gives a real improvement (`650534 -> 642851` with BHT64, `642241` with BHT128).
- `BP_INIT_TAKEN=1` is not useful when local history is still enabled in this small predictor point; it slightly worsened the baseline to `650464` cycles.
- `BHR3` is not worth the added predictor pressure here. `BHT64/BHR3/BTB128` measured `642391` cycles, essentially the same as `BHT128/BHR2/BTB128`, but it does not solve timing.
- `BTB256` is rejected by resource, not performance. It reached `640890` cycles, but synthesis used `11235` LUT and `21304` FF, exceeding the hard `LUT < 9000` target.
- The best resource-legal performance candidate, `BHT64/BHR2/BTB128`, still fails post-route timing. It uses `8124` LUT and keeps RAMD64E at `16`, but the best tested route is WNS `-0.228 ns`; route-only `NoTimingRelaxation` and `AdvancedSkewModeling` are worse.
- Conclusion: larger BTB is a performance win but not timing-clean in the current microarchitecture. Do not increase BTB beyond 64 for the hard 100 MHz target unless a separate RTL timing boundary or placement change first removes the DMEM/load-response to EX result critical path.

## M-Extension Load-Response Forwarding Finding
- The DMEM/load-response critical path can appear under `u_multiplier` names after Vivado hierarchy rebuild, but disabling M-extension load-response forwarding is not a valid small fix.
- With `FAST_MUL=0`, load-to-mul correctness depends on forwarding the same-cycle load response into the multiplier operand path. If that path is disabled without a matching ID/EX replay or operand capture, the existing load-mul test computes the wrong result.
- Stalling only IF/ID is also insufficient because the dependent M-extension instruction may already be held in ID/EX with stale operands when the load response arrives.
- A correct timing-safe version would need a dedicated ID/EX M-extension replay path or operand update on the wait cycle. That should be treated as a larger architectural experiment, with a new regression for load-to-mul replay and a CoreMark performance screen before Vivado.

## BTB Index Hash Finding
- A tiny BTB64 XOR hash can recover a measurable amount of CoreMark performance without increasing BTB depth. The best tested shift is `BP_BTB_INDEX_HASH=8`.
- The improvement is stable but small:
  - CoreMark 2: `650534 -> 646977`
  - CoreMark 50: `16263300 -> 16172005`
  - estimated 100 MHz CoreMark/MHz: about `3.074 -> 3.092`
- The timing cost is not acceptable at the current fragile point. The hash 8 implementation fails at WNS `-0.511 ns`, even though resources remain below the hard limit at LUT `6912` and RAMD64E `16`.
- The worst path is not the BTB hash lookup path. It is a route-dominated control path from `ex_mem_valid` into `redirect_valid`, so more predictor capacity or index tweaks are unlikely to be the highest-confidence route to a better board candidate.
- Keep `BP_BTB_INDEX_HASH` as a default-off experiment switch. Do not use hash 8 for the board bitstream until the redirect/control timing path is improved.

## Redirect/MUL Boundary Finding
- Registering a broad EX/MEM forwarding write-enable boundary is not a good timing fix here. It moved the worst path into `ex_mem_rd -> redirect_valid` and failed post-route timing at WNS `-0.812 ns`, despite preserving CoreMark cycles.
- A narrow jump redirect split is safer: keep ordinary unpredicted jump flush detection simple, and only compare targets for early-redirected JALR mismatch. This preserves behavior and reduces LUT slightly, but by itself still failed timing at WNS `-0.113 ns`.
- The useful margin gain came from the multiply early-forward guard. `mul_early_valid` is already the aligned valid for the slow multiplier's early result, so feeding `mul_meta_valid_pipe[1]` and `mul_meta_reg_write_pipe[1]` into the EX result forwarding mux adds timing pressure without improving correctness for the current M-extension path.
- The accepted combined result keeps CoreMark unchanged at `16263300` cycles for 50 iterations, while post-route physopt improves from the fragile Phase 46 WNS `0.000 ns` to `0.007 ns` and LUT drops from `6800` to `6780`.
- The new worst setup path is DMEM BRAM output to `ex_mem_alu_result`. Further performance work should assume load-response/EX-result logic is again the limiting region; re-enabling aggressive load replay or adding predictor capacity should not be attempted without immediate post-route verification.

## Load-Control Replay Retest Finding
- Sharing the load-response formatter is not a reliable timing optimization. It improved synthesis but failed post-route timing at WNS `-0.413 ns`; the routed worst path moved into `ex_mem_reg_write -> redirect_valid` with very high routing delay. Keep the duplicated kept formatter for the current physical design point.
- `ENABLE_LOAD_CONTROL_EARLY_REPLAY=1` is the strongest near-term performance knob that still stays within resource limits. Current CoreMark 2 improves `650534 -> 638694` cycles and load-use stalls drop to `21001`.
- The retested `lctrl=1` synthesis is better than the accepted baseline synthesis (`-2.264 ns` vs `-3.011 ns`) even though it adds control replay logic. This is enough evidence to run a full implementation, but not enough to accept it without post-route closure.
- Acceptance criteria for `lctrl=1`: post-route WNS must be non-negative at 100 MHz, LUT must stay below 9000, and full ModelSim plus official rv32ui/rv32um plus CoreMark 50 must be rerun before replacing the Phase 48 board candidate.
- The first full `lctrl=1` implementation failed post-route timing at WNS `-0.401 ns` with LUT `7054`. The worst path changed from direct DMEM output to an ID/EX operand through the ALU into `ex_mem_alu_result`, and route delay was `8.074 ns`. This is still the same load-response/EX-result physical region, not a predictor-capacity issue.
- Closing `lctrl=1` likely needs either a different route from the existing placement or a targeted RTL boundary on load-response-to-ALU consumers. Disabling all load-response EX forwarding is not acceptable: it dropped CoreMark 2 to `673993` cycles, below the 3.0 CoreMark/MHz target.
- A route-only `NoTimingRelaxation` pass from the same placement improves `lctrl=1` to WNS `-0.295 ns`, but still fails setup timing and changes the worst path into frontend flush/reset control. That means implementation strategy can recover about 0.1 ns, but not the full 0.4 ns needed.

## Phase 49 Replay/Boundary Rejection Finding
- `ENABLE_LOAD_CONTROL_EARLY_REPLAY=1` remains a strong performance knob but is not currently timing-clean. The best short simulation point in this pass was CoreMark 2 `638694` cycles, but the first implementation failed at WNS `-0.401 ns`, and the best recorded route-only rescue from that placement was still negative.
- Prefetch flush payload-hold was rejected and reverted. It preserved CoreMark 2 (`638694` cycles) and static checks, but full implementation worsened to WNS `-0.476 ns`; the route-only `Explore` result remained negative at WNS `-0.421 ns`.
- `MUL_STAGES=2` with `lctrl=1` was rejected. It still met the 3.0 short performance target at CoreMark 2 `646614` cycles, but synthesis and implementation both worsened, with full implementation WNS `-0.452 ns`, LUT `6924`, FF `8430`.
- Delaying branch predictor branch-update by one cycle was rejected and reverted. It passed full ModelSim and kept CoreMark 2 at `646793` cycles, and synthesis improved to WNS `-2.064 ns`, but full implementation still failed at WNS `-0.402 ns`, TNS `-12.851 ns`, LUT/FF/BRAM/DSP `6965/8659/24/12`. The worst path moved to `ex_mem_rd_reg[0] -> redirect_valid_reg/D`, so this did not solve the routed redirect/control pressure.
- Route-only `Explore + AggressiveExplore` from the accepted Phase 48 placement was also not useful. It ended at WNS `-0.193 ns`, TNS `-2.977 ns`, with 36 setup failing endpoints. The accepted `AdvancedSkewModeling` artifact remains better at WNS `0.007 ns`.
- Current board candidate remains `build/vivado_impl_soc_top_coremark30_mul_early_boundary_adv_skew/soc_top_physopt.bit`: CoreMark 50 `16263300`, about `3.074 CoreMark/MHz`, LUT `6780`, FF `8280`, BRAM36 `24`, DSP `12`, WNS `0.007 ns`.
- Next promising work should target the DMEM/load-response-to-EX-result cone directly, or add a controlled replay boundary only for a narrower consumer class. Re-enabling broad early replay or increasing predictor pressure should not be retried without a new architectural timing boundary.
## 2026-05-27 CSR Branch Initial Findings
- Current branch: `新增CSR`; `git status --short` showed no tracked/untracked changes at the start of this CSR pass.
- Existing CSR hardware is minimal:
  - `rtl/csr_unit.v` only implements `mcycle` and `minstret` counters.
  - `rtl/cpu_core.v` reads only CSR addresses `0xB00` (`mcycle`) and `0xB02` (`minstret`), returning zero for everything else.
  - `decoder.v` marks `OPCODE_SYSTEM` with `funct3 != 0` as a CSR instruction and always enables register writeback, but there is no CSR write/update path.
  - `exception.v` is a standalone placeholder for illegal/load/store misaligned causes and is not integrated into the pipeline trap flow.
- Existing CSR regression is `tb/tb_csr_counter.v` plus `tb/programs/csr_counter.hex`; it only checks `csrr mcycle` and `csrr minstret`.
- Existing CoreMark code reads `mcycle` using `csrr`, so the current subset is enough for benchmarking but not enough for privileged/software bring-up.
- Official `riscv-tests` includes `rv32mi` CSR/trap tests, but the current local `sw/riscv-tests-env/riscv_test.h` is a user-mode oriented minimal harness and does not yet provide a machine trap setup suitable for those tests.
- Main CSR gaps for an industrial-style RV32IM machine-mode core:
  - CSRRW/CSRRS/CSRRC and immediate variants need read-modify-write semantics.
  - Machine CSRs such as `mstatus`, `misa`, `mie`, `mtvec`, `mscratch`, `mepc`, `mcause`, `mtval`, `mip`, `mcycle`, and `minstret` need defined behavior.
  - `ecall`, `ebreak`, `mret`, illegal instruction, misaligned fetch/load/store, and interrupt/trap redirect behavior need a precise pipeline integration point.
  - The implementation must preserve existing CoreMark/timing-sensitive behavior and avoid adding broad combinational paths into redirect/load-response critical regions.
- Parameterization requirement:
  - CSR data paths, CSR registers, trap PC/mtval/mepc values, and read/write masks should use `XLEN`.
  - RV32 and RV64 differ in `misa.MXL`, `mstatus` high fields, and counter width exposure, so these must be represented by helper constants/masks instead of hard-coded 32-bit literals.
- Current `cpu_core.v` control structure relevant to trap integration:
  - Existing redirect/flush is built around branch mispredict and jump flush detection; there is no trap/mret redirect class yet.
  - `frontend_flush` feeds the prefetch flush path; adding trap/mret should reuse this path rather than creating a separate front-end kill mechanism.
  - `dmem_write` is already gated by `!replay_flush`, but first-stage CSR work needs a more general kill/commit gate for store, CSR write, branch predictor update, register write, and long-latency M-extension issue.
  - Branch predictor update currently uses `ctrl_valid && ctrl_branch && !pipe_wait` and ID-stage JAL update; trap/mret must prevent wrong-path predictor updates.
  - Existing `ctrl_pending_conflict_stall` already treats CSR instructions as side-effecting during pending load-control replay, which supports the design choice that CSR updates must occur only at a safe commit boundary.
- RISC-V official spec notes used for design:
  - Zicsr CSR instructions atomically read-modify-write a 12-bit CSR address and have special read/write suppression rules for `rd=x0`, `rs1=x0`, and `uimm=0`.
  - `mtvec` direct mode sends traps to BASE; vectored mode changes only asynchronous interrupt targets, so first-stage synchronous-only trap handling can use BASE for all traps.
  - On M-mode trap entry, `mepc`, `mcause`, and optionally `mtval` are written and `mstatus.MIE/MPIE/MPP` are updated.
  - `mret` restores interrupt enable state and jumps to `mepc`.
- User-approved first-stage CSR/trap scope:
  - Handle only M-mode synchronous exceptions and Zicsr.
  - Do not implement S/U mode, PMP, MMU, timer/software/external interrupt response, CLINT, or PLIC.
  - Keep `mie`, `mip`, and `mstatus.MIE` as register foundations for later interrupts, but do not trigger asynchronous traps in this phase.
  - Trap causes: instruction address misaligned 0, illegal instruction 2, breakpoint 3, load address misaligned 4, store/AMO address misaligned 6, environment call from M-mode 11.
  - `mtval`: illegal instruction/illegal CSR writes original 32-bit instruction zero-extended to XLEN; instruction address misaligned writes the bad control-flow target; load/store misaligned writes the effective address; ecall/ebreak writes zero.
  - Legal `mret` is a redirect, not an exception; illegal `mret` forms trap cause 2.
  - Trap/mret/older flush kill gates must cover register writes, load/mul shared writeback, DMEM writes, CSR writes, trap entry, mret recovery, predictor update, RAS update, M-extension issue, replay capture, and `minstret` counting.
- CSR table design direction:
  - Implement readable machine CSRs: `mstatus`, `misa`, `mie`, `mtvec`, `mscratch`, `mepc`, `mcause`, `mtval`, `mip`, `mcycle`, and `minstret`.
  - Keep `mvendorid`, `marchid`, `mimpid`, and `mhartid` as read-only identity CSRs. `mhartid` returns the `HART_ID` parameter; the other identity CSRs may return zero in this first stage.
  - Treat unimplemented or privilege-invalid CSR access as illegal instruction trap.
  - Treat writes to read-only CSRs as illegal instruction trap.
  - Use WARL masks for writable CSRs rather than storing arbitrary bits.
- Verification design direction:
  - Use test-first development for every CSR/trap behavior: add a focused failing test, verify it fails for the expected missing behavior, then implement the minimal RTL.
  - Start with `csr_unit` unit tests for Zicsr semantics and CSR bank state because these isolate XLEN, WARL, trap entry, and mret behavior from pipeline hazards.
  - Add CPU-level program tests only after CSR unit behavior is proven, so failures can be attributed to pipeline integration rather than CSR bank semantics.
  - Add at least one `XLEN=64` compile/unit smoke for `csr_unit`; the full CPU can remain RV32 in this phase.

## 2026-05-27 CSR Phase 50 Findings
- The first-stage CSR implementation now covers the approved M-mode synchronous scope: Zicsr CSR read/write semantics, an XLEN-parameterized M-mode CSR bank, trap entry, MRET restore, ECALL, EBREAK, illegal CSR access, general illegal instruction decode, load/store address misaligned traps, and branch/JAL/JALR instruction-address-misaligned traps.
- `csr_unit` is the single owner of CSR state. `cpu_core` only issues normal CSR commit, trap entry, and MRET commit requests at controlled pipeline boundaries, while keeping redirect, flush, younger-instruction kill, and side-effect gating in core control.
- The conservative CSR hazard is intentionally broader than only CSR-after-CSR. Branch/jump/load/store instructions can themselves create trap entries, so they now wait behind an older CSR write to avoid trapping through stale `mtvec`/CSR state. The CoreMark 2 smoke changed only from the previous CSR-pass `649738`-class result to `649739`, so the functional safety cost is currently negligible at this smoke size.
- Official `rv32mi/csr` and `rv32mi/mcsr` now pass after the riscv-test scripts default to `rv32im_zicsr_zifencei` and the local test environment includes official `encoding.h`.
- Official `rv32mi` trap programs are not yet valid acceptance tests in this repo. `rv32mi/illegal` still times out with no pass/fail marker because the local minimal `sw/riscv-tests-env/riscv_test.h` does not install the official machine trap-vector startup handler. A real machine-mode riscv-test environment should be added before using official `illegal`, `scall`, `sbreak`, or misaligned trap tests as sign-off.
- The first-stage implementation deliberately does not implement S/U mode, PMP, MMU, CLINT, PLIC, timer/software/external interrupt response, or asynchronous trap taking. `mie`, `mip`, and `mstatus.MIE` exist as future interrupt foundations only.
- No new Vivado timing sign-off was run for this CSR branch. Functional sign-off currently consists of focused CSR trap programs, CSR unit tests including XLEN64, full ModelSim regression, official rv32ui/rv32um simulation, official rv32mi CSR smoke, and a short CoreMark smoke.

## 2026-05-28 CSR Phase 51 Findings
- The local official-riscv-test environment now has a real machine-mode reset/trap harness while preserving the project's fixed external pass/fail addresses. This makes official `rv32mi` trap tests useful acceptance inputs instead of timing out before `mtvec` is initialized.
- The harness intentionally stays first-stage: it installs `mtvec` and calls the official test-provided weak `mtvec_handler`, but it does not initialize PMP, SATP, medeleg/mideleg, S-mode, U-mode, or asynchronous interrupt state.
- `misa` must behave as a legal WARL CSR for the official `ma_fetch` test. Writes that request unsupported extensions, including the C bit, are accepted and read back as the fixed implemented ISA value; treating those writes as illegal traps is too strict for machine-mode software compatibility.
- The accepted official `rv32mi` first-stage set is `csr,mcsr,illegal,scall,sbreak,shamt,lh-misaligned,lw-misaligned,sh-misaligned,sw-misaligned,ma_fetch,ma_addr`.
- `rv32mi/instret_overflow` is now the main precise-counter gap. Focused `csr_unit` coverage proves low/high `minstret` overflow state update works, but the CPU-level test still fails when reading `minstreth` after the overflow sequence. The next fix should inspect retire-count timing versus CSR read visibility, not the basic CSR bank arithmetic.
- `rv32mi/zicntr` is not first-stage acceptance because it uses user-level counter aliases such as `cycle` and `instret` at `0xC00/0xC02`, which are not implemented in the current M-mode-only CSR bank.
- `rv32mi/breakpoint` and PMP-oriented tests remain out of scope: debug trigger CSRs (`tcontrol`, `tselect`, `tdata*`) and PMP registers are deliberately not part of this CSR phase.

## 2026-05-28 CSR Phase 52 Findings
- Normal CSR state updates must be aligned to the retire boundary, not to EX/MEM. Otherwise split writes to counter CSRs can be interleaved with implicit `mcycle/minstret` updates and become architecturally visible in the wrong order.
- The `csr_unit` explicit-counter-write priority was correct, but only once `cpu_core` presented ordinary CSR commits at the same boundary as `retire_count_i`. The bug was top-level pipeline timing, not CSR-bank arithmetic.
- A younger CSR-state reader must stall while an older CSR instruction is still in ID/EX, EX/MEM, or MEM/WB. A hazard that only watches EX/MEM is too narrow after CSR commits move to MEM/WB.
- The official first-stage `rv32mi` acceptance set can now include `instret_overflow` in addition to `csr,mcsr,illegal,scall,sbreak,shamt,lh-misaligned,lw-misaligned,sh-misaligned,sw-misaligned,ma_fetch,ma_addr`.
- The added CSR precision stalls mainly affect CSR-heavy tests. The short CoreMark smoke moved only from the previous `649739`-class measured cycles to `649741`, so this is a good correctness tradeoff for the CSR branch.
- Remaining first-stage exclusions are unchanged: user counter aliases used by `zicntr`, debug trigger/breakpoint CSRs, PMP, asynchronous interrupt response, and Vivado timing sign-off are still future phases.

## 2026-05-28 CSR Phase 53 Findings
- CSR functional acceptance should be scriptable. `run_csr_phase_acceptance.ps1 -SkipVivado` now provides a repeatable simulation gate for the CSR branch instead of relying on a hand-run command list.
- `run_vivado_impl.ps1` is not a timing acceptance gate by itself. It can complete, write a bitstream, and return exit 0 even when post-route WNS is negative. Hardware signoff needs an explicit timing report gate, now added as `check_vivado_timing.ps1`.
- The current CSR branch passes simulation acceptance but fails Huoyue `soc_top` 100 MHz timing. The `alt_spread` implementation has correct memory QoR (`RAMD64E=0`, `BlockRAM=24`) and moderate resources (`6962` LUT), so the immediate blocker is timing, not BRAM inference or resource overflow.
- The worst path is a route-dominated PC/redirect/control cone from `mul_meta_rd_pipe[2][0]` to `pc_reg[2]_rep`, with Vivado-optimized logic names crossing multiplier, CSR, redirect, and PC-select logic. This points to the control/hazard/redirect path, not the CSR bank arithmetic, as the next area to inspect.
- Do not add more privileged features until this path is addressed. Adding `zicntr`, async interrupts, PMP, or debug CSRs would increase control/state pressure before the current branch has a timing-clean hardware baseline.

## 2026-05-28 CSR Phase 54 Timing Findings
- The detailed Phase 53 worst path is not a simple CSR-bank path. It starts at `mul_meta_rd_pipe_reg[2][0]`, then passes through optimized logic corresponding to multiplier forwarding/result selection, ALU/effective-address calculation, trap/CSR redirect classification, ID-stage redirect gating, and final PC selection before reaching `pc_reg[2]_rep`.
- The timing path is route-heavy (`9.838 ns` route out of `12.887 ns` data delay), so placement matters, but the number of participating control/data conditions is still too high for a robust 100 MHz signoff point.
- The Phase 52 precise-retire fix widened CSR-state hazards to include ID/EX, EX/MEM, and MEM/WB CSR instructions. This is architecturally correct for `instret_overflow`, but it also feeds `fetch_stall`, `id_jal_redirect`, `id_jalr_ras_redirect`, `id_stage_accept`, and the PC hold/update block through `hazard_stall`.
- Any timing rescue must preserve the key CSR rule: younger CSR-state readers and younger trap-generating instructions cannot observe or trap through stale CSR state while an older CSR write has not reached the MEM/WB CSR commit boundary.
- A safe first boundary is to remove `csr_redirect_detect` from the same-cycle ID-stage JAL/JALR PC-select expressions while keeping it on side-effect gates. An older EX trap/MRET redirect is already captured into `redirect_valid` and will flush/overwrite the speculative younger fetch on the next cycle; predictor update and RAS pop/push must still be killed in the detection cycle.
- The new `trap_kills_id_redirect` program protects this behavior by placing `jal fail` immediately after `ecall`. The trap handler must still run and return to a safe label, proving the younger ID redirect is functionally harmless when its side effects are killed.
- Phase 54 timing runs show a stepwise shift of the worst path as each direct CSR/control edge is removed:
  - Phase 53 baseline: WNS `-3.121 ns`, worst endpoint `pc_reg`.
  - ID redirect split: WNS `-3.482 ns`, worst endpoint RAS stack CE.
  - RAS registered side-effect boundary: WNS `-2.909 ns`, worst endpoint `minstret`.
  - counter write suppression boundary: WNS `-2.399 ns`, worst endpoint `minstret`.
  - counter case split: WNS `-1.964 ns`, worst endpoint `mtval`.
  - trap/MRET commit registered boundary: WNS `-1.987 ns`, worst endpoint branch predictor `update_pc_q` CE.
- The latest final routed path is from `redirect_csr_flush_reg` into branch predictor update register CE, route-heavy at `77.957%`. This is no longer a CSR-bank data-path problem; it is a side-effect request boundary problem.
- Branch predictor updates are normal side effects and must be killed by older trap/MRET/redirect flushes, but the predictor should not see the whole EX/ID/flush control cone directly. Registering `bp_update_*` in `cpu_core` is the next targeted boundary to test.
- Registering branch predictor update requests improved post-route WNS from `-1.987 ns` to `-1.545 ns` and moved the worst endpoint away from the predictor. The new worst endpoint is `redirect_fallthrough_pc_q` CE, so the next high-confidence boundary is redirect payload CE removal.
- Redirect payload registers (`redirect_pc_q`, `redirect_fallthrough_pc_q`, `redirect_taken_q`) do not need a wide enable. They are consumed only when `redirect_valid` is high in the following cycle. Loading their next values every cycle keeps semantics while avoiding a control-heavy CE path.
- The broad no-CE redirect payload attempt was not useful: post-route WNS regressed to `-1.617 ns` and the worst path moved to `redirect_pc_q` D. Reject this exact shape because it trades a bad CE path for a bad redirect target data path.
- A narrower payload-capture gate is more promising: capture payload when the instruction class is a possible control transfer, but do not include `ctrl_valid`/`control_load_resp_dep`. If the control instruction is waiting on a load response, the captured payload may be stale but is not consumed because `redirect_valid` remains false. The next Vivado run should test whether this removes the load-response dependency from payload CE without creating the unconditional D-path problem.
- The narrower payload-capture gate also failed physically: post-route WNS regressed to `-2.045 ns` with the worst path still entering `redirect_pc_q` D. Reject redirect-payload capture rewrites for now; they do not remove enough target-data pressure and are worse than the branch predictor update boundary.
- The fallthrough-only redirect boundary was also physically worse than the retained branch predictor update boundary. It passed fast functional acceptance, but post-route WNS regressed to `-1.914 ns` and the worst path moved to `redirect_pc_q` D. Reject this shape as well; redirect payload rewrites are repeatedly exposing the target-data path instead of reducing the routed critical cone.
- Moving aligned branches with EX/MEM operand forwarding into the existing control replay path was not worth keeping. It passed simulation acceptance but regressed post-route WNS to `-1.979 ns`, moved the worst endpoint to `redirect_csr_flush_reg/D`, increased setup failing endpoints to `1041`, and cost CoreMark cycles. Reject this direction unless the CSR/trap redirect register boundary is redesigned more broadly.
- Removing only the CSR redirect write to `redirect_fallthrough_pc_q` also failed physically. It preserved simulation behavior and CoreMark cycles, but post-route WNS regressed to `-2.014 ns` and the worst path again moved to `redirect_pc_q` D. Treat redirect-payload/fallthrough gating tweaks as exhausted for now; they consistently trade one failing redirect path for another.
- ExtraNetDelay placement is currently the best physical strategy for the retained RTL, improving WNS slightly from `-1.545 ns` to `-1.482 ns` without RTL changes. It is still far from timing-clean, but it is a better base for route-only experiments than the previous AltSpread result.
- Reusing the ExtraNetDelay post-place checkpoint with route-only `AdvancedSkewModeling + AggressiveExplore` improved the retained RTL physical result to WNS `-1.204 ns`, TNS `-511.827 ns`, setup endpoints `900`, WHS `0.024 ns`. QoR remained valid (`RAMD64E=0`, `BlockRAM=24`) and a bitstream was generated.
- The current best worst path is still a route-heavy redirect/control endpoint: `u_core/ex_mem_rd_reg[4]_replica/C` -> `u_core/redirect_fallthrough_pc_q_reg[7]/D`, data delay `11.017 ns`, route `76.455%`, logic levels `14`. This confirms physical strategy can recover about `0.34 ns` from the retained RTL baseline, but the remaining `1.2 ns` gap is still too large to treat as a pure router-choice problem.
- A second post-route `AggressiveExplore` physopt pass improved the best physical result to WNS `-1.064 ns`, TNS `-473.626 ns`, setup endpoints `897`, WHS `0.024 ns`, but still failed timing. Its worst path is `u_core/mul_meta_rd_pipe_reg[2][1]/C` -> `u_core/redirect_fallthrough_pc_q_reg[7]/D`, with data delay `10.876 ns`, route `80.912%`, and logic levels `11`.
- After more than three failed local redirect-payload/gating experiments, the problem should be treated as an architectural boundary issue rather than another expression-level rewrite. A better boundary is to separate CSR/trap/MRET redirect payload from normal branch/jump redirect payload so CSR redirects do not write or select through the normal fallthrough/target registers.
- The dedicated CSR redirect PC boundary is functionally clean in simulation: focused trap/misaligned-control tests, branch/jump official rv32ui tests, CSR unit tests including XLEN64, and full fast CSR phase acceptance all pass. CoreMark 2 stayed at `649893` cycles, so the boundary has no measured short-smoke performance cost.
- The dedicated CSR redirect PC boundary was still physically worse and was rejected/reverted. Full ExtraNetDelay implementation regressed to WNS `-1.969 ns`, TNS `-858.503 ns`, setup endpoints `1005`, with the worst path from `redirect_jump_flush_reg` into `bp_update_target_q`. This shows that separating CSR payload alone does not reduce the broader redirect/predictor update cone; it can instead expose the predictor target update path again.
- Predictor update valid and predictor update payload should be treated as separate timing domains. `bp_update_q` is the architectural side-effect gate; payload registers are ignored when that gate is false, so their muxes should not include kill terms such as `!flush` or `!csr_redirect_detect`. The predictor payload kill-split keeps simulation behavior and CoreMark 2 unchanged while giving Vivado less control fan-in on predictor payload D paths.
- The predictor payload kill-split was physically worse and was rejected/reverted. Full ExtraNetDelay implementation regressed to WNS `-2.213 ns`, TNS `-951.804 ns`, setup endpoints `1298`, with the worst path again ending at `redirect_fallthrough_pc_q`. Treat predictor/redirect payload expression rewrites as exhausted for this phase; the remaining fix likely needs a larger control-flow resolution boundary or a non-RTL implementation constraint/floorplan strategy.

## 2026-05-31 CSR Phase 55 Redirect Request Boundary Findings
- The Phase 54 retained baseline is now frozen in git before the larger experiment. Commit `8c0220f Add CSR timing rescue baseline` contains the known-good functional baseline and the current best retained RTL timing boundaries.
- A true redirect request boundary needs an explicit pending-kill interval. If redirect/flush consumes the request one cycle after EX/control detection, younger IF/ID and ID/EX instructions can otherwise advance far enough to issue stores, M-extension work, predictor/RAS updates, or replay captures before the actual flush cycle.
- The pending-kill signal should cover both `ctrl_redirect_req_valid_q` and `redirect_valid`. The request-pending cycle kills younger side effects before PC redirection; the redirect-valid cycle performs the normal PC redirect/flush.
- Do not gate MEM/WB retire globally with the pending redirect signal. For a branch/JALR redirect, the redirecting instruction itself reaches EX/MEM before the request is consumed; it still needs to retire, and JALR may still need to write `rd`. Younger EX/MEM and ID/EX work are killed by the pending/flush boundary instead.
- The first focused simulation results show the pending-kill shape is plausible: CSR trap/MRET tests, misaligned control-flow trap tests, and basic branch/JAL/JALR official tests pass after the RTL change. Full CSR acceptance and Vivado timing are still required before accepting or rejecting the candidate.
- Final result: reject this exact request-boundary shape. It is functionally clean and within the short CoreMark screen, but post-route timing remains worse than the Phase 54 best physical artifact. The endpoint moved to `ctrl_redirect_req_pc_q`, so the request packet still captures too much branch/JALR target computation in one cycle.
- Next architectural timing attempt should not simply add another valid/payload request register. It must split target computation itself, for example by precomputing/carrying branch target and JALR base earlier, or by isolating trap/CSR target capture from normal branch/JALR target-data capture with a different latency policy.
