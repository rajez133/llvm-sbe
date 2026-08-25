# PPE42 LLVM Backend — TODO List

Priority order: **Bug Fixes → New ISA Features → Optimisations → Cleanup**

---

## PRIORITY 1 — Bug Fixes (correctness of currently supported features)

### P1-A · Fix `LI8_VDR` pseudo expansion for arbitrary 64-bit immediates ✅ Done
**Status:** Fixed in patch 0009
**Risk:** High — the current expansion in `PPCInstrInfo.cpp` emits the ORI/ORIS
instructions in the wrong order for values where all four 16-bit slices are non-zero
(e.g., `0xDEADBEEFCAFEBABEULL` produces wrong output). Tested constants work by luck.  
**Action:** Rewrite `LI8_VDR` expansion to correctly handle all four slices:
```
LIS  rHi, imm[63:48]          # high 16 bits of high word
ORI  rHi, rHi, imm[47:32]     # low  16 bits of high word
LIS  rLo, imm[31:16]          # high 16 bits of low word
ORI  rLo, rLo, imm[15:0]      # low  16 bits of low word
```
Omit each instruction if the corresponding slice is zero.  
**Patch:** 0009

---

### P1-B · Replace accidental `OR8_VDR` path with explicit 32-bit OR lowering ✅ Done
**Status:** Fixed in patch 0010
**Risk:** Medium — when a 64-bit OR constant affects both the high and low word, the
DAG combine in patch 0005 falls through to the 64-bit OR path which selects `OR8_VDR`.
This works because RegisterTuples happen to alias to the right GPRs, but it is not
intentional and will break under register pressure or instruction scheduling changes.
**Action:** Extend the `ISD::OR` DAG combine in `PPCISelLowering.cpp` to explicitly
lower both-words constants to:
`EXTRACT_SUBREG hi → ORI/ORIS → INSERT_SUBREG` for each word independently.
**Patch:** 0009 (can be combined with P1-A)

---

### P1-C · Restrict GPR register class to the 16 PPE42 hardware registers ✅ Done
**Status:** Fixed in patches 0011 (AltOrder) + 0012 (reserved regs)
**Risk:** Real but only observable with register-pressure-heavy code (functions with
many live variables, many parameters, or complex loops). Current test cases fit
comfortably in the first 10 GPRs so the bug is not triggered yet. Needs a larger test
case first to verify the change is correct.
**Prerequisite:** Write a test that forces allocation of R11+ before implementing, so
the fix can be validated immediately.
**Action:** In `PPCRegisterInfo.td` (or a subtarget override), define a PPE42-specific
allocation order for `GPRC` limited to:
`R0, R1, R2, R3, R4, R5, R6, R7, R8, R9, R10, R13, R28, R29, R30, R31`
**Patch:** 0011 + 0012

---

### P1-D · Replace `G3Itineraries` with `NoItineraries` in the PPE42 processor definition ✅ Done
**Status:** Fixed in patch 0013
**Risk:** Medium — `G3Itineraries` describes a G3 (603) pipeline with a dedicated FPU
unit (`G3_FPU1`), two integer units (`G3_IU1`, `G3_IU2`), and FP instruction latencies.
None of these units exist on PPE42. The scheduler is fed a reservation table built for
a completely different microarchitecture, which can produce suboptimal instruction
ordering. This is not a correctness bug — wrong itineraries produce legal code — but it
is actively misleading and should be fixed before any scheduling work begins.
**Action:** Change `PPC.td` line 592 from:
```tablegen
def : Processor<"ppe42", G3Itineraries, [DirectivePPE42, FeatureMFTB, FeaturePPE42]>;
```
to:
```tablegen
def : Processor<"ppe42", NoItineraries, [DirectivePPE42, FeatureMFTB, FeaturePPE42]>;
```
`NoItineraries` is the correct declaration for a processor with no reservation table:
it explicitly bypasses the HazardRecognizer, which is both correct and marginally
faster to compile. Also remove `hasNoSchedulingInfo = 1` from `LVD`/`STVD` in
`PPCInstrPPEVD.td` since it is no longer needed once `NoItineraries` is set.
**Note:** Do not implement a full `PPE42Model` at this step — that is P2-H. This is
only removing the actively wrong G3 table.
**Patch:** 0013

---

