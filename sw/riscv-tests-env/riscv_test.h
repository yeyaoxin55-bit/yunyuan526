#ifndef YL3_RISCV_TEST_H
#define YL3_RISCV_TEST_H

#include "encoding.h"

#define RVTEST_RV64U
#define RVTEST_RV64UF
#define RVTEST_RV64UV
#define RVTEST_RV64UVX
#define RVTEST_RV32U
#define RVTEST_RV32UF
#define RVTEST_RV32UV
#define RVTEST_RV32UVX
#define RVTEST_RV64M
#define RVTEST_RV32M

#define TESTNUM t6

#define RVTEST_CODE_BEGIN                                               \
        .section .text.init, "ax";                                      \
        .align 2;                                                       \
        .weak mtvec_handler;                                            \
        .globl _start;                                                  \
_start:                                                                 \
        j yl3_rvtest_reset_vector;                                      \
        .align 2;                                                       \
yl3_rvtest_trap_vector:                                                 \
        la t5, mtvec_handler;                                           \
        beqz t5, yl3_rvtest_unhandled_trap;                             \
        jr t5;                                                          \
yl3_rvtest_unhandled_trap:                                              \
        RVTEST_FAIL;                                                    \
yl3_rvtest_reset_vector:                                                \
        la sp, __stack_top;                                             \
        la gp, __global_pointer$;                                       \
        li TESTNUM, 0;                                                  \
        la t0, yl3_rvtest_trap_vector;                                  \
        csrw mtvec, t0;

#define RVTEST_CODE_END                                                 \
1:      j 1b

#define RVTEST_PASS                                                     \
        li t0, 0x00017ff0;                                              \
        li t1, 1;                                                       \
        sw t1, 0(t0);                                                   \
1:      j 1b

#define RVTEST_FAIL                                                     \
        li t0, 0x00017ff4;                                              \
        mv t1, TESTNUM;                                                 \
        bnez t1, 1f;                                                    \
        li t1, 1;                                                       \
1:      sw t1, 0(t0);                                                   \
2:      j 2b

#define RVTEST_DATA_BEGIN                                               \
        .align 4;                                                       \
        .global begin_signature;                                        \
begin_signature:

#define RVTEST_DATA_END                                                 \
        .align 4;                                                       \
        .global end_signature;                                          \
end_signature:

#endif
