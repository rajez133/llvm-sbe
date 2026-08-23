# Why Spilling Needs a Target Hook

**Part of:** [Chapter 1 — LLVM Backend Concepts](ch1-llvm-backend-concepts.md)  
**Related:** [backend-pipeline-deep-dive.md](backend-pipeline-deep-dive.md) — Stage 5

---

## The question

Spilling a register means saving it to the stack and reloading it later.
Save = store instruction. Reload = load instruction.
Both exist. Why can't the register allocator just emit them directly?

The answer is that a spill is not just a load or store. It carries five
kinds of information and performs actions that a naked
`BuildMI(…, PPC::STW)` cannot express. The register allocator calls the
target hook `storeRegToStackSlot()` / `loadRegFromStackSlot()` and the
target provides everything the RA cannot know.

---

## How the RA calls the hook

The generic spiller (in `llvm/lib/CodeGen/InlineSpiller.cpp`) calls:

```cpp
// InlineSpiller.cpp:1136
TII.storeRegToStackSlot(MBB, SpillBefore, NewVReg, isKill, StackSlot,
                        MRI.getRegClass(NewVReg), &TRI, Register());

// InlineSpiller.cpp:1100
TII.loadRegFromStackSlot(MBB, MI, NewVReg, StackSlot,
                         MRI.getRegClass(NewVReg), &TRI, Register());
```

`TII` is the `TargetInstrInfo` for the current target — `PPCInstrInfo` on
PowerPC. The RA provides: the register to spill, the stack slot index, and
the register class. It provides nothing else. Everything below is the
target's job.

---

## Reason 1 — The RA doesn't know which opcode to use

The RA only knows a virtual register has class `:vdrc` (or `:gprc`, or
`:crrc`, …). It has no idea whether the right store instruction is `STW`,
`STVD`, `STFD`, or `STVX`. That mapping is a target fact encoded in
`StoreSpillOpcodesArray`:

```cpp
// PPCInstrInfo.h:195  (Pwr8StoreOpcodes row, one entry per SOK_* index)
#define Pwr8StoreOpcodes  \
  { PPC::STW,       // SOK_Int4Spill     — 32-bit GPR
    PPC::STD,       // SOK_Int8Spill     — 64-bit GPR
    PPC::STFD,      // SOK_Float8Spill   — FPR double
    PPC::STFS,      // SOK_Float4Spill   — FPR single
    PPC::SPILL_CR,  // SOK_CRSpill       — condition register (pseudo!)
    …
    PPC::STVD }     // SOK_VDRSpill      — PPE42 VDR pair
```

`getSpillIndex(RC)` maps the register class to a `SOK_*` row index:

```cpp
// PPCInstrInfo.cpp:1932
} else if (PPC::VDRCRegClass.hasSubClassEq(RC)) {
    OpcodeIndex = SOK_VDRSpill;   // → STVD on spill, LVD on reload
}
```

`getStoreOpcodeForSpill(RC)` then reads
`StoreSpillOpcodesArray[getSpillTarget()][OpcodeIndex]` to produce the
final opcode. `getSpillTarget()` picks the row (0 = Pwr8/PPE42,
1 = Pwr9, 2 = Pwr10, 3 = Future).

**PPE42 relevance:** PPE42 is the only subtarget that defines `VDRC`.
Without this mapping the RA would have no way to know that a 64-bit VDR
pair needs `STVD`/`LVD` rather than two `STW`/`LWZ` instructions.

---

## Reason 2 — Some register classes cannot be spilled with a single instruction

**This is the most important reason for any micro-controller ISA.**

A general-purpose store instruction (`stw`, `stb`, …) can only write a
*general-purpose register* to memory. Registers that are not
memory-accessible at all — control registers, flag registers, vector
accumulators — need a multi-step sequence that first moves the value into
a GPR, then stores the GPR.

### PowerPC Condition Register (CR)

PowerPC's Condition Register (`CR0`–`CR7`) has no `store cr0, offset(r1)`
instruction. It is not directly memory-accessible. Spilling it requires
three real instructions:

```asm
; To spill CR0 to the stack:
mfocrf  r10, CR0          ; (1) move CR field → GPR
;  (if spilling CR1..CR7, also shift the bits into CR0's slot:)
;  rlwinm  r10, r10, SB, 0, 31
stw     r10, 16(r1)       ; (2) store GPR → stack
```

The RA inserts a single `SPILL_CR` pseudo. During `eliminateFrameIndex()`
(called from `prologepilog`), `lowerCRSpilling()` expands it to the real
sequence:

```cpp
// PPCRegisterInfo.cpp:982
void PPCRegisterInfo::lowerCRSpilling(…) {
  // MFOCRF: move condition register field into a fresh virtual GPR
  BuildMI(…, TII.get(PPC::MFOCRF), Reg).addReg(SrcReg, …);

  // If not CR0, rotate bits into CR0's slot in the word
  if (SrcReg != PPC::CR0)
    BuildMI(…, TII.get(PPC::RLWINM), Reg2).addReg(Reg)
        .addImm(getEncodingValue(SrcReg) * 4).addImm(0).addImm(31);

  // STW: store the GPR to the frame slot
  addFrameReference(BuildMI(…, TII.get(PPC::STW)).addReg(Reg), FrameIndex);

  MBB.erase(II);   // discard the SPILL_CR pseudo
}
```

If the RA emitted raw instructions instead of the `SPILL_CR` pseudo, it
would need to know: (a) that CR is not memory-accessible, (b) which GPR to
use as scratch, (c) the exact rotation amount per CR field. All of these
are target-specific facts.

### Analogy for any micro-controller ISA

Any ISA where a register is not directly memory-accessible has this
problem. Common examples:

| Architecture | Register type | What a "spill" really is |
|---|---|---|
| PowerPC | Condition register (`CR`) | `mfcr` + shift + `stw` |
| ARM Cortex-M | `APSR` (flags register) | `MRS r0, APSR` + `STR r0, [sp]` |
| x86 | `EFLAGS` | `PUSHF` (special instruction, not a store) |
| AVR (8-bit MCU) | `SREG` (status reg) | `IN r0, SREG` + `STD Y+n, r0` |
| RISC-V with F extension | `fcsr` (FP control+status) | `FRCSR rd` + `SW rd, offset(sp)` |

In every case, the ISA provides a "move-to-GPR" or "read-status" special
instruction. None of these can be expressed as a plain `store reg, addr`.

### PPE42 relevance

PPE42 does not have a CR-spill problem because it does not use the full
CR register file heavily — it is a 32-bit embedded core. But the principle
applies to VDR pairs: `VDRC` registers are 64-bit pairs of consecutive
GPRs. The spill instruction is `STVD` (a single 64-bit D-form store that
writes both GPRs atomically). The RA cannot know this; the hook provides
it.

---

## Reason 3 — The spill must carry `MachineMemOperand` metadata

After building the spill instruction, `storeRegToStackSlotNoUpd` attaches
a `MachineMemOperand`:

```cpp
// PPCInstrInfo.cpp:1989
MachineMemOperand *MMO = MF.getMachineMemOperand(
    MachinePointerInfo::getFixedStack(MF, FrameIdx),  // ← "fixed stack slot"
    MachineMemOperand::MOStore,
    MFI.getObjectSize(FrameIdx),
    MFI.getObjectAlign(FrameIdx));
NewMIs.back()->addMemOperand(MF, MMO);
```

`MachinePointerInfo::getFixedStack` tags the store as "known fixed stack
slot, not a heap or global pointer." This metadata is visible to:

- **Alias analysis** — the scheduler and optimisers know this store cannot
  alias with any heap or global access, so they can freely reorder
  non-stack memory operations across it.
- **Post-RA scheduler** — can move loads/stores from heap memory past the
  spill without a dependency edge.
- **Stack slot coloring** — knows which frame slots are used by spill
  instructions, enabling slot reuse.

A raw `BuildMI(…, STVD).addReg(…).addImm(…).addReg(PPC::R1)` has no
`MachineMemOperand` at all. The scheduler would treat it as an opaque
side-effecting instruction and refuse to reorder anything past it.

**PPE42 relevance:** `STVD` spills are the only 64-bit stack stores on
PPE42. Proper `MachineMemOperand` tagging ensures that the post-RA
scheduler can still reorder surrounding 32-bit loads/stores around them.

---

## Reason 4 — The register class may need silent correction before the opcode is chosen (PPE42-adjacent)

On PowerPC with VSX, a value can be defined by an Altivec instruction
(class `VRRC`) and used by a VSX instruction (class `VSRC`). These two
instruction sets have a critical difference: **VSX load/store instructions
swap the doublewords** in a vector; Altivec ones do not. If the RA naively
used `stvx` (Altivec) on spill and `lxvd2x` (VSX) on reload, the vector
would come back byte-swapped and silently wrong.

`storeRegToStackSlot` silently corrects this before the opcode lookup:

```cpp
// PPCInstrInfo.cpp:2009
RC = updatedRC(RC);

// PPCInstrInfo.cpp:5223
const TargetRegisterClass *PPCInstrInfo::updatedRC(const TargetRegisterClass *RC) const {
    if (Subtarget.hasVSX() && RC == &PPC::VRRCRegClass)
        return &PPC::VSRCRegClass;   // force the VSX spill opcode
    return RC;
}
```

