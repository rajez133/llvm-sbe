#ifndef TARGET_H
#define TARGET_H

/*
 * PPE42 SRAM memory map
 * ---------------------
 * These constants are shared between the linker script and C source.
 * The linker script includes this header via the preprocessor (-include).
 */

#define SRAM_START   0xFFF60000
#define SRAM_LENGTH  0x60000

#endif /* TARGET_H */
