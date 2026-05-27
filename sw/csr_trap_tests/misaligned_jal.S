    .section .text
    .globl main
main:
    la t0, trap_handler
    csrw mtvec, t0
    li s1, 0x44444444
    .balign 4
faulting_jal:
    jal s1, bad_jal_target
after_fault:
    li t0, 0x00010000
    lw t1, 0(t0)
    bnez t1, fail
    lw t1, 4(t0)
    la t2, faulting_jal
    bne t1, t2, fail
    lw t1, 8(t0)
    la t2, bad_jal_target
    bne t1, t2, fail
    li t2, 0x44444444
    bne s1, t2, fail
    ret
    .2byte 0
bad_jal_target:
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
