#ifndef PRINTF_H
#define PRINTF_H

/**
 * printf - copy a string to the PPE42 output buffer.
 *
 * Only a plain character pointer is accepted; no format substitution is
 * performed.  The string is copied verbatim into the memory-mapped output
 * buffer located at:
 *   0xFFF60000 + (0x400 * 16)  =  0xFFF64000
 *
 * Returns the number of characters written (excluding the NUL terminator).
 */
int printf(const char *str);

#endif /* PRINTF_H */
