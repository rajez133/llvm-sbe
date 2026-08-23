# Chapter 1 — LLVM Backend Concepts You Need to Know

**Audience:** Advanced software engineer; new to LLVM compiler internals.  
**Purpose:** Minimum-viable mental model for understanding the PPE42 backend changes in Chapters 2 and 3.

---

## 1. The Backend Pipeline (What `llc` Does)

`llc` takes LLVM IR and produces machine code in five stages:

```
LLVM IR
   │
   ▼  [Target-independent]
SelectionDAG          ← IR ops become a tree of typed nodes
   │
   ▼  [Target-specific: instruction selection]
MachineInstr (SSA)    ← real opcodes, virtual registers
   │
   ▼  [Register Allocation]
MachineInstr (phys)   ← virtual regs → physical regs; spills inserted
   │
   ▼  [Post-RA Pseudo Expansion]
MachineInstr (final)  ← pseudo-instructions expanded to real sequences
   │
   ▼  [Assembly Emission / MC layer]
.s / .o
```

Each stage is a pass (or group of passes). The key insight: **later passes see less information**. Register allocation, for example, does not know the original C intent — it only sees opcodes and liveness intervals.

> **Deep dive:** [backend-pipeline-deep-dive.md](backend-pipeline-deep-dive.md) — full walkthrough with a concrete example (arithmetic + branch + function call), annotated stage diagram, and a step-by-step guide for root-causing backend bugs using `llc -print-after-all`.
>
> **Pass reference:** [pass-source-map.md](pass-source-map.md) — every pass visible in `debug-all-passes.txt` mapped to its exact source file and entry point.

---

## 2. SelectionDAG and the DAG Combiner

The SelectionDAG is a Directed Acyclic Graph where each node is an operation (load, add, or, …) and edges are data-flow dependencies.

```
       [ISD::OR  i64]
       /           \
[ISD::LOAD i64]   [Constant 0x8000000000000000]
```

Before instruction selection, the **DAG combiner** runs repeatedly and rewrites nodes. This is where target-specific simplifications happen. Example: on PPE42, a 64-bit `ISD::OR` with a constant is split into two 32-bit `ISD::OR` nodes (one per GPR half) — because PPE42 has no native 64-bit ALU.

> **Where in the code:** `PPCISelLowering.cpp` — the method `PerformDAGCombine()` dispatches to per-opcode handlers. The PPE42-specific `ISD::OR` handler is at ~line 16684.

---

## 3. TableGen: Describing Registers and Instructions Declaratively

LLVM uses a domain-specific language called **TableGen** (`.td` files) to describe:

- **Registers** (`PPCRegisterInfo.td`) — names, encoding, sub-register relationships
- **Instructions** (`PPCInstrInfo.td`, `PPCInstrPPEVD.td`) — opcode, operand types, assembly syntax, DAG patterns
- **Register classes** — groups of registers the allocator can treat as interchangeable

TableGen generates C++ tables at build time. You write one `.td` definition; you get a matcher, encoder, decoder, and printer for free.

### Register Classes

A **register class** groups registers that are interchangeable for a given value type:

```
def GPRC : RegisterClass<"PPC", [i32], 32, (add R0, R1, … R31)>;
```

The third argument (`32`) is the alignment in bits. The fourth argument is the **allocation order** — the allocator tries registers in this order.

### AltOrders

`GPRC` has multiple allocation orders selected at runtime:

```
let AltOrders = [
  (add R2-R12, R30-R13, ...),   // index 0: default
  ...,
  (add R3-R10, R31-R28, R0, R1, R2, R13)  // index 3: PPE42
];
let AltOrderSelect = [{ return getGPRAllocationOrderIdx(); }];
```

`getGPRAllocationOrderIdx()` returns `3` when `isPPE42()` is true — so the allocator uses the PPE42 order automatically, without needing a separate register class.

### Instruction Patterns

Each instruction can carry a **DAG pattern** that tells the instruction selector when to emit it:

```tablegen
def LVD : DForm_1<5, (outs vdrc:$RST), (ins (memri $D, $RA):$src),
                  "lvd $RST, $src", IIC_LdStLoad,
                  [(set i64:$RST, (load iaddr:$src))]>;
```

The last argument is the pattern: "when the DAG has a 64-bit load from an `iaddr` address, emit `LVD`."

---

## 4. Register Allocation and Spilling

The register allocator assigns physical registers to virtual registers (SSA values). When it runs out of physical registers it **spills** — stores a value to the stack and reloads it when needed.

```
Virtual reg %42 (i64, lives across 20 instructions)
  → no free physical register
  → insert:  STVD %42, <frame_slot>     ← spill store
  → insert:  %43 = LVD  <frame_slot>    ← spill reload
```

At this point the frame slot is represented as a **FrameIndex** — an abstract integer that has not yet been resolved to a real stack offset. The actual offset is filled in later by `eliminateFrameIndex()`.