### P1-E · Fix PPCAsmParser — register names without `%` prefix ✅ Not required
**Status:** Not needed — our assembly source (`startup.s`) uses `%rN` syntax
throughout, which is already fully supported. `llc -filetype=obj` compiles
LLVM IR directly to object code without going through `llvm-mc`, which is the
correct and standard pipeline. No parser fix is required.

---

## PRIORITY 2 — New ISA Features

### P2-A · Add PPE42-specific 64-bit shift/rotate instructions
**Status:** Missing
**ISA:** `rldicl`, `rldicr` (PPE42X), `slvd`, `srvd` (shift VDR left/right)
**Action:** Add to `PPCInstrPPEVD.td`. Add DAG patterns for shift/rotate on `MVT::i64`
when `isPPE42()`.
**Patch:** 0013

---

### P2-B · Verify all `i64` arithmetic operations expand correctly on PPE42
**Status:** Missing — no test coverage
**Background:** PPE42 makes `i64` a legal type via `VDRC`. Operations with no explicit
PPE42 instruction (add, subtract, multiply, divide, shifts by variable amount,
comparisons, bitwise AND/OR/XOR/NOT) fall back to the generic 32-bit pair expansion
already present in the `!isPPC64()` branch of `PPCISelLowering.cpp`. This fallback has
never been exercised on PPE42 — it may silently reach `Select()` as an unmatched DAG
node and trigger `llvm_unreachable`.
**Action:** Write a C test that exercises every `i64` operation class:
```c
uint64_t test_i64_arith(uint64_t a, uint64_t b) {
    uint64_t add  = a + b;
    uint64_t sub  = a - b;
    uint64_t mul  = a * b;
    uint64_t and  = a & b;
    uint64_t or_  = a | b;
    uint64_t xor_ = a ^ b;
    uint64_t not_ = ~a;
    uint64_t shl  = a << 3;
    uint64_t shr  = a >> 3;
    uint64_t sar  = (int64_t)a >> 3;
    return add ^ sub ^ mul ^ and ^ or_ ^ xor_ ^ not_ ^ shl ^ shr ^ sar;
}
```
Compile with `-mcpu=ppe42` and verify: (1) it compiles without `llvm_unreachable`,
(2) the output uses `ADDC`/`ADDE` for add, `SUBFC`/`SUBFE` for subtract, and
`RLWINM`/`ORI` pairs for constant shifts. Add explicit `setOperationAction(…, Expand)`
entries in `PPCISelLowering.cpp` for any operation that currently relies on implicit
fallback.
**Patch:** 0023

---

### P2-C · Add `lvdx` / `stvdx` (X-form indexed load/store)
**Status:** Missing
**Encoding:** opcode 31, extended opcode 519 (lvdx) / 647 (stvdx)
**Format:** `lvdx rT, rA, rB` — X-Form
**Action:** Add to `PPCInstrPPEVD.td` using `XForm_1_memOp`. Add DAG patterns for
indexed 64-bit load/store.
**Patch:** 0010

---

### P2-D · Add `lvdu` / `stvdu` (D-form update — base register updated after access)
**Status:** Missing
**Encoding:** same opcodes 5/6 but with a different sub-opcode or update field per ISA
**Format:** `lvdu rT, d(rA)` — rA updated to rA+d after load
**Action:** Add to `PPCInstrPPEVD.td`. Add DAG patterns for pre/post-increment loads.
**Patch:** 0010 (can be combined with P2-C)

---

### P2-E · Add `lsku` / `stsku` stack frame instructions
**Status:** Missing
**Importance:** High — these are the EABI stack frame manipulation instructions used
in function prologues and epilogues. Without them the backend falls back to standard
PPC `stwu`/`lwz` sequences which are less efficient and may not match the ABI exactly.
**Action:** Add instruction definitions. Hook into `PPCFrameLowering` to emit
`lsku`/`stsku` in prologue/epilogue when targeting PPE42.
**Patch:** 0011

---

### P2-F · Add fused compare-branch instructions (opcode 1)
**Status:** Missing
**ISA:** `bnbw`, `bnbwi`, `clrbwbc`, `clrbwibc`, `cmplwbc`, `cmpwbc`, `cmpwibc`
**Encoding:** opcode 1 (exclusive to PPE42, unused in standard PPC)
**Action:** Add instruction definitions in a new `PPCInstrPPEFusedBranch.td`.
Add a peephole / DAG combine pass to fuse `cmp` + `bc` sequences into the fused form.
**Patch:** 0012

---

