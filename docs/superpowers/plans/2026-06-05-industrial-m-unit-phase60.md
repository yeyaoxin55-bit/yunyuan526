# Phase 60 Industrial M-Unit Backend and CPU Boundary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a signoff-oriented M-unit backend flow first, then integrate the M-unit into `cpu_core` through a narrower scoreboard/writeback boundary that avoids the redirect/fallthrough critical cone.

**Architecture:** Phase60A adds selectable M-unit backends and Vivado OOC synthesis/report gates without changing CPU behavior. Phase60B replaces `cpu_core`'s fixed `mul_meta_*` tracking only after Phase60A has isolated backend evidence, using registered dependency signals and no same-cycle M response forwarding into control-flow paths.

**Tech Stack:** Verilog RTL, ModelSim, Vivado 2022.2, PowerShell regression scripts, existing CSR/riscv-test/CoreMark acceptance harnesses.

---

## File Map

Phase60A files:

- Modify `rtl/m_unit.v`: add `M_BACKEND` parameter and instantiate a backend module.
- Create `rtl/m_unit_backend_generic.v`: portable generic backend that preserves current multiply semantics.
- Create `rtl/m_unit_backend_xilinx_dsp.v`: Xilinx-oriented backend with explicit pipeline structure.
- Create `tb/tb_m_unit_backend_select.v`: verifies generic and Xilinx backend selection produce the same architectural results.
- Create `scripts/check_m_unit_backend_boundary.ps1`: structural guard for backend split and backend selection.
- Create `scripts/run_m_unit_ooc_synth.ps1`: OOC synthesis wrapper for `m_unit`.
- Create `scripts/check_m_unit_ooc_reports.ps1`: parses OOC reports for timing, DSP usage, and warning screens.
- Modify `scripts/run_modelsim.ps1`: compile new backend modules and run backend selection test.
- Modify `scripts/run_external_modelsim.ps1`: compile new backend modules for external programs.
- Modify `scripts/vivado_synth.tcl` and `scripts/vivado_impl.tcl`: include backend modules in Vivado source lists.
- Modify `scripts/check_project.ps1`: require new backend files and checks.

Phase60B files:

- Create `scripts/check_cpu_m_unit_boundary_v2.ps1`: structural RED/GREEN check for CPU integration v2.
- Modify `rtl/cpu_core.v`: remove active `mul_meta_*` M response tracking and connect `m_unit` through issue/scoreboard/writeback boundaries.
- Create focused CPU tests only if existing tests do not prove the new conservative stall behavior:
  - `tb/tb_m_unit_cpu_order_boundary.v`
  - `tb/programs/m_unit_cpu_order_boundary.hex`

Planning/status files:

- Modify `task_plan.md`
- Modify `findings.md`
- Modify `progress.md`

## Phase60A Keep Gate

Phase60A can be kept without CPU integration if these pass:

```powershell
scripts/check_m_unit_backend_boundary.ps1
scripts/check_project.ps1
scripts/run_modelsim.ps1
scripts/run_m_unit_ooc_synth.ps1 -Backend generic -Xlen 32
scripts/run_m_unit_ooc_synth.ps1 -Backend xilinx_dsp -Xlen 32
scripts/check_m_unit_ooc_reports.ps1 -ReportDir build\vivado_synth_m_unit_xilinx_dsp_xlen32_100m -RequireDsp
git diff --check
```

Expected key output:

```text
M-unit backend boundary OK
Project structure OK
PASS m_unit backend selection regression completed
Vivado synthesis completed
M-unit OOC reports OK
```

## Phase60B Keep Gate

Phase60B can be kept only if Phase60A is already clean and these pass:

```powershell
scripts/check_cpu_m_unit_boundary_v2.ps1
scripts/check_project.ps1
scripts/run_modelsim.ps1
scripts/run_riscv_suite.ps1 -Suite rv32um -FastMul 0 -MulStages 1
scripts/run_csr_phase_acceptance.ps1 -SkipVivado
scripts/run_coremark.ps1 -Iterations 2 -TotalDataSize 2000 -MaxCycles 2000000 -FastMul 0 -MulStages 1 -PerfStats
scripts/run_vivado_impl.ps1 -Top soc_top -Constraint huoyue_uart -OutDir build\vivado_impl_soc_top_phase60_m_unit_cpu_v2_extra_net_delay_100m -Jobs 4 -PlaceDirective ExtraNetDelay_high -PhysOptDirective AggressiveExplore -RouteDirective Explore -PostRoutePhysOptDirective AggressiveExplore
scripts/check_vivado_qor.ps1 -ReportDir build\vivado_impl_soc_top_phase60_m_unit_cpu_v2_extra_net_delay_100m -Top soc_top -RequireDmemBlockRam
scripts/check_vivado_timing.ps1 -ReportDir build\vivado_impl_soc_top_phase60_m_unit_cpu_v2_extra_net_delay_100m
git diff --check
```

First-screen retention rule:

- If CoreMark 2 exceeds `682500` cycles, reject the CPU integration.
- If full implementation does not beat WNS `-1.064 ns`, reject the CPU integration.
- If implementation reaches WNS `>= 0.000 ns`, keep and proceed to final acceptance.

## Task 1: Backend Structural RED Check

**Files:**
- Create: `scripts/check_m_unit_backend_boundary.ps1`
- Modify: `scripts/check_project.ps1`

- [ ] **Step 1: Create the backend boundary check**

Create `scripts/check_m_unit_backend_boundary.ps1`:

```powershell
$ErrorActionPreference = "Stop"

function Require-File($Path) {
  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Missing required file: $Path"
  }
}

function Require-Match($Path, $Pattern, $Description) {
  $text = Get-Content -Raw $Path
  if ($text -notmatch $Pattern) {
    throw "Missing $Description in $Path"
  }
}

function Reject-Match($Path, $Pattern, $Description) {
  $text = Get-Content -Raw $Path
  if ($text -match $Pattern) {
    throw "Rejected $Description in $Path"
  }
}

Require-File "rtl/m_unit.v"
Require-File "rtl/m_unit_backend_generic.v"
Require-File "rtl/m_unit_backend_xilinx_dsp.v"
Require-File "tb/tb_m_unit_backend_select.v"

Require-Match "rtl/m_unit.v" "parameter\s+M_BACKEND\s*=" "M_BACKEND parameter"
Require-Match "rtl/m_unit.v" "M_BACKEND_GENERIC" "generic backend selector"
Require-Match "rtl/m_unit.v" "M_BACKEND_XILINX_DSP" "xilinx backend selector"
Require-Match "rtl/m_unit.v" "m_unit_backend_generic" "generic backend instantiation"
Require-Match "rtl/m_unit.v" "m_unit_backend_xilinx_dsp" "xilinx backend instantiation"

Require-Match "rtl/m_unit_backend_generic.v" "module\s+m_unit_backend_generic\b" "generic backend module"
Require-Match "rtl/m_unit_backend_generic.v" '\$signed\(lhs_ext\)\s*\*\s*\$signed\(rhs_ext\)' "generic single signed product"
Require-Match "rtl/m_unit_backend_generic.v" "product_pipe\s*\[1\]\s*<=\s*product" "generic registered product stage 1"
Require-Match "rtl/m_unit_backend_generic.v" "product_pipe\s*\[2\]\s*<=\s*product_pipe\s*\[1\]" "generic registered product stage 2"

Require-Match "rtl/m_unit_backend_xilinx_dsp.v" "module\s+m_unit_backend_xilinx_dsp\b" "xilinx backend module"
Require-Match "rtl/m_unit_backend_xilinx_dsp.v" "use_dsp" "DSP synthesis attribute"
Require-Match "rtl/m_unit_backend_xilinx_dsp.v" "product_pipe" "xilinx full product pipeline"
Reject-Match "rtl/m_unit_backend_xilinx_dsp.v" "redirect|fallthrough|bp_update|csr_|trap|mret" "CPU control coupling in backend"

Write-Host "M-unit backend boundary OK"
```

- [ ] **Step 2: Run RED**

Run:

```powershell
scripts/check_m_unit_backend_boundary.ps1
```

Expected result before implementation:

```text
Missing required file: rtl/m_unit_backend_generic.v
```

- [ ] **Step 3: Hook the check into project structure**

Modify `scripts/check_project.ps1`:

```powershell
"rtl/m_unit_backend_generic.v",
"rtl/m_unit_backend_xilinx_dsp.v",
"tb/tb_m_unit_backend_select.v",
"scripts/check_m_unit_backend_boundary.ps1",
```

Near the existing industrial M-unit check invocation, add:

```powershell
& scripts/check_m_unit_backend_boundary.ps1
```

- [ ] **Step 4: Verify RED through project check**

Run:

```powershell
scripts/check_project.ps1
```

Expected result before implementation:

```text
Missing required files:
rtl/m_unit_backend_generic.v
rtl/m_unit_backend_xilinx_dsp.v
tb/tb_m_unit_backend_select.v
scripts/check_m_unit_backend_boundary.ps1
```

or the new backend check fails on missing backend files.

## Task 2: Split Generic Backend Without Behavior Change

**Files:**
- Create: `rtl/m_unit_backend_generic.v`
- Modify: `rtl/m_unit.v`
- Modify: `scripts/run_modelsim.ps1`
- Modify: `scripts/run_external_modelsim.ps1`
- Modify: `scripts/vivado_synth.tcl`
- Modify: `scripts/vivado_impl.tcl`

- [ ] **Step 1: Create generic backend module**

Create `rtl/m_unit_backend_generic.v`:

