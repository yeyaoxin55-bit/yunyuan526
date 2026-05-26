# RV64IM Parameterization Design

## Goal

Add a real RV32IM/RV64IM architecture-width switch while keeping RV32IM as the default configuration. `XLEN` remains the external architecture-width parameter. RV64 W-class instruction behavior is represented internally with a decoded `word_op` control bit rather than a new top-level feature parameter.

## Current State

The project exposes `XLEN` in several modules, but the implemented CPU is still RV32IM-oriented. The core pipeline, decoder immediates, memory data path, load/store expansion, CSR data, fast multiply path, testbenches, and riscv-test scripts contain many fixed 32-bit declarations and constants.

The existing multiplier and divider are close to XLEN-parameterized for full-width M operations, but RV64M W operations need explicit 32-bit execution semantics. Simple `XLEN=64` substitution cannot implement `MULW`, `DIVW`, `DIVUW`, `REMW`, or `REMUW`.

## Architecture

The CPU keeps a 32-bit SoC address space for this milestone. PC, instruction memory addresses, data memory addresses, UART loader addresses, and MMIO/debug markers remain 32-bit. Integer register data, ALU results, CSR counters, DMEM read/write data, forwarding paths, multiply/divide operands, and writeback data become `XLEN` wide.

The decode stage adds RV64-only `OP-IMM-32` and `OP-32` recognition when `XLEN == 64`. A new `word_op` control signal marks instructions that operate on the low 32 bits and sign-extend the 32-bit result to `XLEN`. This signal covers both RV64I W-class ALU instructions and RV64M W-class multiply/divide/remainder instructions.

The data memory becomes `XLEN` wide with `XLEN/8` byte enables. RV32 keeps 32-bit words and 4-bit byte enables. RV64 uses 64-bit words and 8-bit byte enables, adding `LD`, `SD`, and `LWU` behavior while preserving byte/half/word misaligned support already present in the current design.

## Decoder

The decoder becomes parameterized by `XLEN` and emits an `XLEN`-wide immediate. It adds:

- `OPCODE_OP_IMM_32 = 7'b0011011`
- `OPCODE_OP_32 = 7'b0111011`
- `word_op`

For `XLEN == 32`, RV64-only opcodes decode as no-write NOPs. The project does not yet have full illegal-instruction exceptions, so the safe behavior is not to write architectural state.

## ALU

The ALU stays XLEN-wide for normal operations. It gains a `word_op` input. When `word_op` is set, the operation uses the low 32 bits, uses 5-bit shifts, and returns `{{(XLEN-32){result32[31]}}, result32}`. This implements `ADDIW`, `ADDW`, `SUBW`, `SLLIW`, `SLLW`, `SRLIW`, `SRLW`, `SRAIW`, and `SRAW`.

Normal RV64 shifts use a 6-bit shift amount. RV32 shifts keep the existing 5-bit behavior.

## RV64M

Full-width M operations continue to use XLEN operands:

- `MUL`, `MULH`, `MULHSU`, `MULHU`
- `DIV`, `DIVU`, `REM`, `REMU`

W-class M operations are enabled only by `XLEN == 64` and `word_op`:

- `MULW`: multiply `rs1[31:0] * rs2[31:0]`, take result `[31:0]`, sign-extend to 64 bits.
- `DIVW`/`DIVUW`: divide 32-bit operands, with RISC-V divide-by-zero and signed-overflow behavior, sign-extend the 32-bit quotient.
- `REMW`/`REMUW`: compute 32-bit remainder, with RISC-V divide-by-zero behavior, sign-extend the 32-bit remainder.

The existing divider can remain XLEN-wide for normal M. The W-class path can use a small 32-bit combinational helper in the execute stage or a parameterized divider command width flag. For this milestone, a compact execute-stage helper is acceptable because it only handles W-class RV64M and keeps the existing full-width divider untouched.

## Testing

Add directed tests first:

- `tb/tb_rv64i_basic.v`: `ADDIW`, W shifts, W register-register ALU, sign extension, `LD`, `SD`, and `LWU`.
- `tb/tb_rv64m_basic.v`: `MULW`, `DIVW`, `DIVUW`, `REMW`, and `REMUW`, including sign extension and divide edge cases.

Then run:

- New RV64 directed tests.
- Existing full ModelSim RTL regression for RV32IM behavior.
- Official riscv-tests RV64UI/RV64UM applicable subset when the local toolchain and submodule content are available.

## Success Criteria

- Default `XLEN=32` behavior remains compatible with current RV32IM tests.
- `XLEN=64` directed RV64I/RV64M tests pass.
- `XLEN` is passed through CPU top-level wrappers and test harnesses.
- Documentation states that this milestone supports RV64 integer data semantics with the current 32-bit SoC address map.
