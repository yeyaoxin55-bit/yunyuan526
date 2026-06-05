# Phase61 Prefetch Valid-Only Flush Boundary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cut the redirect/frontend timing cone by making `prefetch` flush clear only valid bits while leaving payload registers untouched.

**Architecture:** `cpu_core` still owns redirect, flush, side-effect kill, and PC selection. `prefetch` becomes a valid-tagged payload buffer: reset initializes payloads, normal fetch/stall paths update payloads, and flush invalidates entries without driving payload reset/CE paths.

**Tech Stack:** Verilog RTL, ModelSim, Vivado 2022.2, PowerShell structural checks, existing CSR/CoreMark/Vivado acceptance scripts.

---

## File Map

- Modify `rtl/prefetch.v`: update the `flush_i` branch so it only clears `current_valid` and `skid_valid`.
- Modify `tb/tb_prefetch.v`: add RED/GREEN coverage for current-entry flush, skid-entry flush, and fetch-after-flush recovery.
- Create `scripts/check_prefetch_valid_flush_boundary.ps1`: reject payload assignments in the flush branch.
- Modify `scripts/check_project.ps1`: require and run the new structural check.
- Modify `task_plan.md`: record Phase61 strategy, gate, and final decision.
- Modify `findings.md`: record timing/function findings.
- Modify `progress.md`: log commands and outcomes.

## Keep Gate

Run these before retaining any RTL:

```powershell
scripts/check_prefetch_valid_flush_boundary.ps1
scripts/check_project.ps1
git diff --check
scripts/run_modelsim.ps1
scripts/run_csr_phase_acceptance.ps1 -SkipVivado
scripts/run_vivado_impl.ps1 -Top soc_top -Constraint huoyue_uart -OutDir build\vivado_impl_soc_top_phase61_prefetch_valid_flush_extra_net_delay_100m -Jobs 4 -PlaceDirective ExtraNetDelay_high -PhysOptDirective AggressiveExplore -RouteDirective Explore -PostRoutePhysOptDirective AggressiveExplore
scripts/check_vivado_qor.ps1 -ReportDir build\vivado_impl_soc_top_phase61_prefetch_valid_flush_extra_net_delay_100m -Top soc_top -RequireDmemBlockRam
scripts/check_vivado_timing.ps1 -ReportDir build\vivado_impl_soc_top_phase61_prefetch_valid_flush_extra_net_delay_100m
```

Retention rule:

- Reject if CSR acceptance fails.
- Reject if CoreMark 2 exceeds `682500` cycles.
- Reject if full implementation WNS is worse than `-1.064 ns`.
- Keep as new timing baseline only if it beats `-1.064 ns`.
- Promote as timing-clean baseline if WNS is non-negative.

## Task 1: Structural RED Check

**Files:**

- Create: `scripts/check_prefetch_valid_flush_boundary.ps1`
- Modify: `scripts/check_project.ps1`

- [ ] **Step 1: Create the structural check**

Create `scripts/check_prefetch_valid_flush_boundary.ps1`:

```powershell
$ErrorActionPreference = "Stop"

$path = "rtl/prefetch.v"
if (-not (Test-Path -LiteralPath $path)) {
  throw "Missing required file: $path"
}

$text = Get-Content -Raw $path
if ($text -notmatch "module\s+prefetch\b") {
  throw "Missing prefetch module"
}

$flushMatch = [regex]::Match(
  $text,
  "end\s+else\s+if\s*\(\s*flush_i\s*\)\s+begin(?<body>.*?)end\s+else\s+if\s*\(\s*stall_i\s*\)",
  [System.Text.RegularExpressions.RegexOptions]::Singleline
)
if (-not $flushMatch.Success) {
  throw "Could not locate standalone flush_i branch before stall_i branch"
}

$body = $flushMatch.Groups["body"].Value
$required = @("current_valid", "skid_valid")
foreach ($name in $required) {
  if ($body -notmatch ("\b" + $name + "\s*<=\s*1'b0\s*;")) {
    throw "Flush branch must clear $name"
  }
}

$payloads = @(
  "current_pc",
  "current_instr",
  "current_pred_taken",
  "current_pred_target",
  "skid_pc",
  "skid_instr",
  "skid_pred_taken",
  "skid_pred_target"
)
foreach ($name in $payloads) {
  if ($body -match ("\b" + $name + "\s*<=")) {
    throw "Flush branch must not assign payload register $name"
  }
}

Write-Host "Prefetch valid-only flush boundary OK"
```