```verilog
module m_unit_backend_generic #(
    parameter XLEN = 32,
    parameter PIPE_STAGES = 4
) (
    input wire clk,
    input wire rst,
    input wire advance_i,
    input wire valid_i,
    input wire [2:0] op_i,
    input wire [XLEN-1:0] rs1_i,
    input wire [XLEN-1:0] rs2_i,
    output wire valid_o,
    output wire [XLEN-1:0] result_o
);
    localparam PIPE_DEPTH = (PIPE_STAGES < 4) ? 4 : PIPE_STAGES;

    localparam OP_MUL    = 3'b000;
    localparam OP_MULH   = 3'b001;
    localparam OP_MULHSU = 3'b010;
    localparam OP_MULHU  = 3'b011;

    reg [PIPE_DEPTH-1:0] valid_pipe;
    reg [2:0] op_pipe [0:PIPE_DEPTH-1];
    reg [XLEN-1:0] rs1_pipe [0:PIPE_DEPTH-1];
    reg [XLEN-1:0] rs2_pipe [0:PIPE_DEPTH-1];
    reg signed [(2*XLEN)+1:0] product_pipe [0:PIPE_DEPTH-1];
    reg [XLEN-1:0] result_pipe [0:PIPE_DEPTH-1];
    reg [XLEN-1:0] product_result;

    integer i;

    wire [2:0] stage_op = op_pipe[0];
    wire lhs_signed = (stage_op == OP_MULH) || (stage_op == OP_MULHSU);
    wire rhs_signed = (stage_op == OP_MULH);
    wire signed [XLEN:0] lhs_ext = lhs_signed ? {rs1_pipe[0][XLEN-1], rs1_pipe[0]} :
                                                {1'b0, rs1_pipe[0]};
    wire signed [XLEN:0] rhs_ext = rhs_signed ? {rs2_pipe[0][XLEN-1], rs2_pipe[0]} :
                                                {1'b0, rs2_pipe[0]};
    wire signed [(2*XLEN)+1:0] product = $signed(lhs_ext) * $signed(rhs_ext);

    assign valid_o = valid_pipe[PIPE_DEPTH-1];
    assign result_o = result_pipe[PIPE_DEPTH-1];

    always @(*) begin
        case (op_pipe[2])
            OP_MUL: product_result = product_pipe[2][XLEN-1:0];
            OP_MULH,
            OP_MULHSU,
            OP_MULHU: product_result = product_pipe[2][(2*XLEN)-1:XLEN];
            default: product_result = {XLEN{1'b0}};
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            valid_pipe <= {PIPE_DEPTH{1'b0}};
            for (i = 0; i < PIPE_DEPTH; i = i + 1) begin
                op_pipe[i] <= OP_MUL;
                rs1_pipe[i] <= {XLEN{1'b0}};
                rs2_pipe[i] <= {XLEN{1'b0}};
                product_pipe[i] <= {((2*XLEN)+2){1'b0}};
                result_pipe[i] <= {XLEN{1'b0}};
            end
        end else if (advance_i) begin
            valid_pipe[0] <= valid_i;
            op_pipe[0] <= op_i;
            rs1_pipe[0] <= rs1_i;
            rs2_pipe[0] <= rs2_i;
            product_pipe[0] <= {((2*XLEN)+2){1'b0}};
            result_pipe[0] <= {XLEN{1'b0}};

            valid_pipe[1] <= valid_pipe[0];
            op_pipe[1] <= op_pipe[0];
            rs1_pipe[1] <= {XLEN{1'b0}};
            rs2_pipe[1] <= {XLEN{1'b0}};
            product_pipe[1] <= product;
            result_pipe[1] <= {XLEN{1'b0}};

            valid_pipe[2] <= valid_pipe[1];
            op_pipe[2] <= op_pipe[1];
            rs1_pipe[2] <= {XLEN{1'b0}};
            rs2_pipe[2] <= {XLEN{1'b0}};
            product_pipe[2] <= product_pipe[1];
            result_pipe[2] <= {XLEN{1'b0}};

            valid_pipe[3] <= valid_pipe[2];
            op_pipe[3] <= op_pipe[2];
            rs1_pipe[3] <= {XLEN{1'b0}};
            rs2_pipe[3] <= {XLEN{1'b0}};
            product_pipe[3] <= product_pipe[2];
            result_pipe[3] <= product_result;

            for (i = 4; i < PIPE_DEPTH; i = i + 1) begin
                valid_pipe[i] <= valid_pipe[i-1];
                op_pipe[i] <= op_pipe[i-1];
                rs1_pipe[i] <= {XLEN{1'b0}};
                rs2_pipe[i] <= {XLEN{1'b0}};
                product_pipe[i] <= product_pipe[i-1];
                result_pipe[i] <= result_pipe[i-1];
            end
        end
    end
endmodule
```

- [ ] **Step 2: Modify `m_unit` to instantiate the generic backend**

Modify `rtl/m_unit.v` parameters:

```verilog
parameter XLEN = 32,
parameter MUL_PIPE_STAGES = 3,
parameter EPOCH_WIDTH = 2,
parameter M_BACKEND = 0
```

Add localparams:

```verilog
localparam M_BACKEND_GENERIC = 0;
localparam M_BACKEND_XILINX_DSP = 1;
```

Replace the internal product/result pipeline with backend wires:

```verilog
wire backend_valid;
wire [XLEN-1:0] backend_result;
```

Instantiate the backend:

```verilog
generate
    if (M_BACKEND == M_BACKEND_XILINX_DSP) begin : gen_xilinx_backend
        m_unit_backend_xilinx_dsp #(
            .XLEN(XLEN),
            .PIPE_STAGES(PIPE_DEPTH)
        ) u_backend (
            .clk(clk),
            .rst(rst),
            .advance_i(advance_pipe),
            .valid_i(req_valid_i),
            .op_i(req_op_i),
            .rs1_i(req_rs1_i),
            .rs2_i(req_rs2_i),
            .valid_o(backend_valid),
            .result_o(backend_result)
        );
    end else begin : gen_generic_backend
        m_unit_backend_generic #(
            .XLEN(XLEN),
            .PIPE_STAGES(PIPE_DEPTH)
        ) u_backend (
            .clk(clk),
            .rst(rst),
            .advance_i(advance_pipe),
            .valid_i(req_valid_i),
            .op_i(req_op_i),
            .rs1_i(req_rs1_i),
            .rs2_i(req_rs2_i),
            .valid_o(backend_valid),
            .result_o(backend_result)
        );
    end
endgenerate
```

Keep metadata pipes in `m_unit` aligned to `PIPE_DEPTH`. The final outputs should use:

```verilog
wire final_valid = valid_pipe[PIPE_DEPTH-1] && backend_valid;
assign resp_result_o = backend_result;
```

- [ ] **Step 3: Add backend module to source lists**

Add these RTL files before `rtl/m_unit.v` in:

- `scripts/run_modelsim.ps1`
- `scripts/run_external_modelsim.ps1`
- `scripts/vivado_synth.tcl`
- `scripts/vivado_impl.tcl`

```powershell
"rtl/m_unit_backend_generic.v",
"rtl/m_unit_backend_xilinx_dsp.v",
```

For Tcl source lists:

```tcl
[file join $repo_root "rtl" "m_unit_backend_generic.v"] \
[file join $repo_root "rtl" "m_unit_backend_xilinx_dsp.v"] \
```

- [ ] **Step 4: Run focused GREEN**

Run:

```powershell
scripts/check_industrial_m_unit_boundary.ps1
scripts/check_m_unit_backend_boundary.ps1
```

