# TableGen `.td` Syntax — A Deep Dive

**Part of:** [Chapter 1 — LLVM Backend Concepts](ch1-llvm-backend-concepts.md)  
**Reference:** [backend-pipeline-deep-dive.md](backend-pipeline-deep-dive.md)

---

## Purpose

After reading this document you will be able to:

1. Read any `def` in any `.td` file and understand every token — what it does, where it comes from, and what code it generates.
2. Trace a `def` from its class hierarchy all the way to the `bits<32> Inst` encoding and the C++ pattern-matching code.
3. Write a new instruction definition for the PPE42 backend without guessing.

The entire document uses `def LVD` as the running example because it is the simplest real PPE42 instruction and touches every concept.

---

## 0 — What TableGen is

TableGen is a **domain-specific language** that compiles `.td` files into C++ code. You write a description once; TableGen generates:

| Generated file | What it contains |
|---|---|
| `PPCGenInstrInfo.inc` | `enum` of all opcodes, `MCInstrDesc` tables |
| `PPCGenDAGISel.inc` | The giant `Select()` switch — pattern → opcode matching |
| `PPCGenAsmWriter.inc` | `printInstruction()` — opcode → assembly string |
| `PPCGenDisassemblerTables.inc` | `decodeInstruction()` — bits → opcode |
| `PPCGenRegisterInfo.inc` | Register class tables, allocation orders |

You never edit these `.inc` files directly. The `.td` files are the single source of truth.

---

## 1 — The `def` statement and `class` hierarchy

The top-level statement is:

```tablegen
def LVD : DForm_1<5, (outs vdrc:$RST), (ins (memri $D, $RA):$src),
                  "lvd $RST, $src", IIC_LdStLoad,
                  [(set i64:$RST, (load iaddr:$src))]> {
  let hasNoSchedulingInfo = 1;
  let DecoderNamespace = "PPE42";
}
```

`def LVD` creates a **concrete record** called `LVD` that is an instance of the class `DForm_1`. The angle brackets `<…>` pass template parameters to the class. The braces `{…}` override specific fields of the resulting record.

Think of it as:

```
class DForm_1 is a template
def LVD      is "new DForm_1(5, …)" — a filled-in instance
```

---

## 2 — The class hierarchy

Understanding `DForm_1` requires following the inheritance chain. Every indentation is "inherits from":

```
Instruction             ← built-in LLVM TableGen base class
  └── I                 ← PPCInstrFormats.td:13  — base for all 32-bit PPC instrs
        └── DForm_base  ← PPCInstrFormats.td:242 — D-form bit layout (RST/RA/D)
              └── DForm_1 + MemriOp  ← PPCInstrFormats.td:256,89
                    └── LVD         ← PPCInstrPPEVD.td:23 — the concrete instruction
```

Let's read each level.

### Level 1 — `Instruction` (LLVM built-in)

`Instruction` is defined in `llvm/include/llvm/Target/Target.td`. It provides the fundamental fields that every instruction must have:

```tablegen
class Instruction {
  string Namespace;           // e.g. "PPC"
  dag    OutOperandList;      // output operands (outs)
  dag    InOperandList;       // input operands  (ins)
  string AsmString;           // assembly text template
  list<dag> Pattern;          // DAG patterns for ISel
  // … ~30 more fields (isReturn, isBranch, isPseudo, …)
}
```

You never touch `Instruction` directly; you always go through a target-specific base like `I`.

### Level 2 — `class I` ([`PPCInstrFormats.td:13`](../llvm/llvm/llvm/lib/Target/PowerPC/PPCInstrFormats.td:13))

```tablegen
class I<bits<6> opcode, dag OOL, dag IOL, string asmstr, InstrItinClass itin>
        : Instruction {
  field bits<32> Inst;       // the 32-bit encoding
  field bits<32> SoftFail = 0;
  let Size = 4;              // 4 bytes per instruction

  let Namespace = "PPC";
  let Inst{0-5} = opcode;   // bits 0–5 are the major opcode
  let OutOperandList = OOL;
  let InOperandList  = IOL;
  let AsmString = asmstr;
  let Itinerary = itin;

  bits<1> MemriOp = 0;      // overridden by MemriOp mixin
  let TSFlags{10} = MemriOp; // stored in MCInstrDesc::TSFlags bit 10
  // … TSFlags for PPC970 scheduling groups, XFormMemOp, Prefixed, etc.
}
```