### P2-G · Restrict condition register to CR0 only
**Status:** Missing
**ISA:** PPE42 has only CR0 (4 bits: LT, GT, EQ, SO). CR1–CR7 do not exist.
**Risk:** Medium — LLVM may allocate CR1–CR7 for boolean/comparison results.
**Action:** Override `CRRC` allocation order to only include `CR0` when `isPPE42()`.
Remove CR logical instructions from the PPE42 instruction set.
**Patch:** 0014

---

### P2-H · Add `dcbq` (cache query) instruction
**Status:** Missing
**Encoding:** opcode 31, extended opcode (per ISA manual)
**Action:** Add as a simple X-Form instruction with memory side-effect.
**Patch:** 0015

---

### P2-I · PPE42-specific instruction scheduler
**Status:** Missing
**ISA:** In-order pipeline, ALU=1 cycle, Branch=2 cycles, Load/Store=2+memory cycles
**Action:** Define a `PPE42Model` scheduling model. Add latency annotations to
LVD/STVD and the ALU instructions.
**Patch:** 0016

---

## PRIORITY 3 — Optimisations

These are code-quality improvements grounded in the actual assembly output currently
generated from `test.c`. Each one is a real instruction saving verified against the
disassembly in `appsource/output/test_c/`.

---

### OPT-A · `lis rX, V` + `or rD, rD, rX` → `oris rD, rD, V` (save 1 instruction + 1 temp register)
**Where it fires:** Test case 4, high-word OR (`value2 |= 0x1234000000005678`)
**Current output:**
```asm
lis r6, 4660          # r6 = 0x12340000
or  r4, r4, r6        # r4 |= 0x12340000
```
**Optimised:**
```asm
oris r4, r4, 0x1234   # r4 |= 0x12340000  (1 instruction, r6 not needed)
```
**Rule:** When the constant has zeros in bits [15:0], `lis + or` into a temp register
is always replaceable by `oris` directly into the destination. This is the exact mirror
of the existing single-word OR optimisation (patch 0005) which already handles
`oris`/`ori` for constants where only one 16-bit slice is non-zero. This case is a
16-bit constant shifted left 16 — it should be folded in the same DAG combine.
**Action:** Extend the `ISD::OR` DAG combine in `PPCISelLowering.cpp`: after checking
`ImmHi != 0 && ImmLo == 0`, also check whether `ImmHi` fits in 16 bits (i.e.,
`ImmHi & 0xFFFF == 0`, meaning only the upper 16 bits of the high word are set). If so
emit `oris rD, rD, ImmHi >> 16` directly. The current code emits `lis + or` for this
sub-case.
**Patch:** 0018

---

### OPT-B · `lis rX, -1` + `ori rX, rX, 65535` → `li rX, -1` ✅ Done
**Status:** Fixed in patch 0009
**Where it fires:** `LI8_VDR` expansion for the constant `-1` (used in `rldimi` for
test case 3)
**Current output (inside `LI8_VDR -1` expansion):**
```asm
li  r7, -1            # r7 = 0xFFFFFFFF  ✓  (sign-extension correct)
lis r6, -1            # r6 = 0xFFFF0000
ori r6, r6, 65535     # r6 = 0xFFFFFFFF  — wasted: same as li r6, -1
```
**Optimised:**
```asm
li  r7, -1            # r7 = 0xFFFFFFFF
li  r6, -1            # r6 = 0xFFFFFFFF  (1 instruction instead of 2)
```
**Rule:** When all 32 bits of a word are 1 (value = `0xFFFFFFFF`), `lis -1 / ori rX,rX,65535`
is equivalent to `li -1` because `li` sign-extends a 16-bit `-1` to `0xFFFFFFFF`.
`LI8_VDR` already emits `li` for the low-word slice but uses `lis + ori` for the
high-word slice — this asymmetry is a bug in the expansion logic.
**Action:** In the `LI8_VDR` expansion in `PPCInstrInfo.cpp`, after splitting the
64-bit immediate into `ImmHi` / `ImmLo`, check if the full 32-bit word equals
`0xFFFFFFFF`. If so emit `li rX, -1` instead of `lis + ori`.
**Patch:** 0009 (combine with P1-B fix)

---

