/*
 * CoreMark baremetal port for the YL3 RV32IM/RV64IM harness.
 */
#ifndef YL3_CORE_PORTME_H
#define YL3_CORE_PORTME_H

#ifndef HAS_FLOAT
#define HAS_FLOAT 0
#endif
#ifndef HAS_TIME_H
#define HAS_TIME_H 0
#endif
#ifndef USE_CLOCK
#define USE_CLOCK 0
#endif
#ifndef HAS_STDIO
#define HAS_STDIO 0
#endif
#ifndef HAS_PRINTF
#define HAS_PRINTF 0
#endif

typedef unsigned int   size_t;
#ifndef NULL
#define NULL ((void *)0)
#endif
typedef signed short   ee_s16;
typedef unsigned short ee_u16;
typedef signed int     ee_s32;
typedef unsigned char  ee_u8;
typedef unsigned int   ee_u32;
#if defined(__riscv_xlen) && (__riscv_xlen == 64)
typedef unsigned long  ee_ptr_int;
#else
typedef ee_u32         ee_ptr_int;
#endif
typedef ee_u32         ee_size_t;
typedef ee_u32         CORE_TICKS;

#define align_mem(x) (void *)(4 + (((ee_ptr_int)(x)-1) & ~3))

#ifndef SEED_METHOD
#define SEED_METHOD SEED_VOLATILE
#endif
#ifndef MEM_METHOD
#define MEM_METHOD MEM_STATIC
#endif
#ifndef MULTITHREAD
#define MULTITHREAD 1
#define USE_PTHREAD 0
#define USE_FORK    0
#define USE_SOCKET  0
#endif
#ifndef MAIN_HAS_NOARGC
#define MAIN_HAS_NOARGC 1
#endif
#ifndef MAIN_HAS_NORETURN
#define MAIN_HAS_NORETURN 0
#endif

#ifndef COMPILER_VERSION
#if defined(__riscv_xlen) && (__riscv_xlen == 64)
#define COMPILER_VERSION "RISC-V GCC RV64IM"
#else
#define COMPILER_VERSION "RISC-V GCC RV32IM"
#endif
#endif
#ifndef COMPILER_FLAGS
#if defined(__riscv_xlen) && (__riscv_xlen == 64)
#define COMPILER_FLAGS "-O3 -march=rv64im -mabi=lp64"
#else
#define COMPILER_FLAGS "-O3 -march=rv32im -mabi=ilp32"
#endif
#endif
#ifndef MEM_LOCATION
#define MEM_LOCATION "STATIC"
#endif

extern ee_u32 default_num_contexts;

typedef struct CORE_PORTABLE_S {
    ee_u8 portable_id;
} core_portable;

void portable_init(core_portable *p, int *argc, char *argv[]);
void portable_fini(core_portable *p);
int ee_printf(const char *fmt, ...);

#if !defined(PROFILE_RUN) && !defined(PERFORMANCE_RUN) && !defined(VALIDATION_RUN)
#if (TOTAL_DATA_SIZE == 1200)
#define PROFILE_RUN 1
#elif (TOTAL_DATA_SIZE == 2000)
#define PERFORMANCE_RUN 1
#else
#define VALIDATION_RUN 1
#endif
#endif

#endif
