#include "sbe/format.h"

/* Locate these symbols in the ELF/map file and inspect them after execution. */
volatile char sbe_test_output[64];
volatile int sbe_test_output_length;

int main(void)
{
    sbe_test_output_length = sbe_snprintf((char *)sbe_test_output,
                                          sizeof(sbe_test_output),
                                          "Hello world");
    return 0;
}
