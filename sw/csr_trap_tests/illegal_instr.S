    .section .text
    .globl main
main:
    la t0, trap_handler
    csrw mtvec, t0
    li s1, 0x5555aaaa
faulting_instr:
    .word 0
after_fault:
    li t0, 0x00010000
    lw t1, 0(t0)
    li t2, 2
    bne t1, t2, fail
    lw t1, 4(t0)
    la t2, faulting_instr
    bne t1, t2, fail
    lw t1, 8(t0)
    bnez t1, fail
    li t2, 0x5555aaaa
    bne s1, t2, fail
    ret

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
