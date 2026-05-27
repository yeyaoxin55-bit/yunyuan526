# Machine-Mode CSR and Synchronous Trap Design

## Scope

This phase upgrades the current counter-only CSR support into a practical
machine-mode CSR and synchronous trap subsystem.

In scope:

- Zicsr read-modify-write instructions.
- Machine-mode CSR bank centralized in `csr_unit`.
- M-mode synchronous exceptions.
- `mret` state restore and PC target generation.
- XLEN-parameterized CSR state so the same CSR block supports RV32 and RV64.

Out of scope for this phase:

- S-mode and U-mode behavior.
- PMP, MMU, virtual memory, delegation, and privilege transitions below M-mode.
- Timer, software, and external interrupt response.
- CLINT, PLIC, and board-level interrupt wiring.
- Full official privileged test-suite compliance beyond the selected smoke subset.

`mie`, `mip`, and `mstatus.MIE` are kept as register foundations for later
interrupt work, but they do not trigger asynchronous traps in this phase.

## Architecture

`csr_unit` owns CSR architectural state. It becomes an XLEN-parameterized
machine-mode CSR bank with CSR legality checks, Zicsr operation handling, trap
entry state updates, and `mret` state restore.

`cpu_core` owns pipeline control. It detects instruction and pipeline events,
chooses exception priority, decides whether a CSR/trap/mret request is killed,
performs PC redirection, flushes younger instructions, and gates side effects.
`cpu_core` does not directly maintain CSR architectural state.

The CSR interface is split into three classes:

- CSR instruction request: read and optional write for Zicsr instructions.
- Trap entry request: write `mepc`, `mcause`, `mtval`, update `mstatus`, and
  return `trap_pc`.
- MRET request: restore `mstatus` and return `mret_pc`.

CSR state updates occur only when `csr_commit_valid && !kill`. CSR read data can
be formed in EX for writeback, but the state update must be commit-gated.

## CSR Register Set

First-stage CSRs:

| CSR | Address | Behavior |
| --- | --- | --- |
| `mvendorid` | `0xF11` | Read-only, returns zero |
| `marchid` | `0xF12` | Read-only, returns zero |
| `mimpid` | `0xF13` | Read-only, returns zero |
| `mhartid` | `0xF14` | Read-only, returns `HART_ID` |
| `mstatus` | `0x300` | RW/WARL, M-mode fields only |
| `misa` | `0x301` | Read-only, generated from `XLEN` and extension parameters |
| `mie` | `0x304` | RW/WARL, stores `MSIE`, `MTIE`, `MEIE` foundations |
| `mtvec` | `0x305` | RW/WARL, stores BASE and MODE |
| `mscratch` | `0x340` | RW, XLEN-wide |
| `mepc` | `0x341` | RW/WARL, masked by IALIGN |
| `mcause` | `0x342` | RW/WARL, synchronous causes in this phase |
| `mtval` | `0x343` | RW, XLEN-wide |
| `mip` | `0x344` | RW/WARL foundation bits, no interrupt response |
| `mcycle` | `0xB00` | RW counter |
| `minstret` | `0xB02` | RW retired-instruction counter |

RV32 counter-high CSRs:

| CSR | Address | Behavior |
| --- | --- | --- |
| `mcycleh` | `0xB80` | RV32 read/write high 32 counter bits |
| `minstreth` | `0xB82` | RV32 read/write high 32 counter bits |

In RV64, `mcycleh` and `minstreth` are illegal CSR accesses.

Unimplemented CSR access, privilege-invalid access, illegal CSR encoding, and
write attempts to read-only CSRs raise illegal-instruction traps.

## Zicsr Semantics

The decoder passes CSR operation type, CSR address, `rd`, `rs1`, and `zimm` to
the pipeline. `csr_unit` implements the read-modify-write behavior:

- `CSRRW`: old value is read; new value is source value.
- `CSRRS`: old value is read; new value is `old | source`.
- `CSRRC`: old value is read; new value is `old & ~source`.
- Immediate forms use `zimm[4:0]` zero-extended to XLEN as the source value.

Read/write suppression follows Zicsr rules:

- `CSRRW rd=x0` does not need to read the CSR, but still writes the CSR.
- `CSRRS/CSRRC rs1=x0` read the CSR and do not write it.
- `CSRRSI/CSRRCI uimm=0` read the CSR and do not write it.
- Faulting CSR instructions do not write `rd`.

When an explicit CSR write targets a counter CSR in the same cycle that implicit
counter increment would update the same counter, the explicit write wins for
that CSR. Other counters may still increment according to retire rules.

