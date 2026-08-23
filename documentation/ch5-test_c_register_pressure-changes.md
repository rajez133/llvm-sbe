# Chapter 5 — Changes for `test_c_register_pressure/test.c`

**Prerequisite:** [Chapter 4 — Changes for test_c/test.c](ch4-test_c-changes.md)
**Source file:** `appsource/test_c_register_pressure/test.c`  
**Goal:** Correctly compile a function that exhausts the available VDR registers and must spill to the stack.

---

## 1. What This Test Does and Why It Is Harder

```c
void pressure_test(void) {
    uint64_t a = MEM(0x50000);   // 8 live 64-bit values simultaneously
    uint64_t b = MEM(0x50008);
    ...
    uint64_t h = MEM(0x50038);

    a |= 0x0000000100000001ULL;  // all 8 still live at the same time
    ...
    h |= 0x0000000800000008ULL;

    MEM(0x50000) = a;            // all 8 written back
    ...
}
```

Eight `uint64_t` values are **simultaneously live** — the compiler cannot reuse any register until all values have been written back.

Each `uint64_t` needs a VDR pair (2 GPRs). Eight values need 16 GPRs. But PPE42 has only 16 real GPRs — and some are reserved. The allocator must **spill** some values to the stack.

---

## 2. The Register Budget

```
PPE42 hardware GPRs:
  R0  R1  R2  R3  R4  R5  R6  R7  R8  R9  R10  R13  R28  R29  R30  R31
  (16 total)

Reserved (cannot be allocated):
  R1  — stack pointer
  R2  — SDA2 pointer (EABI)
  R13 — SDA pointer  (EABI)

Available for VDR pairs (volatile, callee-saved):
  Volatile:      R3:R4 (d3)  R4:R5 (d4)  R5:R6 (d5)  R6:R7 (d6)
                 R7:R8 (d7)  R8:R9 (d8)  R9:R10 (d9)
  Callee-saved:  R28:R29 (d28)  R29:R30 (d29)  R30:R31 (d30)

7 volatile VDR pairs + 3 callee-saved = 10 pairs available
8 values needed → 2 must spill to the stack
```

Spilling means: store the VDR value to a stack slot, free the registers, reload when needed.

---

## 3. The Two Problems Exposed

Running this test before the fixes revealed two bugs, triggered in sequence:

```
Problem A: Allocator tries to spill a VDR
              → getSpillIndex() returns SOK_VDRSpill
              → looks up STVD in StoreSpillOpcodesArray
              ✓ found (already added in Ch2 work)

Problem B: eliminateFrameIndex() sees STVD
              → checks ImmToIdxMap.count(PPC::STVD)
              → count == 0 → noImmForm = true
              → forces X-form fallback
              → WRONG: emits "stvd d28, r1(0)" instead of "stvd d28, 0(r1)"
              → MC emitter: getDispRIEncoding asserts "not an expression"
              → CRASH
```

Problem A was already solved as part of Chapter 4's work (adding `SOK_VDRSpill` to the spill opcode table). Problem B is the fix in this chapter.

---

## 4. How Spilling Works End-to-End

### Step 1 — The allocator decides to spill

The greedy register allocator runs out of available VDR pairs for `d28` (value `e`). It calls:

```cpp
getStoreOpcodeForSpill(&PPC::VDRCRegClass)  →  PPC::STVD
getLoadOpcodeForSpill (&PPC::VDRCRegClass)  →  PPC::LVD
```

These are looked up via `SOK_VDRSpill` (index 19) in the `Pwr8StoreOpcodes` / `Pwr8LoadOpcodes` arrays in `PPCInstrInfo.h`.

### Step 2 — The spill MachineInstr is built

```cpp
// PPCInstrInfo.cpp: StoreRegToStackSlot()
addFrameReference(
    BuildMI(MF, DL, get(PPC::STVD)).addReg(SrcReg, kill),
    FrameIdx);

// addFrameReference (PPCInstrBuilder.h):
return MIB.addImm(0).addFrameIndex(FI);
```

