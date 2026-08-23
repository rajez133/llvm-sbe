# PPE42 LLVM Backend — Documentation

**Target:** PPE42 (32-bit PowerPC variant used in IBM P8 core)  
**Compiler:** LLVM/Clang 21.1.4 (custom fork with PPE42 backend additions)

---

## Documents

| # | File | Covers |
|---|------|--------|
| 1 | [ch1-llvm-backend-concepts.md](ch1-llvm-backend-concepts.md) | Pipeline, SelectionDAG, TableGen, register allocation, frame index elimination, MC layer |
| 1a | [backend-pipeline-deep-dive.md](backend-pipeline-deep-dive.md) | Full pipeline walkthrough with example, annotated diagram, root-cause debugging guide |
| 1b | [pass-source-map.md](pass-source-map.md) | Every `print-after-all` pass → source file + entry point (quick reference) |
| 2 | [ch2-ppc-llvm-structure.md](ch2-ppc-llvm-structure.md) | High-level structure of PPC LLVM backend: subtargets, processor hierarchy, feature flags |
| 3 | [ch3-ppe42-design.md](ch3-ppe42-design.md) | PPE42 design decisions: subtarget approach, base variant, 64-bit operation strategy |
| 4 | [ch4-test_c-changes.md](ch4-test_c-changes.md) | 64-bit load/OR/store on a 32-bit core: VDR register class, LVD/STVD, DAG combine, RLDIMI, LI8_VDR |
| 5 | [ch5-test_c_register_pressure-changes.md](ch5-test_c_register_pressure-changes.md) | Register pressure, VDR spilling, ImmToIdxMap fix, assembly parser workaround |

Read in order: Chapter 1 builds the vocabulary; Chapters 2–3 explain the design; Chapters 4–5 walk through each code change.

---

## Quick-Reference: Where Each Concept Lives in the Source

```
llvm/lib/Target/PowerPC/
├── PPC.td                    FeaturePPE42, Processor def for "ppe42"
├── PPCRegisterInfo.td        VDRC register class, VDRTuples, GPRC AltOrder index 3
├── PPCInstrPPEVD.td          LVD, STVD, RLDIMI_VDR, LI8_VDR, OR8_VDR
├── PPCISelLowering.cpp       addRegisterClass(MVT::i64, VDRC); OR DAG combine
├── PPCISelDAGToDAG.cpp       tryAsSingleRLDIMI() → RLDIMI_VDR selection
├── PPCInstrInfo.h            SOK_VDRSpill; Pwr8StoreOpcodes/LoadOpcodes arrays
├── PPCInstrInfo.cpp          expandPostRAPseudo (LI8_VDR, OR8_VDR); getSpillIndex
├── PPCRegisterInfo.cpp       ImmToIdxMap (LVD/STVD entries); getReservedRegs; eliminateFrameIndex
└── PPCSubtarget.h            isPPE42(); getGPRAllocationOrderIdx()
```

---

## Known Open Issues

See [TODO_PPE42_BACKEND.md](TODO_PPE42_BACKEND.md) for the full tracked issue list.
