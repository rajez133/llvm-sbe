# Chapter 2 — High-Level Structure of the PPC LLVM Backend

**Audience:** Engineer working on PPE42; assumes Chapter 1 concepts are understood.  
**Purpose:** Orient yourself inside the upstream PPC backend before reading about PPE42-specific changes in Chapter 3.

---

## 1. One Target, Many Variants

The entire PowerPC family — from the embedded 440 to the server-class Power10 — is compiled by a **single LLVM target** registered as `"ppc"` / `"ppc64"`. There is no separate `llvm::PowerPC32Target` and `llvm::PowerPC64Target` class hierarchy. Instead, every variant is a **subtarget** of `PPCTargetMachine`, distinguished at runtime by a set of boolean feature flags.

```
PPCTargetMachine          ← one target machine for all PPC variants
    └── PPCSubtarget      ← instantiated per compilation unit with a feature string
          ├── bool IsPPC64           (64-bit pointer mode)
          ├── bool HasVSX            (VSX vector extension)
          ├── bool HasAltivec        (Altivec/VMX)
          ├── bool HasSPE            (Signal Processing Engine — e500)
          ├── bool IsBookE           (embedded Book-E architecture)
          ├── bool HasP8Vector       (POWER8 vector)
          ├── bool HasP9Vector       (POWER9 vector)
          ├── …
          └── unsigned CPUDirective  (e.g. DIR_440, DIR_PWR8, DIR_PWR9, …)
```

The feature flags are generated from TableGen. Each `SubtargetFeature<…>` in [`PPC.td`](../llvm/llvm/llvm/lib/Target/PowerPC/PPC.td) becomes a `bool` field in `PPCSubtarget` (via the `#include "PPCGenSubtargetInfo.inc"` macro expansion at [`PPCSubtarget.h:94`](../llvm/llvm/llvm/lib/Target/PowerPC/PPCSubtarget.h:94)).

---

## 2. The Processor Hierarchy

> **What is an itinerary?**
> An *itinerary* (sometimes written *itinery* in older LLVM comments) is a TableGen record that describes the **pipeline timing** of every instruction on a given processor. It answers questions like: which functional unit does this instruction use, how many cycles does it occupy that unit, and what is its result latency? The scheduler reads these records at compile time to decide instruction ordering. Each processor entry in [`PPC.td`](../llvm/llvm/llvm/lib/Target/PowerPC/PPC.td) names its itinerary model (e.g. `G3Itineraries`, `PPC440Model`) and LLVM's `ScheduleDAGRRList` uses that model when scheduling for that CPU. For targets where timing information is not yet available, the special `NoItineraries` record is used as a placeholder.

### 2.1 Embedded cores (32-bit, no FPU, no Altivec)

| `-mcpu=` | Itineraries | Key features |
|---|---|---|
| `generic` | `G3Itineraries` | `FeatureHardFloat`, `FeatureMFTB` |
| `440` / `450` | `PPC440Model` | `FeatureBookE`, `FeatureISEL`, FP reciprocal |
| `e500` | `PPCE500Model` | `FeatureBookE`, `FeatureSPE` (embedded FP via GPR pairs) |
| `e500mc` | `PPCE500mcModel` | Book-E + FPU |
| `e5500` | `PPCE5500Model` | 64-bit Book-E |

### 2.2 Classic desktop/workstation (32-bit or early 64-bit)

| `-mcpu=` | Itineraries | Key features |
|---|---|---|
| `601`–`604` | `G3Itineraries` | FPU, basic integer |
| `750` / `g3` | `G3Itineraries` | FPU |
| `7400` / `g4` | `G4Itineraries` | Altivec |
| `970` / `g5` | `G5Model` | 64-bit, Altivec |

### 2.3 Server-class (64-bit, POWER ISA)

| `-mcpu=` | Itineraries/Model | Key extensions added |
|---|---|---|
| `pwr3`–`pwr6` | `G5Model` | Progressively wider issue, more FP |
| `pwr7` | `PPCPwr7Model` | VSX (unified FP+vector), 64-bit |
| `pwr8` | `PPCPwr8Model` | HTM, crypto, direct-move, POWER8 vector |
| `pwr9` | `PPCPwr9Model` | P9 vector, prefixed instructions begin |
| `pwr10` | `PPCPwr10Model` | MMA (matrix), 34-bit prefixed, DMR |
| `future` | `PPCFutureModel` | Future POWER ISA extensions |

---

## 3. How Variant-Specific Code Is Structured

There are four mechanisms by which a code path is restricted to a specific variant:

### 3.1 `if (Subtarget.isXxx())` in C++ lowering code

The most common pattern. Each feature flag generates an `isXxx()` getter on `PPCSubtarget`. Example from the upstream backend:

```cpp
// PPCISelLowering.cpp
if (Subtarget.hasAltivec()) {
    // register Altivec vector types and operations
}

if (!Subtarget.isPPC64()) {
    // 32-bit: expand i64 shifts into SHL_PARTS / SRA_PARTS
    setOperationAction(ISD::SHL_PARTS, MVT::i32, Custom);
}
```

Used for logic that executes at lowering time: registering register classes, choosing operation legalisation actions, DAG combines.

### 3.2 `Predicates = [IsXxx]` in `.td` instruction definitions

```tablegen
// Guard an instruction so it only matches on targets with a given feature:
let Predicates = [HasVSX] in {
def XSMULDP : ...;   // VSX double-precision multiply
}
```