The crucial line is `field bits<32> Inst`. This is the **32-bit instruction word**. Each subclass fills in different bit ranges of `Inst`. `class I` fills bits 0–5 with the major opcode.

`TSFlags` is a 64-bit flags word stored on every `MCInstrDesc` at runtime. Bit assignments here correspond directly to the `TSFlags` checks in C++ — e.g. `PPCInstrInfo::isXFormMemOp(opcode)` reads `TSFlags{6}`.

### Level 3 — `class DForm_base` ([`PPCInstrFormats.td:242`](../llvm/llvm/llvm/lib/Target/PowerPC/PPCInstrFormats.td:242))

```tablegen
class DForm_base<bits<6> opcode, dag OOL, dag IOL, string asmstr,
                 InstrItinClass itin, list<dag> pattern>
  : I<opcode, OOL, IOL, asmstr, itin> {
  bits<5>  RST;   // destination or source register (5 bits → 32 regs)
  bits<5>  RA;    // base address register
  bits<16> D;     // signed 16-bit displacement

  let Pattern = pattern;

  let Inst{6-10}  = RST;   // register field
  let Inst{11-15} = RA;    // base register field
  let Inst{16-31} = D;     // displacement field
}
```

This is the **D-form instruction layout** from the PowerPC architecture specification:

```
 bits: 31         26 25    21 20   16 15              0
       ┌────────────┬────────┬───────┬────────────────┐
       │   opcode   │  RST   │  RA   │       D        │
       │   [0–5]    │ [6–10] │[11–15]│   [16–31]      │
       └────────────┴────────┴───────┴────────────────┘
```

The three fields `RST`, `RA`, `D` are declared as `bits<N>` **member variables**. When an instance is created and operands are bound (during ISel or assembly parsing), these variables get the actual register numbers and immediate value, and the `let Inst{…} = …` lines pack them into the right bit positions of the 32-bit word.

### Level 4 — `class DForm_1` + `class MemriOp` ([`PPCInstrFormats.td:256`](../llvm/llvm/llvm/lib/Target/PowerPC/PPCInstrFormats.td:256), [`PPCInstrFormats.td:89`](../llvm/llvm/llvm/lib/Target/PowerPC/PPCInstrFormats.td:89))

```tablegen
class MemriOp { bits<1> MemriOp = 1; }   // PPCInstrFormats.td:89

class DForm_1<bits<6> opcode, dag OOL, dag IOL, string asmstr,
              InstrItinClass itin, list<dag> pattern>
  : DForm_base<opcode, OOL, IOL, asmstr, itin, pattern>, MemriOp {
}
```

`DForm_1` adds nothing new except **mixing in `MemriOp`**. This sets the `MemriOp` bit to 1, which propagates to `TSFlags{10}` via the assignment in `class I`. In C++, `PPCInstrInfo` queries this flag to know which instructions take a register+immediate memory operand (used in `eliminateFrameIndex`).

The `,` in `: DForm_base<…>, MemriOp` is **multiple inheritance** in TableGen — the record gets fields from both parents.

---

## 3 — The `def LVD` parameters, one by one

```tablegen
def LVD : DForm_1<
    5,                              // ① opcode
    (outs vdrc:$RST),               // ② output operand list
    (ins (memri $D, $RA):$src),     // ③ input operand list
    "lvd $RST, $src",               // ④ assembly string template
    IIC_LdStLoad,                   // ⑤ itinerary class
    [(set i64:$RST, (load iaddr:$src))]  // ⑥ DAG pattern
> {
  let hasNoSchedulingInfo = 1;      // ⑦ field overrides
  let DecoderNamespace = "PPE42";   // ⑧
}
```

