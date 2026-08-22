// PPE42 64-bit OR and LI8_VDR test
// Tests all OR optimization cases, and LI8_VDR immediate materialisation

int main(void) {
    volatile unsigned long long *addr1 = (volatile unsigned long long *)0x50008;
    volatile unsigned long long *addr2 = (volatile unsigned long long *)0x50009;
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

    // Test Case 4: OR with both words affected (random pattern)
    // Expected: Lower to 2x 32-bit OR operations (ORI + ORIS)
    // 0x1234000000005678 = both high (0x12340000) and low (0x00005678) words affected
    value2 = *addr2;
    value2 |= 0x1234000000005678ULL;  // Both words - should use 2x 32-bit OR
    *addr2 = value2;

    // -------------------------------------------------------------------------
    // Test Case 5: LI8_VDR arbitrary 64-bit immediate — exposes P1-A bug
    //
    // The constant 0xDEADBEEFCAFEBABEULL has ALL FOUR 16-bit slices non-zero:
    //   ImmHi = 0xDEADBEEF  →  hi[31:16]=0xDEAD  hi[15:0]=0xBEEF
    //   ImmLo = 0xCAFEBABE  →  lo[31:16]=0xCAFE  lo[15:0]=0xBABE
    //
    // CURRENT (buggy) LI8_VDR expansion for ImmLo=0xCAFEBABE:
    //   LI  rLo, 0xBABE    →  rLo = 0xFFFFBABE  (sign-extend corrupts upper half!)
    //   ORIS rLo, rLo, 0xCAFE  →  rLo = 0xFFFFBABE  (OR into corrupted value)
    //   WRONG result: rLo = 0xFFFFBABE  instead of  0xCAFEBABE
    //
    // CORRECT LI8_VDR expansion for ImmLo=0xCAFEBABE:
    //   LIS rLo, 0xCAFE    →  rLo = 0xCAFE0000  (load upper half first)
    //   ORI rLo, rLo, 0xBABE  →  rLo = 0xCAFEBABE  ✓
    //
    // HOW TO READ THE OUTPUT (before P1-A fix):
    //   Look for the constant load sequence for 0xDEADBEEFCAFEBABE.
    //   The low register should contain 0xCAFEBABE but will show 0xFFFFBABE.
    //   Concretely: expect to see  LIS rLo + ORI, but actually see LI + ORIS.
    // -------------------------------------------------------------------------
    value1 = *addr1;
    value1 |= 0xDEADBEEFCAFEBABEULL;  // All four 16-bit slices non-zero
    *addr1 = value1;

    // -------------------------------------------------------------------------
    // Test Case 6: LI8_VDR — one word fits entirely in lower 15 bits → LI
    //
    // Immediate: 0x0000000500DEADBEULL
    //   High word = 0x00000005  →  Hi16=0x0000, Lo16=0x0005, bit15=0
    //                              Optimised path:  LI  rHi, 5   (single instruction)
    //   Low  word = 0x00DEADBE  →  Hi16=0x00DE, Lo16=0xADBE
    //                              General path:    LIS rLo, 0x00DE
    //                                               ORI rLo, rLo, 0xADBE
    //
    // Before the LI optimisation (P1-B fix), the expander would always emit
    // LIS rHi, 0 even though the entire high word fits in a signed 15-bit
    // immediate.  After the fix a single LI replaces LIS+ORI for that half.
    // -------------------------------------------------------------------------
    value2 = *addr2;
    value2 |= 0x0000000500DEADBEULL;  // High word fits in lower 15 bits → LI rHi, 5
    *addr2 = value2;

    // TODO: Add PPE42-specific LLVM unit tests using the LLVM FileCheck / lit
    //       framework (test/CodeGen/PowerPC/ppe42-li8-vdr-imm.ll) to formally
    //       verify the LI optimisation (Test Cases 5 and 6) and the
    //       sign-extension guard (Hi16==0, bit15==1 must NOT use LI).
    //       Deferred until the team is familiar with the lit/FileCheck workflow.

    // Infinite loop
    while (1);

    return 0;
}

// Made with Bob
