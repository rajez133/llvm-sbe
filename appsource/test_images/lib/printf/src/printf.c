#include "printf.h"
#include "target.h"

/*
 * PPE42 output buffer address derived from the shared memory map:
 *   base   = SRAM_START           = 0xFFF60000
 *   offset = 0x400 * 16           = 0x4000
 *   addr   = SRAM_START + 0x4000  = 0xFFF64000
 *
 * Total buffer size = 0x400 * 16  = 0x4000 (16 KiB)
 *
 * Each printf call writes at the current write pointer, then advances it
 * to the next 8-byte (d-word) aligned offset so the next call starts on
 * a fresh aligned slot.
 */
#define OUTPUT_BUF_ADDR  ((unsigned int)(SRAM_START) + (0x400U * 16U))
#define OUTPUT_BUF_SIZE  (0x400U * 16U)   /* 16 KiB */
#define DWORD_ALIGN      8U

int printf(const char *str)
{
    /* Persistent byte offset into the output buffer. */
    static unsigned int offset = 0U;

    volatile char *buf = (volatile char *)OUTPUT_BUF_ADDR;
    int len = 0;

    /* Write characters until NUL or end of buffer. */
    while (*str != '\0' &&
           (offset + (unsigned int)len) < (OUTPUT_BUF_SIZE - 1U)) {
        buf[offset + (unsigned int)len] = *str;
        ++len;
        ++str;
    }
    buf[offset + (unsigned int)len] = '\0';

    /* Advance offset to the next d-word (8-byte) aligned position,
     * including the NUL terminator in the consumed byte count.       */
    offset += (unsigned int)len + 1U;
    offset  = (offset + (DWORD_ALIGN - 1U)) & ~(DWORD_ALIGN - 1U);

    /* Wrap around if we have exhausted the buffer. */
    if (offset >= OUTPUT_BUF_SIZE) {
        offset = 0U;
    }

    return len;
}
