#include "sbe/format.h"

int sbe_snprintf(char *buffer, size_t size, const char *text)
{
    size_t length = 0;

    while (text[length] != '\0') {
        if (size != 0 && length + 1 < size)
            buffer[length] = text[length];
        ++length;
    }

    if (size != 0)
        buffer[length < size ? length : size - 1] = '\0';

    return (int)length;
}