### ① `5` — Major opcode

This is the 6-bit major opcode placed at `Inst{0-5}` by `class I`. In the PPE42 architecture specification, opcode 5 is assigned to `lvd`. Opcode 6 is `stvd`.

```
Inst[31:26] = 0b000101 = 5
```

### ② `(outs vdrc:$RST)` — Output operand list

`outs` and `ins` are special DAG operators that build the `OutOperandList` / `InOperandList` fields. The general form of one entry is:

```
regclass_or_type : $variable_name
```

- **`vdrc`** is a `RegisterOperand` — a named wrapper around the `VDRC` register class:

  ```tablegen
  // PPCRegisterInfo.td:663
  def vdrc : RegisterOperand<VDRC> {
    let ParserMatchClass = PPCRegVDRCAsmOperand;
    let PrintMethod = "printVDRCOperand";
  }
  ```

  `VDRC` is the register class holding VDR pairs (consecutive even–odd GPR pairs):

  ```tablegen
  // PPCRegisterInfo.td:175
  def VDRC : RegisterClass<"PPC", [i64], 64, (add VDRTuples)>;
  //                        ^ns   ^types ^align ^members
  ```

  The `[i64]` means VDRC holds values of type `i64`. The 64-bit alignment means a VDR pair must be aligned to a 64-bit boundary in memory when spilled.

- **`$RST`** is the **operand variable name**. Everywhere `$RST` appears in the assembly string or in the `Inst` bit assignments, it refers to this operand. `bits<5> RST` in `DForm_base` gets the register number from this operand.

### ③ `(ins (memri $D, $RA):$src)` — Input operand list

This deserves careful reading — there is nesting here.

```
(ins  (memri $D, $RA):$src  )
       ^compound operand^ ^name^
```

`memri` is a **compound memory operand** defined in [`PPCRegisterInfo.td:1024`](../llvm/llvm/llvm/lib/Target/PowerPC/PPCRegisterInfo.td:1024):

```tablegen
def memri : Operand<iPTR> {
  let PrintMethod = "printMemRegImm";
  let MIOperandInfo = (ops dispRI:$imm, ptr_rc_nor0:$reg);
  let OperandType = "OPERAND_MEMORY";
}
```

`MIOperandInfo = (ops dispRI:$imm, ptr_rc_nor0:$reg)` means `memri` **expands into two sub-operands** in the `MachineInstr`:
- `dispRI:$imm` — a signed 16-bit displacement (encoded in `D`)
- `ptr_rc_nor0:$reg` — a base register (encoded in `RA`; the `nor0` means R0 is not valid as a base)

The syntax `(memri $D, $RA):$src` binds the two sub-fields `$D` and `$RA` to the `bits<16> D` and `bits<5> RA` encoding variables in `DForm_base`, while naming the whole compound operand `$src` for use in the assembly string.

So in the `MachineInstr`, a `LVD` has **3 operands** (not 2):
```
%dest:vdrc = LVD  imm:D,  reg:RA
              ^sub-op1^  ^sub-op2^
```

### ④ `"lvd $RST, $src"` — Assembly string template

The `$name` variables are substituted when the instruction printer calls `printInstruction()`. The printer generates code from this string:

- `$RST` → calls `printVDRCOperand()` (from `vdrc.PrintMethod`) → emits e.g. `d4`
- `$src` → calls `printMemRegImm()` (from `memri.PrintMethod`) → emits e.g. `8(r4)`

Result: `lvd d4, 8(r4)`

### ⑤ `IIC_LdStLoad` — Instruction itinerary class

```tablegen
// PPCSchedule.td:40
def IIC_LdStLoad : InstrItinClass;
```

`InstrItinClass` is an empty marker class. It identifies this instruction's **scheduling latency class**. Each `Processor` definition maps `IIC_LdStLoad` to a concrete latency via an `InstrItinData` record. PPE42 uses `G3Itineraries` and `IIC_LdStLoad` maps to a 2-cycle load latency in that table.

