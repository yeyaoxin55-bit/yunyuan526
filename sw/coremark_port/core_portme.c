/*
 * CoreMark baremetal port for the YL3 RV32IM ModelSim harness.
 */
#include <stdarg.h>
#include "coremark.h"
#include "core_portme.h"

#ifndef CPU_HZ
#define CPU_HZ 100000000u
#endif
#ifndef COREMARK_UART_OUTPUT
#define COREMARK_UART_OUTPUT 0
#endif

#if VALIDATION_RUN
volatile ee_s32 seed1_volatile = 0x3415;
volatile ee_s32 seed2_volatile = 0x3415;
volatile ee_s32 seed3_volatile = 0x66;
#endif
#if PERFORMANCE_RUN
volatile ee_s32 seed1_volatile = 0x0;
volatile ee_s32 seed2_volatile = 0x0;
volatile ee_s32 seed3_volatile = 0x66;
#endif
#if PROFILE_RUN
volatile ee_s32 seed1_volatile = 0x8;
volatile ee_s32 seed2_volatile = 0x8;
volatile ee_s32 seed3_volatile = 0x8;
#endif
volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;

ee_u32 default_num_contexts = 1;

static CORE_TICKS start_time_val;
static CORE_TICKS stop_time_val;
static volatile ee_u32 validation_seen;
static volatile ee_u32 finished_seen;
static volatile ee_u32 fatal_error_seen;

#define UART_TXDATA_ADDR 0x00020000u
#define UART_STATUS_ADDR 0x00020004u
#define UART_READY_MASK  0x00000001u
#define SOC_PASS_ADDR    0x00020010u
#define SOC_FAIL_ADDR    0x00020014u
#define SOC_CYCLE_ADDR   0x00020018u

static volatile ee_u32 *const uart_txdata = (volatile ee_u32 *)UART_TXDATA_ADDR;
static volatile ee_u32 *const uart_status = (volatile ee_u32 *)UART_STATUS_ADDR;
static volatile ee_u32 *const soc_pass = (volatile ee_u32 *)SOC_PASS_ADDR;
static volatile ee_u32 *const soc_fail = (volatile ee_u32 *)SOC_FAIL_ADDR;
static volatile ee_u32 *const soc_cycle = (volatile ee_u32 *)SOC_CYCLE_ADDR;

static CORE_TICKS read_mcycle(void)
{
    ee_u32 value;
    __asm__ volatile("csrr %0, mcycle" : "=r"(value));
    return value;
}

void start_time(void)
{
    start_time_val = read_mcycle();
}

void stop_time(void)
{
    stop_time_val = read_mcycle();
}

CORE_TICKS get_time(void)
{
    return stop_time_val - start_time_val;
}

secs_ret time_in_secs(CORE_TICKS ticks)
{
    return ticks / (ee_u32)CPU_HZ;
}

static void uart_putchar(char c)
{
#if COREMARK_UART_OUTPUT
    while ((*uart_status & UART_READY_MASK) == 0u) {
    }
    *uart_txdata = (ee_u32)(ee_u8)c;
#else
    (void)c;
#endif
}

static void uart_puts(const char *s)
{
    while (*s != '\0') {
        uart_putchar(*s++);
    }
}

static void uart_put_u32(ee_u32 value)
{
    char buf[10];
    int pos = 0;

    if (value == 0u) {
        uart_putchar('0');
        return;
    }

    while (value != 0u && pos < (int)sizeof(buf)) {
        buf[pos++] = (char)('0' + (value % 10u));
        value /= 10u;
    }
    while (pos > 0) {
        uart_putchar(buf[--pos]);
    }
}

static void uart_put_s32(ee_s32 value)
{
    if (value < 0) {
        uart_putchar('-');
        uart_put_u32((ee_u32)(-value));
    } else {
        uart_put_u32((ee_u32)value);
    }
}

static void uart_put_hex_u32(ee_u32 value, ee_u32 min_digits)
{
    ee_s32 shift;
    ee_u32 digit;
    uart_puts("0x");
    for (shift = 28; shift >= 0; shift -= 4) {
        digit = (value >> (ee_u32)shift) & 0xfu;
        if (digit != 0u || (ee_u32)shift < (min_digits * 4u) || shift == 0) {
            uart_putchar((char)(digit < 10u ? ('0' + digit) : ('a' + digit - 10u)));
        }
    }
}

static void uart_put_fixed_3(ee_u32 milli_value)
{
    uart_put_u32(milli_value / 1000u);
    uart_putchar('.');
    uart_putchar((char)('0' + ((milli_value / 100u) % 10u)));
    uart_putchar((char)('0' + ((milli_value / 10u) % 10u)));
    uart_putchar((char)('0' + (milli_value % 10u)));
}

