## 0. PURPOSE

This document defines the **minimum architectural specification** required to implement a PPE42XM LLVM backend starting from a PPC32 backend.

Focus:
- Target lowering
- Register model
- Instruction set delta
- Encoding constraints
- Execution semantics

---

## 1. ARCHITECTURE SUMMARY

- Base ISA: Power ISA v2.07 (subset)
- Not fully Power ISA compliant
- Core is **in-order**, **non-speculative**
- No branch prediction
- 32-bit architecture with limited 64-bit support (via VDR)

Variants:
- PPE42 → base
- PPE42X → adds limited 64-bit features
- PPE42XM → adds multiply high word

---

## 2. REGISTER MODEL

### 2.1 General Purpose Registers (GPR)

- Total: **16 registers**
- Width: 32-bit
- Subset of PowerPC GPRs:


R0, R1, R2, R3–R10, R13, R28–R31

### 2.2 LLVM Implication

- MUST redefine register class:
  - Remove GPR11–GPR27
- Calling convention must respect:
  - R1 = stack pointer
  - R3–R10 = argument registers

---

### 2.3 Virtual Doubleword Registers (VDR)

- Constructed from **pairs of consecutive GPRs**
- Used for:
  - 64-bit loads/stores
  - Some shift/rotate ops (PPE42X/XM)

Example:

VDR(r) = {GPR(r), GPR(r+1 mod 32)}

Restrictions:
- Not all GPRs usable as VDR base (ABI reserved gaps)

---

### 2.4 Condition Register (CR)

- Only **CR0 exists**
- 4 bits:


CR0[0] = LT CR0[1] = GT CR0[2] = EQ CR0[3] = SO

LLVM Impact:
- Remove multi-field CR handling
- Remove CR logical ops

---

### 2.5 Special Purpose Registers (Relevant)


LR    (link) CTR   (counter + branch target) XER   (SO, OV, CA) MSR   (core control) SRR0  (PC save) SRR1  (MSR save) IVPR  (interrupt base) EDR   (fault info) SPRG0 (scratch) TCR / TSR (timers) DBCR / DACR (debug)

---

## 3. MACHINE STATE (MSR)

Important bits:


EE   : external interrupt enable ME   : machine check enable UIE  : unmaskable interrupt enable IPE  : imprecise store mode WE   : wait mode LP   : priority hint

LLVM impact:
- affects instruction scheduling barriers
- affects exception semantics

---

## 4. MEMORY MODEL

- 32-bit flat address space
- Big-endian only
- Byte-addressable
- Alignment: enforced by memory system (not core)
- No MMU defined at architecture level

Key rule:

Instruction addresses always 4-byte aligned

---

## 5. EXECUTION MODEL

- Strict in-order execution
- No speculation
- No branch prediction
- Pipeline behavior:

| Class | Cycles |
|------|--------|
| ALU  | 1 cycle (pipelined) |
| Branch | 2 cycles |
| Fused compare-branch | 3 cycles |
| Load/store | 2 + memory |

---

## 6. INSTRUCTION SET DELTA (vs PPC32)

### 6.1 REMOVED / NOT IMPLEMENTED

Remove from backend:

- `sc` (system call)
- privilege model instructions
- floating point
- vector / SIMD
- string/multiple load/store
- divide instructions
- CR logical instructions
- `isync`, `eieio` (replace with `sync`)
- instruction cache ops

---

### 6.2 CORE ADDITIONS (PPE42)

#### Virtual Doubleword


lvd   lvdu   lvdx stvd  stvdu  stvdx

#### Cache Query


dcbq

#### Fused Compare + Branch


bnbw, bnbwi clrbwbc, clrbwibc cmplwbc, cmpwbc, cmpwibc

Properties:
- combine compare + branch
- separate encoding (opcode 1)

---

### 6.3 PPE42X / PPE42XM ADDITIONS

#### Multiply / Arithmetic


mulli mullw mulhw (XM only)

#### 64-bit Rotate / Shift


rldicl rldicr rldimi slvd srvd

---

### 6.4 Stack Frame Instructions (CRITICAL)


lsku stsku

Used for:
- EABI stack manipulation
- FUNCTION PROLOGUE / EPILOGUE

LLVM note:
- Can map to frame lowering optimization

---

## 7. INSTRUCTION BEHAVIOUR NOTES

### 7.1 Load Semantics

- Loads are ALWAYS:
  - blocking
  - precise

### 7.2 Store Semantics

Controlled by:

MSR[IPE]

- IPE = 0 → precise
- IPE = 1 → imprecise (async completion)

LLVM implication:
- barrier insertion needed
- different ordering model

---

### 7.3 Synchronization

Supported instructions:


sync   (full barrier) mfmsr mtmsr rfi

Note:
- no `isync` instruction

---

## 8. BRANCH MODEL

Branch types:


b      (unconditional) bc     (conditional) bcctr  (via CTR) bclr   (via LR)

Properties:

- No speculation
- No prediction
- All branches resolved before next fetch

Displacement:

| Instruction | Range |
|------------|------|
| b          | ±32MB |
| bc         | ±32KB |
| fused      | ±2KB |

---

## 9. INTERRUPTS / EXCEPTIONS

Key registers:


SRR0 = return PC SRR1 = saved MSR

Single pair only.

Consequences:
- nested interrupts unsafe unless saved manually

Types:
- machine check
- program
- data/instruction storage
- alignment
- external / timers

---

## 10. DEBUG MODEL (OPTIONAL FOR LLVM)

- external debug via XIR
- trap instruction can halt
- DACR supports address watchpoints

---

## 11. ABI RELEVANT FACTS

- Based on PowerPC EABI (32-bit)
- Stack:
  - R1 = stack pointer
- Arguments:
  - R3–R10
- Return:
  - R3

Differences:
- fewer GPRs → register pressure adjustments required

---

## 12. LLVM BACKEND CHANGES (ACTIONABLE)

### 12.1 Register File

- redefine GPR class → 16 registers
- adjust callee-saved set

---

### 12.2 Instruction Selection

- remove unsupported PPC ops
- add:
  - VDR load/store
  - fused compare-branch
  - lsku/stsku

---

### 12.3 Lowering

- replace compare+branch sequences with fused ops where possible
- handle CTR/LR based branching

---

### 12.4 Calling Convention

- preserve EABI
- reduce available temporaries

---

### 12.5 Scheduler

- no speculation model
- strict dependency scheduling
- load-use stalls mandatory

---

## 13. ENCODING NOTES

- Instruction width: 32 bits
- Opcode field: bits [0:5]
- PPE-specific:
  - opcode 1 → fused compare-branch
  - opcode 31 → extended ops (dcbq, lvdx, stvdx)

---

## 14. CRITICAL DIFFERENCES SUMMARY

| Feature | PPC32 | PPE42 |
|--------|------|------|
| GPR count | 32 | 16 |
| CR fields | 8 | 1 |
| Privilege | Yes | No |
| Speculation | Yes | No |
| Branch prediction | Yes | No |
| Load/store model | OoO possible | Strict in-order |
| 64-bit ops | No | Partial via VDR |
| Stack ops | standard | + lsku/stsku |

---

## END