Result: `STVD  d28,  Imm=0,  FrameIndex(N)`

```
operand 1: d28          (register to store)
operand 2: Imm = 0      (displacement — placeholder)
operand 3: FrameIndex N (base register — placeholder)
```

### Step 3 — Frame index elimination

After RA, `eliminateFrameIndex()` resolves `FrameIndex N` to a real `r1 + offset`:

```cpp
// PPCRegisterInfo.cpp — simplified
unsigned FIOperandNum = 3;  // FrameIndex is at operand 3
unsigned OffsetOperandNo = getOffsetONFromFION(MI, 3);  // returns 2

// Gate check:
bool noImmForm = !ImmToIdxMap.count(PPC::STVD);  // ← THE BUG

// Replace FI with real base register
MI.getOperand(3).ChangeToRegister(R1, false);

// If noImmForm == false AND offset fits in 16 bits → encode directly
if (!noImmForm && isInt<16>(Offset)) {
    MI.getOperand(2).ChangeToImmediate(Offset);  // operand 2 = real offset
    return;  // done: STVD d28, 16(r1) ✓
}

// Otherwise → X-form fallback (WRONG for LVD/STVD)
li  rN, Offset
// rewrite operands to: STVD d28, r1, rN
// → prints as: stvd d28, r1(0)  ✗
```

---

## 5. The Fix — One Line in `PPCRegisterInfo.cpp`

```cpp
// PPCRegisterInfo.cpp — constructor, ~line 145
// PPE42 VDR (D-form LVD/STVD).
// Self-mapped as interim: enables the D-form immediate fast-path.
// If a frame ever exceeds 32 KB, the X-form conversion path fires;
// at that point implement P2-A (lvdx/stvdx) and change to:
//   ImmToIdxMap[PPC::LVD]  = PPC::LVDX;
//   ImmToIdxMap[PPC::STVD] = PPC::STVDX;
ImmToIdxMap[PPC::LVD]  = PPC::LVD;
ImmToIdxMap[PPC::STVD] = PPC::STVD;
```

**Why self-mapping works:** The X-form conversion path only fires when `noImmForm == false` AND the offset does NOT fit in 16 bits. For all normal function frames (< 32 KB), `isInt<16>(Offset)` is true → the early-return fires → `STVD d28, 16(r1)`. The self-mapping is never actually followed.

**Decision flow after the fix:**

```
eliminateFrameIndex sees STVD
        │
        ▼
ImmToIdxMap.count(STVD) == 1  →  noImmForm = false
        │
        ▼
isInt<16>(16) == true          →  OffsetFitsMnemonic = true
        │
        ▼
Early return: MI.getOperand(2).ChangeToImmediate(16)
Result: STVD d28, 16(r1)  ✓  (correct D-form)
```

---

## 6. Before and After

**Before the fix — assembly (broken):**

```asm
# Spill: wrong X-form fallback, wasted li, wrong operand order
li   r0, 16
stvd d28, r1(0)          # ← base register first: WRONG format
li   r0, 24
stvd d28, r1(0)          # ← all spills use offset 0, unused li instructions
lvd  d4, r1(r4)          # ← reload: X-form style, r4 used as index
```

**After the fix — assembly (correct):**

```asm
# Spill: correct D-form, no wasted instructions
stvd d28, 16(r1)         # ← offset(base): correct D-form ✓
stvd d28, 24(r1)         # ← each slot at its real offset ✓
stvd d28, 32(r1)
stvd d28, 40(r1)
lvd  d4, 16(r1)          # ← reload: also correct D-form ✓
```

**Binary encoding for `stvd d28, 16(r1)` (opcode 6, D-form):**

```
 0      5  6    10 11   15 16          31
┌────────┬────────┬───────┬─────────────┐
│  0110  │ 11100  │ 00001 │ 0000000010000│
│  (6)   │ (d28=28→14?)│ (r1=1)│   (16)  │
└────────┴────────┴───────┴─────────────┘

Actual: 0x1b810010
  fffa0248: 1b 81 00 10   stvd d28, 16(r1)  ✓
```

---