### OPT-C · Remove redundant `oris rX, rX, 65535` after `li rX, -1` ✅ Done
**Status:** Fixed in patch 0009 (automatic consequence of OPT-B)
**Where it fires:** `LI8_VDR -1` expansion — the `oris` for the lower 16 bits of the
high word is emitted even though `li rX, -1` already produced `0xFFFFFFFF`
**Current output:**
```asm
li  r7, -1            # r7 = 0xFFFFFFFF
lis r6, -1
ori r6, r6, 65535
oris r7, r7, 65535    # no-op: 0xFFFFFFFF | (0xFFFF << 16) = 0xFFFFFFFF — redundant
```
**Rule:** The `LI8_VDR` expansion emits `oris rLo, rLo, (ImmHi & 0xFFFF)` to fill in
bits [47:32] of the low register. For the value `-1`, `ImmHi & 0xFFFF = 0xFFFF`, so
this generates `oris r7, r7, 65535`. But `r7` already holds `0xFFFFFFFF` from
`li r7, -1` — ORing in `0xFFFF0000` is a no-op.
**Root cause:** The current `LI8_VDR` expansion checks `(ImmLo >> 16) != 0` to decide
whether to emit `oris rLo`, but this check is performed on the raw 32-bit slice before
detecting that the full word is already `0xFFFFFFFF`. Fix OPT-B first; OPT-C becomes
automatic when the whole-word `-1` check is in place.
**Patch:** 0009 (automatic consequence of OPT-B)

---

### OPT-D · Peephole: eliminate `ORIS`/`ORI` no-ops on known-value registers
**Where it fires:** General case — any `ori rX, rX, 0` or `oris rX, rX, 0` is a no-op.
**Action:** Add a PPE42-specific peephole pass (or extend the existing
`PPCMIPeephole`) to remove zero-immediate OR instructions. This catches cases where
constant folding partially resolves but leaves a zero-immediate OR in the instruction
stream.
**Patch:** 0019

---

### OPT-E · Fold `ori rX, rBase, N` + `lvd/stvd D(rX)` → `lvd/stvd (D+N)(rBase)`
**Where it fires:** Any time two pointer values share a common `lis`-materialised base
and the compiler computes a closer base register via `ori` before applying a small
D-form offset — instead of folding the full offset back to the original base.
**Concrete example from current output** (`addr1=0x50008`, `addr2=0x50009`, `r3=0x50000`):
```asm
; Current (3 instructions for each addr2 access):
ori  r4, r3, 8     ; r4 = 0x50008
lvd  d5, 1(r4)     ; EA = 0x50009  ← r4 used as base, D=1
stvd d5, 1(r4)     ; EA = 0x50009

; Optimal (2 instructions — ori eliminated, r4 freed):
lvd  d5, 9(r3)     ; EA = 0x50009  ← r3 used directly, D=9
stvd d5, 9(r3)     ; EA = 0x50009
```
**Why it is valid:** The LVD/STVD D-form field is a signed 16-bit immediate
(`-32768..+32767`). `D=9` is well within range. `r3` is already live (from
`lis r3, 5`). The `ori` computes `r4 = r3 | 8 = 0x50008`, then the load uses
`1(r4)` — but `r3 + 9` reaches the same effective address in one step.
**Root cause:** The DAG instruction selector address-matching pattern anchors on the
most recently computed base register (`r4 = ori r3, 8`) and applies the residual
offset (`D=1`). It does not look back through the `ori` to the original `lis` base
to check whether `D_total = ori_imm + D_residual` still fits in 16 bits and would
eliminate the `ori` entirely.
**Action:** In `PPCISelDAGToDAG.cpp`, extend the `SelectAddrImm` / `tryAddressMode`
logic for PPE42 to look through a single `ori rX, rBase, N` when selecting the
D-form base/offset for LVD/STVD: if `N + D_residual` fits in a signed 16-bit field,
use `rBase` as the base register and `N + D_residual` as `D`. This is safe because
`ori` with a zero upper half is a pure add when `rBase` upper 16 bits are zero (which
is guaranteed when `rBase` was produced by `lis`).
**Saves:** 1 instruction + 1 live register per LVD/STVD access that currently goes
through an `ori`-computed intermediate base.
**Patch:** 0020

---

## PRIORITY 4 — Cleanup

### P4-A · Gate `ppc-asm-full-reg-names` behind `isPPE42()` flag ✅ Done
**Status:** Fixed in patch 0015. Reverted `cl::init(true)` to `cl::init(false)` in
`PPCInstPrinter.cpp`. Test scripts now pass `-ppc-asm-full-reg-names` explicitly to
`llc` invocations that generate assembly for inspection.
**Patch:** 0015

