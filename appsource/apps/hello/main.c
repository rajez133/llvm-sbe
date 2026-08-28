#include "sbe/format.h"

/* Locate these symbols in the ELF/map file and inspect them after execution. */
volatile char* sbe_test_output = (volatile char*) 0xFFF60000 + (0x400 * 16);
volatile int sbe_test_output_length;

int main(void)
{
    sbe_test_output_length = sbe_snprintf((char *)sbe_test_output,
                                           1024,
                                          "Hello world");
    while (1)
    {
        // Infinite loop
    }
    return 0;
}
