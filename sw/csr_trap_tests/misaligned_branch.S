    .section .text
    .globl main
main:
    la t0, trap_handler
    csrw mtvec, t0
    .balign 4
faulting_branch:
    beq zero, zero, bad_branch_target
after_fault:
    li t0, 0x00010000
    lw t1, 0(t0)
    bnez t1, fail
    lw t1, 4(t0)
    la t2, faulting_branch
    bne t1, t2, fail
    lw t1, 8(t0)
    la t2, bad_branch_target
    bne t1, t2, fail
    ret
    .2byte 0
bad_branch_target:
    j fail

    .balign 4
trap_handler:
    li t0, 0x00010000
    csrr t1, mcause
    sw t1, 0(t0)
    csrr t1, mepc
    sw t1, 4(t0)
    csrr t2, mtval
    sw t2, 8(t0)
    addi t1, t1, 4
    csrw mepc, t1
    mret

fail:
    call yl3_fail