---

### P4-B · Squash patches 0001, 0002, 0004 in git history (VDR design churn)
**Status:** Patch 0002 added `VD31` as a custom register class definition. Patch 0004
completely replaced the custom VDR class with `RegisterTuples`, removing `VD31` and
all other `VDN` symbols — `VD31`'s wrap-around concern is a non-issue in the tuple
design since `R31_R0` is a valid first-class tuple. Patches 0001 + 0002 are
intermediate states that no longer represent the architecture.

> **Verification:** `isVDRRegNumber()` range `0 || 2–9 || 28–31` in the asm parser IS
> still correct and needed (index 31 maps to the `R31_R0` tuple). Only the register
> *class* definition was replaced — the parser range is correct as-is.

**Action:** Rebase / squash patches 0001, 0002, 0004 into a single clean patch:
`0001-Add-PPE42-VDR-registers-and-LVD-STVD-instructions.patch`
This eliminates the intermediate broken state from CI history.  
**Patch:** git history rebase, no LLVM code change

---

### P4-C · Move explicit OR lowering strategy into a code comment
Now that P1-B is done and the both-words OR path is explicit, add a comment in
`PPCISelLowering.cpp` explaining the deliberate lowering strategy.
**Patch:** Part of 0010

---

## Summary Table

| ID     | Description                                        | Priority    | Patch  |
|--------|----------------------------------------------------|-------------|--------|
| P1-A   | Fix `LI8_VDR` 64-bit immediate expansion           | ✅ Done     | 0009   |
| P1-B   | Explicit 64-bit OR lowering (remove OR8_VDR)       | ✅ Done     | 0010   |
| P1-C   | Restrict GPR class to 16 PPE42 registers           | ✅ Done     | 0011+0012 |
| P1-D   | Replace `G3Itineraries` with `NoItineraries`       | ✅ Done     | 0013   |
| P1-E   | PPCAsmParser `rN` without `%` — not required       | ✅ N/A      | —      |
| P2-A   | 64-bit shift/rotate (`slvd`, `srvd`, `rldicl`)     | 🟡 Medium   | 0013   |
| P2-B   | Verify all `i64` arithmetic ops expand correctly   | 🔴 High     | 0023   |
| P2-C   | Add `lvdx` / `stvdx` indexed instructions          | 🟡 High     | 0010   |
| P2-D   | Add `lvdu` / `stvdu` update instructions           | 🟡 High     | 0010   |
| P2-E   | Add `lsku` / `stsku` stack frame instructions      | 🟡 High     | 0011   |
| P2-F   | Fused compare-branch (opcode 1)                    | 🟡 Medium   | 0012   |
| P2-G   | Restrict CR to CR0 only                            | 🟡 Medium   | 0014   |
| P2-H   | Add `dcbq` cache query instruction                 | 🟢 Low      | 0015   |
| P2-I   | PPE42 scheduling model                             | 🟢 Low      | 0016   |
| OPT-A  | `lis+or` → `oris` (high-word constant, 1 insn)     | 🟠 Medium   | 0018   |
| OPT-B  | `lis -1 + ori` → `li -1` in LI8_VDR expansion     | ✅ Done     | 0009   |
| OPT-C  | Remove redundant `oris` after `li -1` (auto)       | ✅ Done     | 0009   |
| OPT-D  | Peephole: remove zero-immediate ORI/ORIS no-ops    | 🟢 Low      | 0019   |
| OPT-E  | Fold `ori+lvd/stvd` → `lvd/stvd (D+N)(rBase)`     | 🟠 Medium   | 0020   |
| P4-A   | Gate full register names behind isPPE42()          | 🔵 Cleanup  | 0017   |
| P4-B   | Squash patches 0001+0002+0004 in git history       | 🔵 Cleanup  | rebase |
| P4-C   | Comment explicit OR lowering strategy              | 🔵 Cleanup  | 0010   |

---

## PRIORITY 5 — LLVM Unit / Integration Tests (lit + FileCheck)

> Deferred until the team is familiar with the LLVM `lit` / FileCheck workflow.  
> All tests live under `llvm/test/CodeGen/PowerPC/` and are run with:
> ```
> llvm-lit llvm/test/CodeGen/PowerPC/ppe42-*.ll
> ```

---

### TEST-A · `LI8_VDR` immediate materialisation (`ppe42-li8-vdr-imm.ll`)

