# Machine-Mode CSR Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement an XLEN-parameterized M-mode CSR bank, Zicsr semantics, and first-stage synchronous trap/MRET integration for the CSR feature branch.

**Architecture:** `csr_unit` owns all CSR architectural state and provides CSR read data, trap target, and MRET target. `cpu_core` owns pipeline priority, redirect, flush, and side-effect kill gates, and commits CSR/trap/MRET requests only when the producing instruction is not killed. The implementation is staged so CSR unit behavior is proven before CPU pipeline integration.

**Tech Stack:** Verilog RTL, ModelSim PowerShell scripts, xPack RISC-V GCC bare-metal assembly tests, existing `cpu_top`/`tb_external_program` harnesses.

---

## File Structure

- Modify: `rtl/defines.vh`
  - Add CSR operation encodings, system event encodings, CSR addresses, and machine cause constants.
- Modify: `rtl/decoder.v`
  - Decode CSR operation type and `SYSTEM funct3=000` events while preserving existing control outputs.
- Modify: `rtl/csr_unit.v`
  - Replace the counter-only unit with an XLEN-parameterized M-mode CSR bank.
  - Keep `mcycle_o` and `minstret_o` outputs for existing debug and CoreMark paths.
- Modify: `rtl/cpu_core.v`
  - Add CSR operation pipeline registers.
  - Add trap/MRET redirect class and side-effect kill gates.
  - Commit CSR writes, trap entry, and MRET restore through `csr_unit`.
- Modify: `scripts/run_modelsim.ps1`
  - Compile and run CSR unit and decoder tests.
- Create: `scripts/run_csr_unit_modelsim.ps1`
  - Fast CSR-unit-only regression for red/green cycles.
- Create: `scripts/run_csr_trap_programs.ps1`
  - Build selected assembly programs and run them through `tb_external_program`.
- Create: `tb/tb_csr_unit_zicsr.v`
  - Unit test for CSR read/write and suppression semantics.
- Create: `tb/tb_csr_unit_trap_mret.v`
  - Unit test for trap entry, MRET restore, `mstatus`, `mepc`, `mcause`, `mtval`, `trap_pc`, and `mret_pc`.
- Create: `tb/tb_csr_unit_xlen64.v`
  - XLEN=64 compile and smoke test.
- Create: `tb/tb_decoder_system.v`
  - Decoder test for CSR op and `ECALL/EBREAK/MRET` classification.
- Create: `sw/csr_trap_tests/csr_rw.S`
  - Bare-metal CSR read/write integration test.
- Create: `sw/csr_trap_tests/ecall_mret.S`
  - Bare-metal ECALL trap and MRET return integration test.
- Create: `sw/csr_trap_tests/illegal_csr.S`
  - Bare-metal illegal CSR trap and no-faulting-rd-write test.
- Create: `sw/csr_trap_tests/misaligned_store.S`
  - Bare-metal misaligned store trap and no-DMEM-corruption test.

## Interface Contract

Use these encodings in `rtl/defines.vh`:

```verilog
`define CSR_OP_NONE 3'd0
`define CSR_OP_RW   3'd1
`define CSR_OP_RS   3'd2
`define CSR_OP_RC   3'd3
`define CSR_OP_RWI  3'd4
`define CSR_OP_RSI  3'd5
`define CSR_OP_RCI  3'd6

`define SYS_EVT_NONE   3'd0
`define SYS_EVT_ECALL  3'd1
`define SYS_EVT_EBREAK 3'd2
`define SYS_EVT_MRET   3'd3
`define SYS_EVT_ILLEGAL 3'd4

`define CSR_MSTATUS  12'h300
`define CSR_MISA     12'h301
`define CSR_MIE      12'h304
`define CSR_MTVEC    12'h305
`define CSR_MSCRATCH 12'h340
`define CSR_MEPC     12'h341
`define CSR_MCAUSE   12'h342
`define CSR_MTVAL    12'h343
`define CSR_MIP      12'h344
`define CSR_MCYCLE   12'hB00
`define CSR_MINSTRET 12'hB02
`define CSR_MCYCLEH  12'hB80
`define CSR_MINSTRETH 12'hB82
`define CSR_MVENDORID 12'hF11
`define CSR_MARCHID   12'hF12
`define CSR_MIMPID    12'hF13
`define CSR_MHARTID   12'hF14

`define CAUSE_INSTR_ADDR_MISALIGNED 32'd0
`define CAUSE_ILLEGAL_INSTRUCTION   32'd2
`define CAUSE_BREAKPOINT            32'd3
`define CAUSE_LOAD_ADDR_MISALIGNED  32'd4
`define CAUSE_STORE_ADDR_MISALIGNED 32'd6
`define CAUSE_ECALL_MMODE           32'd11
```

Use this `csr_unit` port contract:

```verilog
module csr_unit #(
    parameter XLEN = 32,
    parameter HART_ID = 0,
    parameter SUPPORT_M = 1,
    parameter SUPPORT_ZICSR = 1,
    parameter SUPPORT_C = 0
) (
    input wire clk,
    input wire rst,

    input wire retire_i,
    input wire [1:0] retire_count_i,

    input wire csr_read_valid_i,
    input wire [2:0] csr_read_op_i,
    input wire [11:0] csr_read_addr_i,
    input wire [XLEN-1:0] csr_read_wdata_i,
    input wire csr_read_rd_zero_i,
    output reg [XLEN-1:0] csr_read_data_o,
    output reg csr_read_illegal_o,

    input wire csr_commit_valid_i,
    input wire [2:0] csr_commit_op_i,
    input wire [11:0] csr_commit_addr_i,
    input wire [XLEN-1:0] csr_commit_wdata_i,
    input wire csr_commit_rd_zero_i,

    input wire trap_commit_valid_i,
    input wire [XLEN-1:0] trap_mepc_i,
    input wire [XLEN-1:0] trap_mcause_i,
    input wire [XLEN-1:0] trap_mtval_i,

    input wire mret_commit_valid_i,

    output wire [XLEN-1:0] trap_pc_o,
    output wire [XLEN-1:0] mret_pc_o,
    output reg [XLEN-1:0] mcycle_o,
    output reg [XLEN-1:0] minstret_o
);
```

## Task 1: Zicsr Unit Test and CSR Bank Core

**Files:**
- Modify: `rtl/defines.vh`
- Modify: `rtl/csr_unit.v`
- Create: `tb/tb_csr_unit_zicsr.v`
- Create: `scripts/run_csr_unit_modelsim.ps1`
- Modify: `scripts/run_modelsim.ps1`

- [ ] **Step 1: Write the failing Zicsr unit test**

Create `tb/tb_csr_unit_zicsr.v`:

```verilog
`timescale 1ns/1ps
`include "defines.vh"