The RA does not emit these instructions directly. It calls the target hook `storeRegToStackSlot()` / `loadRegFromStackSlot()` (`PPCInstrInfo.cpp`) because: the RA does not know which opcode to use per register class; some register classes (like the PowerPC Condition Register) cannot be spilled with a single instruction and require a multi-step sequence; the spill instruction must carry `MachineMemOperand` alias metadata; and side-effects must be recorded on `PPCFunctionInfo` for correct prologue generation.

> **Deep dive:** [why-spill-needs-target-hook.md](why-spill-needs-target-hook.md) — full explanation of all five reasons with PPE42-specific examples, the CR multi-instruction expansion, the `updatedRC` VRRC→VSRC correction, and the complete PPE42 spill path end to end.

---

## 5. Frame Index Elimination (`eliminateFrameIndex`)

After register allocation, every `FrameIndex` operand must be replaced with a real `base_register + offset` pair. This is done by `PPCRegisterInfo::eliminateFrameIndex()`.

The function decides how to encode the offset:

```
┌─────────────────────────────────────────────────────┐
│  Does the instruction have an immediate-offset form? │
│  (checked via ImmToIdxMap)                          │
│                                                     │
│  YES → and offset fits in 16 bits?                  │
│    YES → encode directly: STVD d28, 16(r1)  ✓       │
│    NO  → convert to X-form: li rN, offset           │
│           stvdx d28, r1, rN                         │
│                                                     │
│  NO  → force X-form regardless of offset size       │
└─────────────────────────────────────────────────────┘
```

`ImmToIdxMap` maps each D-form instruction to its X-form counterpart:

```cpp
ImmToIdxMap[PPC::STW]  = PPC::STWX;   // D-form → X-form
ImmToIdxMap[PPC::LWZ]  = PPC::LWZX;
// … etc for every spill-capable instruction
```

If an instruction is **missing** from this map, `noImmForm = true` is set and the X-form conversion fires unconditionally — even if the offset is small and would fit in 16 bits. This is Bug 1 in Chapter 5.

---

## 6. Post-RA Pseudo Expansion

Some instructions are **pseudos** — they exist only to give the register allocator a single opaque node, and they are expanded into real instructions after RA. This matters because the real expansion may need two registers (the RA must have already allocated them).

Example: `LI8_VDR d5, 0x8000000000000000` is a pseudo that tells RA "I need a VDR pair". After RA it expands to:

```asm
lis  r5, -32768      ← high GPR of the pair: rHi = 0x80000000
li   r6, 0           ← low  GPR of the pair: rLo = 0x00000000
```

The expansion lives in `PPCInstrInfo::expandPostRAPseudo()`.

---

## 7. The MC (Machine Code) Layer

The MC layer handles everything below MachineInstr: encoding, fixups, ELF section layout. When you run `llc -filetype=obj`, the MC layer encodes each `MCInst` to binary. When you run `llc -filetype=asm`, it calls the `InstPrinter` to format each instruction as text.

```
MachineInstr  ──lowering──▶  MCInst  ──encoder──▶  .o bytes
                                      ──printer──▶  .s text
```

The encoder reads each operand as a typed `MCOperand`. If it expects a displacement (`getDispRIEncoding`) but finds a register instead of an immediate, it asserts. This is exactly the crash seen before the `ImmToIdxMap` fix.

---

## 8. Subtarget Features and `isPPE42()`

A **subtarget feature** is a boolean flag passed via `-mcpu=` or `-mattr=`. For PPE42:

```tablegen
// PPC.td
def FeaturePPE42 : SubtargetFeature<"ppe42", "IsPPE42", "true",
                                     "Enable PPE42 instructions">;
def : Processor<"ppe42", G3Itineraries, [DirectivePPE42, FeaturePPE42]>;
```

This generates a `bool IsPPE42` field and an `isPPE42()` getter on `PPCSubtarget`. All PPE42-specific code paths are guarded by `if (Subtarget.isPPE42())` or `Predicates = [IsPPE42]` in `.td` files.

---

## Key Files Reference

| File | Role |
|------|------|
| `PPCRegisterInfo.td` | Register definitions, register classes, allocation orders |
| `PPCInstrPPEVD.td` | LVD, STVD, RLDIMI_VDR, LI8_VDR, OR8_VDR instruction defs |
| `PPCISelLowering.cpp` | DAG combine: 64-bit OR → two 32-bit ORs; VDR type registration |
| `PPCISelDAGToDAG.cpp` | Pattern matching: RLDIMI_VDR selection (`tryAsSingleRLDIMI`) |
| `PPCInstrInfo.cpp` | Post-RA pseudo expansion (LI8_VDR, OR8_VDR); spill opcode table |
| `PPCRegisterInfo.cpp` | `ImmToIdxMap`; `getReservedRegs`; `eliminateFrameIndex` |
| `PPCSubtarget.h` | `isPPE42()`; `getGPRAllocationOrderIdx()` |
| `PPC.td` | `FeaturePPE42`; processor definition for `ppe42` |

---

*Next: [Chapter 2 — PPC LLVM Backend Structure](ch2-ppc-llvm-structure.md)*