## 7. The Workaround — Bypassing the Assembly Parser Bug

When generating the `.s` file for inspection and then assembling it with `llvm-mc -mcpu=ppe42`, a second unrelated bug surfaces: `llvm-mc` rejects standard PPC register names written without a `%` prefix (e.g. `stwu r1, -64(r1)`, `lis r10, 5`).

**Root cause (documented in TODO P1-C):** `PPCAsmParser::parseOperand()` treats `r10` as a symbol reference (MCSymbolRefExpr) rather than a register number, causing `Match_InvalidOperand`. This is an independent bug in the assembly parser.

**Workaround:** Compile directly from LLVM IR to object file using `llc -filetype=obj`, skipping `llvm-mc` entirely. This is the same approach already used in `test_c/test_c.sh`:

```bash
# Instead of:
llc -filetype=asm ... -o test.s
llvm-mc -triple=powerpc-unknown-linux-gnu -mcpu=ppe42 test.s -o test.o  # FAILS

# Use:
llc -march=ppc32 -mcpu=ppe42 -filetype=obj test-opt.ll -o test.o  # ✓
```

The `.s` file is still generated (for human inspection / debugging) but is never fed to `llvm-mc`.

---

## 8. Full Pipeline for `test_c_register_pressure/test.c`

```
test.c
  │  clang -target powerpc-unknown-linux-gnu -mcpu=ppe42 -O2 -S -emit-llvm
  ▼
test.ll
  │  opt -O2
  ▼
test-opt.ll
  │  llc -march=ppc32 -mcpu=ppe42 -filetype=asm   (for inspection)
  │                                                 ↓ test.s (DO NOT assemble via llvm-mc)
  │  llc -march=ppc32 -mcpu=ppe42 -filetype=obj   (for object file)
  │
  │  Stage 3 (Register Allocation):
  │    8 live VDRs, 10 available pairs
  │    2 VDRs spilled: STVD dN, FrameIndex / LVD dN, FrameIndex inserted
  │
  │  Stage 5 (Frame Index Elimination):
  │    ImmToIdxMap has LVD, STVD → noImmForm = false
  │    Offset fits 16 bits → encode directly
  │    STVD dN, FrameIndex → STVD dN, offset(r1)  ✓
  │
  │  Stage 6 (MC Emission):
  │    getDispRIEncoding reads operand as immediate → encodes correctly ✓
  ▼
test.o
  │  ld.lld + startup.o
  ▼
a.out  →  a.dis
```

**Final disassembly (spill/reload section):**

```asm
fffa0248: 1b 81 00 10    stvd d28, 16(r1)   # spill: d28 → stack+16
fffa024c: 17 83 00 20    lvd  d28, 32(r3)   # load next value
fffa0250: 1b 81 00 18    stvd d28, 24(r1)   # spill: d28 → stack+24
...
fffa0284: 14 81 00 10    lvd  d4, 16(r1)    # reload: stack+16 → d4
```

---

## Summary of Changes

| Change | File | What it does |
|--------|------|-------------|
| Add `SOK_VDRSpill` to spill opcode table | `PPCInstrInfo.h` | Tells RA to use LVD/STVD for VDR spills |
| Register LVD/STVD as spill opcodes | `PPCInstrInfo.h` (`Pwr8StoreOpcodes`/`Pwr8LoadOpcodes`) | Maps SOK_VDRSpill → STVD/LVD at index 19 |
| Handle `VDRC` in `getSpillIndex()` | `PPCInstrInfo.cpp` | Routes VDR spills to SOK_VDRSpill |
| Add `LVD`/`STVD` to `ImmToIdxMap` | `PPCRegisterInfo.cpp` | Enables D-form fast path in `eliminateFrameIndex` |

Changes from Chapter 4 (registers, LVD/STVD instructions, GPR allocation order) are prerequisites and also required here.

---

*Back: [Chapter 4 — Changes for test_c/test.c](ch4-test_c-changes.md)*
*Back: [Chapter 1 — LLVM Backend Concepts](ch1-llvm-backend-concepts.md)*
