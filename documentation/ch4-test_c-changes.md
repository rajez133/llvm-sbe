# Chapter 4 — Changes for `test_c/test.c`

**Prerequisite:** [Chapter 3 — PPE42 Backend Design](ch3-ppe42-design.md)
**Source file:** `appsource/test_c/test.c`  
**Goal:** Compile 64-bit load/OR/store operations on a 32-bit-only processor (PPE42).

---

## The Problem in One Sentence

PPE42 is a **32-bit** PowerPC core. It has no 64-bit ALU. Yet the C code operates on `uint64_t` values. The compiler must lower every 64-bit operation into sequences of 32-bit instructions — and no existing LLVM target does this the way PPE42 needs.

---

## 1. What the C Code Asks For

```c
// Six test cases, all variations of:
volatile uint64_t *addr = (volatile uint64_t *)0x50008;
uint64_t value = *addr;          // 64-bit load
value |= <constant>;             // 64-bit OR with constant
*addr = value;                   // 64-bit store
```

The constants exercise five distinct patterns:

| Case | Constant | Pattern |
|------|----------|---------|
| 1 | `0x8000000000000000` | Only high 32-bit word affected |
| 2 | `0x0000000000008000` | Only low 32-bit word affected |
| 3 | `0x00000003FF000000` | Contiguous run of 1-bits spanning both words |
| 4 | `0x1234000000005678` | Both words affected, arbitrary pattern |
| 5 | `0xDEADBEEFCAFEBABE` | All four 16-bit slices non-zero |

Each case requires a different instruction sequence.

---

## 2. The Hardware Constraint: No 64-bit Registers

Standard PowerPC has 32-bit GPRs (R0–R31). PPE42 adds **Virtual Doubleword Registers (VDRs)**: not real hardware registers but a CPU convention — two consecutive GPRs treated as a 64-bit pair.

```
d4  =  R4 (high 32 bits) : R5 (low 32 bits)
d8  =  R8 (high 32 bits) : R9 (low 32 bits)
d28 = R28 (high 32 bits) : R29 (low 32 bits)
```

PPE42 adds two instructions that operate on VDR pairs as if they were 64-bit:

| Instruction | Opcode | Format | What it does |
|-------------|--------|--------|-------------|
| `lvd  dN, D(rA)` | 5 | D-form | Load 8 bytes from memory into VDR pair dN |
| `stvd dN, D(rA)` | 6 | D-form | Store 8 bytes from VDR pair dN to memory |

All other 64-bit operations (OR, constant load) are synthesised from 32-bit instructions operating on each half of the pair independently.

---

## 3. Change 1 — New VDR Register Class (`PPCRegisterInfo.td`)

**Why needed:** LLVM's register allocator needs a register class to represent the 64-bit `i64` type on PPE42. Without one, it would have no way to allocate storage for `uint64_t` values.

**What was added:**

```tablegen
// PPCRegisterInfo.td
def VDRTuples : RegisterTuples<
  [sub_gpr_hi, sub_gpr_lo],
  [(add R0, R2, R3, R4, R5, R6, R7, R8, R9, R28, R29, R30, R31),   // hi GPR
   (add R1, R3, R4, R5, R6, R7, R8, R9, R10, R29, R30, R31, R0)]>; // lo GPR

def VDRC : RegisterClass<"PPC", [i64], 64, (add VDRTuples)>;
```

`RegisterTuples` creates one pseudo-register per pair (e.g. `VD_R4_R5`) and sets up the sub-register indices `sub_gpr_hi` / `sub_gpr_lo` automatically. When the allocator assigns `VD_R4_R5`, it simultaneously reserves both R4 and R5.

**Valid VDR pairs (PPE42 hardware rule):**

```
d0  = R0:R1     d2  = R2:R3     d3  = R3:R4
d4  = R4:R5     d5  = R5:R6     d6  = R6:R7
d7  = R7:R8     d8  = R8:R9     d9  = R9:R10
d28 = R28:R29   d29 = R29:R30   d30 = R30:R31   d31 = R31:R0
```

---

## 4. Change 2 — Register VDR Type with the DAG Lowering (`PPCISelLowering.cpp`)

**Why needed:** The DAG lowering must know that `MVT::i64` is legal on PPE42 and which register class holds it.

```cpp
// PPCISelLowering.cpp
if (Subtarget.isPPE42()) {
    addRegisterClass(MVT::i64, &PPC::VDRCRegClass);
}
```

This single line tells the SelectionDAG: *"on PPE42, i64 values live in VDRC registers."* Without it, the DAG would expand every i64 operation into pairs of i32 operations before instruction selection — before the VDR instructions have a chance to match.

---

## 5. Change 3 — LVD and STVD Instructions (`PPCInstrPPEVD.td`)

**Why needed:** The load/store DAG patterns need real instructions to match.