module tb_csr_unit_zicsr;
    reg clk;
    reg rst;
    reg retire_i;
    reg [1:0] retire_count_i;
    reg csr_read_valid_i;
    reg [2:0] csr_read_op_i;
    reg [11:0] csr_read_addr_i;
    reg [31:0] csr_read_wdata_i;
    reg csr_read_rd_zero_i;
    wire [31:0] csr_read_data_o;
    wire csr_read_illegal_o;
    reg csr_commit_valid_i;
    reg [2:0] csr_commit_op_i;
    reg [11:0] csr_commit_addr_i;
    reg [31:0] csr_commit_wdata_i;
    reg csr_commit_rd_zero_i;
    reg trap_commit_valid_i;
    reg [31:0] trap_mepc_i;
    reg [31:0] trap_mcause_i;
    reg [31:0] trap_mtval_i;
    reg mret_commit_valid_i;
    wire [31:0] trap_pc_o;
    wire [31:0] mret_pc_o;
    wire [31:0] mcycle_o;
    wire [31:0] minstret_o;

    csr_unit #(.XLEN(32), .HART_ID(0)) dut (
        .clk(clk),
        .rst(rst),
        .retire_i(retire_i),
        .retire_count_i(retire_count_i),
        .csr_read_valid_i(csr_read_valid_i),
        .csr_read_op_i(csr_read_op_i),
        .csr_read_addr_i(csr_read_addr_i),
        .csr_read_wdata_i(csr_read_wdata_i),
        .csr_read_rd_zero_i(csr_read_rd_zero_i),
        .csr_read_data_o(csr_read_data_o),
        .csr_read_illegal_o(csr_read_illegal_o),
        .csr_commit_valid_i(csr_commit_valid_i),
        .csr_commit_op_i(csr_commit_op_i),
        .csr_commit_addr_i(csr_commit_addr_i),
        .csr_commit_wdata_i(csr_commit_wdata_i),
        .csr_commit_rd_zero_i(csr_commit_rd_zero_i),
        .trap_commit_valid_i(trap_commit_valid_i),
        .trap_mepc_i(trap_mepc_i),
        .trap_mcause_i(trap_mcause_i),
        .trap_mtval_i(trap_mtval_i),
        .mret_commit_valid_i(mret_commit_valid_i),
        .trap_pc_o(trap_pc_o),
        .mret_pc_o(mret_pc_o),
        .mcycle_o(mcycle_o),
        .minstret_o(minstret_o)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task clear_req;
        begin
            retire_i = 1'b0;
            retire_count_i = 2'd0;
            csr_read_valid_i = 1'b0;
            csr_read_op_i = `CSR_OP_NONE;
            csr_read_addr_i = 12'h000;
            csr_read_wdata_i = 32'h00000000;
            csr_read_rd_zero_i = 1'b0;
            csr_commit_valid_i = 1'b0;
            csr_commit_op_i = `CSR_OP_NONE;
            csr_commit_addr_i = 12'h000;
            csr_commit_wdata_i = 32'h00000000;
            csr_commit_rd_zero_i = 1'b0;
            trap_commit_valid_i = 1'b0;
            trap_mepc_i = 32'h00000000;
            trap_mcause_i = 32'h00000000;
            trap_mtval_i = 32'h00000000;
            mret_commit_valid_i = 1'b0;
        end
    endtask

    task csr_commit;
        input [2:0] op;
        input [11:0] addr;
        input [31:0] data;
        input rd_zero;
        begin
            csr_read_valid_i = 1'b1;
            csr_read_op_i = op;
            csr_read_addr_i = addr;
            csr_read_wdata_i = data;
            csr_read_rd_zero_i = rd_zero;
            #1;
            if (csr_read_illegal_o) begin
                $display("FAIL unexpected illegal CSR addr=%03x op=%0d", addr, op);
                $finish;
            end
            csr_commit_valid_i = 1'b1;
            csr_commit_op_i = op;
            csr_commit_addr_i = addr;
            csr_commit_wdata_i = data;
            csr_commit_rd_zero_i = rd_zero;
            @(posedge clk);
            #1;
            clear_req();
        end
    endtask

    task csr_read_expect;
        input [11:0] addr;
        input [31:0] expected;
        begin
            csr_read_valid_i = 1'b1;
            csr_read_op_i = `CSR_OP_RS;
            csr_read_addr_i = addr;
            csr_read_wdata_i = 32'h00000000;
            csr_read_rd_zero_i = 1'b0;
            #1;
            if (csr_read_illegal_o || csr_read_data_o !== expected) begin
                $display("FAIL csr_read addr=%03x expected=%08x got=%08x illegal=%b",
                    addr, expected, csr_read_data_o, csr_read_illegal_o);
                $finish;
            end
            clear_req();
        end
    endtask

    initial begin
        clear_req();
        rst = 1'b1;
        repeat (4) @(posedge clk);
        rst = 1'b0;
        @(posedge clk);

        csr_commit(`CSR_OP_RW, `CSR_MSCRATCH, 32'h12345678, 1'b0);
        csr_read_expect(`CSR_MSCRATCH, 32'h12345678);

        csr_commit(`CSR_OP_RS, `CSR_MSCRATCH, 32'h0000ff00, 1'b0);
        csr_read_expect(`CSR_MSCRATCH, 32'h1234ff78);

        csr_commit(`CSR_OP_RC, `CSR_MSCRATCH, 32'h00000078, 1'b0);
        csr_read_expect(`CSR_MSCRATCH, 32'h1234ff00);

        csr_commit(`CSR_OP_RWI, `CSR_MSCRATCH, 32'h0000001f, 1'b0);
        csr_read_expect(`CSR_MSCRATCH, 32'h0000001f);

        csr_commit(`CSR_OP_RSI, `CSR_MSCRATCH, 32'h00000000, 1'b0);
        csr_read_expect(`CSR_MSCRATCH, 32'h0000001f);

        csr_commit(`CSR_OP_RCI, `CSR_MSCRATCH, 32'h00000001, 1'b0);
        csr_read_expect(`CSR_MSCRATCH, 32'h0000001e);

        csr_commit(`CSR_OP_RS, `CSR_MSCRATCH, 32'h00000000, 1'b0);
        csr_read_expect(`CSR_MSCRATCH, 32'h0000001e);

        csr_read_valid_i = 1'b1;
        csr_read_op_i = `CSR_OP_RW;
        csr_read_addr_i = `CSR_MISA;
        csr_read_wdata_i = 32'hffffffff;
        csr_read_rd_zero_i = 1'b0;
        #1;
        if (!csr_read_illegal_o) begin
            $display("FAIL write to read-only misa was not illegal");
            $finish;
        end
        clear_req();

        $display("PASS csr_unit zicsr regression completed");
        $finish;
    end
endmodule
```

- [ ] **Step 2: Create the CSR unit regression script**

Create `scripts/run_csr_unit_modelsim.ps1`:

```powershell
$ErrorActionPreference = "Stop"

$vlib = Get-Command vlib -ErrorAction SilentlyContinue
$vlog = Get-Command vlog -ErrorAction SilentlyContinue
$vsim = Get-Command vsim -ErrorAction SilentlyContinue
if (-not $vlib -or -not $vlog -or -not $vsim) {
  throw "ModelSim commands not found in PATH. Required: vlib, vlog, vsim."
}

$workDir = "build/modelsim_csr_unit"
if (Test-Path -LiteralPath $workDir) {
  Remove-Item -LiteralPath $workDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $workDir | Out-Null
& vlib "$workDir/work"

$sources = @(
  "rtl/csr_unit.v",
  "tb/tb_csr_unit_zicsr.v"
)

$compileOutput = & vlog -work "$workDir/work" +incdir+rtl @sources 2>&1
$compileOutput
if ($LASTEXITCODE -ne 0 -or (($compileOutput | Out-String) -match "Errors:\s*[1-9]")) {
  throw "ModelSim vlog failed"
}

$simOutput = & vsim -c -lib "$workDir/work" tb_csr_unit_zicsr -do "run -all; quit -f" 2>&1
$simOutput
$simText = $simOutput | Out-String
if ($LASTEXITCODE -ne 0 -or $simText -match "FAIL " -or $simText -match "Errors:\s*[1-9]") {
  throw "CSR unit test failed: tb_csr_unit_zicsr"
}
```

- [ ] **Step 3: Run the failing test**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_csr_unit_modelsim.ps1
```

Expected: FAIL at compile because current `csr_unit` does not expose the CSR read/commit/trap/MRET ports and `defines.vh` does not define the CSR op constants.

- [ ] **Step 4: Add CSR op and CSR address constants**

Modify `rtl/defines.vh` by inserting the Interface Contract constants after the opcode definitions and before `ALU_ADD`.

- [ ] **Step 5: Replace `csr_unit` with the CSR bank skeleton**

Modify `rtl/csr_unit.v` so it uses the Interface Contract module header. The first green implementation must include:

```verilog
    localparam [XLEN-1:0] ZERO = {XLEN{1'b0}};
    localparam [XLEN-1:0] MSTATUS_MIE  = {{(XLEN-4){1'b0}}, 1'b1, 3'b000};
    localparam [XLEN-1:0] MSTATUS_MPIE = {{(XLEN-8){1'b0}}, 1'b1, 7'b0000000};
    localparam [XLEN-1:0] MSTATUS_MPP  = {{(XLEN-13){1'b0}}, 2'b11, 11'b00000000000};
    localparam [XLEN-1:0] MSTATUS_MASK = MSTATUS_MIE | MSTATUS_MPIE | MSTATUS_MPP;
    localparam [XLEN-1:0] MIE_MIP_MASK = {{(XLEN-12){1'b0}}, 1'b1, 3'b000, 1'b1, 3'b000, 1'b1, 3'b000};

    reg [XLEN-1:0] mstatus_r;
    reg [XLEN-1:0] mie_r;
    reg [XLEN-1:0] mtvec_r;
    reg [XLEN-1:0] mscratch_r;
    reg [XLEN-1:0] mepc_r;
    reg [XLEN-1:0] mcause_r;
    reg [XLEN-1:0] mtval_r;
    reg [XLEN-1:0] mip_r;

    wire [1:0] misa_mxl = (XLEN == 64) ? 2'b10 : 2'b01;
    wire [XLEN-1:0] misa_value =
        ({XLEN{1'b0}} |
         ({{(XLEN-2){1'b0}}, misa_mxl} << (XLEN - 2)) |
         ({{(XLEN-9){1'b0}}, 1'b1} << 8) |
         ({{(XLEN-13){1'b0}}, 1'b1} << 12));

    function [XLEN-1:0] mask_mepc;
        input [XLEN-1:0] value;
        begin
            mask_mepc = SUPPORT_C ? {value[XLEN-1:1], 1'b0} :
                                    {value[XLEN-1:2], 2'b00};
        end
    endfunction

    function csr_is_read_only;
        input [11:0] addr;
        begin
            csr_is_read_only = (addr[11:10] == 2'b11);
        end
    endfunction

    function csr_write_requested;
        input [2:0] op;
        input [XLEN-1:0] src;
        begin
            case (op)
                `CSR_OP_RW,
                `CSR_OP_RWI: csr_write_requested = 1'b1;
                `CSR_OP_RS,
                `CSR_OP_RC,
                `CSR_OP_RSI,
                `CSR_OP_RCI: csr_write_requested = |src;
                default: csr_write_requested = 1'b0;
            endcase
        end
    endfunction
```

The write path must update `mscratch` through `CSRRW`, `CSRRS`, `CSRRC`, and immediate forms, and must reject writes to read-only CSRs.

- [ ] **Step 6: Run the Zicsr unit test to verify green**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_csr_unit_modelsim.ps1
```

Expected: PASS with `PASS csr_unit zicsr regression completed`.

- [ ] **Step 7: Add the test to the full ModelSim source list**

Modify `scripts/run_modelsim.ps1`:

```powershell
# Add after "tb/tb_csr_counter.v",
"tb/tb_csr_unit_zicsr.v",
```

Add to `$tests`:

```powershell
# Add after "tb_csr_counter",
"tb_csr_unit_zicsr",
```

- [ ] **Step 8: Commit Task 1**

Run:

```powershell
git add rtl/defines.vh rtl/csr_unit.v tb/tb_csr_unit_zicsr.v scripts/run_csr_unit_modelsim.ps1 scripts/run_modelsim.ps1
git commit -m "Add Zicsr CSR bank unit coverage"
```

## Task 2: Trap, MRET, and XLEN=64 CSR Unit Coverage

**Files:**
- Modify: `rtl/csr_unit.v`
- Create: `tb/tb_csr_unit_trap_mret.v`
- Create: `tb/tb_csr_unit_xlen64.v`
- Modify: `scripts/run_csr_unit_modelsim.ps1`
- Modify: `scripts/run_modelsim.ps1`

- [ ] **Step 1: Add trap and MRET failing test**

Create `tb/tb_csr_unit_trap_mret.v`:

```verilog
`timescale 1ns/1ps
`include "defines.vh"

module tb_csr_unit_trap_mret;
    reg clk;
    reg rst;
    reg retire_i;
    reg [1:0] retire_count_i;
    reg csr_read_valid_i;
    reg [2:0] csr_read_op_i;
    reg [11:0] csr_read_addr_i;
    reg [31:0] csr_read_wdata_i;
    reg csr_read_rd_zero_i;
    wire [31:0] csr_read_data_o;
    wire csr_read_illegal_o;
    reg csr_commit_valid_i;
    reg [2:0] csr_commit_op_i;
    reg [11:0] csr_commit_addr_i;
    reg [31:0] csr_commit_wdata_i;
    reg csr_commit_rd_zero_i;
    reg trap_commit_valid_i;
    reg [31:0] trap_mepc_i;
    reg [31:0] trap_mcause_i;
    reg [31:0] trap_mtval_i;
    reg mret_commit_valid_i;
    wire [31:0] trap_pc_o;
    wire [31:0] mret_pc_o;
    wire [31:0] mcycle_o;
    wire [31:0] minstret_o;

    csr_unit #(.XLEN(32), .HART_ID(0)) dut (
        .clk(clk),
        .rst(rst),
        .retire_i(retire_i),
        .retire_count_i(retire_count_i),
        .csr_read_valid_i(csr_read_valid_i),
        .csr_read_op_i(csr_read_op_i),
        .csr_read_addr_i(csr_read_addr_i),
        .csr_read_wdata_i(csr_read_wdata_i),
        .csr_read_rd_zero_i(csr_read_rd_zero_i),
        .csr_read_data_o(csr_read_data_o),
        .csr_read_illegal_o(csr_read_illegal_o),
        .csr_commit_valid_i(csr_commit_valid_i),
        .csr_commit_op_i(csr_commit_op_i),
        .csr_commit_addr_i(csr_commit_addr_i),
        .csr_commit_wdata_i(csr_commit_wdata_i),
        .csr_commit_rd_zero_i(csr_commit_rd_zero_i),
        .trap_commit_valid_i(trap_commit_valid_i),
        .trap_mepc_i(trap_mepc_i),
        .trap_mcause_i(trap_mcause_i),
        .trap_mtval_i(trap_mtval_i),
        .mret_commit_valid_i(mret_commit_valid_i),
        .trap_pc_o(trap_pc_o),
        .mret_pc_o(mret_pc_o),
        .mcycle_o(mcycle_o),
        .minstret_o(minstret_o)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task clear_req;
        begin
            retire_i = 1'b0;
            retire_count_i = 2'd0;
            csr_read_valid_i = 1'b0;
            csr_read_op_i = `CSR_OP_NONE;
            csr_read_addr_i = 12'h000;
            csr_read_wdata_i = 32'h00000000;
            csr_read_rd_zero_i = 1'b0;
            csr_commit_valid_i = 1'b0;
            csr_commit_op_i = `CSR_OP_NONE;
            csr_commit_addr_i = 12'h000;
            csr_commit_wdata_i = 32'h00000000;
            csr_commit_rd_zero_i = 1'b0;
            trap_commit_valid_i = 1'b0;
            trap_mepc_i = 32'h00000000;
            trap_mcause_i = 32'h00000000;
            trap_mtval_i = 32'h00000000;
            mret_commit_valid_i = 1'b0;
        end
    endtask

    task csr_write;
        input [11:0] addr;
        input [31:0] value;
        begin
            csr_commit_valid_i = 1'b1;
            csr_commit_op_i = `CSR_OP_RW;
            csr_commit_addr_i = addr;
            csr_commit_wdata_i = value;
            csr_commit_rd_zero_i = 1'b0;
            @(posedge clk);
            #1;
            clear_req();
        end
    endtask

    task csr_expect;
        input [11:0] addr;
        input [31:0] expected;
        begin
            csr_read_valid_i = 1'b1;
            csr_read_op_i = `CSR_OP_RS;
            csr_read_addr_i = addr;
            csr_read_wdata_i = 32'h00000000;
            csr_read_rd_zero_i = 1'b0;
            #1;
            if (csr_read_illegal_o || csr_read_data_o !== expected) begin
                $display("FAIL csr_expect addr=%03x expected=%08x got=%08x illegal=%b",
                    addr, expected, csr_read_data_o, csr_read_illegal_o);
                $finish;
            end
            clear_req();
        end
    endtask

    initial begin
        clear_req();
        rst = 1'b1;
        repeat (4) @(posedge clk);
        rst = 1'b0;

        csr_write(`CSR_MTVEC, 32'h00000105);
        if (trap_pc_o !== 32'h00000104) begin
            $display("FAIL trap_pc expected BASE 00000104 got %08x", trap_pc_o);
            $finish;
        end

        csr_write(`CSR_MSTATUS, 32'h00000008);
        trap_commit_valid_i = 1'b1;
        trap_mepc_i = 32'h00000023;
        trap_mcause_i = `CAUSE_ECALL_MMODE;
        trap_mtval_i = 32'h00000000;
        @(posedge clk);
        #1;
        clear_req();

        csr_expect(`CSR_MEPC, 32'h00000020);
        csr_expect(`CSR_MCAUSE, `CAUSE_ECALL_MMODE);
        csr_expect(`CSR_MTVAL, 32'h00000000);
        csr_expect(`CSR_MSTATUS, 32'h00001880);

        csr_write(`CSR_MEPC, 32'h00000027);
        if (mret_pc_o !== 32'h00000024) begin
            $display("FAIL mret_pc expected 00000024 got %08x", mret_pc_o);
            $finish;
        end

        mret_commit_valid_i = 1'b1;
        @(posedge clk);
        #1;
        clear_req();
        csr_expect(`CSR_MSTATUS, 32'h00000088);

        $display("PASS csr_unit trap mret regression completed");
        $finish;
    end
endmodule
```

- [ ] **Step 2: Add XLEN=64 failing test**

Create `tb/tb_csr_unit_xlen64.v`:

```verilog
`timescale 1ns/1ps
`include "defines.vh"

module tb_csr_unit_xlen64;
    reg clk;
    reg rst;
    wire [63:0] csr_read_data_o;
    wire csr_read_illegal_o;
    wire [63:0] trap_pc_o;
    wire [63:0] mret_pc_o;
    wire [63:0] mcycle_o;
    wire [63:0] minstret_o;

    reg csr_read_valid_i;
    reg [2:0] csr_read_op_i;
    reg [11:0] csr_read_addr_i;
    reg [63:0] csr_read_wdata_i;
    reg csr_read_rd_zero_i;
    reg csr_commit_valid_i;
    reg [2:0] csr_commit_op_i;
    reg [11:0] csr_commit_addr_i;
    reg [63:0] csr_commit_wdata_i;
    reg csr_commit_rd_zero_i;
    reg trap_commit_valid_i;
    reg [63:0] trap_mepc_i;
    reg [63:0] trap_mcause_i;
    reg [63:0] trap_mtval_i;
    reg mret_commit_valid_i;

    csr_unit #(.XLEN(64), .HART_ID(5)) dut (
        .clk(clk),
        .rst(rst),
        .retire_i(1'b0),
        .retire_count_i(2'd0),
        .csr_read_valid_i(csr_read_valid_i),
        .csr_read_op_i(csr_read_op_i),
        .csr_read_addr_i(csr_read_addr_i),
        .csr_read_wdata_i(csr_read_wdata_i),
        .csr_read_rd_zero_i(csr_read_rd_zero_i),
        .csr_read_data_o(csr_read_data_o),
        .csr_read_illegal_o(csr_read_illegal_o),
        .csr_commit_valid_i(csr_commit_valid_i),
        .csr_commit_op_i(csr_commit_op_i),
        .csr_commit_addr_i(csr_commit_addr_i),
        .csr_commit_wdata_i(csr_commit_wdata_i),
        .csr_commit_rd_zero_i(csr_commit_rd_zero_i),
        .trap_commit_valid_i(trap_commit_valid_i),
        .trap_mepc_i(trap_mepc_i),
        .trap_mcause_i(trap_mcause_i),
        .trap_mtval_i(trap_mtval_i),
        .mret_commit_valid_i(mret_commit_valid_i),
        .trap_pc_o(trap_pc_o),
        .mret_pc_o(mret_pc_o),
        .mcycle_o(mcycle_o),
        .minstret_o(minstret_o)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task clear_req;
        begin
            csr_read_valid_i = 1'b0;
            csr_read_op_i = `CSR_OP_NONE;
            csr_read_addr_i = 12'h000;
            csr_read_wdata_i = 64'h0000000000000000;
            csr_read_rd_zero_i = 1'b0;
            csr_commit_valid_i = 1'b0;
            csr_commit_op_i = `CSR_OP_NONE;
            csr_commit_addr_i = 12'h000;
            csr_commit_wdata_i = 64'h0000000000000000;
            csr_commit_rd_zero_i = 1'b0;
            trap_commit_valid_i = 1'b0;
            trap_mepc_i = 64'h0000000000000000;
            trap_mcause_i = 64'h0000000000000000;
            trap_mtval_i = 64'h0000000000000000;
            mret_commit_valid_i = 1'b0;
        end
    endtask

    task read_csr;
        input [11:0] addr;
        begin
            csr_read_valid_i = 1'b1;
            csr_read_op_i = `CSR_OP_RS;
            csr_read_addr_i = addr;
            csr_read_wdata_i = 64'h0000000000000000;
            csr_read_rd_zero_i = 1'b0;
            #1;
        end
    endtask

    initial begin
        clear_req();
        rst = 1'b1;
        repeat (4) @(posedge clk);
        rst = 1'b0;

        read_csr(`CSR_MISA);
        if (csr_read_illegal_o || csr_read_data_o[63:62] !== 2'b10) begin
            $display("FAIL RV64 misa.MXL expected 2 got %016x illegal=%b",
                csr_read_data_o, csr_read_illegal_o);
            $finish;
        end
        clear_req();

        read_csr(`CSR_MHARTID);
        if (csr_read_illegal_o || csr_read_data_o !== 64'h0000000000000005) begin
            $display("FAIL RV64 mhartid expected 5 got %016x illegal=%b",
                csr_read_data_o, csr_read_illegal_o);
            $finish;
        end
        clear_req();

        read_csr(`CSR_MCYCLEH);
        if (!csr_read_illegal_o) begin
            $display("FAIL RV64 mcycleh access was not illegal");
            $finish;
        end
        clear_req();

        csr_commit_valid_i = 1'b1;
        csr_commit_op_i = `CSR_OP_RW;
        csr_commit_addr_i = `CSR_MSCRATCH;
        csr_commit_wdata_i = 64'h1122334455667788;
        @(posedge clk);
        #1;
        clear_req();

        read_csr(`CSR_MSCRATCH);
        if (csr_read_data_o !== 64'h1122334455667788) begin
            $display("FAIL RV64 mscratch width got %016x", csr_read_data_o);
            $finish;
        end

        $display("PASS csr_unit xlen64 regression completed");
        $finish;
    end
endmodule
```

- [ ] **Step 3: Extend the CSR unit regression script**

Modify `scripts/run_csr_unit_modelsim.ps1` so `$sources` includes:

```powershell
"tb/tb_csr_unit_trap_mret.v",
"tb/tb_csr_unit_xlen64.v"
```

Replace the single-test run with:

```powershell
$tests = @(
  "tb_csr_unit_zicsr",
  "tb_csr_unit_trap_mret",
  "tb_csr_unit_xlen64"
)

foreach ($test in $tests) {
  $simOutput = & vsim -c -lib "$workDir/work" $test -do "run -all; quit -f" 2>&1
  $simOutput
  $simText = $simOutput | Out-String
  if ($LASTEXITCODE -ne 0 -or $simText -match "FAIL " -or $simText -match "Errors:\s*[1-9]") {
    throw "CSR unit test failed: $test"
  }
}
```

- [ ] **Step 4: Run the failing trap/MRET tests**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_csr_unit_modelsim.ps1
```

Expected: `tb_csr_unit_trap_mret` and `tb_csr_unit_xlen64` fail because trap entry, MRET restore, and RV64 behavior are not fully implemented yet.

- [ ] **Step 5: Implement trap entry and MRET restore**

In `rtl/csr_unit.v`, add this trap and MRET update behavior inside the clocked block, before normal CSR commit writes:

```verilog
            if (trap_commit_valid_i) begin
                mepc_r <= mask_mepc(trap_mepc_i);
                mcause_r <= trap_mcause_i;
                mtval_r <= trap_mtval_i;
                mstatus_r <= ((mstatus_r & ~MSTATUS_MIE) |
                              ((mstatus_r & MSTATUS_MIE) ? MSTATUS_MPIE : ZERO) |
                              MSTATUS_MPP);
            end else if (mret_commit_valid_i) begin
                mstatus_r <= ((mstatus_r & ~MSTATUS_MIE) |
                              ((mstatus_r & MSTATUS_MPIE) ? MSTATUS_MIE : ZERO) |
                              MSTATUS_MPIE |
                              MSTATUS_MPP);
            end else if (csr_commit_valid_i) begin
                // Normal CSR write path from Task 1 remains here.
            end
```

Set targets:

```verilog
    assign trap_pc_o = {mtvec_r[XLEN-1:2], 2'b00};
    assign mret_pc_o = mask_mepc(mepc_r);
```

Ensure `mstatus`, `mtvec`, `mepc`, `mcause`, and `mtval` are handled in the read and write functions.

- [ ] **Step 6: Implement RV64 and counter-high legality**

In `csr_unit`, make CSR address validation treat `mcycleh/minstreth` as legal only when `XLEN == 32`. Read `mcycleh/minstreth` from the high halves of the internal 64-bit counters in RV32. Return illegal for these addresses in RV64.

- [ ] **Step 7: Run the CSR unit tests to verify green**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_csr_unit_modelsim.ps1
```

Expected: PASS for all three CSR unit tests.

- [ ] **Step 8: Add tests to full ModelSim regression**

Modify `scripts/run_modelsim.ps1` source list:

```powershell
"tb/tb_csr_unit_trap_mret.v",
"tb/tb_csr_unit_xlen64.v",
```

Modify `$tests`:

```powershell
"tb_csr_unit_trap_mret",
"tb_csr_unit_xlen64",
```

- [ ] **Step 9: Commit Task 2**

Run:

```powershell
git add rtl/csr_unit.v tb/tb_csr_unit_trap_mret.v tb/tb_csr_unit_xlen64.v scripts/run_csr_unit_modelsim.ps1 scripts/run_modelsim.ps1
git commit -m "Add CSR trap and RV64 unit coverage"
```

## Task 3: Decoder System Classification

**Files:**
- Modify: `rtl/decoder.v`
- Create: `tb/tb_decoder_system.v`
- Modify: `scripts/run_modelsim.ps1`

- [ ] **Step 1: Add decoder failing test**

Create `tb/tb_decoder_system.v`:

```verilog
`timescale 1ns/1ps
`include "defines.vh"

module tb_decoder_system;
    reg [31:0] instr;
    wire [6:0] opcode;
    wire [4:0] rd;
    wire [2:0] funct3;
    wire [4:0] rs1;
    wire [4:0] rs2;
    wire [6:0] funct7;
    wire [31:0] imm;
    wire [4:0] alu_op;
    wire alu_src_imm;
    wire reg_write;
    wire mem_read;
    wire mem_write;
    wire [1:0] wb_sel;
    wire branch;
    wire jump;
    wire jalr;
    wire csr_instr;
    wire [2:0] csr_op;
    wire [2:0] sys_event;
    wire illegal_instr;
    wire m_ext;

    decoder dut (
        .instr(instr),
        .opcode(opcode),
        .rd(rd),
        .funct3(funct3),
        .rs1(rs1),
        .rs2(rs2),
        .funct7(funct7),
        .imm(imm),
        .alu_op(alu_op),
        .alu_src_imm(alu_src_imm),
        .reg_write(reg_write),
        .mem_read(mem_read),
        .mem_write(mem_write),
        .wb_sel(wb_sel),
        .branch(branch),
        .jump(jump),
        .jalr(jalr),
        .csr_instr(csr_instr),
        .csr_op(csr_op),
        .sys_event(sys_event),
        .illegal_instr(illegal_instr),
        .m_ext(m_ext)
    );

    task expect;
        input [31:0] value;
        input exp_csr;
        input [2:0] exp_csr_op;
        input [2:0] exp_sys;
        input exp_illegal;
        input exp_reg_write;
        begin
            instr = value;
            #1;
            if (csr_instr !== exp_csr ||
                csr_op !== exp_csr_op ||
                sys_event !== exp_sys ||
                illegal_instr !== exp_illegal ||
                reg_write !== exp_reg_write) begin
                $display("FAIL instr=%08x csr=%b/%b sys=%0d/%0d illegal=%b/%b reg_write=%b/%b",
                    value, csr_instr, exp_csr, csr_op, exp_csr_op,
                    sys_event, exp_sys, illegal_instr, exp_illegal,
                    reg_write, exp_reg_write);
                $finish;
            end
        end
    endtask

    initial begin
        expect(32'h00000073, 1'b0, `CSR_OP_NONE, `SYS_EVT_ECALL, 1'b0, 1'b0);
        expect(32'h00100073, 1'b0, `CSR_OP_NONE, `SYS_EVT_EBREAK, 1'b0, 1'b0);
        expect(32'h30200073, 1'b0, `CSR_OP_NONE, `SYS_EVT_MRET, 1'b0, 1'b0);
        expect(32'h300110f3, 1'b1, `CSR_OP_RW, `SYS_EVT_NONE, 1'b0, 1'b1);
        expect(32'h3001a0f3, 1'b1, `CSR_OP_RS, `SYS_EVT_NONE, 1'b0, 1'b1);
        expect(32'h3001b0f3, 1'b1, `CSR_OP_RC, `SYS_EVT_NONE, 1'b0, 1'b1);
        expect(32'h3002d0f3, 1'b1, `CSR_OP_RWI, `SYS_EVT_NONE, 1'b0, 1'b1);
        expect(32'h3002e0f3, 1'b1, `CSR_OP_RSI, `SYS_EVT_NONE, 1'b0, 1'b1);
        expect(32'h3002f0f3, 1'b1, `CSR_OP_RCI, `SYS_EVT_NONE, 1'b0, 1'b1);
        expect(32'h10500073, 1'b0, `CSR_OP_NONE, `SYS_EVT_ILLEGAL, 1'b1, 1'b0);

        $display("PASS decoder system regression completed");
        $finish;
    end
endmodule
```

- [ ] **Step 2: Run the failing decoder test**

Run a focused compile:

```powershell
if (Test-Path -LiteralPath build\modelsim_decoder_system) { Remove-Item -LiteralPath build\modelsim_decoder_system -Recurse -Force }
New-Item -ItemType Directory -Force -Path build\modelsim_decoder_system | Out-Null
vlib build\modelsim_decoder_system\work
vlog -work build\modelsim_decoder_system\work +incdir+rtl rtl/decoder.v tb/tb_decoder_system.v
vsim -c -lib build\modelsim_decoder_system\work tb_decoder_system -do "run -all; quit -f"
```

Expected: FAIL at compile because `decoder` does not expose `csr_op`, `sys_event`, or `illegal_instr`.

- [ ] **Step 3: Extend decoder outputs**

Modify `rtl/decoder.v` module port list:

```verilog
    output reg csr_instr,
    output reg [2:0] csr_op,
    output reg [2:0] sys_event,
    output reg illegal_instr,
    output reg m_ext
```

Initialize new outputs in the combinational default block:

```verilog
        csr_op = `CSR_OP_NONE;
        sys_event = `SYS_EVT_NONE;
        illegal_instr = 1'b0;
```

Replace the `OPCODE_SYSTEM` case with:

```verilog
            `OPCODE_SYSTEM: begin
                case (funct3)
                    3'b000: begin
                        if (instr == 32'h00000073) begin
                            sys_event = `SYS_EVT_ECALL;
                        end else if (instr == 32'h00100073) begin
                            sys_event = `SYS_EVT_EBREAK;
                        end else if (instr == 32'h30200073) begin
                            sys_event = `SYS_EVT_MRET;
                        end else begin
                            sys_event = `SYS_EVT_ILLEGAL;
                            illegal_instr = 1'b1;
                        end
                    end
                    3'b001: begin csr_instr = 1'b1; csr_op = `CSR_OP_RW;  reg_write = 1'b1; end
                    3'b010: begin csr_instr = 1'b1; csr_op = `CSR_OP_RS;  reg_write = 1'b1; end
                    3'b011: begin csr_instr = 1'b1; csr_op = `CSR_OP_RC;  reg_write = 1'b1; end
                    3'b101: begin csr_instr = 1'b1; csr_op = `CSR_OP_RWI; reg_write = 1'b1; end
                    3'b110: begin csr_instr = 1'b1; csr_op = `CSR_OP_RSI; reg_write = 1'b1; end
                    3'b111: begin csr_instr = 1'b1; csr_op = `CSR_OP_RCI; reg_write = 1'b1; end
                    default: begin
                        sys_event = `SYS_EVT_ILLEGAL;
                        illegal_instr = 1'b1;
                    end
                endcase
            end
```

- [ ] **Step 4: Update decoder instantiations**

Modify `rtl/cpu_core.v` wires near the existing decoder outputs:

```verilog
    wire [2:0] dec_csr_op;
    wire [2:0] dec_sys_event;
    wire dec_illegal_instr;
```

Update the decoder instance:

```verilog
        .csr_instr(dec_csr_instr),
        .csr_op(dec_csr_op),
        .sys_event(dec_sys_event),
        .illegal_instr(dec_illegal_instr),
        .m_ext(dec_m_ext)
```

- [ ] **Step 5: Run the decoder test to verify green**

Run the focused command from Step 2.

Expected: PASS with `PASS decoder system regression completed`.

- [ ] **Step 6: Add the decoder test to full ModelSim**

Modify `scripts/run_modelsim.ps1` source list:

```powershell
"tb/tb_decoder_system.v",
```

Modify `$tests`:

```powershell
"tb_decoder_system",
```

- [ ] **Step 7: Commit Task 3**

Run:

```powershell
git add rtl/decoder.v rtl/cpu_core.v tb/tb_decoder_system.v scripts/run_modelsim.ps1
git commit -m "Decode CSR and machine system events"
```

## Task 4: CPU CSR Read/Write Integration

**Files:**
- Modify: `rtl/cpu_core.v`
- Create: `sw/csr_trap_tests/csr_rw.S`
- Create: `scripts/run_csr_trap_programs.ps1`

- [ ] **Step 1: Add the CSR RW program**

Create `sw/csr_trap_tests/csr_rw.S`:

```asm
    .section .text
    .globl main
main:
    li t0, 0x12345678
    csrw mscratch, t0
    csrr t1, mscratch
    li t2, 0x00010000
    sw t1, 0(t2)
    bne t1, t0, fail

    li t3, 0x00000100
    csrw mtvec, t3
    csrr t4, mtvec
    sw t4, 4(t2)
    bne t4, t3, fail

    li t5, 0x00000027
    csrw mepc, t5
    csrr t6, mepc
    sw t6, 8(t2)
    li t0, 0x00000024
    bne t6, t0, fail

    li t0, 0x0000000f
    csrs mscratch, t0
    csrr t1, mscratch
    sw t1, 12(t2)
    li t0, 0x1234567f
    bne t1, t0, fail

    li t0, 0x00000070
    csrc mscratch, t0
    csrr t1, mscratch
    sw t1, 16(t2)
    li t0, 0x1234560f
    bne t1, t0, fail

    ret

fail:
    call yl3_fail
```

- [ ] **Step 2: Add the program runner script**

Create `scripts/run_csr_trap_programs.ps1`:

```powershell
param(
  [string[]]$Tests = @("csr_rw"),
  [string]$ToolPrefix = "xpack-riscv-none-elf-gcc-15.2.0-1\bin\riscv-none-elf-",
  [int]$MaxCycles = 200000
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$gccPrefix = if ([System.IO.Path]::IsPathRooted($ToolPrefix)) { $ToolPrefix } else { Join-Path $repoRoot $ToolPrefix }
$objcopy = $gccPrefix + "objcopy.exe"

foreach ($test in $Tests) {
  $src = Join-Path $repoRoot "sw\csr_trap_tests\$test.S"
  if (-not (Test-Path -LiteralPath $src)) {
    throw "CSR trap test source not found: $src"
  }

  $buildOutput = & powershell -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\build_baremetal.ps1") `
    -Sources $src `
    -OutName $test `
    -ToolPrefix $gccPrefix `
    -OutDir (Join-Path $repoRoot "build\csr_trap_tests") `
    -March "rv32im_zicsr" `
    -Mabi "ilp32" 2>&1
  $buildOutput
  if ($LASTEXITCODE -ne 0) {
    throw "CSR trap test build failed: $test"
  }

  $elfLine = $buildOutput | Where-Object { $_ -match "^ELF=" } | Select-Object -Last 1
  if (-not $elfLine) {
    throw "Failed to parse ELF path for $test"
  }
  $elf = ($elfLine -replace "^ELF=", "").Trim()

  $hexOutput = & powershell -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\convert_elf_to_hex.ps1") `
    -Elf $elf `
    -Objcopy $objcopy `
    -OutDir (Join-Path $repoRoot "build\csr_trap_tests\hex") 2>&1
  $hexOutput
  if ($LASTEXITCODE -ne 0) {
    throw "CSR trap test hex conversion failed: $test"
  }

  $imemLine = $hexOutput | Where-Object { $_ -match "^IMEM_HEX=" } | Select-Object -Last 1
  $dmemLine = $hexOutput | Where-Object { $_ -match "^DMEM_HEX=" } | Select-Object -Last 1
  if (-not $imemLine -or -not $dmemLine) {
    throw "Failed to parse hex paths for $test"
  }
  $imem = ($imemLine -replace "^IMEM_HEX=", "").Trim()
  $dmem = ($dmemLine -replace "^DMEM_HEX=", "").Trim()

  Write-Host "RUN_CSR_TRAP_TEST=$test"
  & powershell -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\run_external_modelsim.ps1") `
    -IMemHex $imem `
    -DMemHex $dmem `
    -MaxCycles $MaxCycles `
    -DMemBase 65536 `
    -PassAddr 98288 `
    -FailAddr 98292
  if ($LASTEXITCODE -ne 0) {
    throw "CSR trap simulation failed: $test"
  }
}
```

- [ ] **Step 3: Run the failing CSR RW integration test**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_csr_trap_programs.ps1 -Tests csr_rw
```

Expected: FAIL because `cpu_core` still only reads `mcycle/minstret` and does not commit normal CSR writes.

- [ ] **Step 4: Add CSR pipeline registers**

Modify `rtl/cpu_core.v` by adding ID/EX registers:

```verilog
    reg [2:0] id_ex_csr_op;
    reg [31:0] id_ex_instr;
```

Add EX/MEM registers:

```verilog
    reg ex_mem_csr_instr;
    reg [2:0] ex_mem_csr_op;
    reg [11:0] ex_mem_csr_addr;
    reg [31:0] ex_mem_csr_wdata;
    reg ex_mem_csr_rd_zero;
```

Reset and flush these registers to safe values in the same branches that clear
`id_ex_csr_instr` and `ex_mem_valid`.

- [ ] **Step 5: Connect CSR read and commit ports**

Replace the old `csr_unit` instance in `rtl/cpu_core.v` with the Interface Contract connection. Use ID/EX for read:

```verilog
    wire [31:0] csr_src_value = id_ex_csr_op[2] ? {27'd0, id_ex_rs1} : forward_a_data;
    wire [31:0] csr_read_data;
    wire csr_read_illegal;
```

Connect:

```verilog
        .csr_read_valid_i(id_ex_valid && id_ex_csr_instr),
        .csr_read_op_i(id_ex_csr_op),
        .csr_read_addr_i(id_ex_csr_addr),
        .csr_read_wdata_i(csr_src_value),
        .csr_read_rd_zero_i(id_ex_rd == 5'd0),
        .csr_read_data_o(csr_read_data),
        .csr_read_illegal_o(csr_read_illegal),
        .csr_commit_valid_i(ex_mem_valid && ex_mem_csr_instr && !ex_mem_trap_valid),
        .csr_commit_op_i(ex_mem_csr_op),
        .csr_commit_addr_i(ex_mem_csr_addr),
        .csr_commit_wdata_i(ex_mem_csr_wdata),
        .csr_commit_rd_zero_i(ex_mem_csr_rd_zero),
```

Set `ex_result` CSR path to `csr_read_data`.

- [ ] **Step 6: Carry CSR write source into EX/MEM**

In the EX/MEM update block, assign:

```verilog
                ex_mem_csr_instr <= id_ex_csr_instr && id_ex_valid && !csr_read_illegal;
                ex_mem_csr_op <= id_ex_csr_op;
                ex_mem_csr_addr <= id_ex_csr_addr;
                ex_mem_csr_wdata <= csr_src_value;
                ex_mem_csr_rd_zero <= (id_ex_rd == 5'd0);
```

When clearing EX/MEM, set these to:

```verilog
                ex_mem_csr_instr <= 1'b0;
                ex_mem_csr_op <= `CSR_OP_NONE;
                ex_mem_csr_addr <= 12'h000;
                ex_mem_csr_wdata <= 32'h00000000;
                ex_mem_csr_rd_zero <= 1'b0;
```

- [ ] **Step 7: Run CSR RW integration to verify green**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_csr_trap_programs.ps1 -Tests csr_rw
```

Expected: PASS external program.

- [ ] **Step 8: Commit Task 4**

Run:

```powershell
git add rtl/cpu_core.v sw/csr_trap_tests/csr_rw.S scripts/run_csr_trap_programs.ps1
git commit -m "Integrate normal CSR read and writeback"
```

## Task 5: ECALL Trap and MRET Redirect Integration

**Files:**
- Modify: `rtl/cpu_core.v`
- Create: `sw/csr_trap_tests/ecall_mret.S`

- [ ] **Step 1: Add the ECALL/MRET program**

Create `sw/csr_trap_tests/ecall_mret.S`:

```asm
    .section .text
    .globl main
main:
    la t0, trap_handler
    csrw mtvec, t0
    ecall

after_ecall:
    li t0, 0x00010000
    lw t1, 0(t0)
    li t2, 11
    bne t1, t2, fail
    lw t1, 8(t0)
    bnez t1, fail
    lw t1, 12(t0)
    li t2, after_ecall
    bne t1, t2, fail
    ret

trap_handler:
    li t0, 0x00010000
    csrr t1, mcause
    sw t1, 0(t0)
    csrr t1, mepc
    sw t1, 4(t0)
    csrr t2, mtval
    sw t2, 8(t0)
    addi t1, t1, 4
    sw t1, 12(t0)
    csrw mepc, t1
    mret

fail:
    call yl3_fail
```

- [ ] **Step 2: Run the failing ECALL/MRET test**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_csr_trap_programs.ps1 -Tests ecall_mret
```

Expected: FAIL because `ECALL` and `MRET` do not redirect through `mtvec/mepc`.

- [ ] **Step 3: Add system event pipeline registers**

Modify `rtl/cpu_core.v` by adding ID/EX registers:

```verilog
    reg [2:0] id_ex_sys_event;
    reg id_ex_illegal_instr;
```

Assign on decode accept:

```verilog
                id_ex_sys_event <= dec_sys_event;
                id_ex_illegal_instr <= dec_illegal_instr && if_id_valid;
                id_ex_instr <= if_id_instr;
```

Clear them on reset, flush, hazard bubble, and wait bubble.

- [ ] **Step 4: Add trap/MRET detect wires**

Add near redirect detection:

```verilog
    wire id_ex_ecall = id_ex_valid && (id_ex_sys_event == `SYS_EVT_ECALL);
    wire id_ex_ebreak = id_ex_valid && (id_ex_sys_event == `SYS_EVT_EBREAK);
    wire id_ex_mret = id_ex_valid && (id_ex_sys_event == `SYS_EVT_MRET);
    wire id_ex_illegal_csr = id_ex_valid && id_ex_csr_instr && csr_read_illegal;
    wire ex_trap_valid = id_ex_valid &&
                         (id_ex_illegal_instr || id_ex_illegal_csr ||
                          id_ex_ecall || id_ex_ebreak);
    wire ex_mret_valid = id_ex_mret && !ex_trap_valid;
    wire [31:0] ex_trap_cause =
        (id_ex_illegal_instr || id_ex_illegal_csr) ? `CAUSE_ILLEGAL_INSTRUCTION :
        id_ex_ebreak ? `CAUSE_BREAKPOINT :
        `CAUSE_ECALL_MMODE;
    wire [31:0] ex_trap_tval =
        (id_ex_illegal_instr || id_ex_illegal_csr) ? id_ex_instr :
        32'h00000000;
```

- [ ] **Step 5: Merge trap/MRET into redirect**

Use `csr_trap_pc` and `csr_mret_pc` from the CSR instance:

```verilog
    wire trap_redirect_detect = !redirect_valid && !pipe_wait && ex_trap_valid;
    wire mret_redirect_detect = !redirect_valid && !pipe_wait && ex_mret_valid;
    wire csr_redirect_detect = trap_redirect_detect || mret_redirect_detect;
    wire [31:0] csr_redirect_pc = trap_redirect_detect ? csr_trap_pc : csr_mret_pc;
```

Update redirect storage:

```verilog
            if (csr_redirect_detect) begin
                redirect_pc_q <= csr_redirect_pc;
                redirect_fallthrough_pc_q <= csr_redirect_pc;
                redirect_taken_q <= 1'b1;
            end else if (redirect_candidate_valid) begin
                redirect_pc_q <= redirect_target_pc;
                redirect_fallthrough_pc_q <= redirect_fallthrough_pc;
                redirect_taken_q <= take_branch;
            end
```

Include CSR redirect in redirect valid and flush:

```verilog
    wire redirect_detect = csr_redirect_detect || branch_mispredict_detect || jump_needs_flush_detect;
    wire trap_or_mret_flush = redirect_valid && redirect_csr_flush;
    wire flush = trap_or_mret_flush || branch_mispredict || jump_needs_flush;
```

Add `redirect_csr_flush` as a new redirect classification register.

- [ ] **Step 6: Commit trap or MRET state update**

Connect CSR instance:

```verilog
        .trap_commit_valid_i(trap_redirect_detect),
        .trap_mepc_i(id_ex_pc),
        .trap_mcause_i(ex_trap_cause),
        .trap_mtval_i(ex_trap_tval),
        .mret_commit_valid_i(mret_redirect_detect),
```

Gate `id_ex_reg_write`, `id_ex_mem_read`, `id_ex_mem_write`, `id_ex_csr_instr`,
`mul_start`, `div_launch`, `bp_update`, `ras_push`, and `ras_pop` with a local
kill signal:

```verilog
    wire side_effect_kill = flush || csr_redirect_detect;
```

Use `!side_effect_kill` wherever the current instruction would create a new
side effect.

- [ ] **Step 7: Run ECALL/MRET test to verify green**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_csr_trap_programs.ps1 -Tests ecall_mret
```

Expected: PASS external program.

- [ ] **Step 8: Commit Task 5**

Run:

```powershell
git add rtl/cpu_core.v sw/csr_trap_tests/ecall_mret.S
git commit -m "Add ECALL trap and MRET redirect"
```

## Task 6: Illegal CSR and Misaligned Store Traps

**Files:**
- Modify: `rtl/cpu_core.v`
- Create: `sw/csr_trap_tests/illegal_csr.S`
- Create: `sw/csr_trap_tests/misaligned_store.S`

- [ ] **Step 1: Add illegal CSR program**

Create `sw/csr_trap_tests/illegal_csr.S`:

```asm
    .section .text
    .globl main
main:
    la t0, trap_handler
    csrw mtvec, t0
    li s1, 0x11111111
    li s2, 0x22222222
faulting:
    csrrw s1, mvendorid, s2
after_fault:
    li t0, 0x00010000
    lw t1, 0(t0)
    li t2, 2
    bne t1, t2, fail
    lw t1, 4(t0)
    li t2, faulting
    bne t1, t2, fail
    lw t1, 8(t0)
    li t2, 0xf11290f3
    bne t1, t2, fail
    lw t1, 12(t0)
    li t2, 0x11111111
    bne t1, t2, fail
    ret

trap_handler:
    li t0, 0x00010000
    csrr t1, mcause
    sw t1, 0(t0)
    csrr t1, mepc
    sw t1, 4(t0)
    csrr t2, mtval
    sw t2, 8(t0)
    sw s1, 12(t0)
    addi t1, t1, 4
    csrw mepc, t1
    mret

fail:
    call yl3_fail
```

- [ ] **Step 2: Add misaligned store program**

Create `sw/csr_trap_tests/misaligned_store.S`:

```asm
    .section .text
    .globl main
main:
    la t0, trap_handler
    csrw mtvec, t0
    li t0, 0x00010040
    li t1, 0xa5a5a5a5
    sw t1, 0(t0)
faulting_store:
    sw zero, 2(t0)
after_fault:
    li t2, 0x00010000
    lw t3, 0(t2)
    li t4, 6
    bne t3, t4, fail
    lw t3, 4(t2)
    li t4, 0x00010042
    bne t3, t4, fail
    lw t3, 0(t0)
    li t4, 0xa5a5a5a5
    bne t3, t4, fail
    ret

trap_handler:
    li t2, 0x00010000
    csrr t3, mcause
    sw t3, 0(t2)
    csrr t3, mtval
    sw t3, 4(t2)
    csrr t3, mepc
    addi t3, t3, 4
    csrw mepc, t3
    mret

fail:
    call yl3_fail
```

- [ ] **Step 3: Run failing trap tests**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_csr_trap_programs.ps1 -Tests illegal_csr,misaligned_store
```

Expected: `illegal_csr` fails if CSR illegal trap or `rd` kill is missing. `misaligned_store` fails because the current DMEM path allows misaligned stores when `SUPPORT_MISALIGNED_DMEM=1`.

- [ ] **Step 4: Add illegal CSR trap priority**

In `rtl/cpu_core.v`, make `id_ex_illegal_csr` set `ex_trap_valid`, use cause 2, and set `ex_trap_tval=id_ex_instr`. Gate:

```verilog
    wire id_ex_faulting = ex_trap_valid || ex_mret_valid;
```

Use this to block:

```verilog
                ex_mem_reg_write <= id_ex_reg_write && !ex_trap_valid && !ex_mret_valid;
                ex_mem_mem_read <= id_ex_mem_read && !ex_trap_valid && !ex_mret_valid;
                ex_mem_mem_write <= id_ex_mem_write && !ex_trap_valid && !ex_mret_valid;
                ex_mem_csr_instr <= id_ex_csr_instr && !ex_trap_valid && !ex_mret_valid;
```

- [ ] **Step 5: Add misaligned memory detection**

Add wires:

```verilog
    wire [31:0] ex_effective_addr = alu_y;
    wire ex_load_misaligned =
        id_ex_valid && id_ex_mem_read &&
        (((id_ex_funct3 == 3'b001) && ex_effective_addr[0]) ||
         ((id_ex_funct3 == 3'b010) && |ex_effective_addr[1:0]));
    wire ex_store_misaligned =
        id_ex_valid && id_ex_mem_write &&
        (((id_ex_funct3 == 3'b001) && ex_effective_addr[0]) ||
         ((id_ex_funct3 == 3'b010) && |ex_effective_addr[1:0]));
```

Extend trap cause priority:

```verilog
    wire ex_trap_valid = id_ex_valid &&
                         (id_ex_illegal_instr || id_ex_illegal_csr ||
                          id_ex_ecall || id_ex_ebreak ||
                          ex_load_misaligned || ex_store_misaligned);
```

Set cause and `mtval`:

```verilog
    wire [31:0] ex_trap_cause =
        (id_ex_illegal_instr || id_ex_illegal_csr) ? `CAUSE_ILLEGAL_INSTRUCTION :
        id_ex_ebreak ? `CAUSE_BREAKPOINT :
        id_ex_ecall ? `CAUSE_ECALL_MMODE :
        ex_load_misaligned ? `CAUSE_LOAD_ADDR_MISALIGNED :
        `CAUSE_STORE_ADDR_MISALIGNED;

    wire [31:0] ex_trap_tval =
        (id_ex_illegal_instr || id_ex_illegal_csr) ? id_ex_instr :
        (ex_load_misaligned || ex_store_misaligned) ? ex_effective_addr :
        32'h00000000;
```

- [ ] **Step 6: Run illegal CSR and misaligned store tests to verify green**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_csr_trap_programs.ps1 -Tests illegal_csr,misaligned_store
```

Expected: PASS for both programs.

- [ ] **Step 7: Commit Task 6**

Run:

```powershell
git add rtl/cpu_core.v sw/csr_trap_tests/illegal_csr.S sw/csr_trap_tests/misaligned_store.S
git commit -m "Trap illegal CSR and misaligned stores"
```

## Task 7: Regression Integration and Final Verification

**Files:**
- Modify: `scripts/check_project.ps1`
- Modify: `scripts/run_modelsim.ps1`
- Modify: `findings.md`
- Modify: `progress.md`
- Modify: `task_plan.md`

- [ ] **Step 1: Add new source files to project structure check**

Modify `scripts/check_project.ps1` `$required` list:

```powershell
"tb/tb_csr_unit_zicsr.v",
"tb/tb_csr_unit_trap_mret.v",
"tb/tb_csr_unit_xlen64.v",
"tb/tb_decoder_system.v",
"scripts/run_csr_unit_modelsim.ps1",
"scripts/run_csr_trap_programs.ps1",
"sw/csr_trap_tests/csr_rw.S",
"sw/csr_trap_tests/ecall_mret.S",
"sw/csr_trap_tests/illegal_csr.S",
"sw/csr_trap_tests/misaligned_store.S",
```

- [ ] **Step 2: Run focused CSR regressions**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_csr_unit_modelsim.ps1
powershell -ExecutionPolicy Bypass -File scripts\run_csr_trap_programs.ps1 -Tests csr_rw,ecall_mret,illegal_csr,misaligned_store
```

Expected: all tests pass.

- [ ] **Step 3: Run project structure check**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\check_project.ps1
```

Expected: `Project structure OK`.

- [ ] **Step 4: Run full ModelSim regression**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_modelsim.ps1
```

Expected: all listed testbenches pass with no `FAIL` lines and no ModelSim errors.

- [ ] **Step 5: Run applicable RV32UI regression**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_riscv_suite.ps1 -Suite rv32ui -Tests add,addi,and,andi,auipc,beq,bge,bgeu,blt,bltu,bne,jal,jalr,lb,lbu,lh,lhu,lui,lw,or,ori,sb,sh,simple,sll,slli,slt,slti,sltiu,sltu,sra,srai,srl,srli,sub,sw,xor,xori
```

Expected: `RISCV_SUITE_FAIL=` is empty.

- [ ] **Step 6: Run RV32UM regression**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_riscv_suite.ps1 -Suite rv32um
```

Expected: `RISCV_SUITE_FAIL=` is empty.

- [ ] **Step 7: Run CoreMark smoke**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_coremark.ps1 -Iterations 2 -TotalDataSize 2000 -MaxCycles 5000000 -OptLevel -O3 -ExtraCFlags "-funroll-loops" -PerfStats
```

Expected: CoreMark completes, reports `COREMARK_CPI`, and prints no fail marker.

- [ ] **Step 8: Run optional privileged smoke and record outcome**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_riscv_suite.ps1 -Suite rv32mi -Tests csr,illegal,scall,sbreak,ma_fetch,lw-misaligned,sw-misaligned
```

Expected: pass if the existing riscv-test environment is sufficient. If this fails due to environment setup rather than RTL behavior, record the exact failing test and log path in `findings.md`; keep custom CSR trap tests as the hard first-stage gate.

- [ ] **Step 9: Update planning files**

Append to `progress.md` using the exact command results observed during this
task. If a command fails, record the command, exit behavior, and the first
failing test name instead of summarizing it as passing.

```markdown
## 2026-05-27 CSR Implementation Verification
- Focused CSR unit tests command: `powershell -ExecutionPolicy Bypass -File scripts\run_csr_unit_modelsim.ps1`
- Focused CSR unit tests result: record the observed PASS lines or the first failing test.
- CSR trap program command: `powershell -ExecutionPolicy Bypass -File scripts\run_csr_trap_programs.ps1 -Tests csr_rw,ecall_mret,illegal_csr,misaligned_store`
- CSR trap program result: record each observed `RUN_CSR_TRAP_TEST=` line and whether the external program passed.
- Full ModelSim command: `powershell -ExecutionPolicy Bypass -File scripts\run_modelsim.ps1`
- Full ModelSim result: record whether all listed testbenches passed or the first failing testbench.
- RV32UI/RV32UM result: record the observed `RISCV_SUITE_FAIL=` lines.
- CoreMark smoke result: record the observed cycle count and `COREMARK_CPI` line.
- rv32mi smoke result: record pass status, or record the first failing test and why it appears to be an environment limitation.
```

Update `task_plan.md` Phase 50 with the final accepted status and verification evidence.

- [ ] **Step 10: Commit final integration notes**

Run:

```powershell
git add scripts/check_project.ps1 scripts/run_modelsim.ps1 findings.md progress.md task_plan.md
git commit -m "Verify machine-mode CSR integration"
```

## Self-Review Checklist

- Spec coverage:
  - Zicsr semantics: Task 1 and Task 4.
  - Machine CSR bank: Task 1 and Task 2.
  - Trap entry and MRET: Task 2 and Task 5.
  - Illegal CSR and misaligned store: Task 6.
  - XLEN=64 CSR smoke: Task 2.
  - Side-effect kill gates: Task 5 and Task 6.
  - Regression and CoreMark preservation: Task 7.
- Type consistency:
  - CSR op signals use `[2:0]`.
  - CSR addresses use `[11:0]`.
  - CSR state ports use `[XLEN-1:0]` inside `csr_unit`.
  - Current CPU integration remains 32-bit and feeds `csr_unit #(.XLEN(32))`.
- Commit rhythm:
  - Each task ends with a focused commit after green verification.
