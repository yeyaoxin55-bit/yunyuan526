    .section .init, "ax"
    .globl _start
_start:
    la sp, __stack_top
    .option push
    .option norelax
    la gp, __global_pointer$
    .option pop

    la t0, __bss_start
    la t1, __bss_end
1:
    bgeu t0, t1, 2f
    sw zero, 0(t0)
    addi t0, t0, 4
    j 1b

2:
    call main
    li t0, 0x00017ff0
    li t1, 1
    sw t1, 0(t0)

3:
    j 3b

    .globl yl3_fail
yl3_fail:
    li t0, 0x00017ff4
    li t1, 1
    sw t1, 0(t0)
4:
    j 4b