```tablegen
def LVD : DForm_1<5, (outs vdrc:$RST), (ins (memri $D, $RA):$src),
                  "lvd $RST, $src", IIC_LdStLoad,
                  [(set i64:$RST, (load iaddr:$src))]>;

def STVD : DForm_1<6, (outs), (ins vdrc:$RST, (memri $D, $RA):$dst),
                   "stvd $RST, $dst", IIC_LdStStore,
                   [(store i64:$RST, iaddr:$dst)]>;
```

The DAG pattern `(set i64:$RST, (load iaddr:$src))` means: *whenever the DAG contains a 64-bit load from a D-form address, select `LVD`.*

**Encoding (D-form, 32 bits):**

```
 0      5  6     10 11    15 16          31
┌────────┬─────────┬────────┬─────────────┐
│ opcode │   RT    │   RA   │      D      │
│  5/6   │ (VDR#) │(base r)│  (offset)   │
└────────┴─────────┴────────┴─────────────┘
```

---

## 6. Change 4 — 64-bit OR Lowering in the DAG Combiner (`PPCISelLowering.cpp`)

This is the most complex change. PPE42 has no 64-bit OR instruction, so every `i64 OR constant` must be broken into at most two 32-bit OR instructions — one per word.

**Decision tree:**

```
i64 OR constant
        │
        ├─ only high word affected (ImmLo == 0)
        │       → ORIS rHi, rHi, ImmHi[31:16]  (1 instruction)
        │         ORI  rHi, rHi, ImmHi[15:0]   (if needed)
        │
        ├─ only low word affected (ImmHi == 0)
        │       → ORIS rLo, rLo, ImmLo[31:16]  (if needed)
        │         ORI  rLo, rLo, ImmLo[15:0]   (1 instruction)
        │
        ├─ both words, contiguous run of 1-bits
        │       → defer to tryAsSingleRLDIMI() → RLDIMI_VDR (1 instruction)
        │
        └─ both words, arbitrary pattern
                → handle hi and lo words independently (up to 4 instructions)
```

**Why defer to RLDIMI for run-of-ones?** `rldimi` (Rotate Left Doubleword Immediate then Mask Insert) can insert any contiguous mask of bits in a single instruction. For `0x00000003FF000000` (10 contiguous 1-bits), it beats four ORI/ORIS instructions.

**The DAG transformation:**

```
Before:
  [ISD::OR i64]
  /           \
[d5]    [0x1234000000005678]

After combiner:
  [INSERT_SUBREG sub_gpr_lo]
  /                        \
  [INSERT_SUBREG sub_gpr_hi]    [ISD::OR i32]
  /                   \         /         \
[d5]         [ISD::OR i32]   [rLo]   [0x5678]
             /           \
          [rHi]    [0x12340000]
```

The two `ISD::OR i32` nodes are then selected to standard PPC `ORIS`/`ORI` instructions.

**Assembly output for each test case:**

```asm
; Case 1: 0x8000000000000000 — only high word, only top bit
oris r5, r5, 32768        ; r5 |= 0x80000000

; Case 2: 0x0000000000008000 — only low word, bit 15
ori  r6, r6, 32768        ; r6 |= 0x00008000

; Case 3: 0x00000003FF000000 — run of 1s → RLDIMI
rldimi d5, d7, 24, 30     ; single instruction covers the mask

; Case 4: 0x1234000000005678 — both words
oris r5, r5, 4660         ; r5 |= 0x12340000  (4660 = 0x1234)
ori  r6, r6, 22136        ; r6 |= 0x00005678  (22136 = 0x5678)

; Case 5: 0xDEADBEEFCAFEBABE — all four 16-bit slices
ori  r5, r5, 48879        ; 0xBEEF
ori  r6, r6, 47806        ; 0xBABE
oris r5, r5, 57005        ; 0xDEAD
oris r6, r6, 51966        ; 0xCAFE
```

---

## 7. Change 5 — RLDIMI_VDR Instruction and Selection (`PPCInstrPPEVD.td` + `PPCISelDAGToDAG.cpp`)

**Why needed:** Case 3's constant is a contiguous run of 1-bits. A `rldimi` instruction can insert it in one shot.

```tablegen
def RLDIMI_VDR : MDForm_1<30, 3, (outs vdrc:$RA),
                          (ins vdrc:$RTi, vdrc:$RS, u6imm:$SH, u6imm:$MBE),
                          "rldimi $RA, $RS, $SH, $MBE", ...>;
```

The selection logic in `PPCISelDAGToDAG.cpp::tryAsSingleRLDIMI()` receives the `ISD::OR` node (when the DAG combiner left it intact for run-of-ones), analyses the constant to extract `SH` (shift) and `MBE` (mask begin/end), and emits `RLDIMI_VDR`.

For `0x00000003FF000000`:
- Bits 22–31 set → shift = 24, mask = bits 30–39 (using 64-bit rldimi convention)
- Assembly: `rldimi d5, d7, 24, 30`

---

## 8. Change 6 — LI8_VDR and OR8_VDR Pseudos (`PPCInstrPPEVD.td` + `PPCInstrInfo.cpp`)

**Why needed:** Loading a 64-bit constant into a VDR requires up to 4 instructions (2 per 32-bit word). This must happen **after** register allocation, because the two GPRs in the pair must already be assigned.