Expected:

```text
Industrial M-unit boundary OK
M-unit backend boundary OK
```

Then run focused ModelSim for M-unit tests, or full:

```powershell
scripts/run_modelsim.ps1
```

Expected for focused tests:

```text
PASS m_unit multiplier directed regression completed
PASS m_unit pipeline regression completed
Errors: 0, Warnings: 0
```

## Task 3: Xilinx DSP Backend

**Files:**
- Create: `rtl/m_unit_backend_xilinx_dsp.v`
- Modify: `tb/tb_m_unit_backend_select.v`

- [ ] **Step 1: Create Xilinx DSP backend**

Create `rtl/m_unit_backend_xilinx_dsp.v` with the same external behavior as the generic backend and explicit DSP-oriented attributes:

```verilog
module m_unit_backend_xilinx_dsp #(
    parameter XLEN = 32,
    parameter PIPE_STAGES = 4
) (
    input wire clk,
    input wire rst,
    input wire advance_i,
    input wire valid_i,
    input wire [2:0] op_i,
    input wire [XLEN-1:0] rs1_i,
    input wire [XLEN-1:0] rs2_i,
    output wire valid_o,
    output wire [XLEN-1:0] result_o
);
    localparam PIPE_DEPTH = (PIPE_STAGES < 4) ? 4 : PIPE_STAGES;

    localparam OP_MUL    = 3'b000;
    localparam OP_MULH   = 3'b001;
    localparam OP_MULHSU = 3'b010;
    localparam OP_MULHU  = 3'b011;

    reg [PIPE_DEPTH-1:0] valid_pipe;
    reg [2:0] op_pipe [0:PIPE_DEPTH-1];
    reg [XLEN-1:0] rs1_pipe [0:PIPE_DEPTH-1];
    reg [XLEN-1:0] rs2_pipe [0:PIPE_DEPTH-1];
    (* use_dsp = "yes" *) reg signed [(2*XLEN)+1:0] product_pipe [0:PIPE_DEPTH-1];
    (* use_dsp = "yes" *) wire signed [(2*XLEN)+1:0] product;
    reg [XLEN-1:0] result_pipe [0:PIPE_DEPTH-1];
    reg [XLEN-1:0] product_result;

    integer i;

    wire lhs_signed = (op_pipe[0] == OP_MULH) || (op_pipe[0] == OP_MULHSU);
    wire rhs_signed = (op_pipe[0] == OP_MULH);
    wire signed [XLEN:0] lhs_ext = lhs_signed ? {rs1_pipe[0][XLEN-1], rs1_pipe[0]} :
                                                {1'b0, rs1_pipe[0]};
    wire signed [XLEN:0] rhs_ext = rhs_signed ? {rs2_pipe[0][XLEN-1], rs2_pipe[0]} :
                                                {1'b0, rs2_pipe[0]};

    assign product = $signed(lhs_ext) * $signed(rhs_ext);
    assign valid_o = valid_pipe[PIPE_DEPTH-1];
    assign result_o = result_pipe[PIPE_DEPTH-1];

    always @(*) begin
        case (op_pipe[2])
            OP_MUL: product_result = product_pipe[2][XLEN-1:0];
            OP_MULH,
            OP_MULHSU,
            OP_MULHU: product_result = product_pipe[2][(2*XLEN)-1:XLEN];
            default: product_result = {XLEN{1'b0}};
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            valid_pipe <= {PIPE_DEPTH{1'b0}};
            for (i = 0; i < PIPE_DEPTH; i = i + 1) begin
                op_pipe[i] <= OP_MUL;
                rs1_pipe[i] <= {XLEN{1'b0}};
                rs2_pipe[i] <= {XLEN{1'b0}};
                product_pipe[i] <= {((2*XLEN)+2){1'b0}};
                result_pipe[i] <= {XLEN{1'b0}};
            end
        end else if (advance_i) begin
            valid_pipe[0] <= valid_i;
            op_pipe[0] <= op_i;
            rs1_pipe[0] <= rs1_i;
            rs2_pipe[0] <= rs2_i;
            product_pipe[0] <= {((2*XLEN)+2){1'b0}};
            result_pipe[0] <= {XLEN{1'b0}};

            valid_pipe[1] <= valid_pipe[0];
            op_pipe[1] <= op_pipe[0];
            rs1_pipe[1] <= {XLEN{1'b0}};
            rs2_pipe[1] <= {XLEN{1'b0}};
            product_pipe[1] <= product;
            result_pipe[1] <= {XLEN{1'b0}};

            valid_pipe[2] <= valid_pipe[1];
            op_pipe[2] <= op_pipe[1];
            rs1_pipe[2] <= {XLEN{1'b0}};
            rs2_pipe[2] <= {XLEN{1'b0}};
            product_pipe[2] <= product_pipe[1];
            result_pipe[2] <= {XLEN{1'b0}};

            valid_pipe[3] <= valid_pipe[2];
            op_pipe[3] <= op_pipe[2];
            rs1_pipe[3] <= {XLEN{1'b0}};
            rs2_pipe[3] <= {XLEN{1'b0}};
            product_pipe[3] <= product_pipe[2];
            result_pipe[3] <= product_result;

            for (i = 4; i < PIPE_DEPTH; i = i + 1) begin
                valid_pipe[i] <= valid_pipe[i-1];
                op_pipe[i] <= op_pipe[i-1];
                rs1_pipe[i] <= {XLEN{1'b0}};
                rs2_pipe[i] <= {XLEN{1'b0}};
                product_pipe[i] <= product_pipe[i-1];
                result_pipe[i] <= result_pipe[i-1];
            end
        end
    end
endmodule
```

- [ ] **Step 2: Add backend selection test**