static void mul_u32_u32_to_u64(ee_u32 a, ee_u32 b, ee_u32 *hi, ee_u32 *lo)
{
    ee_u32 a0 = a & 0xffffu;
    ee_u32 a1 = a >> 16;
    ee_u32 b0 = b & 0xffffu;
    ee_u32 b1 = b >> 16;
    ee_u32 p0 = a0 * b0;
    ee_u32 p1 = a0 * b1;
    ee_u32 p2 = a1 * b0;
    ee_u32 p3 = a1 * b1;
    ee_u32 middle = (p0 >> 16) + (p1 & 0xffffu) + (p2 & 0xffffu);

    *lo = (p0 & 0xffffu) | (middle << 16);
    *hi = p3 + (p1 >> 16) + (p2 >> 16) + (middle >> 16);
}

static void mul_u64_u32_low64(ee_u32 hi_in,
                              ee_u32 lo_in,
                              ee_u32 multiplier,
                              ee_u32 *hi_out,
                              ee_u32 *lo_out)
{
    ee_u32 lo_hi;
    ee_u32 lo_lo;
    ee_u32 hi_hi;
    ee_u32 hi_lo;

    mul_u32_u32_to_u64(lo_in, multiplier, &lo_hi, &lo_lo);
    mul_u32_u32_to_u64(hi_in, multiplier, &hi_hi, &hi_lo);
    (void)hi_hi;

    *lo_out = lo_lo;
    *hi_out = lo_hi + hi_lo;
}

static ee_u32 div_u64_u32_to_u32(ee_u32 hi, ee_u32 lo, ee_u32 divisor)
{
    ee_s32 bit;
    ee_u32 rem_hi = 0u;
    ee_u32 rem_lo = 0u;
    ee_u32 quotient = 0u;

    if (divisor == 0u) {
        return 0xffffffffu;
    }

    for (bit = 63; bit >= 0; bit--) {
        ee_u32 next_bit;
        rem_hi = (rem_hi << 1) | (rem_lo >> 31);
        rem_lo <<= 1;
        if (bit >= 32) {
            next_bit = (hi >> (ee_u32)(bit - 32)) & 1u;
        } else {
            next_bit = (lo >> (ee_u32)bit) & 1u;
        }
        rem_lo |= next_bit;

        if (rem_hi != 0u || rem_lo >= divisor) {
            ee_u32 old_rem_lo = rem_lo;
            rem_lo -= divisor;
            if (old_rem_lo < divisor) {
                rem_hi--;
            }
            if (bit >= 32) {
                quotient = 0xffffffffu;
            } else {
                quotient |= 1u << (ee_u32)bit;
            }
        }
    }

    return quotient;
}

static ee_u32 muldiv_u32_u32_scale(ee_u32 a, ee_u32 b, ee_u32 scale, ee_u32 divisor)
{
    ee_u32 hi;
    ee_u32 lo;
    ee_u32 scaled_hi;
    ee_u32 scaled_lo;

    mul_u32_u32_to_u64(a, b, &hi, &lo);
    mul_u64_u32_low64(hi, lo, scale, &scaled_hi, &scaled_lo);
    return div_u64_u32_to_u32(scaled_hi, scaled_lo, divisor);
}

static void uart_vprintf_lite(const char *fmt, va_list args)
{
    while (*fmt != '\0') {
        if (*fmt != '%') {
            uart_putchar(*fmt++);
        } else {
            ee_u32 long_arg = 0u;
            fmt++;
            if (*fmt == '0') {
                fmt++;
                while (*fmt >= '0' && *fmt <= '9') {
                    fmt++;
                }
            }
            if (*fmt == 'l') {
                long_arg = 1u;
                fmt++;
            }

            if (*fmt == 's') {
                const char *s = va_arg(args, const char *);
                uart_puts(s == NULL ? "(null)" : s);
            } else if (*fmt == 'c') {
                uart_putchar((char)va_arg(args, int));
            } else if (*fmt == 'd') {
                uart_put_s32((ee_s32)va_arg(args, int));
            } else if (*fmt == 'u') {
                uart_put_u32(long_arg ? (ee_u32)va_arg(args, unsigned long) : va_arg(args, ee_u32));
            } else if (*fmt == 'x' || *fmt == 'X') {
                uart_put_hex_u32(long_arg ? (ee_u32)va_arg(args, unsigned long) : va_arg(args, ee_u32), 4u);
            } else if (*fmt == 'f') {
                uart_put_u32(va_arg(args, ee_u32));
            } else if (*fmt == '%') {
                uart_putchar('%');
            } else {
                uart_putchar('%');
                if (*fmt != '\0') {
                    uart_putchar(*fmt);
                }
            }
            if (*fmt != '\0') {
                fmt++;
            }
        }
    }
}