- [ ] **Step 2: Run RED**

Run:

```powershell
scripts/check_prefetch_valid_flush_boundary.ps1
```

Expected before RTL change:

```text
Flush branch must not assign payload register current_pc
```

- [ ] **Step 3: Hook into project check**

Add `scripts/check_prefetch_valid_flush_boundary.ps1` to the required file list in `scripts/check_project.ps1`.

Add this invocation near the other structural checks:

```powershell
& scripts/check_prefetch_valid_flush_boundary.ps1
```

- [ ] **Step 4: Run project RED**

Run:

```powershell
scripts/check_project.ps1
```

Expected before RTL change:

```text
Flush branch must not assign payload register current_pc
```

## Task 2: Prefetch RED Test

**Files:**

- Modify: `tb/tb_prefetch.v`

- [ ] **Step 1: Extend `tb_prefetch`**

Add checks after the existing accept/hold scenario:

```verilog
        stall = 1'b0;
        flush = 1'b1;
        @(posedge clk);
        #1;
        flush = 1'b0;
        if (valid !== 1'b0) begin
            $display("FAIL prefetch flush current valid: valid=%b pc=%08x instr=%08x",
                valid, pc, instr);
            $finish;
        end
        if (pc !== 32'h00000010 || instr !== 32'h00100093 ||
            pred_taken !== 1'b1 || pred_target !== 32'h00000040) begin
            $display("FAIL prefetch flush changed current payload: pc=%08x instr=%08x pred=%b target=%08x",
                pc, instr, pred_taken, pred_target);
            $finish;
        end

        fetch_valid = 1'b1;
        fetch_pc = 32'h00000020;
        fetch_instr = 32'h00300193;
        fetch_pred_taken = 1'b0;
        fetch_pred_target = 32'h00000024;
        @(posedge clk);
        #1;
        fetch_valid = 1'b0;
        if (valid !== 1'b1 || pc !== 32'h00000020 || instr !== 32'h00300193 ||
            pred_taken !== 1'b0 || pred_target !== 32'h00000024) begin
            $display("FAIL prefetch fetch after flush: valid=%b pc=%08x instr=%08x pred=%b target=%08x",
                valid, pc, instr, pred_taken, pred_target);
            $finish;
        end

        stall = 1'b1;
        fetch_valid = 1'b1;
        fetch_pc = 32'h00000024;
        fetch_instr = 32'h00400213;
        fetch_pred_taken = 1'b1;
        fetch_pred_target = 32'h00000080;
        @(posedge clk);
        #1;
        flush = 1'b1;
        stall = 1'b0;
        fetch_valid = 1'b0;
        @(posedge clk);
        #1;
        flush = 1'b0;
        if (valid !== 1'b0) begin
            $display("FAIL prefetch flush skid valid: valid=%b pc=%08x instr=%08x",
                valid, pc, instr);
            $finish;
        end

        fetch_valid = 1'b1;
        fetch_pc = 32'h00000028;
        fetch_instr = 32'h00500293;
        fetch_pred_taken = 1'b0;
        fetch_pred_target = 32'h0000002c;
        @(posedge clk);
        #1;
        fetch_valid = 1'b0;
        if (valid !== 1'b1 || pc !== 32'h00000028 || instr !== 32'h00500293 ||
            pred_taken !== 1'b0 || pred_target !== 32'h0000002c) begin
            $display("FAIL prefetch fetch after skid flush: valid=%b pc=%08x instr=%08x pred=%b target=%08x",
                valid, pc, instr, pred_taken, pred_target);
            $finish;
        end
```

- [ ] **Step 2: Run RED**

Run a focused compile/sim:

```powershell
$workDir = "build/modelsim_prefetch_phase61_red"; if (Test-Path -LiteralPath $workDir) { Remove-Item -LiteralPath $workDir -Recurse -Force }; New-Item -ItemType Directory -Force -Path $workDir | Out-Null; vlib "$workDir/work"; vlog -work "$workDir/work" rtl/prefetch.v tb/tb_prefetch.v; vsim -c -lib "$workDir/work" tb_prefetch -do "run -all; quit -f"
```

Expected before RTL change:

```text
FAIL prefetch flush changed current payload
```

## Task 3: Implement Valid-Only Flush

**Files:**

- Modify: `rtl/prefetch.v`

- [ ] **Step 1: Change the flush branch**

