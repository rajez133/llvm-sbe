// Simple 64-bit load/store test for PPE42
// This tests if LLVM can generate LVD/STVD instructions for normal C code

int main(void) {
    // Test 64-bit load and store
    volatile unsigned long long *addr = (volatile unsigned long long *)0x50000;
    unsigned long long value;

    // Load 64-bit value from memory
    value = *addr;

    // Modify it
    value |= (1ULL << 63);

    // Store it back
    *addr = value;

    // Infinite loop
    while (1);

    return 0;
}

// Made with Bob
