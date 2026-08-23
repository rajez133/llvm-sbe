# Chapter 3 — PPE42 Backend Design

**Audience:** Engineer adding or extending PPE42 support.  
**Purpose:** Document the three foundational design decisions — subtarget approach, derivation base, and 64-bit operation strategy — with current implementation, trade-offs, and an ideal design to consider later.

---

## Decision 1 — Feature Flag for PPE42

The upstream PPC backend implements every processor variant — from the embedded 440 to server-class POWER10 — using a **single `PPCSubtarget` class** with boolean feature flags. There is no precedent for a separate subtarget class per CPU. PPE42 follows the same pattern: it is a new feature flag, not a new class.

```tablegen
// PPC.td:89
def FeaturePPE42 : SubtargetFeature<"ppe42", "IsPPE42", "true",
                                    "Enable PPE42 instructions">;
```

This sets `bool IsPPE42` on `PPCSubtarget`. All PPE42-specific code paths are guarded by `if (Subtarget.isPPE42())` in C++ or `Predicates = [IsPPE42]` in `.td` files.

---

## Decision 2 — Which Existing Variant PPE42 Derives From

### Base feature set

PPE42 carries only two features: `FeatureMFTB` (time-base register) and `FeaturePPE42`. It deliberately omits everything that does not exist on the hardware:

| Feature | Reason omitted |
|---|---|
| `FeatureISEL` | PPE42 does not have the `isel` (integer select) instruction |
| `FeatureFRES` / `FeatureFRSQRTE` | PPE42 has no FPU at all |
| `FeatureICBT` | No instruction-cache block touch |
| `FeatureBookE` | PPE42 is not a Book-E core (different exception model, no LWARX/STWCX variants) |
| `FeatureMSYNC` | PPE42 uses standard `sync` not `msync` |

`DirectivePPE42` reuses `DIR_440` (the same CPU directive integer value), meaning the assembler treats PPE42 like a 440 for instruction encoding purposes. Both are 32-bit PowerPC with the same base instruction encoding.

### Scheduling model: NoItineraries, not G3Itineraries

The current definition uses `G3Itineraries`:

```tablegen
// PPC.td:592  — current, should be changed
def : Processor<"ppe42", G3Itineraries, [DirectivePPE42, FeatureMFTB,
                                         FeaturePPE42]>;
```

`G3Itineraries` is wrong for PPE42. It models a G3 (603) chip that has a dedicated FPU unit (`G3_FPU1`), two integer units (`G3_IU1`, `G3_IU2`), and FP instruction latencies. None of these exist on PPE42. Feeding the scheduler a table built for a different pipeline does not improve code quality — it just misleads it.

The correct choice is `NoItineraries`, which is defined in [`TargetItinerary.td`](../llvm/llvm/llvm/include/llvm/Target/TargetItinerary.td) as:

```tablegen
// Subtargets using NoItineraries can bypass the scheduler's
// expensive HazardRecognizer because no reservation table is needed.
def NoItineraries : ProcessorItineraries<[], [], []>;
```

PPE42 is a simple in-order single-issue pipeline with no hardware multi-threading and no symmetric multiprocessing. It has no reservation table to model. `NoItineraries` is precisely the right declaration: it tells the scheduler "there is no hazard table, skip the HazardRecognizer", which is both correct and marginally faster to compile.

The definition should be:

```tablegen
def : Processor<"ppe42", NoItineraries, [DirectivePPE42, FeatureMFTB,
                                         FeaturePPE42]>;
```

---

## Decision 3 — Supporting 64-bit Operations on a 32-bit ISA

### The problem

PPE42 is a 32-bit processor. Its registers are 32 bits wide. Its ALU operates on 32-bit values. Yet the firmware code being compiled uses `uint64_t` for hardware register values and bitmasks.

LLVM IR represents 64-bit values as `i64`. The PPE42 backend must either:
1. **Expand** every `i64` operation into two `i32` operations (the standard approach for 32-bit targets), or
2. **Make `i64` legal** via a custom register class that pairs two 32-bit GPRs, and handle each operation individually.

### Current design: make `i64` legal via VDRC, expand operations selectively

