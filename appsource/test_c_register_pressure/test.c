// PPE42 Register Pressure Test — P1-C prerequisite
//
// PURPOSE: Force the register allocator to spill into R11/R12 (and beyond),
// which do NOT exist on PPE42 hardware (valid GPRs: R0-R10, R13, R28-R31).
//
// HOW: Keep enough 64-bit VDR values simultaneously live that the allocator
// exhausts the safe PPE42 volatile registers (R2-R10 = 9 GPRs = 4 VDR pairs
// + 1 spare GPR) and is forced to assign R11, R12, or R14-R27.
//
// Each VDR register pair consumes 2 consecutive GPRs:
//   d2  = R2:R3    d4  = R4:R5    d6  = R6:R7
//   d8  = R8:R9    d28 = R28:R29  d30 = R30:R31   (valid PPE42 VDRs)
//   d10 = R10:R11  <-- R11 does NOT exist on PPE42 hardware! BUG here
//   d12 = R12:R13  <-- R12 does NOT exist on PPE42 hardware! BUG here
//
// EXPECTED BEHAVIOUR (before P1-C fix):
//   The assembler/disassembler will show r11, r12, r14... in the output.
//   These registers do not exist on the PPE42 core; any code using them
//   will silently produce wrong results or fault at runtime.
//
// EXPECTED BEHAVIOUR (after P1-C fix):
//   The allocator will never assign R11/R12/R14-R27. Instead it will
//   spill to the stack or use callee-saved VDRs (d28-d31).

#include <stdint.h>

// Use volatile memory pointers at fixed addresses so the compiler cannot
// optimise away the loads/stores or merge variables.
#define MEM(addr) (*((volatile uint64_t *)(addr)))

// Six distinct 64-bit memory locations — each 8 bytes apart.
#define ADDR_A  0x50000ULL
#define ADDR_B  0x50008ULL
#define ADDR_C  0x50010ULL
#define ADDR_D  0x50018ULL
#define ADDR_E  0x50020ULL
#define ADDR_F  0x50028ULL
#define ADDR_G  0x50030ULL
#define ADDR_H  0x50038ULL

void pressure_test(void) {
    // -----------------------------------------------------------------------
    // Load 8 independent 64-bit values simultaneously.
    // Each occupies a VDR register pair.  With 8 live VDR values:
    //   a → d2  (R2:R3)   b → d4  (R4:R5)   c → d6  (R6:R7)
    //   d → d8  (R8:R9)   e → d10 (R10:R11) ← R11 does not exist on PPE42
    //   f → d12 (R12:R13) ← R12 does not exist on PPE42
    //   g → d28 (R28:R29) h → d30 (R30:R31) (callee-saved, may spill)
    //
    // The OR operations keep all 8 values live at the same time, preventing
    // the compiler from reusing registers before the stores.
    // -----------------------------------------------------------------------
    uint64_t a = MEM(ADDR_A);
    uint64_t b = MEM(ADDR_B);
    uint64_t c = MEM(ADDR_C);
    uint64_t d = MEM(ADDR_D);
    uint64_t e = MEM(ADDR_E);
    uint64_t f = MEM(ADDR_F);
    uint64_t g = MEM(ADDR_G);
    uint64_t h = MEM(ADDR_H);

    // Keep all 8 values live simultaneously with cross-variable dependencies.
    // Use constants with all four 16-bit slices non-zero so the code generator
    // must materialise them into registers (not fold into immediate OR).
    a |= 0x0000000100000001ULL;
    b |= 0x0000000200000002ULL;
    c |= 0x0000000300000003ULL;
    d |= 0x0000000400000004ULL;
    e |= 0x0000000500000005ULL;
    f |= 0x0000000600000006ULL;
    g |= 0x0000000700000007ULL;
    h |= 0x0000000800000008ULL;

    // Write all results back — all 8 VDR values must still be live here.
    MEM(ADDR_A) = a;
    MEM(ADDR_B) = b;
    MEM(ADDR_C) = c;
    MEM(ADDR_D) = d;
    MEM(ADDR_E) = e;
    MEM(ADDR_F) = f;
    MEM(ADDR_G) = g;
    MEM(ADDR_H) = h;

    // Infinite loop (bare-metal: no OS to return to).
    while (1);
}