By substituting `VSRCRegClass` for `VRRCRegClass`, the opcode lookup
returns `STXV` / `LXV` (VSX, correct byte order) instead of `STVX` /
`LVX` (Altivec, would corrupt the vector). The RA never sees this
substitution — it only provides the original class from the
`MachineRegisterInfo`.

**Why this matters for any ISA:** Whenever two instruction sets overlap on
the same architectural register (common on targets that added vector
extensions over time), the spill hook is the natural place to pick the
instruction set that preserves the value correctly. The RA is not equipped
to reason about instruction-set byte-order semantics.

**PPE42 note:** PPE42 does not have VSX, so `updatedRC` is a no-op for
PPE42 (`hasVSX()` returns false). But the pattern is instructive: if PPE42
ever gained a second way to access VDR pairs with different byte semantics,
this is exactly where the correction would live.

---

## Reason 5 — Side-effects must be recorded on `PPCFunctionInfo`

```cpp
// PPCInstrInfo.cpp:1963
FuncInfo->setHasSpills();      // ← marks that at least one spill exists
FuncInfo->setSpillsCR();       // ← set if the spilled class is CRRCRegClass
FuncInfo->setHasNonRISpills(); // ← set if opcode is X-form (not D-form)
```

These three flags influence later passes:

| Flag | Effect |
|---|---|
| `setHasSpills()` | `prologepilog` knows it must compute a proper stack frame; some function-size optimisations are disabled |
| `setSpillsCR()` | The prologue/epilogue inserter reserves a GPR scratch slot for CR spill/restore |
| `setHasNonRISpills()` | The frame lowering may need to ensure a frame pointer (FP) is available because X-form spills use `rN + r1` addressing, which requires a scavenged register |

A raw `BuildMI` call emitted directly by the RA would never set these
flags. The prologue would be generated without the scratch slot, and the
function might crash or produce wrong values at runtime.

**PPE42 relevance:**

- `setHasSpills()` — applies to any PPE42 function with register pressure.
- `setHasNonRISpills()` — applies if a PPE42 spill overflows 16 bits
  (frame larger than 32 KB) and `eliminateFrameIndex` converts `STVD` to
  its X-form. That path fires `setHasNonRISpills()`, telling the frame
  lowering to preserve a GPR for index-form addressing.

---

## Summary

```
RA only knows:        What the target hook provides:
──────────────        ──────────────────────────────
  which vreg          → which opcode  (STVD, STW, SPILL_CR, …)
  which stack slot    → how many instructions  (1 for STVD, 3 for SPILL_CR)
  which reg class     → register class correction  (VRRC→VSRC byte-order fix)
                      → MachineMemOperand metadata  (alias/scheduler info)
                      → PPCFunctionInfo side-effects  (setHasSpills, setSpillsCR, …)
```

The RA is target-independent by design. It knows liveness, interference,
and priorities. It has no knowledge of instruction encodings, ISA
constraints, or frame-layout side-effects. The spill hook is the precise
boundary where target knowledge is injected.

---

## Quick reference — PPE42 spill path end to end

```
RA decides %vreg:vdrc must be spilled
    │
    ▼
InlineSpiller::insertSpill()   [InlineSpiller.cpp:1124]
    │   calls TII.storeRegToStackSlot(MBB, …, RC=VDRC, …)
    ▼
PPCInstrInfo::storeRegToStackSlot()   [PPCInstrInfo.cpp:1997]
    │   RC = updatedRC(RC)          → VDRC unchanged (no VSX on PPE42)
    │   calls storeRegToStackSlotNoUpd()
    ▼
PPCInstrInfo::StoreRegToStackSlot()   [PPCInstrInfo.cpp:1955]
    │   opcode = getStoreOpcodeForSpill(VDRC)
    │          = StoreSpillOpcodesArray[0 /*Pwr8/PPE42*/][SOK_VDRSpill]
    │          = PPC::STVD
    │   BuildMI(…, STVD).addReg(physReg).addFrameReference(FrameIdx)
    │   FuncInfo->setHasSpills()
    ▼
storeRegToStackSlotNoUpd() attaches MachineMemOperand(getFixedStack)
    ▼
MachineInstr:  STVD $r28_r29, 0, %stack.0   ← FrameIndex still abstract
    │
    ▼  (later, inside prologepilog)
PPCRegisterInfo::eliminateFrameIndex()       [PPCRegisterInfo.cpp:1699]
    │   ImmToIdxMap[STVD] = STVD (self-mapped, D-form fast-path)
    │   offset 16 fits in isInt<16> → patch imm in place
    ▼
MachineInstr:  STVD $r28_r29, 16, $r1       ← concrete "stvd d28, 16(r1)"
```

---

*Back: [Chapter 1 — LLVM Backend Concepts](ch1-llvm-backend-concepts.md)*  
*Related: [backend-pipeline-deep-dive.md](backend-pipeline-deep-dive.md) — Stage 5 (Register Allocation)*