PPE42 registers `i64` as a legal type backed by the `VDRC` register class (pairs of consecutive even–odd GPRs):

```cpp
// PPCISelLowering.cpp:768
if (Subtarget.isPPE42()) {
    addRegisterClass(MVT::i64, &PPC::VDRCRegClass);
}
```

This makes `i64` a **first-class type** from the legaliser's point of view. The pipeline then handles each `i64` operation as follows:

| Operation | How handled | Implementation |
|---|---|---|
| `load i64` | Legal → `LVD` instruction | `.td` pattern in `PPCInstrPPEVD.td` |
| `store i64` | Legal → `STVD` instruction | `.td` pattern in `PPCInstrPPEVD.td` |
| `or i64, constant` (run-of-ones) | Custom → `RLDIMI_VDR` | `tryAsSingleRLDIMI()` in `PPCISelDAGToDAG.cpp` |
| `or i64, constant` (single word) | DAG combine → `ORIS`/`ORI` on sub-reg | `PerformDAGCombine()` in `PPCISelLowering.cpp` |
| `or i64, reg` | Post-RA pseudo `OR8_VDR` → 2×`OR` | `expandPostRAPseudo()` in `PPCInstrInfo.cpp` |
| `i64` immediate load | Post-RA pseudo `LI8_VDR` → `LIS`/`ORI`/`LI` per half | `expandPostRAPseudo()` in `PPCInstrInfo.cpp` |
| All other `i64` ops (add, sub, mul, shift, …) | **Implicitly falls through to generic expansion** | LLVM legaliser expands to `i32` pairs using `SHL_PARTS`/`SRA_PARTS`/etc. |

The phrase "making all 64-bit operations valid" in the current design means: once `i64` is registered as legal, the legaliser does not complain about `i64` nodes. For operations that PPE42 has no instruction for (add, sub, multiply, shift by variable amount, …), the legaliser expands them using the generic 32-bit expansion that exists for all 32-bit PPC targets (`SHL_PARTS`, carry-chain adds, etc.) — these expansions are already present in `PPCISelLowering.cpp` under the `!isPPC64()` branch.

**Why this design is correct but has a hidden dependency:**

The `SHL_PARTS` / `SRA_PARTS` / `SRL_PARTS` expansions (for 64-bit shifts on 32-bit PPC) operate on pairs of `i32` values. They are triggered by:

```cpp
// PPCISelLowering.cpp:761
// 32-bit PowerPC wants to expand i64 shifts itself.
setOperationAction(ISD::SHL_PARTS, MVT::i32, Custom);
setOperationAction(ISD::SRA_PARTS, MVT::i32, Custom);
setOperationAction(ISD::SRL_PARTS, MVT::i32, Custom);
```

These set `i32` (not `i64`) parts as Custom — meaning the legaliser first expands `SHL i64` into `SHL_PARTS` on two `i32` values, then the Custom handler in `PPCISelLowering.cpp` emits the correct rotate-and-mask sequence. This works for PPE42 because PPE42 inherits the `!isPPC64()` branch.

**Tracking what is and is not explicitly handled:**

```
i64 operation        | PPE42 explicit?  | Falls through to…
─────────────────────|──────────────────|──────────────────────────────────
load / store         | YES (LVD/STVD)   | —
or with constant     | YES (combine)    | —
or with register     | YES (OR8_VDR)    | —
immediate load       | YES (LI8_VDR)    | —
rotate-insert bits   | YES (RLDIMI_VDR) | —
add / sub            | NO               | expand to ADDC/ADDE i32 pairs
multiply             | NO               | expand to 32-bit multiply sequence
shift (by constant)  | NO               | expand to RLWINM/ORI pairs
shift (by variable)  | NO               | expand to SHL_PARTS i32 sequence
compare              | NO               | expand to two 32-bit compares
```

**Current design is pragmatic and correct for the firmware use-cases targeted** (load, bitwise operations, store). Every unhandled operation falls back to the generic 32-bit expansion that has existed in the PPC backend for years and is well-tested.

**Cost of current design:**