Create `tb/tb_m_unit_backend_select.v` that instantiates two RV32 M-units. Use the same signal names for both instances so the test can issue identical transactions to both backends:

```verilog
m_unit #(
    .XLEN(32),
    .MUL_PIPE_STAGES(4),
    .EPOCH_WIDTH(2),
    .M_BACKEND(0)
) dut_generic (
    .clk(clk),
    .rst(rst),
    .req_valid_i(req_valid),
    .req_ready_o(req_ready_generic),
    .req_op_i(req_op),
    .req_rs1_i(req_rs1),
    .req_rs2_i(req_rs2),
    .req_rd_i(req_rd),
    .req_reg_write_i(req_reg_write),
    .req_epoch_i(req_epoch),
    .current_epoch_i(current_epoch),
    .resp_valid_o(resp_valid_generic),
    .resp_ready_i(resp_ready),
    .resp_rd_o(resp_rd_generic),
    .resp_result_o(resp_result_generic),
    .resp_reg_write_o(resp_reg_write_generic),
    .resp_epoch_o(resp_epoch_generic)
);

m_unit #(
    .XLEN(32),
    .MUL_PIPE_STAGES(4),
    .EPOCH_WIDTH(2),
    .M_BACKEND(1)
) dut_xilinx (
    .clk(clk),
    .rst(rst),
    .req_valid_i(req_valid),
    .req_ready_o(req_ready_xilinx),
    .req_op_i(req_op),
    .req_rs1_i(req_rs1),
    .req_rs2_i(req_rs2),
    .req_rd_i(req_rd),
    .req_reg_write_i(req_reg_write),
    .req_epoch_i(req_epoch),
    .current_epoch_i(current_epoch),
    .resp_valid_o(resp_valid_xilinx),
    .resp_ready_i(resp_ready),
    .resp_rd_o(resp_rd_xilinx),
    .resp_result_o(resp_result_xilinx),
    .resp_reg_write_o(resp_reg_write_xilinx),
    .resp_epoch_o(resp_epoch_xilinx)
);
```

Use the same issue/expect helper shape as `tb/tb_m_unit_multiplier.v`, and check these cases on both instances:

```verilog
MUL    32'hffff_ffff, 32'h0000_0002 -> 32'hffff_fffe
MULH   32'hffff_ffff, 32'h0000_0002 -> 32'hffff_ffff
MULHSU 32'hffff_ffff, 32'h0000_0002 -> 32'hffff_ffff
MULHU  32'hffff_ffff, 32'h0000_0002 -> 32'h0000_0001
MUL    32'h0001_0001, 32'h0000_0003 -> 32'h0003_0003
```

The test must finish with:

```verilog
$display("PASS m_unit backend selection regression completed");
$finish;
```

- [ ] **Step 3: Add the test to `scripts/run_modelsim.ps1`**

Add to `$sources`:

```powershell
"tb/tb_m_unit_backend_select.v",
```

Add to `$tests` after the existing M-unit tests:

```powershell
"tb_m_unit_backend_select",
```

- [ ] **Step 4: Run GREEN**

Run:

```powershell
scripts/run_modelsim.ps1
```

Expected:

```text
PASS m_unit multiplier directed regression completed
PASS m_unit pipeline regression completed
PASS m_unit backend selection regression completed
Errors: 0, Warnings: 0
```

## Task 4: M-Unit OOC Synthesis Flow

**Files:**
- Create: `scripts/run_m_unit_ooc_synth.ps1`
- Create: `scripts/check_m_unit_ooc_reports.ps1`
- Modify: `scripts/check_project.ps1`

- [ ] **Step 1: Create OOC synthesis wrapper**

Create `scripts/run_m_unit_ooc_synth.ps1`:

```powershell
param(
  [ValidateSet("generic", "xilinx_dsp")]
  [string]$Backend = "generic",
  [ValidateSet(32, 64)]
  [int]$Xlen = 32,
  [string]$VivadoPath = "",
  [int]$Jobs = 4
)

$ErrorActionPreference = "Stop"

$backendValue = if ($Backend -eq "xilinx_dsp") { 1 } else { 0 }
$outDir = "build/vivado_synth_m_unit_${Backend}_xlen${Xlen}_100m"

& scripts/run_vivado_synth.ps1 `
  -VivadoPath $VivadoPath `
  -Top m_unit `
  -Constraint 100m `
  -OutDir $outDir `
  -Jobs $Jobs `
  -Generic @("XLEN=$Xlen", "M_BACKEND=$backendValue", "MUL_PIPE_STAGES=4", "EPOCH_WIDTH=2")

if ($LASTEXITCODE -ne 0) {
  throw "M-unit OOC synthesis failed"
}

Write-Host "M_UNIT_OOC_BACKEND=$Backend"
Write-Host "M_UNIT_OOC_XLEN=$Xlen"
Write-Host "M_UNIT_OOC_REPORT_DIR=$outDir"
```

- [ ] **Step 2: Create OOC report checker**

Create `scripts/check_m_unit_ooc_reports.ps1`:

```powershell
param(
  [Parameter(Mandatory=$true)]
  [string]$ReportDir,
  [switch]$RequireDsp,
  [double]$MinWns = 0.0
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $ReportDir)) {
  throw "Missing report directory: $ReportDir"
}

$timing = Join-Path $ReportDir "timing_summary_synth.rpt"
$util = Join-Path $ReportDir "utilization_synth.rpt"
$dsp = Join-Path $ReportDir "dsp_utilization_synth.rpt"

foreach ($path in @($timing, $util)) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Missing report: $path"
  }
}

$timingText = Get-Content -Raw $timing
$utilText = Get-Content -Raw $util
$dspText = if (Test-Path -LiteralPath $dsp) { Get-Content -Raw $dsp } else { "" }
$allText = $timingText + "`n" + $utilText + "`n" + $dspText

if ($allText -match "DRC.*MREG|DRC.*PREG|not pipelined|unpipeline|un-pipeline") {
  throw "Rejected OOC report: found DSP pipeline warning text"
}

$wnsMatch = [regex]::Match($timingText, "WNS\(ns\)\s+([-+]?[0-9]*\.?[0-9]+)")
if (-not $wnsMatch.Success) {
  $wnsMatch = [regex]::Match($timingText, "WNS\(ns\).*?`r?`n\s*([-+]?[0-9]*\.?[0-9]+)", [System.Text.RegularExpressions.RegexOptions]::Singleline)
}
if (-not $wnsMatch.Success) {
  throw "Could not parse WNS from $timing"
}
$wns = [double]$wnsMatch.Groups[1].Value
if ($wns -lt $MinWns) {
  throw "OOC WNS below threshold: $wns < $MinWns"
}

if ($RequireDsp) {
  $hasDsp = ($utilText -match "DSPs\s*\|\s*[1-9]") -or
            ($utilText -match "DSP48E1\s*\|\s*[1-9]") -or
            ($dspText -match "DSP48E1\s*\|\s*[1-9]")
  if (-not $hasDsp) {
    throw "Required DSP usage was not found in OOC reports"
  }
}

Write-Host "M-unit OOC reports OK"
Write-Host "M_UNIT_OOC_WNS_NS=$wns"
```

- [ ] **Step 3: Hook files into `check_project`**

Add required files:

```powershell
"scripts/run_m_unit_ooc_synth.ps1",
"scripts/check_m_unit_ooc_reports.ps1",
```

- [ ] **Step 4: Run OOC generic backend**

Run:

```powershell
scripts/run_m_unit_ooc_synth.ps1 -Backend generic -Xlen 32
```

Expected:

```text
Vivado synthesis completed
M_UNIT_OOC_BACKEND=generic
M_UNIT_OOC_XLEN=32
```

- [ ] **Step 5: Run OOC Xilinx backend**

Run:

```powershell
scripts/run_m_unit_ooc_synth.ps1 -Backend xilinx_dsp -Xlen 32
```

Expected:

```text
Vivado synthesis completed
M_UNIT_OOC_BACKEND=xilinx_dsp
M_UNIT_OOC_XLEN=32
```

- [ ] **Step 6: Check OOC reports**

Run:

```powershell
scripts/check_m_unit_ooc_reports.ps1 -ReportDir build\vivado_synth_m_unit_xilinx_dsp_xlen32_100m -RequireDsp
```

Expected:

```text
M-unit OOC reports OK
M_UNIT_OOC_WNS_NS=<non-negative value>
```

If this fails due DSP pipeline warnings or WNS below `0.000`, do not start Phase60B.

## Task 5: Phase60A Commit

**Files:**
- Modified/created Phase60A files only.

- [ ] **Step 1: Run Phase60A full verification**

Run:

```powershell
scripts/check_m_unit_backend_boundary.ps1
scripts/check_industrial_m_unit_boundary.ps1
scripts/check_project.ps1
scripts/run_modelsim.ps1
scripts/run_m_unit_ooc_synth.ps1 -Backend generic -Xlen 32
scripts/run_m_unit_ooc_synth.ps1 -Backend xilinx_dsp -Xlen 32
scripts/check_m_unit_ooc_reports.ps1 -ReportDir build\vivado_synth_m_unit_xilinx_dsp_xlen32_100m -RequireDsp
git diff --check
```

Expected: all pass.

- [ ] **Step 2: Update planning files**

Append to `progress.md`:

```markdown
## 2026-06-05 CSR Branch Session - Phase60A M-unit backend OOC
- Added selectable M-unit backends and kept CPU behavior unchanged.
- Verified ModelSim M-unit and full regression.
- Ran OOC synthesis for generic and Xilinx DSP backends.
- OOC report check passed for Xilinx backend with DSP usage and no known pipeline warning text.
```

Append to `findings.md`:

```markdown
## 2026-06-05 Phase60A Findings
- The M-unit backend can now be measured independently from `cpu_core`.
- Phase60B is allowed only after OOC backend evidence exists.
```

Append to `task_plan.md` under a new Phase 60 section with the actual OOC WNS and DSP usage.

- [ ] **Step 3: Commit Phase60A**

Run:

```powershell
git add rtl/m_unit.v rtl/m_unit_backend_generic.v rtl/m_unit_backend_xilinx_dsp.v tb/tb_m_unit_backend_select.v scripts/check_m_unit_backend_boundary.ps1 scripts/run_m_unit_ooc_synth.ps1 scripts/check_m_unit_ooc_reports.ps1 scripts/check_project.ps1 scripts/run_modelsim.ps1 scripts/run_external_modelsim.ps1 scripts/vivado_synth.tcl scripts/vivado_impl.tcl task_plan.md findings.md progress.md
git commit -m "Add M-unit backend OOC synthesis gate"
```

## Task 6: CPU Boundary v2 RED Check

**Files:**
- Create: `scripts/check_cpu_m_unit_boundary_v2.ps1`
- Modify: `scripts/check_project.ps1`

- [ ] **Step 1: Create CPU boundary v2 check**

Create `scripts/check_cpu_m_unit_boundary_v2.ps1`:

```powershell
$ErrorActionPreference = "Stop"

$path = "rtl/cpu_core.v"
if (-not (Test-Path -LiteralPath $path)) {
  throw "Missing $path"
}

$text = Get-Content -Raw $path

foreach ($pattern in @(
  "mul_meta_valid_pipe",
  "mul_meta_rd_pipe",
  "mul_meta_reg_write_pipe"
)) {
  if ($text -match $pattern) {
    throw "Rejected active fixed-latency M metadata tracking: $pattern"
  }
}

foreach ($pattern in @(
  "m_unit\s*#",
  "m_epoch_q",
  "m_scoreboard",
  "m_resp_pending_q",
  "m_issue_valid",
  "m_resp_ready"
)) {
  if ($text -notmatch $pattern) {
    throw "Missing CPU M-unit boundary signal or instance: $pattern"
  }
}

foreach ($pattern in @(
  "branch_target.*m_resp",
  "jalr_target.*m_resp",
  "redirect_pc.*m_resp",
  "redirect_fallthrough.*m_resp",
  "bp_update_target.*m_resp",
  "bp_update_pc.*m_resp"
)) {
  if ($text -match $pattern) {
    throw "Rejected M response same-cycle forwarding into control path: $pattern"
  }
}

Write-Host "CPU M-unit boundary v2 OK"
```

- [ ] **Step 2: Run RED**

Run:

```powershell
scripts/check_cpu_m_unit_boundary_v2.ps1
```

Expected before CPU integration:

```text
Rejected active fixed-latency M metadata tracking: mul_meta_valid_pipe
```

- [ ] **Step 3: Hook check into project after CPU integration**

Do not add this check to `scripts/check_project.ps1` until the CPU integration branch starts. Once Phase60B implementation begins, add:

```powershell
"scripts/check_cpu_m_unit_boundary_v2.ps1",
```

and invoke:

```powershell
& scripts/check_cpu_m_unit_boundary_v2.ps1
```

## Task 7: CPU Integration v2

**Files:**
- Modify: `rtl/cpu_core.v`
- Test: existing `tb/tb_mul_result_forward_early.v`, `tb/tb_mul_pipeline_back_to_back.v`, `tb/tb_load_mul_forward_boundary.v`, `rv32um`

- [ ] **Step 1: Remove fixed M metadata state**

In `rtl/cpu_core.v`, remove active use of:

```verilog
mul_meta_valid_pipe
mul_meta_rd_pipe
mul_meta_reg_write_pipe
MUL_META_DEPTH
```

Keep `MUL_STAGES` as a compatibility parameter only if existing top-level generics still require it.

- [ ] **Step 2: Add M-unit instance and epoch**

Add CPU-local epoch state:

```verilog
reg [1:0] m_epoch_q;
wire older_flush_for_m = redirect_valid || csr_redirect_detect || redirect_jump_flush;
```

On reset:

```verilog
m_epoch_q <= 2'b00;
```

On older flush:

```verilog
if (older_flush_for_m) begin
    m_epoch_q <= m_epoch_q + 2'b01;
end
```

Instantiate:

```verilog
m_unit #(
    .XLEN(32),
    .MUL_PIPE_STAGES(4),
    .EPOCH_WIDTH(2),
    .M_BACKEND(1)
) u_m_unit (
    .clk(clk),
    .rst(rst),
    .req_valid_i(m_issue_valid),
    .req_ready_o(m_issue_ready),
    .req_op_i(id_ex_funct3),
    .req_rs1_i(m_issue_rs1),
    .req_rs2_i(m_issue_rs2),
    .req_rd_i(id_ex_rd),
    .req_reg_write_i(id_ex_reg_write),
    .req_epoch_i(m_epoch_q),
    .current_epoch_i(m_epoch_q),
    .resp_valid_o(m_resp_valid),
    .resp_ready_i(m_resp_ready),
    .resp_rd_o(m_resp_rd),
    .resp_result_o(m_resp_result),
    .resp_reg_write_o(m_resp_reg_write),
    .resp_epoch_o(m_resp_epoch)
);
```

- [ ] **Step 3: Add conservative scoreboard**

Add small outstanding state:

```verilog
localparam M_SCOREBOARD_DEPTH = 4;
reg [M_SCOREBOARD_DEPTH-1:0] m_scoreboard_valid;
reg [4:0] m_scoreboard_rd [0:M_SCOREBOARD_DEPTH-1];
reg [1:0] m_scoreboard_epoch [0:M_SCOREBOARD_DEPTH-1];
reg m_scoreboard_reg_write [0:M_SCOREBOARD_DEPTH-1];
```

Decode hazard outputs must be registered or otherwise isolated:

```verilog
reg if_id_rs1_m_pending_dep_q;
reg if_id_rs2_m_pending_dep_q;
reg if_id_m_waw_dep_q;
```

Use these registered dependency bits in hazard inputs instead of full response data forwarding.

- [ ] **Step 4: Block same-cycle M response control forwarding**

Remove M response paths from control-flow operand selection. If an operand is pending from M, stall until normal regfile/writeback visibility.

The first candidate must not introduce expressions matching:

```verilog
branch_target.*m_resp
jalr_target.*m_resp
redirect_pc.*m_resp
bp_update_target.*m_resp
```

- [ ] **Step 5: Wire M response into shared writeback2**

Set response ready only when writeback2 can accept the M response:

```verilog
wire m_resp_can_wb = m_resp_valid && !load_wb_write_en;
assign m_resp_ready = m_resp_can_wb;
```

Use existing shared writeback priority:

```verilog
wire shared_wb2_is_load = load_wb_write_en;
wire shared_wb2_we = load_wb_write_en || (m_resp_can_wb && m_resp_reg_write);
wire [4:0] shared_wb2_rd = shared_wb2_is_load ? load_resp_rd : m_resp_rd;
wire [31:0] shared_wb2_data = shared_wb2_is_load ? load_resp_data : m_resp_result;
```

- [ ] **Step 6: Clear scoreboard on accepted writeback or stale discard**

When `m_resp_valid && m_resp_ready`, clear the matching scoreboard entry for `m_resp_rd` and `m_resp_epoch`.