`Predicates` is checked by the ISel pattern engine at compile time per function. If the feature is absent the pattern is never tried.

### 3.3 `Requires<[FeatureXxx]>` in `.td`

```tablegen
// Alternative guard — typically used for ISA-level requirements:
def LXVP : DQ_RD6_RS5_DQ_Form<...>, Requires<[IsISA3_1]>;
```

Similar to `Predicates` but expressed as a `Requires` clause on the instruction record itself rather than on a surrounding block.

### 3.4 Allocation order selection via `getGPRAllocationOrderIdx()`

Different ABIs expect different register preferences. The upstream backend selects the GPR allocation order at runtime:

```cpp
// PPCSubtarget.h
unsigned getGPRAllocationOrderIdx() const {
    if (is64BitELFABI()) return 1;   // 64-bit ELF: R2 moved to end
    if (isAIXABI())      return 2;   // AIX ABI order
    return 0;                         // default (32-bit ELF)
}
```

The corresponding `AltOrders` lists in `PPCRegisterInfo.td` define the actual register sequences for each index.

---

## 4. The Single `PPCSubtarget` Class (No Separate Subtarget Classes)

A notable design decision in the upstream backend: **there is no `PPC32Subtarget` or `PPCEmbeddedSubtarget` class**. The entire variation space — from a 32-bit embedded core with no FPU to a 64-bit server chip with vector matrix multiply — is expressed by turning feature flags on and off inside the single `PPCSubtarget` class.

This means:
- All variants share the same instruction lowering files (`PPCISelLowering.cpp`, `PPCISelDAGToDAG.cpp`, `PPCRegisterInfo.cpp`, etc.) with conditional branches inside.
- Adding a new variant means adding `if (Subtarget.isNewFeature())` branches in the shared files, not creating new classes or files.
- There is no risk of accidentally inheriting the wrong base class behaviour.
- Each shared file is large and has many feature-guarded branches — a known maintenance cost of the approach.

---

## 5. Key Shared Files

These are the files any new backend variant must understand and potentially modify:

| File | Role |
|---|---|
| `PPC.td` | Feature definitions, processor entries, itinerary/model assignments |
| `PPCSubtarget.h` | All feature flag fields; ABI helpers (`isPPC64()`, `hasVSX()`, …) |
| `PPCRegisterInfo.td` | Register definitions, register classes, allocation orders (`AltOrders`) |
| `PPCInstrInfo.td` | Main instruction definitions; includes sub-files |
| `PPCInstrFormats.td` | Instruction encoding format classes (`DForm_1`, `XForm`, `MDForm_1`, …) |
| `PPCISelLowering.cpp` | Operation legalisation actions, calling convention, DAG combine |
| `PPCISelDAGToDAG.cpp` | Custom instruction selection (`Select()`, `tryAsSingleRLDICL()`, …) |
| `PPCInstrInfo.cpp` | Copy, spill, pseudo expansion, peephole |
| `PPCRegisterInfo.cpp` | Frame index elimination, reserved registers, `ImmToIdxMap` |
| `PPCFrameLowering.cpp` | Prologue/epilogue, stack frame layout |

---

## 6. ABI Paths

> **What is a target triple?**
> A *target triple* is a dash-separated string that fully identifies the compilation target. Its canonical form is `<arch>-<vendor>-<os>` or `<arch>-<vendor>-<os>-<environment>`. For example `powerpc-unknown-linux-gnu` means: architecture `powerpc` (32-bit), vendor `unknown` (no specific silicon vendor), OS `linux`, environment `gnu` (glibc + GNU ABI). LLVM parses this string at startup to instantiate the correct `TargetMachine` and select the right ABI, calling convention, and object file format. You pass it to `clang` via `-target <triple>` or bake it into the cross-compiler at configure time with `--target=<triple>`.
>
> **What is an ABI?**
> An *ABI (Application Binary Interface)* is the set of rules that lets separately-compiled code call each other correctly. It specifies: which registers carry function arguments and return values, who saves and restores which registers (caller vs. callee), how the stack frame is laid out, how structs are passed and returned, and how symbols are named in the object file. Getting this wrong produces silent data corruption or crashes at runtime rather than a compile-time error.
>
> The backend determines which ABI to use from the triple **plus** optional feature flags. For example, `powerpc64le` (little-endian 64-bit) forces ELFv2, while big-endian `powerpc64` defaults to ELFv1 unless overridden.

The backend has three ABI paths, chosen by the target triple and feature flags:

| ABI | Condition | Typical triple |
|---|---|---|
| 32-bit ELF SVR4 | `isSVR4ABI() && !isPPC64()` | `powerpc-unknown-linux-gnu` |
| 64-bit ELF SVR4 (ELFv1) | `is64BitELFABI() && !isELFv2ABI()` | `powerpc64-unknown-linux-gnu` |
| 64-bit ELF SVR4 (ELFv2) | `is64BitELFABI() && isELFv2ABI()` | `powerpc64le-unknown-linux-gnu` |
| AIX | `isAIXABI()` | `powerpc-ibm-aix` / `powerpc64-ibm-aix` |

Any new 32-bit variant (embedded or otherwise) uses the **32-bit ELF SVR4** path and inherits its calling convention automatically.

---

*Next: [Chapter 3 — PPE42 Backend Design](ch3-ppe42-design.md)*  
*Back: [Chapter 1 — LLVM Backend Concepts](ch1-llvm-backend-concepts.md)*
