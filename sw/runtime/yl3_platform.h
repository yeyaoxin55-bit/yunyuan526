#ifndef YL3_PLATFORM_H
#define YL3_PLATFORM_H

#include <stdint.h>

#define YL3_PASS_ADDR ((volatile uint32_t *)0x00017ff0u)
#define YL3_FAIL_ADDR ((volatile uint32_t *)0x00017ff4u)

static inline void yl3_pass(void) {
    *YL3_PASS_ADDR = 1u;
    for (;;) {
    }
}

static inline void yl3_fail_code(uint32_t code) {
    *YL3_FAIL_ADDR = code ? code : 1u;
    for (;;) {
    }
}

#endif
