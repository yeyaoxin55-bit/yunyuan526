# RV64 Default CoreMark Design

## Goal

Make RV64IM the default engineering target for the project and prove the default software flow with a small RV64 CoreMark ModelSim run. RV32 directed tests remain available by explicitly setting XLEN to 32 in their testbenches or scripts.

## Scope

This phase stops at ModelSim validation. FPGA UART loading and board score bring-up are reserved for the next phase because the UART loader still sends 32-bit words while RV64 DMEM stores 64-bit words.

## Design

- Top-level RTL defaults move from `XLEN=32` to `XLEN=64` in `cpu_top`, `soc_top`, and `fpga_coremark_top`.
- External program simulation gains an `XLEN` generic and reads pass, fail, and result words through 32-bit byte-addressed helper functions so the same harness works with 32-bit and 64-bit DMEM arrays.
- CoreMark build scripts gain an `XLEN` parameter. `XLEN=64` selects `rv64im_zicsr_zifencei`, `lp64`, and an RV64 linker script. `XLEN=32` preserves the old `rv32im_zicsr_zifencei`, `ilp32` path.
- ELF-to-hex conversion keeps IMEM as 32-bit instruction words and makes DMEM word width configurable. RV64 DMEM output writes 64-bit little-endian memory words and generates eight byte-lane files.
- CoreMark port metadata is selected by `__riscv_xlen`, while CoreMark data types stay 32-bit as required by the benchmark.

## Verification

Run a small RV64 CoreMark smoke test in ModelSim, run existing RV64 directed tests, run the full ModelSim regression if practical, run `scripts/check_project.ps1`, and run `git diff --check`.