When a scoreboard entry epoch becomes stale due older flush, clear it only if doing so cannot unblock a wrong-path instruction. The conservative first implementation may clear all entries on epoch increment because younger in-flight instructions are also killed by the same older flush.

- [ ] **Step 7: Run CPU structural GREEN**

Run:

```powershell
scripts/check_cpu_m_unit_boundary_v2.ps1
```

Expected:

```text
CPU M-unit boundary v2 OK
```

## Task 8: CPU Functional and Performance Verification

**Files:**
- Modify only test expectations if the conservative no-forward policy intentionally changes cycle counts.

- [ ] **Step 1: Run focused ModelSim**

Run:

```powershell
scripts/run_modelsim.ps1
```

Expected:

```text
PASS m_unit multiplier directed regression completed
PASS m_unit pipeline regression completed
Errors: 0, Warnings: 0
```

If `tb_mul_result_forward_early` fails only because the conservative policy adds a stall, inspect whether the old assertion requires same-cycle M response control/data forwarding. Update the test name or expected count only if the architecture intentionally forbids that same-cycle path.

- [ ] **Step 2: Run rv32um**

Run:

```powershell
scripts/run_riscv_suite.ps1 -Suite rv32um -FastMul 0 -MulStages 1
```

Expected:

```text
RISCV_SUITE_PASS=1
```

- [ ] **Step 3: Run CSR acceptance**

Run:

```powershell
scripts/run_csr_phase_acceptance.ps1 -SkipVivado
```

Expected:

```text
CSR_PHASE_ACCEPTANCE_PASS=1
```

- [ ] **Step 4: Run CoreMark screen**

Run:

```powershell
scripts/run_coremark.ps1 -Iterations 2 -TotalDataSize 2000 -MaxCycles 2000000 -FastMul 0 -MulStages 1 -PerfStats
```

Expected:

```text
COREMARK_RESULT_CYCLES=<value <= 682500>
```

If cycles exceed `682500`, reject Phase60B CPU integration.

## Task 9: CPU Physical Screen

**Files:**
- No RTL edits during this task unless the candidate is rejected and a new task is opened.

- [ ] **Step 1: Run full Huoyue implementation**

Run:

```powershell
scripts/run_vivado_impl.ps1 -Top soc_top -Constraint huoyue_uart -OutDir build\vivado_impl_soc_top_phase60_m_unit_cpu_v2_extra_net_delay_100m -Jobs 4 -PlaceDirective ExtraNetDelay_high -PhysOptDirective AggressiveExplore -RouteDirective Explore -PostRoutePhysOptDirective AggressiveExplore
```

Expected command completion is not enough. Continue to QoR/timing checks.

- [ ] **Step 2: Check QoR**

Run:

```powershell
scripts/check_vivado_qor.ps1 -ReportDir build\vivado_impl_soc_top_phase60_m_unit_cpu_v2_extra_net_delay_100m -Top soc_top -RequireDmemBlockRam
```

Expected:

```text
QoR OK: TOP=soc_top RAMD64E=0 BlockRAM=24
```

- [ ] **Step 3: Check timing**

Run:

```powershell
scripts/check_vivado_timing.ps1 -ReportDir build\vivado_impl_soc_top_phase60_m_unit_cpu_v2_extra_net_delay_100m
```

Expected final goal:

```text
Timing OK
```

Retention screen:

- If WNS is worse than `-1.064 ns`, reject and revert Phase60B.
- If WNS is better than `-1.064 ns` but still negative, record the result and decide whether a narrowly targeted physical route/physopt follow-up is justified.
- If WNS is non-negative, keep Phase60B and run final acceptance.

- [ ] **Step 4: Extract worst path if timing fails**

If timing fails, extract:

```powershell
Select-String -Path build\vivado_impl_soc_top_phase60_m_unit_cpu_v2_extra_net_delay_100m\timing_summary_post_route*.rpt -Pattern "WNS\(ns\)|TNS\(ns\)|Failing Endpoints|Slack \(VIOLATED\)|Source:|Destination:|Data Path Delay:|Logic Levels:" -Context 0,1 | Select-Object -First 80
```

Record source, destination, WNS, route percentage, and logic levels in `findings.md`.

## Task 10: Phase60B Decision Commit or Revert

**Files:**
- `rtl/cpu_core.v`
- new/modified tests
- scripts/checks
- planning files

- [ ] **Step 1: If accepted, commit**

Run:

```powershell
git add rtl/cpu_core.v scripts/check_cpu_m_unit_boundary_v2.ps1 scripts/check_project.ps1 task_plan.md findings.md progress.md
git commit -m "Integrate M-unit through isolated CPU boundary"
```

- [ ] **Step 2: If rejected, revert only Phase60B RTL/check hooks**

Do not revert Phase60A. Revert only CPU integration files and hooks:

```powershell
git restore rtl/cpu_core.v
```

If `scripts/check_cpu_m_unit_boundary_v2.ps1` was added only for the rejected candidate, remove it from the worktree after verifying it is not committed:

```powershell
Remove-Item -LiteralPath scripts\check_cpu_m_unit_boundary_v2.ps1
```

Remove its `check_project` hook manually with `apply_patch`, then run:

```powershell
scripts/check_project.ps1
scripts/run_csr_phase_acceptance.ps1 -SkipVivado
git diff --check
```

Append a rejection record to `progress.md` and `findings.md` with the exact WNS and worst path.

## Final Notes

Do not start Phase60B until Phase60A has OOC evidence. Do not keep any candidate that only moves the failing timing path to another redirect/fallthrough endpoint. The purpose of Phase60 is to separate arithmetic backend signoff from CPU control signoff, then rejoin them through a narrower and measurable boundary.