```tablegen
def LI8_VDR : PPCPostRAExpPseudo<(outs vdrc:$rD), (ins s16imm64:$imm), ...>;
def OR8_VDR : PPCPostRAExpPseudo<(outs vdrc:$rD), (ins vdrc:$rA, vdrc:$rB), ...>;
```

Post-RA expansion for `LI8_VDR 0xDEADBEEFCAFEBABE`:

```
Split 64-bit constant:
  ImmHi = 0xDEADBEEF   →  hi16 = 0xDEAD,  lo16 = 0xBEEF
  ImmLo = 0xCAFEBABE   →  hi16 = 0xCAFE,  lo16 = 0xBABE

Expand into:
  lis  rHi, 0xDEAD      → rHi = 0xDEAD0000
  ori  rHi, rHi, 0xBEEF → rHi = 0xDEADBEEF
  lis  rLo, 0xCAFE      → rLo = 0xCAFE0000
  ori  rLo, rLo, 0xBABE → rLo = 0xCAFEBABE
```

**Important:** `li rX, N` sign-extends 16 bits to 32 bits. If `lo16` has bit 15 set (≥ 0x8000), a plain `li` would corrupt the upper 16 bits. The expansion uses `lis + ori` for any word where `hi16 != 0` — never `li` for the high GPR unless `hi16 == 0` and `lo16` bit 15 is clear.

---

## 9. Change 7 — PPE42 GPR Allocation Order (`PPCRegisterInfo.td` + `PPCSubtarget.h`)

**Why needed:** PPE42 has only 16 real GPRs. LLVM's default allocation order includes R11–R27, which do not exist in PPE42 hardware.

**What was added — AltOrder index 3:**

```tablegen
// PPCRegisterInfo.td — inside GPRC definition
let AltOrders = [
  ...,  // index 0, 1, 2 unchanged
  (add (sequence "R%u", 3, 10),    // volatile:      R3–R10
       (sequence "R%u", 31, 28),   // callee-saved:  R31–R28 (reverse for stmw)
       R0, R1, R2, R13)            // special-purpose last
];
```

```cpp
// PPCSubtarget.h
unsigned getGPRAllocationOrderIdx() const {
    if (isPPE42()) return 3;   // ← selects the order above
    ...
}
```

The invalid registers R11, R12, R14–R27 are also **reserved** in `getReservedRegs()`:

```cpp
// PPCRegisterInfo.cpp
if (Subtarget.isPPE42()) {
    for (MCPhysReg R : {PPC::R11, PPC::R12,
                        PPC::R14, ..., PPC::R27})
        markSuperRegs(Reserved, R);
}
```

Reserving guarantees they are never allocated even if the allocation order somehow includes them.

---

## 10. Full Pipeline: `test.c` → Disassembly

```
test.c
  │  clang -target powerpc-unknown-linux-gnu -mcpu=ppe42 -O2 -S -emit-llvm
  ▼
test.ll  (LLVM IR: i64 load/or/store)
  │  opt -O2
  ▼
test-opt.ll
  │  llc -march=ppc32 -mcpu=ppe42 -O2 -filetype=obj
  │
  │  Stage 1: DAG Combiner
  │    ISD::OR i64 const → 32-bit OR pairs (or defer to RLDIMI)
  │
  │  Stage 2: Instruction Selection
  │    (load iaddr)  → LVD
  │    (store iaddr) → STVD
  │    run-of-ones OR → RLDIMI_VDR
  │
  │  Stage 3: Register Allocation
  │    virtual %0 (i64) → d5 (VD_R5_R6)
  │
  │  Stage 4: Post-RA Expansion
  │    LI8_VDR → lis/ori sequences
  │    OR8_VDR → two 32-bit ORs
  │
  │  Stage 5: MC Emission
  │    LVD → opcode 5, D-form encoding
  │    STVD → opcode 6, D-form encoding
  ▼
test.o
  │  ld.lld -T linker
  ▼
a.out  →  llvm-objdump -d --mcpu=ppe42  →  a.dis
```

**Final disassembly (key instructions):**

```asm
fffa0208: 3c 80 00 05    lis r4, 5          ; r4 = 0x00050000
fffa020c: 14 a4 00 08    lvd d5, 8(r4)      ; d5 = mem[0x50008] (64 bits)
fffa0210: 60 83 00 08    ori r3, r4, 8      ; r3 = 0x50008 (addr2)
fffa021c: 64 a5 80 00    oris r5, r5, 32768 ; Case 1: set bit 63
fffa0220: 18 a4 00 08    stvd d5, 8(r4)     ; mem[0x50008] = d5
fffa023c: 78 e5 c7 8c    rldimi d5, d7, 24, 30 ; Case 3: insert run-of-ones
```

---

*Next: [Chapter 5 — Changes for test\_c\_register\_pressure/test.c](ch5-test_c_register_pressure-changes.md)*
*Back: [Chapter 1 — LLVM Backend Concepts](ch1-llvm-backend-concepts.md)*
