    .section .text
    .globl main
main:
    li t0, 0x12345678
    csrw mscratch, t0
    csrr t1, mscratch
    li t2, 0x00010000
    sw t1, 0(t2)
    bne t1, t0, fail

    li t3, 0x00000100
    csrw mtvec, t3
    csrr t4, mtvec
    sw t4, 4(t2)
    bne t4, t3, fail

    li t5, 0x00000027
    csrw mepc, t5
    csrr t6, mepc
    sw t6, 8(t2)
    li t0, 0x00000024
    bne t6, t0, fail

    li t0, 0x0000000f
    csrs mscratch, t0
    csrr t1, mscratch
    sw t1, 12(t2)
    li t0, 0x1234567f
    bne t1, t0, fail

    li t0, 0x00000070
    csrc mscratch, t0
    csrr t1, mscratch
    sw t1, 16(t2)
    li t0, 0x1234560f
    bne t1, t0, fail

    ret

fail:
    call yl3_fail