static int starts_with(const char *s, const char *prefix)
{
    while (*prefix != '\0') {
        if (*s++ != *prefix++) {
            return 0;
        }
    }
    return 1;
}

int ee_printf(const char *fmt, ...)
{
    va_list args;

    if (starts_with(fmt, "Correct operation validated")) {
        validation_seen = 1;
    }
    if (starts_with(fmt, "Errors detected")) {
        finished_seen = 1;
    }
    if (starts_with(fmt, "[%u]ERROR! list")
        || starts_with(fmt, "[%u]ERROR! matrix")
        || starts_with(fmt, "[%u]ERROR! state")
        || starts_with(fmt, "ERROR: ")
        || starts_with(fmt, "ERROR! Please")
        || starts_with(fmt, "Cannot validate")) {
        fatal_error_seen = 1;
    }

    va_start(args, fmt);
#if COREMARK_UART_OUTPUT
    uart_vprintf_lite(fmt, args);
#endif
    va_end(args);
    return 0;
}

void portable_init(core_portable *p, int *argc, char *argv[])
{
    (void)argc;
    (void)argv;
    validation_seen = 0;
    finished_seen = 0;
    fatal_error_seen = 0;
    p->portable_id = 1;
}

void portable_fini(core_portable *p)
{
    volatile ee_u32 *pass = (volatile ee_u32 *)0x00017ff0u;
    volatile ee_u32 *fail = (volatile ee_u32 *)0x00017ff4u;
    volatile ee_u32 *cycles = (volatile ee_u32 *)0x00017ff8u;
    ee_u32 total_cycles = (ee_u32)get_time();
    ee_u32 score_x1000;
    ee_u32 per_mhz_x1000;
    ee_u32 cpu_mhz_x1000 = ((ee_u32)CPU_HZ) / 1000u;
    ee_u32 passed = ((validation_seen || finished_seen) && !fatal_error_seen);

    *cycles = total_cycles;

#if COREMARK_UART_OUTPUT
    uart_puts("\nYL3 CoreMark summary\n");
    uart_puts("CPU_HZ=");
    uart_put_u32((ee_u32)CPU_HZ);
    uart_puts("\nCPU_MHZ=");
    uart_put_fixed_3(cpu_mhz_x1000);
    uart_puts("\nITERATIONS=");
    uart_put_u32((ee_u32)ITERATIONS);
    uart_puts("\nCYCLES=");
    uart_put_u32(total_cycles);
#endif
    if (total_cycles != 0u) {
        score_x1000 = muldiv_u32_u32_scale((ee_u32)ITERATIONS,
                                           (ee_u32)CPU_HZ,
                                           1000u,
                                           total_cycles);
        per_mhz_x1000 = muldiv_u32_u32_scale(score_x1000,
                                             1000u,
                                             1u,
                                             cpu_mhz_x1000);
#if COREMARK_UART_OUTPUT
        uart_puts("\nCOREMARK_PER_SEC=");
        uart_put_fixed_3(score_x1000);
        uart_puts("\nCOREMARK_PER_MHZ=");
        uart_put_fixed_3(per_mhz_x1000);
#endif
    } else {
#if COREMARK_UART_OUTPUT
        uart_puts("\nCOREMARK_PER_SEC=NA");
        uart_puts("\nCOREMARK_PER_MHZ=NA");
#endif
    }
#if COREMARK_UART_OUTPUT
    uart_puts("\nRESULT=");
    uart_puts(passed ? "PASS\n" : "FAIL\n");
#endif

    if (passed) {
        *pass = 1u;
#if COREMARK_UART_OUTPUT
        *soc_pass = 1u;
#endif
    } else {
        *fail = 1u;
#if COREMARK_UART_OUTPUT
        *soc_fail = 1u;
#endif
    }
#if COREMARK_UART_OUTPUT
    *soc_cycle = total_cycles;
#endif
    p->portable_id = 0;
}

void *memset(void *s, int c, ee_size_t n)
{
    ee_u8 *p = (ee_u8 *)s;
    while (n-- != 0u) {
        *p++ = (ee_u8)c;
    }
    return s;
}

void *memcpy(void *dest, const void *src, ee_size_t n)
{
    ee_u8       *d = (ee_u8 *)dest;
    const ee_u8 *s = (const ee_u8 *)src;
    while (n-- != 0u) {
        *d++ = *s++;
    }
    return dest;
}

int memcmp(const void *s1, const void *s2, ee_size_t n)
{
    const ee_u8 *p1 = (const ee_u8 *)s1;
    const ee_u8 *p2 = (const ee_u8 *)s2;
    while (n-- != 0u) {
        if (*p1 != *p2) {
            return (int)*p1 - (int)*p2;
        }
        p1++;
        p2++;
    }
    return 0;
}
