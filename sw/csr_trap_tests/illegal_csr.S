    .section .text
    .globl main
main:
    la t0, trap_handler
    csrw mtvec, t0
    li s1, 0x11111111
    li s2, 0x22222222
faulting:
    csrrw s1, mvendorid, s2
after_fault:
    li t0, 0x00010000
    lw t1, 0(t0)
    li t2, 2
    bne t1, t2, fail
    lw t1, 4(t0)
    la t2, faulting
    bne t1, t2, fail
    lw t1, 8(t0)
    li t2, 0xf11914f3
    bne t1, t2, fail
    lw t1, 12(t0)
    li t2, 0x11111111
    bne t1, t2, fail
    ret

trap_handler:
    li t0, 0x00010000
    csrr t1, mcause
    sw t1, 0(t0)
    csrr t1, mepc
    sw t1, 4(t0)
    csrr t2, mtval
    sw t2, 8(t0)
    sw s1, 12(t0)
    addi t1, t1, 4
    csrw mepc, t1
    mret

fail:
    call yl3_fail