When `hasNoSchedulingInfo = 1` is set (see ⑦), the scheduler ignores this field entirely for the specific instruction — but the field must still be present because `class I` requires it as a template argument.

### ⑥ `[(set i64:$RST, (load iaddr:$src))]` — DAG selection pattern

This is the core of instruction selection. The list contains one or more **DAG patterns**. A pattern is a tree that describes a DAG subtree to match and the output to produce.

```
(set i64:$RST,        ← bind result to $RST, type-check it as i64
  (load              ← match an ISD::LOAD node
    iaddr:$src))     ← whose address matches the iaddr complex pattern
```

**`set`** is a special DAG node meaning "the output of this instruction". It is not a real SDNode — it tells the pattern engine that the matched subtree produces a value that goes into `$RST`.

**`i64:$RST`** type-annotates the result: the matcher rejects this pattern unless the load's value type is `i64`. This is how `LVD` is kept from matching a 32-bit `LWZ` situation.

**`load`** matches `ISD::LOAD` nodes. DAG patterns use `ISD::` node names written in lowercase without the prefix: `ISD::LOAD` → `load`, `ISD::OR` → `or`, `ISD::ADD` → `add`.

**`iaddr`** is a **ComplexPattern** — a C++ function that decides whether a DAG address node matches:

```tablegen
// PPCInstrInfo.td:686
def iaddr : ComplexPattern<iPTR, 2, "SelectAddrImm", [], []>;
//                         ^type ^nresults ^C++ fn
```

When the pattern engine reaches the address node, it calls `SelectAddrImm()` in `PPCISelDAGToDAG.cpp`. That function tries to decompose the address into `(base_reg, imm16)`. If successful it returns 2 results (bound to `$D` and `$RA`); if not, the pattern fails and the engine tries the next candidate.

**How the generated code uses this:**  
TableGen compiles the pattern into a case inside `PPCGenDAGISel.inc`. During `PPCDAGToDAGISel::Select()`, when the engine sees an `ISD::LOAD` node whose value type is `i64` and whose address matches `iaddr`, it emits `PPC::LVD` with the matched operands. No hand-written C++ needed.

---

## 4 — The `{…}` body — field overrides

```tablegen
def LVD : DForm_1<…> {
  let hasNoSchedulingInfo = 1;
  let DecoderNamespace = "PPE42";
}
```

`let field = value;` inside a `def` body **overrides** a field that was set by a parent class. This is TableGen's assignment operator for record fields.

**`hasNoSchedulingInfo = 1`**  
Tells the scheduler to emit no scheduling information for this instruction. LVD does not have a corresponding entry in the PPE42 itinerary tables, so rather than emitting a default 1-cycle assumption (which could mislead the scheduler), we declare it absent. In `debug-all-passes.txt` you will see `! No itinerary` for `LVD`.

**`DecoderNamespace = "PPE42"`**  
Groups the instruction into the `PPE42` disassembler namespace. The disassembler generator creates a separate `decodeToMCInst_PPE42()` function for all instructions that share this namespace. This is necessary because opcode 5 (`LVD`) conflicts with opcode 5 of another PPC instruction in the default namespace — the namespace separation resolves the ambiguity.

---

## 5 — The complete bit encoding

Putting all levels together, here is exactly how a `LVD d4, 8(r4)` is encoded:

```
Instruction:  lvd d4, 8(r4)
               ↓
Operands:  RST = d4 = VD_R4_R5  → sub_gpr_hi = R4 → encoding 4 (0b00100)
           RA  = r4              → encoding 4 (0b00100)
           D   = 8               → encoding 8 (0b0000000000001000)

Bit layout (PowerPC bit 0 = MSB):
 31    26 25  21 20  16 15              0
 ┌───────┬──────┬──────┬────────────────┐
 │ 00101 │00100 │00100 │0000000000001000│
 │  op=5 │ d4=4 │ r4=4 │      D=8      │
 └───────┴──────┴──────┴────────────────┘

Binary: 0000 1010 0010 0100 0000 0000 0000 1000
Hex:    0x0A240008
```

