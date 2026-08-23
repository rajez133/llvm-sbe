# Why Virtual Registers Survive the Register Allocator

**Part of:** [backend-pipeline-deep-dive.md](backend-pipeline-deep-dive.md) — Stage 6  
**Source:** `llvm/lib/CodeGen/VirtRegMap.cpp` — `VirtRegRewriter::rewrite()`

---

## The apparent contradiction

After the greedy register allocator runs, every virtual register has been
assigned a physical register. Yet if you look at the `MachineInstr` dump
immediately after the `greedy` pass (in `-print-after-all` output), you
still see virtual register names like `%1:vdrc` and `%3:gprc`. Physical
registers do not appear until the *next* pass — `virtregrewriter`.

This seems wrong. Why doesn't the RA just patch the instructions as it
assigns registers?

---

## How assignment and patching are separated

The greedy RA maintains a side table called `VirtRegMap` — a flat array
from virtual register index to physical register:

```
VirtRegMap:
  %0 → $r3
  %1 → $r4_r5
  %2 → $r6_r7
  %3 → $r6
  …
```

`assignVirt2Phys` writes into this table:

```cpp
// VirtRegMap.cpp:86
void VirtRegMap::assignVirt2Phys(Register virtReg, MCRegister physReg) {
  Virt2PhysMap[virtReg] = physReg;
}
```

The table is populated incrementally as the RA processes live ranges. The
instructions are never touched during this process. At the end,
`virtregrewriter` does a single linear scan and patches every operand by
looking up `VRM->getPhys(VirtReg)`:

```cpp
// VirtRegMap.cpp:657
MCRegister PhysReg = VRM->getPhys(VirtReg);
// …
MO.setReg(PhysReg);   // patch the operand in place
```

---

## Three reasons the RA cannot patch instructions inline

### Reason 1 — The RA creates new virtual registers during live-range splitting

When the greedy RA cannot fit a live range, it *splits* it — cutting the
range at a convenient program point and inserting a `COPY` to reconnect
the two halves. Each half becomes a **new virtual register**. The new
virtual registers are then placed back into the RA's work queue and
allocated in subsequent iterations.

The key point: at the time the RA inserts the split `COPY`, the new
virtual registers do not yet have physical register assignments. The RA
cannot patch them into physical registers because the assignment for the
new vreg has not been decided yet.

```
Iteration 1:  RA processes %1:vdrc (live across 30 instrs)
              → cannot fit → splits at instruction 15
              → inserts:  %7:vdrc = COPY %1:vdrc   ← %7 is brand new
              → %1 now covers instrs 0–15, assigned $r4_r5
              → %7 goes back into the work queue

Iteration 2:  RA processes %7:vdrc (live across instrs 15–30)
              → assigned $r6_r7

Final state:  %1→$r4_r5, %7→$r6_r7
              Instructions still say %1 and %7
```

Only after both iterations complete is the mapping fully known. Then
`virtregrewriter` applies both assignments in one pass.

### Reason 2 — The RA's liveness analysis is still running

The greedy RA uses `LiveIntervals` to track which physical registers are
free at each program point. If the RA patched instructions inline as it
went, it would invalidate the `MachineOperand` register fields that
`LiveIntervals` uses to compute interference. The RA would be
simultaneously reading and corrupting its own input.

Deferring the rewrite to a separate pass cleanly separates the two
concerns: the RA works entirely in terms of virtual-register liveness
intervals, and `virtregrewriter` applies the final mapping after all
liveness information has been consumed.

### Reason 3 — Identity copies are only detectable after all assignments are final

When the RA splits a live range and both halves end up assigned the same
physical register (because the register became free again between the split
point and the next use), the inserted `COPY` becomes a no-op:

```
%1:vdrc  → assigned $r4_r5
%7:vdrc  → also assigned $r4_r5  (the register was free again)

COPY instruction:  %7:vdrc = COPY %1:vdrc
After rewrite:     $r4_r5  = COPY $r4_r5   ← identity copy, does nothing
```

These identity copies must be detected and removed. They cannot be
detected until all assignments are known, because the same virtual register
copy might be non-trivial if either side ends up on a different physical
register. `virtregrewriter` removes them after the full rewrite:

```cpp
// VirtRegMap.cpp:477
void VirtRegRewriter::handleIdentityCopy(MachineInstr &MI) {
  if (!MI.isIdentityCopy()) return;
  // Replace with KILL (to preserve liveness markers) or erase entirely.
  ++NumIdCopies;
}
```

---

## What `virtregrewriter::rewrite()` does

```
for every basic block:
  for every MachineInstr:
    for every MachineOperand:
      if not a virtual register → skip
      PhysReg = VRM->getPhys(VirtReg)       // look up assignment
      if SubReg != 0:
        PhysReg = TRI->getSubReg(PhysReg, SubReg)  // resolve sub-register
        add implicit super-register kill/def operands
        clear SubReg index (physregs cannot carry sub-reg indexes)
      MO.setReg(PhysReg)                    // patch in place
    handleIdentityCopy(MI)                  // remove $rN = COPY $rN
```

After the loop, `MRI->clearVirtRegs()` is called, and the
`MachineFunctionProperties::NoVRegs` flag is set — a hard assertion that
no virtual registers remain. Every pass that runs after this point can
assume all register operands are physical.

---

## PPE42 sub-register resolution in detail

PPE42 VDR registers are 64-bit pairs of consecutive GPRs. After ISel, an
instruction that needs only the hi half of a VDR pair writes:

```
%3:gprc = COPY %1:vdrc:sub_gpr_hi
```

The VirtRegMap records `%1 → $r4_r5` (the full VDR pair). The rewriter
encounters `sub_gpr_hi` on the operand and calls:

```cpp
// VirtRegMap.cpp:732
PhysReg = TRI->getSubReg(PhysReg, SubReg);
// TRI->getSubReg($r4_r5, sub_gpr_hi) → $r4
```

The result (`$r4`) replaces the operand, and the sub-register index is
cleared. The instruction becomes:

```
$r6 = COPY $r4
```

Without this sub-register resolution step, the MC encoder would receive an
operand that is nominally a physical register but still carries a
sub-register index — something the encoder cannot encode, and which would
trigger an assertion.

---

## Summary

| When | What is recorded | What is in the instructions |
|---|---|---|
| During greedy RA (iterations) | `VirtRegMap[%n] = $rX` filled incrementally | Virtual registers (`%1`, `%7`, …) |
| After all RA iterations complete | `VirtRegMap` fully populated | Still virtual registers |
| After `virtregrewriter` | `VirtRegMap` consumed and cleared | Physical registers only (`$r4`, `$r6`, …) |

The split is intentional: the RA is a complex iterative algorithm that
needs a stable, consistent view of liveness while it runs. Patching
instructions is deferred to a simple, final, one-shot pass that has no
analysis responsibilities of its own.

---

*Back: [backend-pipeline-deep-dive.md](backend-pipeline-deep-dive.md) — Stage 6*  
*Source: [`llvm/lib/CodeGen/VirtRegMap.cpp`](../llvm/llvm/llvm/lib/CodeGen/VirtRegMap.cpp)*
