    .section .text
    .globl main
main:
    la t0, trap_handler
    csrw mtvec, t0

trap_point:
    ecall
    jal fail

after_trap:
    li t0, 0x00010000
    lw t1, 0(t0)
    li t2, 11
    bne t1, t2, fail
    lw t1, 4(t0)
    la t2, trap_point
    bne t1, t2, fail
    lw t1, 8(t0)
    bnez t1, fail
    ret

trap_handler:
    li t0, 0x00010000
    csrr t1, mcause
    sw t1, 0(t0)
    csrr t1, mepc
    sw t1, 4(t0)
    csrr t1, mtval
    sw t1, 8(t0)
    la t1, after_trap
    csrw mepc, t1
    mret

fail:
    call yl3_fail