The encoder method in `PPCMCCodeEmitter.cpp` fills this in by reading the operand values and packing them according to the `Inst{…}` assignments defined in the class hierarchy.

---

## 6 — How the `let … in { … }` block works (RLDIMI_VDR and LI8_VDR)

The `LVD` def stands alone, but two other instructions in `PPCInstrPPEVD.td` use a `let … in { … }` block:

```tablegen
// PPCInstrPPEVD.td:46
let hasSideEffects = 0, Predicates = [IsPPE42] in {
def RLDIMI_VDR : MDForm_1<…>;
}

// PPCInstrPPEVD.td:61
let isReMaterializable = 1, Predicates = [IsPPE42] in {
def LI8_VDR : PPCPostRAExpPseudo<…>;
}
```

`let field = value in { defs… }` is a **scope**: it applies the field assignments to every `def` inside the braces without making each `def` repeat them. It is equivalent to adding `let hasSideEffects = 0;` and `let Predicates = [IsPPE42];` inside every `def` in the block.

**`Predicates = [IsPPE42]`** is the most important one here. It links the instruction to a runtime predicate:

```tablegen
// PPCInstrInfo.td:736
def IsPPE42 : Predicate<"Subtarget->isPPE42()">;
```

`Predicate<"…">` contains a C++ boolean expression. The ISel pattern engine wraps the generated match code with:

```cpp
if (Subtarget->isPPE42()) {
    // try LI8_VDR pattern…
}
```

Without `Predicates = [IsPPE42]`, `LI8_VDR` could match on any PPC target, which would be wrong — only PPE42 has the VDR register class.

---

## 7 — Pseudo-instructions: `PPCPostRAExpPseudo`

`LI8_VDR` and `OR8_VDR` inherit from `PPCPostRAExpPseudo` instead of `DForm_1`:

```tablegen
// PPCInstrFormats.td:2381
class PPCPostRAExpPseudo<dag OOL, dag IOL, string asmstr, list<dag> pattern>
    : PPCEmitTimePseudo<OOL, IOL, asmstr, pattern> {
  let isPseudo = 1;
}

class PPCEmitTimePseudo<dag OOL, dag IOL, string asmstr, list<dag> pattern>
    : I<0, OOL, IOL, asmstr, NoItinerary> {
  let isCodeGenOnly = 1;
  let Inst{31-0} = 0;      // no real encoding — all zeros
  let hasNoSchedulingInfo = 1;
}
```

Key differences from a real instruction:

| Field | Real instruction (`LVD`) | Pseudo (`LI8_VDR`) |
|---|---|---|
| `Inst{…}` | Real bit encoding | All zeros |
| `isPseudo` | 0 | **1** |
| `isCodeGenOnly` | 0 | **1** — never in final `.o` |
| `opcode` (arg 1 of `I`) | 5 | **0** — no major opcode |
| `asmstr` | `"lvd $RST, $src"` | `"#LI8_VDR"` (prefixed `#` = not emitted) |

`isPseudo = 1` tells the backend that this instruction **must be expanded** before assembly emission. The expansion happens in `PPCInstrInfo::expandPostRAPseudo()`, which is called by the generic `postrapseudos` pass.

The `#LI8_VDR` assembly string (with the `#` prefix) is a convention: if a pseudo accidentally reaches the printer, it prints as a comment rather than an invalid mnemonic.

---

## 8 — Reading a new `.td` definition: checklist

When you encounter an unfamiliar `def Foo : SomeClass<…>` in a `.td` file, follow these steps:

```
1. Find SomeClass in PPCInstrFormats.td
   → grep -n "class SomeClass" llvm/lib/Target/PowerPC/PPCInstrFormats.td

2. Follow the inheritance chain upward until you reach class I
   → note which bit ranges each level fills in Inst{…}

3. Read the template parameters (angle brackets):
   - First integer arg   → major opcode
   - (outs …)            → output register classes + variable names
   - (ins  …)            → input operand types (check compound ops like memri)
   - string              → assembly template ($var substitutions)
   - IIC_*               → scheduling class (find in PPCSchedule.td)
   - [(set …)]           → DAG pattern (ISD node + type + ComplexPattern)

4. Read the { let … } body:
   - Predicates = [X]    → guarding condition (find X in PPCInstrInfo.td)
   - isPseudo = 1        → expands in expandPostRAPseudo()
   - DecoderNamespace    → disassembler grouping
   - Other flags         → check TSFlags assignments in class I

5. Check if the pattern is empty ([]):
   - []                  → matched in C++ (grep tryAsSingle* in PPCISelDAGToDAG.cpp)
   - [… dag …]           → auto-matched by the TableGen-generated ISel switch
```

---

## 9 — Side-by-side: `LVD` vs `LWZ`

Comparing `LVD` with the standard 32-bit `LWZ` makes all the differences concrete:

```tablegen
// PPCInstrInfo.td:1988
def LWZ : DForm_1<32, (outs gprc:$RST), (ins (memri $D, $RA):$addr),
                  "lwz $RST, $addr", IIC_LdStLoad,
                  [(set i32:$RST, (load DForm:$addr))]>, ZExt32To64;

// PPCInstrPPEVD.td:23
def LVD : DForm_1<5,  (outs vdrc:$RST), (ins (memri $D, $RA):$src),
                  "lvd $RST, $src",  IIC_LdStLoad,
                  [(set i64:$RST, (load iaddr:$src))]> {
  let hasNoSchedulingInfo = 1;
  let DecoderNamespace = "PPE42";
}
```

| Aspect | `LWZ` | `LVD` |
|---|---|---|
| Opcode | 32 | 5 |
| Output class | `gprc` (32-bit GPR) | `vdrc` (64-bit VDR pair) |
| Result type | `i32` | `i64` |
| Address pattern | `DForm` (no C++ check) | `iaddr` (calls `SelectAddrImm`) |
| Extra mixin | `ZExt32To64` (packs into TSFlags) | none |
| Scheduling info | from `G3Itineraries` | `hasNoSchedulingInfo = 1` |
| Decoder | default PPC namespace | `"PPE42"` namespace |
| Available on | all 32-bit PPC | PPE42 only (via `DecoderNamespace`; LVD has no `Predicates` guard on ISel — guarded implicitly because `vdrc` only exists on PPE42) |

---

## 10 — Where the generated code lives

After `llvm-tblgen` processes the `.td` files, the key generated outputs are:

```
build/lib/Target/PowerPC/PPCGenInstrInfo.inc
  → enum { LVD = 1234, STVD = 1235, … }   (opcode numbers)
  → MCInstrDesc PPCInsts[] = { …, { LVD, 1, 1, 4, … }, … }
                                          ^nOuts ^nIns ^size

build/lib/Target/PowerPC/PPCGenDAGISel.inc
  → Inside PPCDAGToDAGISel::SelectCode():
    case ISD::LOAD: {
      if (N->getValueType(0) == MVT::i64) {
        // iaddr complex pattern check → SelectAddrImm
        if (SelectAddrImm(N->getOperand(1), imm, base)) {
          return CurDAG->getMachineNode(PPC::LVD, …);
        }
      }
    }

build/lib/Target/PowerPC/PPCGenAsmWriter.inc
  → void PPCAsmPrinter::printInstruction(const MCInst *MI) {
      case PPC::LVD:
        O << "lvd ";
        printVDRCOperand(MI, 0, O);   // $RST
        O << ", ";
        printMemRegImm(MI, 1, O);     // $src
        return;
    }

build/lib/Target/PowerPC/PPCGenDisassemblerTables.inc
  → DecoderTable_PPE42[]:
    // when opcode == 5 and namespace == "PPE42": decode as LVD
```

---

*Back: [backend-pipeline-deep-dive.md](backend-pipeline-deep-dive.md)*  
*Reference: [pass-source-map.md](pass-source-map.md)*
