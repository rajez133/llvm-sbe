// PPE42 64-bit OR optimization test
// Tests optimized (single word) and RLDIMI-compatible (continuous 1s) cases

int main(void) {
    volatile unsigned long long *addr1 = (volatile unsigned long long *)0x50000;
    volatile unsigned long long *addr2 = (volatile unsigned long long *)0x50008;
    unsigned long long value1, value2;

    // Test Case 1: OR with constant affecting only HIGH word
    // Expected: Optimized to single ORIS instruction
    value1 = *addr1;
    value1 |= (1ULL << 63);  // 0x8000000000000000 - only high word affected
    *addr1 = value1;

    // Test Case 2: OR with constant affecting only LOW word
    // Expected: Optimized to single ORI instruction
    value2 = *addr2;
    value2 |= (1ULL << 15);  // 0x0000000000008000 - only low word affected
    *addr2 = value2;

    // Test Case 3: OR with continuous stream of 1s (RLDIMI-compatible)
    // Expected: Use RLDIMI instruction
    // 0x00000003FF000000 = continuous 10 bits of 1s from bit 22 to bit 31
    value1 = *addr1;
    value1 |= 0x00000003FF000000ULL;  // Continuous 1s - can use RLDIMI
    *addr1 = value1;

    // Infinite loop
    while (1);

    return 0;
}

// Made with Bob