Verify the post-RA expander picks the minimal instruction sequence for every
significant class of 64-bit immediate value:

| Case | Immediate (hex) | High word | Low word | Expected sequence |
|------|-----------------|-----------|----------|-------------------|
| All slices non-zero | `0xDEADBEEFCAFEBABE` | `LIS+ORI` | `LIS+ORI` | 4 instructions |
| Hi word fits in 15-bit | `0x0000000500DEADBE` | `LI 5` | `LIS+ORI` | 3 instructions |
| Lo word fits in 15-bit | `0xDEADBEEF00000003` | `LIS+ORI` | `LI 3` | 3 instructions |
| Both words fit in 15-bit | `0x0000000500000007` | `LI 5` | `LI 7` | 2 instructions |
| Hi16==0, Lo16 bit15 set | `0x0000000000008000` | zero word | `LIS 0`+`ORI 32768` | must NOT use `LI` |
| All zeros | `0x0000000000000000` | `LI 0` | `LI 0` | 2 instructions |
| All ones (`-1`) | `0xFFFFFFFFFFFFFFFF` | `LI -1` | `LI -1` | 2 instructions |

**Covers fixes:** P1-A, P1-B (sign-extension guard), OPT-B  
**Patch:** 0009 / future

---

### TEST-B · `LVD` / `STVD` load-store (`ppe42-lvd-stvd.ll`)

- 64-bit load from aligned memory address → `lvd dX, D(rA)`
- 64-bit store to aligned memory address → `stvd dX, D(rA)`
- D-form displacement range (0, positive, negative, boundary ±32767)
- Verify only valid VDR registers (`d0`, `d2–d9`, `d28–d31`) appear in output
- Confirm LVD / STVD are NOT selected on plain `powerpc-unknown-linux-gnu`
  (i.e., feature-gated behind `-mcpu=ppe42`)

---

### TEST-C · `OR8_VDR` 64-bit OR expansion (`ppe42-or8-vdr.ll`)

- Only high word affected (e.g. `0x8000000000000000`) → single `oris`
- Only low word affected (e.g. `0x0000000000008000`) → single `ori`
- Both words affected (e.g. `0x1234000000005678`) → `oris` + `ori`
- Constant with contiguous 1-bits (e.g. `0x00000003FF000000`) → `rldimi`
- Verify the two-word expansion produces correct sub-register assignments
  (`sub_gpr_hi` / `sub_gpr_lo`)

---

### TEST-D · `RLDIMI_VDR` rotate-and-insert (`ppe42-rldimi.ll`)

- Correct `SH` / `MBE` encoding for various mask widths and positions
- Boundary cases: full-word mask (all bits set), single-bit mask
- Verify `RLDIMI_VDR` is NOT emitted on plain PPC32

---

### TEST-E · VDR register allocation (`ppe42-regalloc.ll`)

- Verify only valid VDR pairs are allocated (`d0`, `d2–d9`, `d28–d31`)
- Verify `sub_gpr_hi` / `sub_gpr_lo` sub-register indices are assigned correctly
- Write a register-pressure test that forces allocation of `d8`/`d9`/`d28+`
  to validate P1-C (restrict GPR class to 16 hardware registers)

---

### TEST-F · PPE42 subtarget feature isolation (`ppe42-feature-guard.ll`)

- Confirm PPE42-only pseudos (`LI8_VDR`, `OR8_VDR`, `RLDIMI_VDR`, `LVD`, `STVD`)
  are NOT selected when targeting `powerpc-unknown-linux-gnu` (no `-mcpu=ppe42`)
- Confirm `-mcpu=ppe42` enables the feature and selects the correct instructions
- Confirm correct triple: `powerpc-unknown-linux-gnu` + `-mcpu=ppe42`

---

### Summary — Test TODOs

| ID | Test file | Covers |
|----|-----------|--------|
| TEST-A | `ppe42-li8-vdr-imm.ll` | P1-A, P1-B, OPT-B, OPT-C |
| TEST-B | `ppe42-lvd-stvd.ll` | LVD/STVD correctness, feature gating |
| TEST-C | `ppe42-or8-vdr.ll` | OR8_VDR expansion, all constant classes |
| TEST-D | `ppe42-rldimi.ll` | RLDIMI_VDR encoding |
| TEST-E | `ppe42-regalloc.ll` | VDR register allocation, P1-C prerequisite |
| TEST-F | `ppe42-feature-guard.ll` | Subtarget isolation |