- The implicit fallback means it is not obvious which `i64` operations work efficiently and which expand to long sequences. There is no central place that lists "PPE42 supports X but not Y".
- `addRegisterClass(MVT::i64, &PPC::VDRCRegClass)` makes `i64` **legal** globally, which means the legaliser will not expand `i64` nodes before they reach the instruction selector. Any `i64` operation with no matching pattern, no Custom lowering, and no Expand action will silently reach `Select()` as an unmatched DAG node and trigger an `llvm_unreachable`. There is no compile-time inventory of which operations are covered.
- Arithmetic on `i64` VDR pairs is slower than it needs to be: the fallback to `ADDC`/`ADDE` pairs goes through the generic 32-bit path which does not understand VDR pair alignment constraints.

### Ideal design (for future consideration)

Two improvements are worth considering:

#### A — Explicit operation actions for every `i64` op

Add explicit `setOperationAction` entries for **all** `i64` operations inside the `if (Subtarget.isPPE42())` block, rather than relying on implicit fallback:

```cpp
if (Subtarget.isPPE42()) {
    addRegisterClass(MVT::i64, &PPC::VDRCRegClass);

    // These have native PPE42 instruction support:
    // load/store are Legal by default from the register class registration.

    // These fall back to 32-bit pair expansion — make it explicit:
    setOperationAction(ISD::ADD,  MVT::i64, Expand);
    setOperationAction(ISD::SUB,  MVT::i64, Expand);
    setOperationAction(ISD::MUL,  MVT::i64, Expand);
    setOperationAction(ISD::SHL,  MVT::i64, Expand);
    setOperationAction(ISD::SRL,  MVT::i64, Expand);
    setOperationAction(ISD::SRA,  MVT::i64, Expand);
    // … etc for every scalar i64 arithmetic op
}
```

This makes the PPE42 capability surface **explicit and auditable**. It also catches any `i64` operation that is neither explicitly Legal nor Expand — it would hit the legaliser assertion early in compilation rather than silently reaching the instruction selector.

#### B — Not making `i64` globally legal; using `i64` only at the DAG combine/ISel level

An alternative: do **not** call `addRegisterClass(MVT::i64, &PPC::VDRCRegClass)` at all. Instead:

1. Accept `i64` loads/stores via `Custom` lowering in `PPCISelLowering.cpp` that immediately lowers them to `LVD`/`STVD` patterns.
2. Accept `i64` bitwise constants via a `Pat<>` pattern that emits `LI8_VDR`.
3. Let all other `i64` operations be `Expand`ed to `i32` pairs **before** they reach the instruction selector.

**Trade-off:** This approach requires more hand-written lowering code but avoids the "globally legal `i64`" footgun. The VDR register class would still exist for RA purposes (the `LVD`/`STVD` patterns need a `vdrc` output), but it would not be registered as a type-legal class.

**Recommendation:** Approach A (explicit operation actions) is a low-cost improvement that can be done incrementally. It makes the current implicit-fallback behaviour explicit without restructuring anything. Approach B is a larger refactor; it would be worth considering if the current design causes debugging difficulty due to unexpected `i64` nodes reaching `Select()`.

---

## Summary of Current Design Decisions

| Decision | Current choice | Rationale | Future option |
|---|---|---|---|
| Subtarget model | Feature flag `IsPPE42` on shared `PPCSubtarget` | Zero boilerplate; consistent with 440/e500 | New subclass when virtual overrides needed |
| Base variant | `G3Itineraries`, `DIR_440` encoding, no Book-E | Matches PPE42 pipeline depth and ISA encoding; avoids incorrect Book-E features | `PPE42Model` for accurate latency scheduling |
| 64-bit ops | `i64` legal via `VDRC`, explicit for load/store/bitwise, implicit fallback for arithmetic | Covers firmware use-cases; reuses existing 32-bit expansion | Explicit `setOperationAction` for every `i64` op |

---

*Previous: [Chapter 2 — PPC LLVM Backend Structure](ch2-ppc-llvm-structure.md)*  
*Next: [Chapter 4 — Changes for test_c/test.c](ch4-test_c-changes.md)*  
*Reference: [Chapter 1 — LLVM Backend Concepts](ch1-llvm-backend-concepts.md)*