## WARL and WIRI Policy

This phase uses simple deterministic masks.

- `mstatus`: only implemented fields retain written values; unsupported bits
  read zero and ignore writes.
- `mstatus.MIE` and `mstatus.MPIE`: readable/writable and updated by trap/mret.
- `mstatus.MPP`: WARL to Machine mode because lower privilege modes are not
  implemented in this phase.
- `misa`: read-only. `MXL` is generated from `XLEN`; extension bits are generated
  from core parameters.
- `mtvec`: BASE low two bits are zero. MODE accepts direct mode `0` and may
  store vectored mode `1`; unsupported modes are WARL-converted to direct mode.
- `mepc`: low bits are cleared according to IALIGN. With no C extension in this
  phase, IALIGN is 32 and `mepc[1:0]` read as zero.
- `mcause`: interrupt bit is writable for software visibility, but trap entry in
  this phase writes synchronous causes with interrupt bit zero.
- `mie` and `mip`: only `MSIE`, `MTIE`, and `MEIE` foundation bits are retained.
  These bits do not cause asynchronous trap entry in this phase.

## XLEN Parameterization

`csr_unit` exposes XLEN-wide data and PC ports:

```verilog
parameter integer XLEN = 32;
parameter integer HART_ID = 0;
parameter integer RESET_VECTOR = 0;

input  wire [XLEN-1:0] csr_wdata_i;
output reg  [XLEN-1:0] csr_rdata_o;
output wire [XLEN-1:0] trap_pc_o;
output wire [XLEN-1:0] mret_pc_o;
```

Rules:

- CSR values, `mepc`, `mtval`, trap targets, and mret targets are XLEN-wide.
- Instruction words remain 32 bits; illegal instruction `mtval` is zero-extended
  to XLEN.
- `misa.MXL` is `01` for RV32 and `10` for RV64.
- Constants use XLEN-aware localparams or helper functions, not fixed 32-bit
  literals in CSR state logic.
- Internal counters are 64-bit minimum. RV32 exposes high halves through
  `mcycleh` and `minstreth`; RV64 exposes the full 64-bit value through
  `mcycle` and `minstret`.
- The full CPU may remain RV32 in this phase, but `csr_unit` must compile and
  pass unit smoke tests with `XLEN=64`.

## Synchronous Exceptions

First-stage exception sources:

- ID/EX-detectable: illegal instruction, illegal CSR access, ECALL, EBREAK,
  legal or illegal MRET.
- EX control-flow: taken branch, JAL, or JALR target not aligned to IALIGN.
- EX or EX/MEM memory: load/store address not aligned to access width.

Causes:

| Cause | Meaning |
| --- | --- |
| `0` | Instruction address misaligned |
| `2` | Illegal instruction |
| `3` | Breakpoint |
| `4` | Load address misaligned |
| `6` | Store/AMO address misaligned |
| `11` | Environment call from M-mode |

`mtval` policy:

- Illegal instruction or illegal CSR: original 32-bit instruction zero-extended
  to XLEN.
- Instruction address misaligned: bad control-flow target.
- Load/store address misaligned: effective address.
- ECALL and EBREAK: zero.

Legal MRET is not an exception. It is a redirect with CSR state restore. Illegal
MRET encoding or privilege-invalid MRET is an illegal-instruction trap.

## Priority and Pipeline Interaction

Within one instruction:

1. Illegal instruction or illegal CSR.
2. ECALL or EBREAK.
3. Legal MRET redirect.
4. Taken control-flow target misalignment.
5. Load/store misalignment.

Instruction address misalignment applies only when the control transfer is
actually taken. Not-taken branches do not trap on their untaken target. JALR
first clears bit 0 according to ISA semantics, then the result is checked against
IALIGN.

Across the pipeline, instruction age wins:

- Older trap beats younger trap or redirect.
- Older branch/jump flush kills younger trap requests and CSR writes.
- Current committing trap beats the same instruction's ordinary branch/jump
  redirect.
- Legal MRET redirect beats ordinary branch/jump redirect.
- Younger IF/ID, prefetch entries, pending replay state, wrong-path load
  responses, and wrong-path multiplier responses are killed.

`cpu_core` merges trap and mret redirects into the existing frontend flush path.
The prefetch flush mechanism is reused instead of adding a second front-end kill
path.

## Side-Effect Kill Gates

When trap, mret, or an older flush kills an instruction, these side effects must
be blocked:

- Normal regfile writeback.
- Load-response writeback.
- Multiplier-response writeback.
- Shared writeback2.
- DMEM write.
- CSR write.
- Trap entry CSR update.
- MRET CSR restore.
- Branch predictor update.
- RAS push/pop.
- Multiplier/divider issue.
- Load-control replay capture and pending replay capture.
- `minstret` retire counting.

Faulting instructions do not retire and do not write `rd`. Trap entry itself is
not counted by `minstret`. Legal CSR instructions and legal MRET are counted if
they commit successfully.

Misaligned stores must be killed before any DMEM write is asserted. Misaligned
loads must be killed before a later load-response can write the regfile.

## PC Targets

`csr_unit` returns two XLEN-wide targets:

- `trap_pc_o = mtvec.BASE`.
- `mret_pc_o = mepc` masked by IALIGN.

This phase uses direct-mode target behavior for synchronous traps. If
`mtvec.MODE=1` is stored, synchronous exceptions still jump to BASE. Vectored
behavior is reserved for later asynchronous interrupt support.

`cpu_core` decides whether to redirect and how to flush; `csr_unit` only provides
the architectural target.

## Test Plan

Implementation follows test-driven development. Each new behavior starts with a
focused failing test, verified to fail for the expected missing behavior before
RTL changes are made.

Unit tests first:

- `tb_csr_unit_zicsr`: register and immediate Zicsr semantics, including
  read/write suppression rules.
- `tb_csr_unit_trap_mret`: trap entry, `mepc/mcause/mtval/mstatus`, `trap_pc`,
  and `mret_pc`.
- `tb_csr_unit_xlen64`: XLEN=64 compile/smoke, `misa.MXL=2`, width behavior,
  illegal-instruction zero extension, and `mepc` mask.

CPU-level tests after CSR unit tests:

- `tb_csr_rw`: write and read `mscratch`, `mtvec`, and `mepc`.
- `tb_trap_ecall_mret`: ECALL to handler, cause 11, `mepc`, `mtval=0`, handler
  increments `mepc`, then MRET returns to normal code.
- `tb_trap_illegal_csr`: illegal CSR access traps with cause 2 and no `rd`
  writeback from the faulting instruction.
- `tb_trap_misaligned_store`: misaligned store traps with cause 6 and does not
  corrupt DMEM.
- `tb_mret_redirect`: legal MRET jumps to `mepc & ~3` and restores
  `mstatus.MIE/MPIE`.

Final local verification:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\check_project.ps1
powershell -ExecutionPolicy Bypass -File scripts\run_modelsim.ps1
powershell -ExecutionPolicy Bypass -File scripts\run_riscv_suite.ps1 -Suite rv32ui -Tests add,addi,and,andi,auipc,beq,bge,bgeu,blt,bltu,bne,jal,jalr,lb,lbu,lh,lhu,lui,lw,or,ori,sb,sh,simple,sll,slli,slt,slti,sltiu,sltu,sra,srai,srl,srli,sub,sw,xor,xori
powershell -ExecutionPolicy Bypass -File scripts\run_riscv_suite.ps1 -Suite rv32um
powershell -ExecutionPolicy Bypass -File scripts\run_coremark.ps1 -Iterations 2 -TotalDataSize 2000 -MaxCycles 5000000 -OptLevel -O3 -ExtraCFlags "-funroll-loops" -PerfStats
```

Optional official privileged smoke target:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_riscv_suite.ps1 -Suite rv32mi -Tests csr,illegal,scall,sbreak,ma_fetch,lw-misaligned,sw-misaligned
```

The `rv32mi` smoke is a target, not the first hard gate, because the local
`riscv_test.h` environment may need M-mode trap setup changes before official
privileged tests are meaningful. Custom CPU tests are the hard first-stage
acceptance gate.

## Acceptance Criteria

- Existing `mcycle` and `minstret` behavior used by CoreMark continues to work.
- New CSR unit tests pass for RV32 and the XLEN=64 smoke.
- New CPU trap/CSR tests pass.
- Existing ModelSim regression passes.
- Applicable RV32UI and RV32UM regressions pass.
- CoreMark smoke still completes and reports cycles/CPI.
- No asynchronous interrupts are taken in this phase, even if `mie/mip` bits are
  written.
- CSR/trap changes do not add unguarded side effects on killed instructions.

## References

- RISC-V Unprivileged ISA, Zicsr extension:
  https://docs.riscv.org/reference/isa/unpriv/zicsr.html
- RISC-V Privileged Architecture, Machine-level ISA:
  https://docs.riscv.org/reference/isa/priv/machine.html
