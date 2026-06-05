# Phase61 Prefetch Valid-Only Flush Boundary Design

## Context

The retained CSR branch has repeated timing failures in the redirect/frontend control cone. Phase60B proved that an M-unit request/response CPU integration can pass functional and CoreMark screens, but the physical run failed at WNS `-2.718 ns` with the worst path ending at `u_core/u_prefetch/current_pred_target_reg[13]/CE`.

The current `rtl/prefetch.v` flush branch clears both validity state and payload state:

- `current_valid`
- `skid_valid`
- `current_pc`
- `current_instr`
- `current_pred_taken`
- `current_pred_target`
- `skid_pc`
- `skid_instr`
- `skid_pred_taken`
- `skid_pred_target`

Architecturally, frontend flush only needs to invalidate current and skid entries. The payload bits are ignored whenever their valid bit is low. Clearing payload on every flush therefore adds a wide control/reset path without providing architectural value.

## Goal

Create a localized frontend timing boundary by making `prefetch` flush clear only valid bits, while leaving payload registers untouched during flush.

## Scope

In scope:

- `rtl/prefetch.v` flush behavior.
- A focused prefetch unit test proving flush invalidates current and skid entries, while the next valid fetch still loads correctly.
- A structural check that rejects payload writes in the `prefetch` flush branch.
- Existing project/CSR/CoreMark/Vivado acceptance screens.
- Planning records for Phase61.

Out of scope:

- CPU M-unit request/response integration.
- DSP48 primitive/macro backend work.
- CSR/trap semantics changes.
- Branch predictor algorithm changes.
- PMP, MMU, CLINT, PLIC, asynchronous interrupts, or debug CSR work.

## Required Behavior

On reset, `prefetch` keeps the existing deterministic initialization of valid and payload registers.

On `flush_i=1`:

- `current_valid <= 1'b0`
- `skid_valid <= 1'b0`
- payload registers must not be assigned in the flush branch:
  - `current_pc`
  - `current_instr`
  - `current_pred_taken`
  - `current_pred_target`
  - `skid_pc`
  - `skid_instr`
  - `skid_pred_taken`
  - `skid_pred_target`

On `stall_i=1` without flush, existing skid capture behavior is preserved.

On a later non-stalled valid fetch after flush, the new fetch payload must replace the invalid current entry and assert `valid_o`.

## Industrial Retention Gate

The RTL candidate is retainable only if all of these hold:

- Structural checks pass.
- Focused `tb_prefetch` passes.
- Full ModelSim or CSR phase acceptance passes.
- CoreMark 2 does not exceed `682500` cycles.
- Huoyue `soc_top` implementation passes QoR and beats the current best retained physical WNS `-1.064 ns`.

If the full implementation is worse than WNS `-1.064 ns`, revert the RTL/check/test candidate and keep only the documented finding.

If timing improves but is still negative, retain only if it becomes the new best artifact and the physical path evidence is useful for the next phase.

If timing reaches non-negative WNS, promote the candidate as the new hardware baseline.

## Risk

The main semantic risk is hidden consumption of invalid `prefetch` payload. The existing `cpu_core` IF/ID capture already uses `prefetch_valid` to select NOP and default prediction payloads when no valid instruction is available, so preserving stale payload under `valid=0` should be safe. The focused test and CSR acceptance must still prove this in the current integration.

## Next Phase Dependency

Only after Phase61 either improves timing or clearly identifies the next frontend endpoint should Phase62 DSP48 primitive/macro backend work or Phase63 CPU M-unit reintegration proceed.