Replace the `flush_i` branch with:

```verilog
        end else if (flush_i) begin
            current_valid <= 1'b0;
            skid_valid <= 1'b0;
```

Do not assign payload registers in this branch.

- [ ] **Step 2: Run focused GREEN**

Run:

```powershell
$workDir = "build/modelsim_prefetch_phase61_green"; if (Test-Path -LiteralPath $workDir) { Remove-Item -LiteralPath $workDir -Recurse -Force }; New-Item -ItemType Directory -Force -Path $workDir | Out-Null; vlib "$workDir/work"; vlog -work "$workDir/work" rtl/prefetch.v tb/tb_prefetch.v; vsim -c -lib "$workDir/work" tb_prefetch -do "run -all; quit -f"
```

Expected:

```text
PASS prefetch unit regression completed
Errors: 0, Warnings: 0
```

- [ ] **Step 3: Run structural GREEN**

Run:

```powershell
scripts/check_prefetch_valid_flush_boundary.ps1
scripts/check_project.ps1
git diff --check
```

Expected:

```text
Prefetch valid-only flush boundary OK
Project structure OK
```

## Task 4: Functional Acceptance

**Files:**

- Modify: `progress.md`

- [ ] **Step 1: Run full ModelSim**

Run:

```powershell
scripts/run_modelsim.ps1
```

Expected:

```text
PASS prefetch unit regression completed
Errors: 0, Warnings: 0
```

- [ ] **Step 2: Run CSR acceptance without Vivado**

Run:

```powershell
scripts/run_csr_phase_acceptance.ps1 -SkipVivado
```

Expected:

```text
CSR_PHASE_ACCEPTANCE_PASS=1
COREMARK_RESULT_CYCLES=649893
```

Any CoreMark result over `682500` rejects the RTL candidate.

## Task 5: Physical Screen

**Files:**

- Modify: `findings.md`
- Modify: `task_plan.md`
- Modify: `progress.md`

- [ ] **Step 1: Run full implementation**

Run:

```powershell
scripts/run_vivado_impl.ps1 -Top soc_top -Constraint huoyue_uart -OutDir build\vivado_impl_soc_top_phase61_prefetch_valid_flush_extra_net_delay_100m -Jobs 4 -PlaceDirective ExtraNetDelay_high -PhysOptDirective AggressiveExplore -RouteDirective Explore -PostRoutePhysOptDirective AggressiveExplore
```

- [ ] **Step 2: Run QoR and timing checks**

Run:

```powershell
scripts/check_vivado_qor.ps1 -ReportDir build\vivado_impl_soc_top_phase61_prefetch_valid_flush_extra_net_delay_100m -Top soc_top -RequireDmemBlockRam
scripts/check_vivado_timing.ps1 -ReportDir build\vivado_impl_soc_top_phase61_prefetch_valid_flush_extra_net_delay_100m
```

Expected retention interpretation:

- WNS `>= 0.000 ns`: keep and promote as timing-clean.
- `-1.064 ns < WNS < 0.000 ns`: keep as improved baseline and document the new worst path.
- `WNS <= -1.064 ns`: reject and revert RTL/check/test changes, then document the result.

## Task 6: Commit and Push

**Files:**

- All retained files from this phase.

- [ ] **Step 1: Verify final status**

Run:

```powershell
git status --short --branch
git diff --check
```

Expected:

```text
## <current-branch>...origin/<current-branch>
```

plus only intentionally retained Phase61 changes and the existing unrelated untracked old plan file.

- [ ] **Step 2: Commit retained result**

If retained:

```powershell
git add -- rtl/prefetch.v tb/tb_prefetch.v scripts/check_prefetch_valid_flush_boundary.ps1 scripts/check_project.ps1 task_plan.md findings.md progress.md docs/superpowers/specs/2026-06-05-prefetch-valid-flush-boundary-design.md docs/superpowers/plans/2026-06-05-prefetch-valid-flush-boundary.md
git commit -m "Add prefetch valid-only flush boundary"
```

If rejected and reverted:

```powershell
git add -- task_plan.md findings.md progress.md docs/superpowers/specs/2026-06-05-prefetch-valid-flush-boundary-design.md docs/superpowers/plans/2026-06-05-prefetch-valid-flush-boundary.md
git commit -m "Document rejected prefetch flush boundary"
```

- [ ] **Step 3: Push**

Run:

```powershell
git push
```
