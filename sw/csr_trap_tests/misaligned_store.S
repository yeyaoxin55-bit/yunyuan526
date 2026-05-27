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
