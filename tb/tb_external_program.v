`timescale 1ns/1ps

module tb_external_program;
    parameter XLEN = 64;
    parameter IMEM_DEPTH = 16384;
    parameter DMEM_DEPTH = 8192;
    parameter DMEM_BASE = 32'h00010000;
    parameter MAX_CYCLES = 200000;
    parameter MUL_STAGES = 1;
    parameter FAST_MUL = 1;
    parameter ENABLE_LOAD_RESP_EX_FORWARD = 1;
    parameter ENABLE_LOAD_CONTROL_EARLY_REPLAY = 0;
    parameter ENABLE_ID_LOAD_EARLY_READ = 0;
    parameter BP_BHT_DEPTH = 128;
    parameter BP_BHR_WIDTH = 3;
    parameter BP_BTB_DEPTH = 64;
    parameter BP_LOCAL_HISTORY = 1;
    parameter BP_INIT_TAKEN = 0;

    reg clk;
    reg rst;
    integer cycle;
    integer pass_addr;
    integer fail_addr;
    integer pass_value;
    integer fail_value;
    integer trace_interval;
    integer replay_trace;
    integer replay_trace_start;
    integer replay_trace_end;
    integer mem_trace_addr;
    integer mem_trace_start;
    integer mem_trace_end;
    integer result_addr;
    integer perf_stats;
    integer pass_index;
    integer fail_index;
    integer result_index;
    integer perf_retired;
    integer perf_loads;
    integer perf_stores;
    integer perf_branches;
    integer perf_jumps;
    integer perf_muls;
    integer perf_divs;
    integer perf_load_use_stalls;
    integer perf_hazard_id_ex_load_stalls;
    integer perf_hazard_ex_mem_load_stalls;
    integer perf_hazard_mul_src_stalls;
    integer perf_hazard_mul_waw_stalls;
    integer perf_hazard_mul_order_stalls;
    integer perf_hazard_mul_struct_stalls;
    integer perf_exec_wait_stalls;
    integer perf_mem_wait_stalls;
    integer perf_mul_wait_stalls;
    integer perf_div_wait_stalls;
    integer perf_flushes;
    integer perf_branch_mispredict_flushes;
    integer perf_jump_flushes;
    integer perf_jal_flushes;
    integer perf_jalr_flushes;
    integer perf_jal_early_redirects;
    integer perf_taken_branches;
    integer perf_not_taken_branches;
    integer perf_pred_taken_branches;
    integer jalr_i;
    integer jalr_hit;
    integer jalr_empty;
    integer jalr_min_idx;
    reg [31:0] jalr_pc [0:15];
    integer jalr_count [0:15];
    integer jalr_pair_hit;
    integer jalr_pair_empty;
    integer jalr_pair_min_idx;
    reg [31:0] jalr_pair_pc [0:31];
    reg [31:0] jalr_pair_target [0:31];
    integer jalr_pair_count [0:31];
    integer jalr_last_hit;
    integer jalr_last_empty;
    integer jalr_last_target_hits;
    integer jalr_last_target_misses;
    reg [31:0] jalr_last_pc [0:15];
    reg [31:0] jalr_last_target [0:15];
    integer jalr_last_valid [0:15];
    integer load_use_i;
    integer load_use_hit;
    integer load_use_empty;
    integer load_use_min_idx;
    reg [31:0] load_use_pc [0:255];
    integer load_use_count [0:255];
    integer load_use_pair_hit;
    integer load_use_pair_empty;
    integer load_use_pair_min_idx;
    reg [31:0] load_use_load_pc [0:255];
    reg [31:0] load_use_consumer_pc [0:255];
    integer load_use_pair_count [0:255];
    reg [31:0] load_use_stall_load_pc;
    integer branch_i;
    integer branch_hit;
    integer branch_empty;
    integer branch_min_idx;
    reg [31:0] branch_mispredict_pc [0:255];
    integer branch_mispredict_count [0:255];
    integer jump_i;
    integer jump_hit;
    integer jump_empty;
    integer jump_min_idx;
    reg [31:0] jump_flush_pc [0:255];
    integer jump_flush_count [0:255];
    reg [1023:0] imem_hex;
    reg [1023:0] dmem_hex;
    wire [31:0] debug_dmem_word0;
    wire [31:0] debug_dmem_word1;
    wire [31:0] debug_dmem_word2;
    wire [31:0] debug_dmem_word3;
    wire [31:0] debug_dmem_word4;
    localparam TB_DMEM_WORD_SHIFT = (XLEN == 64) ? 3 : 2;

    cpu_top #(
        .XLEN(XLEN),
        .IMEM_DEPTH(IMEM_DEPTH),
        .DMEM_DEPTH(DMEM_DEPTH),
        .DMEM_BASE(DMEM_BASE),
        .ENABLE_LOAD_RESP_EX_FORWARD(ENABLE_LOAD_RESP_EX_FORWARD),
        .ENABLE_LOAD_CONTROL_EARLY_REPLAY(ENABLE_LOAD_CONTROL_EARLY_REPLAY),
        .ENABLE_ID_LOAD_EARLY_READ(ENABLE_ID_LOAD_EARLY_READ),
        .MUL_STAGES(MUL_STAGES),
        .FAST_MUL(FAST_MUL),
        .BP_BHT_DEPTH(BP_BHT_DEPTH),
        .BP_BHR_WIDTH(BP_BHR_WIDTH),
        .BP_BTB_DEPTH(BP_BTB_DEPTH),
        .BP_LOCAL_HISTORY(BP_LOCAL_HISTORY),
        .BP_INIT_TAKEN(BP_INIT_TAKEN),
        .IMEM_INIT_FILE(""),
        .DMEM_INIT_FILE("")
    ) dut (
        .clk(clk),
        .rst(rst),
        .debug_dmem_word0(debug_dmem_word0),
        .debug_dmem_word1(debug_dmem_word1),
        .debug_dmem_word2(debug_dmem_word2),
        .debug_dmem_word3(debug_dmem_word3),
        .debug_dmem_word4(debug_dmem_word4),
        .debug_pass_word(),
        .debug_fail_word(),
        .debug_cycle_word()
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    function [31:0] read_dmem_word32;
        input [31:0] byte_addr;
        reg [31:0] rel_addr;
        reg [31:0] word_index;
        reg [2:0] byte_offset;
        reg [XLEN-1:0] word0;
        reg [XLEN-1:0] word1;
        reg [(2*XLEN)-1:0] read_window;
        begin
            rel_addr = byte_addr - DMEM_BASE;
            word_index = rel_addr >> TB_DMEM_WORD_SHIFT;
            byte_offset = (XLEN == 64) ? rel_addr[2:0] : {1'b0, rel_addr[1:0]};
            word0 = (word_index < DMEM_DEPTH) ? dut.u_dmem.mem[word_index] : {XLEN{1'b0}};
            word1 = ((word_index + 1) < DMEM_DEPTH) ? dut.u_dmem.mem[word_index + 1] : {XLEN{1'b0}};
            read_window = {word1, word0} >> (8 * byte_offset);
            read_dmem_word32 = read_window[31:0];
        end
    endfunction

    initial begin
        if (!$value$plusargs("IMEM_HEX=%s", imem_hex)) begin
            $display("FAIL external: missing +IMEM_HEX=<path>");
            $finish;
        end
        if ($value$plusargs("DMEM_HEX=%s", dmem_hex)) begin
            $readmemh(dmem_hex, dut.u_dmem.mem);
        end
        $readmemh(imem_hex, dut.u_imem.mem);

        if (!$value$plusargs("PASS_ADDR=%d", pass_addr)) pass_addr = DMEM_BASE;
        if (!$value$plusargs("FAIL_ADDR=%d", fail_addr)) fail_addr = DMEM_BASE + 4;
        if (!$value$plusargs("PASS_VALUE=%d", pass_value)) pass_value = 1;
        if (!$value$plusargs("FAIL_VALUE=%d", fail_value)) fail_value = 1;
        if (!$value$plusargs("TRACE_INTERVAL=%d", trace_interval)) trace_interval = 0;
        if (!$value$plusargs("REPLAY_TRACE=%d", replay_trace)) replay_trace = 0;
        if (!$value$plusargs("REPLAY_TRACE_START=%d", replay_trace_start)) replay_trace_start = 0;
        if (!$value$plusargs("REPLAY_TRACE_END=%d", replay_trace_end)) replay_trace_end = MAX_CYCLES;
        if (!$value$plusargs("MEM_TRACE_ADDR=%d", mem_trace_addr)) mem_trace_addr = -1;
        if (!$value$plusargs("MEM_TRACE_START=%d", mem_trace_start)) mem_trace_start = 0;
        if (!$value$plusargs("MEM_TRACE_END=%d", mem_trace_end)) mem_trace_end = MAX_CYCLES;
        if (!$value$plusargs("RESULT_ADDR=%d", result_addr)) result_addr = 0;
        if (!$value$plusargs("PERF_STATS=%d", perf_stats)) perf_stats = 0;

        pass_index = (pass_addr - DMEM_BASE) >> 2;
        fail_index = (fail_addr - DMEM_BASE) >> 2;
        result_index = (result_addr - DMEM_BASE) >> 2;

        perf_retired = 0;
        perf_loads = 0;
        perf_stores = 0;
        perf_branches = 0;
        perf_jumps = 0;
        perf_muls = 0;
        perf_divs = 0;
        perf_load_use_stalls = 0;
        perf_hazard_id_ex_load_stalls = 0;
        perf_hazard_ex_mem_load_stalls = 0;
        perf_hazard_mul_src_stalls = 0;
        perf_hazard_mul_waw_stalls = 0;
        perf_hazard_mul_order_stalls = 0;
        perf_hazard_mul_struct_stalls = 0;
        perf_exec_wait_stalls = 0;
        perf_mem_wait_stalls = 0;
        perf_mul_wait_stalls = 0;
        perf_div_wait_stalls = 0;
        perf_flushes = 0;
        perf_branch_mispredict_flushes = 0;
        perf_jump_flushes = 0;
        perf_jal_flushes = 0;
        perf_jalr_flushes = 0;
        perf_jal_early_redirects = 0;
        perf_taken_branches = 0;
        perf_not_taken_branches = 0;
        perf_pred_taken_branches = 0;
        for (jalr_i = 0; jalr_i < 16; jalr_i = jalr_i + 1) begin
            jalr_pc[jalr_i] = 32'h00000000;
            jalr_count[jalr_i] = 0;
        end
        for (jalr_i = 0; jalr_i < 32; jalr_i = jalr_i + 1) begin
            jalr_pair_pc[jalr_i] = 32'h00000000;
            jalr_pair_target[jalr_i] = 32'h00000000;
            jalr_pair_count[jalr_i] = 0;
        end
        jalr_last_target_hits = 0;
        jalr_last_target_misses = 0;
        for (jalr_i = 0; jalr_i < 16; jalr_i = jalr_i + 1) begin
            jalr_last_pc[jalr_i] = 32'h00000000;
            jalr_last_target[jalr_i] = 32'h00000000;
            jalr_last_valid[jalr_i] = 0;
        end
        for (load_use_i = 0; load_use_i < 256; load_use_i = load_use_i + 1) begin
            load_use_pc[load_use_i] = 32'h00000000;
            load_use_count[load_use_i] = 0;
        end
        for (load_use_i = 0; load_use_i < 256; load_use_i = load_use_i + 1) begin
            load_use_load_pc[load_use_i] = 32'h00000000;
            load_use_consumer_pc[load_use_i] = 32'h00000000;
            load_use_pair_count[load_use_i] = 0;
        end
        for (branch_i = 0; branch_i < 256; branch_i = branch_i + 1) begin
            branch_mispredict_pc[branch_i] = 32'h00000000;
            branch_mispredict_count[branch_i] = 0;
        end
        for (jump_i = 0; jump_i < 256; jump_i = jump_i + 1) begin
            jump_flush_pc[jump_i] = 32'h00000000;
            jump_flush_count[jump_i] = 0;
        end

        rst = 1'b1;
        repeat (5) @(posedge clk);
        rst = 1'b0;

        for (cycle = 0; cycle < MAX_CYCLES; cycle = cycle + 1) begin
            @(posedge clk);
            if (perf_stats != 0) begin
                if (dut.u_core.hazard_stall) begin
                    perf_load_use_stalls = perf_load_use_stalls + 1;
                    if (dut.u_core.u_hazard.id_ex_load_use_stall) begin
                        perf_hazard_id_ex_load_stalls = perf_hazard_id_ex_load_stalls + 1;
                    end
                    if (dut.u_core.u_hazard.if_id_needs_ex_mem_load_stall &&
                        dut.u_core.u_hazard.ex_mem_load_use) begin
                        perf_hazard_ex_mem_load_stalls = perf_hazard_ex_mem_load_stalls + 1;
                    end
                    if (dut.u_core.u_hazard.if_id_mul_src_dep) begin
                        perf_hazard_mul_src_stalls = perf_hazard_mul_src_stalls + 1;
                    end
                    if (dut.u_core.u_hazard.if_id_mul_waw_dep) begin
                        perf_hazard_mul_waw_stalls = perf_hazard_mul_waw_stalls + 1;
                    end
                    if (dut.u_core.u_hazard.if_id_mul_order_dep) begin
                        perf_hazard_mul_order_stalls = perf_hazard_mul_order_stalls + 1;
                    end
                    if (dut.u_core.u_hazard.if_id_mul_struct_dep) begin
                        perf_hazard_mul_struct_stalls = perf_hazard_mul_struct_stalls + 1;
                    end
                    if (dut.u_core.u_hazard.id_ex_load_use) begin
                        load_use_stall_load_pc = dut.u_core.id_ex_pc;
                    end else if (dut.u_core.u_hazard.ex_mem_load_use) begin
                        load_use_stall_load_pc = dut.u_core.ex_mem_pc4 - 32'd4;
                    end else begin
                        load_use_stall_load_pc = dut.u_core.id_ex_pc;
                    end

                    load_use_hit = -1;
                    load_use_empty = -1;
                    load_use_min_idx = 0;
                    for (load_use_i = 0; load_use_i < 256; load_use_i = load_use_i + 1) begin
                        if (load_use_count[load_use_i] != 0 && load_use_pc[load_use_i] == dut.u_core.if_id_pc) begin
                            load_use_hit = load_use_i;
                        end
                        if (load_use_empty < 0 && load_use_count[load_use_i] == 0) begin
                            load_use_empty = load_use_i;
                        end
                        if (load_use_count[load_use_i] < load_use_count[load_use_min_idx]) begin
                            load_use_min_idx = load_use_i;
                        end
                    end
                    if (load_use_hit >= 0) begin
                        load_use_count[load_use_hit] = load_use_count[load_use_hit] + 1;
                    end else if (load_use_empty >= 0) begin
                        load_use_pc[load_use_empty] = dut.u_core.if_id_pc;
                        load_use_count[load_use_empty] = 1;
                    end else begin
                        load_use_pc[load_use_min_idx] = dut.u_core.if_id_pc;
                        load_use_count[load_use_min_idx] = 1;
                    end

                    load_use_pair_hit = -1;
                    load_use_pair_empty = -1;
                    load_use_pair_min_idx = 0;
                    for (load_use_i = 0; load_use_i < 256; load_use_i = load_use_i + 1) begin
                        if (load_use_pair_count[load_use_i] != 0 &&
                            load_use_load_pc[load_use_i] == load_use_stall_load_pc &&
                            load_use_consumer_pc[load_use_i] == dut.u_core.if_id_pc) begin
                            load_use_pair_hit = load_use_i;
                        end
                        if (load_use_pair_empty < 0 && load_use_pair_count[load_use_i] == 0) begin
                            load_use_pair_empty = load_use_i;
                        end
                        if (load_use_pair_count[load_use_i] < load_use_pair_count[load_use_pair_min_idx]) begin
                            load_use_pair_min_idx = load_use_i;
                        end
                    end
                    if (load_use_pair_hit >= 0) begin
                        load_use_pair_count[load_use_pair_hit] = load_use_pair_count[load_use_pair_hit] + 1;
                    end else if (load_use_pair_empty >= 0) begin
                        load_use_load_pc[load_use_pair_empty] = load_use_stall_load_pc;
                        load_use_consumer_pc[load_use_pair_empty] = dut.u_core.if_id_pc;
                        load_use_pair_count[load_use_pair_empty] = 1;
                    end else begin
                        load_use_load_pc[load_use_pair_min_idx] = load_use_stall_load_pc;
                        load_use_consumer_pc[load_use_pair_min_idx] = dut.u_core.if_id_pc;
                        load_use_pair_count[load_use_pair_min_idx] = 1;
                    end
                end
                if (dut.u_core.exec_wait) perf_exec_wait_stalls = perf_exec_wait_stalls + 1;
                if (dut.u_core.mem_wait) perf_mem_wait_stalls = perf_mem_wait_stalls + 1;
                if (dut.u_core.mul_wait) perf_mul_wait_stalls = perf_mul_wait_stalls + 1;
                if (dut.u_core.div_wait) perf_div_wait_stalls = perf_div_wait_stalls + 1;
                if (dut.u_core.flush) perf_flushes = perf_flushes + 1;
                if (dut.u_core.branch_mispredict) perf_branch_mispredict_flushes = perf_branch_mispredict_flushes + 1;
                if (dut.u_core.branch_mispredict_detect) begin
                    branch_hit = -1;
                    branch_empty = -1;
                    branch_min_idx = 0;
                    for (branch_i = 0; branch_i < 256; branch_i = branch_i + 1) begin
                        if (branch_mispredict_count[branch_i] != 0 &&
                            branch_mispredict_pc[branch_i] == dut.u_core.ctrl_pc) begin
                            branch_hit = branch_i;
                        end
                        if (branch_empty < 0 && branch_mispredict_count[branch_i] == 0) begin
                            branch_empty = branch_i;
                        end
                        if (branch_mispredict_count[branch_i] < branch_mispredict_count[branch_min_idx]) begin
                            branch_min_idx = branch_i;
                        end
                    end
                    if (branch_hit >= 0) begin
                        branch_mispredict_count[branch_hit] = branch_mispredict_count[branch_hit] + 1;
                    end else if (branch_empty >= 0) begin
                        branch_mispredict_pc[branch_empty] = dut.u_core.ctrl_pc;
                        branch_mispredict_count[branch_empty] = 1;
                    end else begin
                        branch_mispredict_pc[branch_min_idx] = dut.u_core.ctrl_pc;
                        branch_mispredict_count[branch_min_idx] = 1;
                    end
                end
                if (dut.u_core.jump_needs_flush_detect) begin
                    jump_hit = -1;
                    jump_empty = -1;
                    jump_min_idx = 0;
                    for (jump_i = 0; jump_i < 256; jump_i = jump_i + 1) begin
                        if (jump_flush_count[jump_i] != 0 &&
                            jump_flush_pc[jump_i] == dut.u_core.ctrl_pc) begin
                            jump_hit = jump_i;
                        end
                        if (jump_empty < 0 && jump_flush_count[jump_i] == 0) begin
                            jump_empty = jump_i;
                        end
                        if (jump_flush_count[jump_i] < jump_flush_count[jump_min_idx]) begin
                            jump_min_idx = jump_i;
                        end
                    end
                    if (jump_hit >= 0) begin
                        jump_flush_count[jump_hit] = jump_flush_count[jump_hit] + 1;
                    end else if (jump_empty >= 0) begin
                        jump_flush_pc[jump_empty] = dut.u_core.ctrl_pc;
                        jump_flush_count[jump_empty] = 1;
                    end else begin
                        jump_flush_pc[jump_min_idx] = dut.u_core.ctrl_pc;
                        jump_flush_count[jump_min_idx] = 1;
                    end
                end
                if (dut.u_core.jump_needs_flush) begin
                    perf_jump_flushes = perf_jump_flushes + 1;
                    if (dut.u_core.id_ex_jalr) begin
                        perf_jalr_flushes = perf_jalr_flushes + 1;
                    end else begin
                        perf_jal_flushes = perf_jal_flushes + 1;
                    end
                end
                if (dut.u_core.id_jal_redirect) perf_jal_early_redirects = perf_jal_early_redirects + 1;
                if (!dut.u_core.pipe_wait &&
                    dut.u_core.id_ex_valid &&
                    (dut.u_core.id_ex_reg_write ||
                     dut.u_core.id_ex_mem_read ||
                     dut.u_core.id_ex_mem_write ||
                     dut.u_core.id_ex_branch ||
                     dut.u_core.id_ex_jump ||
                     dut.u_core.id_ex_csr_instr ||
                     dut.u_core.id_ex_m_ext)) begin
                    perf_retired = perf_retired + 1;
                    if (dut.u_core.id_ex_mem_read) perf_loads = perf_loads + 1;
                    if (dut.u_core.id_ex_mem_write) perf_stores = perf_stores + 1;
                    if (dut.u_core.id_ex_branch) begin
                        perf_branches = perf_branches + 1;
                        if (dut.u_core.branch_taken) begin
                            perf_taken_branches = perf_taken_branches + 1;
                        end else begin
                            perf_not_taken_branches = perf_not_taken_branches + 1;
                        end
                        if (dut.u_core.id_ex_pred_taken) perf_pred_taken_branches = perf_pred_taken_branches + 1;
                    end
                    if (dut.u_core.id_ex_jump) perf_jumps = perf_jumps + 1;
                    if (dut.u_core.id_ex_jalr) begin
                        jalr_hit = -1;
                        jalr_empty = -1;
                        jalr_min_idx = 0;
                        for (jalr_i = 0; jalr_i < 16; jalr_i = jalr_i + 1) begin
                            if (jalr_count[jalr_i] != 0 && jalr_pc[jalr_i] == dut.u_core.id_ex_pc) begin
                                jalr_hit = jalr_i;
                            end
                            if (jalr_empty < 0 && jalr_count[jalr_i] == 0) begin
                                jalr_empty = jalr_i;
                            end
                            if (jalr_count[jalr_i] < jalr_count[jalr_min_idx]) begin
                                jalr_min_idx = jalr_i;
                            end
                        end
                        if (jalr_hit >= 0) begin
                            jalr_count[jalr_hit] = jalr_count[jalr_hit] + 1;
                        end else if (jalr_empty >= 0) begin
                            jalr_pc[jalr_empty] = dut.u_core.id_ex_pc;
                            jalr_count[jalr_empty] = 1;
                        end else begin
                            jalr_pc[jalr_min_idx] = dut.u_core.id_ex_pc;
                            jalr_count[jalr_min_idx] = 1;
                        end

                        jalr_pair_hit = -1;
                        jalr_pair_empty = -1;
                        jalr_pair_min_idx = 0;
                        for (jalr_i = 0; jalr_i < 32; jalr_i = jalr_i + 1) begin
                            if (jalr_pair_count[jalr_i] != 0 &&
                                jalr_pair_pc[jalr_i] == dut.u_core.id_ex_pc &&
                                jalr_pair_target[jalr_i] == dut.u_core.jalr_target) begin
                                jalr_pair_hit = jalr_i;
                            end
                            if (jalr_pair_empty < 0 && jalr_pair_count[jalr_i] == 0) begin
                                jalr_pair_empty = jalr_i;
                            end
                            if (jalr_pair_count[jalr_i] < jalr_pair_count[jalr_pair_min_idx]) begin
                                jalr_pair_min_idx = jalr_i;
                            end
                        end
                        if (jalr_pair_hit >= 0) begin
                            jalr_pair_count[jalr_pair_hit] = jalr_pair_count[jalr_pair_hit] + 1;
                        end else if (jalr_pair_empty >= 0) begin
                            jalr_pair_pc[jalr_pair_empty] = dut.u_core.id_ex_pc;
                            jalr_pair_target[jalr_pair_empty] = dut.u_core.jalr_target;
                            jalr_pair_count[jalr_pair_empty] = 1;
                        end else begin
                            jalr_pair_pc[jalr_pair_min_idx] = dut.u_core.id_ex_pc;
                            jalr_pair_target[jalr_pair_min_idx] = dut.u_core.jalr_target;
                            jalr_pair_count[jalr_pair_min_idx] = 1;
                        end

                        jalr_last_hit = -1;
                        jalr_last_empty = -1;
                        for (jalr_i = 0; jalr_i < 16; jalr_i = jalr_i + 1) begin
                            if (jalr_last_valid[jalr_i] != 0 && jalr_last_pc[jalr_i] == dut.u_core.id_ex_pc) begin
                                jalr_last_hit = jalr_i;
                            end
                            if (jalr_last_empty < 0 && jalr_last_valid[jalr_i] == 0) begin
                                jalr_last_empty = jalr_i;
                            end
                        end
                        if (jalr_last_hit >= 0) begin
                            if (jalr_last_target[jalr_last_hit] == dut.u_core.jalr_target) begin
                                jalr_last_target_hits = jalr_last_target_hits + 1;
                            end else begin
                                jalr_last_target_misses = jalr_last_target_misses + 1;
                            end
                            jalr_last_target[jalr_last_hit] = dut.u_core.jalr_target;
                        end else begin
                            jalr_last_target_misses = jalr_last_target_misses + 1;
                            if (jalr_last_empty >= 0) begin
                                jalr_last_pc[jalr_last_empty] = dut.u_core.id_ex_pc;
                                jalr_last_target[jalr_last_empty] = dut.u_core.jalr_target;
                                jalr_last_valid[jalr_last_empty] = 1;
                            end else begin
                                jalr_last_pc[0] = dut.u_core.id_ex_pc;
                                jalr_last_target[0] = dut.u_core.jalr_target;
                                jalr_last_valid[0] = 1;
                            end
                        end
                    end
                    if (dut.u_core.id_ex_is_mul) perf_muls = perf_muls + 1;
                    if (dut.u_core.id_ex_is_div) perf_divs = perf_divs + 1;
                end
            end
            if (trace_interval > 0 && (cycle % trace_interval) == 0) begin
                $display("TRACE external: cycle=%0d pc=%08x imem_addr=%08x ifid_pc=%08x ifid_instr=%08x idex_pc=%08x idex_jump=%b idex_branch=%b dmem_we=%b dmem_addr=%08x dmem_wdata=%08x pass=%08x fail=%08x",
                    cycle,
                    dut.u_core.pc,
                    dut.u_core.imem_addr,
                    dut.u_core.if_id_pc,
                    dut.u_core.if_id_instr,
                    dut.u_core.id_ex_pc,
                    dut.u_core.id_ex_jump,
                    dut.u_core.id_ex_branch,
                    dut.u_core.dmem_write,
                    dut.u_core.dmem_addr,
                    dut.u_core.dmem_wdata,
                    read_dmem_word32(pass_addr[31:0]),
                    read_dmem_word32(fail_addr[31:0]));
            end
            if (replay_trace != 0 && cycle >= replay_trace_start && cycle <= replay_trace_end) begin
                if (dut.u_core.load_control_early_capture ||
                    dut.u_core.ctrl_load_pending_to_replay ||
                    dut.u_core.control_replay_capture ||
                    dut.u_core.redirect_detect ||
                    dut.u_core.flush) begin
                    $display("REPLAY_TRACE cycle=%0d early=%b pending=%b wait=%b to_replay=%b ctrl_replay=%b redirect=%b flush=%b idex_pc=%08x ifid_pc=%08x load_rd=%0d resp_v=%b resp_rd=%0d resp_data=%08x pend_pc=%08x pend_rd=%0d pend_rs1_load=%b pend_rs2_load=%b ctrl_pc=%08x ctrl_branch=%b ctrl_jump=%b ctrl_taken=%b redirect_pc=%08x",
                        cycle,
                        dut.u_core.load_control_early_capture,
                        dut.u_core.ctrl_load_pending_valid,
                        dut.u_core.ctrl_load_pending_wait_resp,
                        dut.u_core.ctrl_load_pending_to_replay,
                        dut.u_core.ctrl_replay_valid,
                        dut.u_core.redirect_detect,
                        dut.u_core.flush,
                        dut.u_core.id_ex_pc,
                        dut.u_core.if_id_pc,
                        dut.u_core.id_ex_rd,
                        dut.u_core.load_resp_valid,
                        dut.u_core.load_resp_rd,
                        dut.u_core.load_resp_data,
                        dut.u_core.ctrl_load_pending_pc,
                        dut.u_core.ctrl_load_pending_load_rd,
                        dut.u_core.ctrl_load_pending_rs1_from_load,
                        dut.u_core.ctrl_load_pending_rs2_from_load,
                        dut.u_core.ctrl_pc,
                        dut.u_core.ctrl_branch,
                        dut.u_core.ctrl_jump,
                        dut.u_core.take_branch || dut.u_core.take_jump,
                        dut.u_core.redirect_pc);
                end
            end
            if (mem_trace_addr >= 0 && cycle >= mem_trace_start && cycle <= mem_trace_end &&
                dut.u_core.dmem_write &&
                dut.u_core.dmem_addr <= mem_trace_addr &&
                (dut.u_core.dmem_addr + 3) >= mem_trace_addr) begin
                $display("MEM_TRACE cycle=%0d addr=%08x target=%08x wdata=%08x byte_en=%b exmem_pc=%08x idex_pc=%08x ifid_pc=%08x replay_flush=%b redirect=%b flush=%b",
                    cycle,
                    dut.u_core.dmem_addr,
                    mem_trace_addr[31:0],
                    dut.u_core.dmem_wdata,
                    dut.u_core.dmem_byte_en,
                    dut.u_core.ex_mem_pc4 - 32'd4,
                    dut.u_core.id_ex_pc,
                    dut.u_core.if_id_pc,
                    dut.u_core.replay_flush,
                    dut.u_core.redirect_detect,
                    dut.u_core.flush);
            end
            if (read_dmem_word32(fail_addr[31:0]) != 32'h00000000) begin
                $display("FAIL external: fail marker at cycle %0d value=%08x exmem_pc=%08x exmem_rd=%0d exmem_mem_write=%b exmem_addr=%08x idex_pc=%08x ifid_pc=%08x",
                    cycle,
                    read_dmem_word32(fail_addr[31:0]),
                    dut.u_core.ex_mem_pc4 - 32'd4,
                    dut.u_core.ex_mem_rd,
                    dut.u_core.ex_mem_mem_write,
                    dut.u_core.ex_mem_alu_result,
                    dut.u_core.id_ex_pc,
                    dut.u_core.if_id_pc);
                $finish;
            end
            if (read_dmem_word32(pass_addr[31:0]) == pass_value[31:0]) begin
                if (perf_stats != 0) begin
                    $display("PERF_STATS retired=%0d loads=%0d stores=%0d branches=%0d jumps=%0d muls=%0d divs=%0d load_use_stalls=%0d exec_wait_stalls=%0d mem_wait_stalls=%0d mul_wait_stalls=%0d div_wait_stalls=%0d flushes=%0d branch_mispredict_flushes=%0d jump_flushes=%0d jal_flushes=%0d jalr_flushes=%0d jal_early_redirects=%0d taken_branches=%0d not_taken_branches=%0d pred_taken_branches=%0d",
                        perf_retired,
                        perf_loads,
                        perf_stores,
                        perf_branches,
                        perf_jumps,
                        perf_muls,
                        perf_divs,
                        perf_load_use_stalls,
                        perf_exec_wait_stalls,
                        perf_mem_wait_stalls,
                        perf_mul_wait_stalls,
                        perf_div_wait_stalls,
                        perf_flushes,
                        perf_branch_mispredict_flushes,
                        perf_jump_flushes,
                        perf_jal_flushes,
                        perf_jalr_flushes,
                        perf_jal_early_redirects,
                        perf_taken_branches,
                        perf_not_taken_branches,
                        perf_pred_taken_branches);
                    $display("HAZARD_STATS id_ex_load=%0d ex_mem_load=%0d mul_src=%0d mul_waw=%0d mul_order=%0d mul_struct=%0d",
                        perf_hazard_id_ex_load_stalls,
                        perf_hazard_ex_mem_load_stalls,
                        perf_hazard_mul_src_stalls,
                        perf_hazard_mul_waw_stalls,
                        perf_hazard_mul_order_stalls,
                        perf_hazard_mul_struct_stalls);
                    $display("JALR_LAST_TARGET hits=%0d misses=%0d", jalr_last_target_hits, jalr_last_target_misses);
                    for (jalr_i = 0; jalr_i < 16; jalr_i = jalr_i + 1) begin
                        if (jalr_count[jalr_i] != 0) begin
                            $display("JALR_TOP pc=%08x count=%0d", jalr_pc[jalr_i], jalr_count[jalr_i]);
                        end
                    end
                    for (jalr_i = 0; jalr_i < 32; jalr_i = jalr_i + 1) begin
                        if (jalr_pair_count[jalr_i] != 0) begin
                            $display("JALR_PAIR_TOP pc=%08x target=%08x count=%0d", jalr_pair_pc[jalr_i], jalr_pair_target[jalr_i], jalr_pair_count[jalr_i]);
                        end
                    end
                    for (load_use_i = 0; load_use_i < 256; load_use_i = load_use_i + 1) begin
                        if (load_use_count[load_use_i] != 0) begin
                            $display("LOAD_USE_TOP consumer_pc=%08x count=%0d", load_use_pc[load_use_i], load_use_count[load_use_i]);
                        end
                    end
                    for (load_use_i = 0; load_use_i < 256; load_use_i = load_use_i + 1) begin
                        if (load_use_pair_count[load_use_i] != 0) begin
                            $display("LOAD_USE_PAIR_TOP load_pc=%08x consumer_pc=%08x count=%0d", load_use_load_pc[load_use_i], load_use_consumer_pc[load_use_i], load_use_pair_count[load_use_i]);
                        end
                    end
                    for (branch_i = 0; branch_i < 256; branch_i = branch_i + 1) begin
                        if (branch_mispredict_count[branch_i] != 0) begin
                            $display("BRANCH_MISPREDICT_TOP pc=%08x count=%0d", branch_mispredict_pc[branch_i], branch_mispredict_count[branch_i]);
                        end
                    end
                    for (jump_i = 0; jump_i < 256; jump_i = jump_i + 1) begin
                        if (jump_flush_count[jump_i] != 0) begin
                            $display("JUMP_FLUSH_TOP pc=%08x count=%0d", jump_flush_pc[jump_i], jump_flush_count[jump_i]);
                        end
                    end
                end
                if (result_addr != 0) begin
                    $display("PASS external program completed cycle=%0d result=%08x", cycle, read_dmem_word32(result_addr[31:0]));
                end else begin
                    $display("PASS external program completed cycle=%0d", cycle);
                end
                $finish;
            end
        end

        $display("FAIL external: timeout pass[%0d]=%08x fail[%0d]=%08x",
            pass_index, read_dmem_word32(pass_addr[31:0]), fail_index, read_dmem_word32(fail_addr[31:0]));
        $finish;
    end
endmodule
