# Pass → Source File Reference Map

**How to use:** Run `llc -print-after-all` to produce `debug-all-passes.txt`.  
Find the pass name in the **Pass ID** column. Open the listed source file. The entry point is in the **Entry Point** column.

`lib/` prefix = `llvm/llvm/llvm/lib/`  
`T/PPC/` = `lib/Target/PowerPC/`

---

## Phase 0 — Pre-ISel IR Passes (LLVM IR in, LLVM IR out)

| # | Pass Name | Pass ID | Source File | Entry Point |
|---|-----------|---------|-------------|-------------|
| 1 | Pre-ISel Intrinsic Lowering | `pre-isel-intrinsic-lowering` | `lib/CodeGen/PreISelIntrinsicLowering.cpp` | `PreISelIntrinsicLowering::run()` |
| 2 | Expand large div/rem | `expand-large-div-rem` | `lib/CodeGen/ExpandLargeDivRem.cpp` | `ExpandLargeDivRem::run()` |
| 3 | Expand fp | `expand-fp` | `lib/CodeGen/ExpandFp.cpp` | `ExpandFp::run()` |
| 4 | Convert i1 constants (PPC) | `ppc-bool-ret-to-int` | `T/PPC/PPCBoolRetToInt.cpp` | `PPCBoolRetToInt::runOnFunction()` |
| 5 | Expand Atomic instructions | `atomic-expand` | `lib/CodeGen/AtomicExpandPass.cpp` | `AtomicExpand::runOnFunction()` |
| 6 | PPC Lower MASS Entries | `ppc-lower-massv-entries` | `T/PPC/PPCLowerMASSVEntries.cpp` | `PPCLowerMASSVEntries::runOnModule()` |
| 7 | Split GEPs | `separate-const-offset-from-gep` | `lib/Transforms/Scalar/SeparateConstOffsetFromGEP.cpp` | `SeparateConstOffsetFromGEP::runOnFunction()` |
| 8 | Early CSE | `early-cse` | `lib/Transforms/Scalar/EarlyCSE.cpp` | `EarlyCSEPass::run()` |
| 9 | Canonicalize natural loops | `loop-simplify` | `lib/Transforms/Utils/LoopSimplify.cpp` | `LoopSimplifyPass::run()` |
| 10 | LCSSA Verifier | `lcssa-verification` | `lib/Analysis/LoopAnalysisManager.cpp` | verification only |
| 11 | Loop-Closed SSA | `lcssa` | `lib/Transforms/Utils/LCSSA.cpp` | `LCSSAPass::run()` |
| 12 | Loop Invariant Code Motion | `licm` | `lib/Transforms/Scalar/LICM.cpp` | `LICMPass::run()` |
| 13 | Module Verifier | `verify` | `lib/IR/Verifier.cpp` | `verifyModule()` |
| 14 | Canonicalize Freeze in Loops | `canon-freeze` | `lib/Transforms/Utils/CanonicalizeFreezeInLoops.cpp` | `CanonicalizeFreezeInLoopsPass::run()` |
| 15 | Loop Strength Reduction | `loop-reduce` | `lib/Transforms/Scalar/LoopStrengthReduce.cpp` | `LoopStrengthReducePass::run()` |
| 16 | Merge contiguous icmps | `mergeicmps` | `lib/Transforms/Scalar/MergeICmps.cpp` | `MergeICmpsPass::run()` |
| 17 | Expand memcmp | `expand-memcmp` | `lib/CodeGen/ExpandMemCmp.cpp` | `ExpandMemCmpPass::run()` |
| 18 | Lower GC Instructions | `gc-lowering` | `lib/CodeGen/GCStrategy.cpp` | `GCLoweringPass::run()` |
| 19 | Shadow Stack GC Lowering | `shadow-stack-gc-lowering` | `lib/CodeGen/ShadowStackGCLowering.cpp` | `ShadowStackGCLowering::runOnFunction()` |
| 20 | Remove unreachable blocks | `unreachableblockelim` | `lib/CodeGen/UnreachableBlockElim.cpp` | `UnreachableBlockElimPass::run()` |
| 21 | Constant Hoisting | `consthoist` | `lib/Transforms/Scalar/ConstantHoisting.cpp` | `ConstantHoistingPass::run()` |
| 22 | Replace with veclib | `replace-with-veclib` | `lib/Transforms/Vectorize/ReplaceWithVeclib.cpp` | `ReplaceWithVeclib::run()` |
| 23 | Partially inline libcalls | `partially-inline-libcalls` | `lib/Transforms/Scalar/PartiallyInlineLibCalls.cpp` | `PartiallyInlineLibCallsPass::run()` |
| 24 | EE instrument | `post-inline-ee-instrument` | `lib/Transforms/Instrumentation/EntryExitInstrumenter.cpp` | `EntryExitInstrumenterPass::run()` |
| 25 | Scalarize masked mem intrinsics | `scalarize-masked-mem-intrin` | `lib/Transforms/Scalar/ScalarizeMaskedMemIntrin.cpp` | `ScalarizeMaskedMemIntrinPass::run()` |
| 26 | Expand reduction intrinsics | `expand-reductions` | `lib/CodeGen/ExpandReductions.cpp` | `ExpandReductions::runOnFunction()` |
| 27 | **CodeGen Prepare** | `codegenprepare` | `lib/CodeGen/CodeGenPrepare.cpp` | `CodeGenPrepare::runOnFunction()` — most important pre-ISel pass |
| 28 | DWARF EH Prepare | `dwarf-eh-prepare` | `lib/CodeGen/DwarfEHPrepare.cpp` | `DwarfEHPrepare::runOnFunction()` |
| 29 | Merge internal globals | `global-merge` | `lib/CodeGen/GlobalMerge.cpp` | `GlobalMerge::runOnModule()` |
| 30 | PPC loop instr form prep | `ppc-loop-instr-form-prep` | `T/PPC/PPCLoopInstrFormPrep.cpp` | `PPCLoopInstrFormPrep::runOnFunction()` |
| 31 | Hardware Loop Insertion | `hardware-loops` | `lib/CodeGen/HardwareLoops.cpp` | `HardwareLoops::runOnFunction()` |
| 32 | ObjC ARC contraction | `objc-arc-contract` | `lib/Transforms/ObjCARC/ObjCARC.cpp` | ObjC only |
| 33 | Prepare callbr | `callbrprepare` | `lib/CodeGen/CallBrPrepare.cpp` | `CallBrPrepare::run()` |
| 34 | Safe Stack | `safe-stack` | `lib/CodeGen/SafeStack.cpp` | `SafeStack::runOnFunction()` |
| 35 | Module Verifier | `verify` | `lib/IR/Verifier.cpp` | `verifyModule()` |

---

## Phase 1 — Instruction Selection (IR → MachineInstr)

| # | Pass Name | Pass ID | Source File | Entry Point |
|---|-----------|---------|-------------|-------------|
| 36 | **PowerPC DAG->DAG Instruction Selection** | `ppc-isel` | `T/PPC/PPCISelDAGToDAG.cpp` | `PPCDAGToDAGISel::Select()` — **main instruction selector** |
| — | (DAG build, inside ppc-isel) | — | `lib/CodeGen/SelectionDAG/SelectionDAGBuilder.cpp` | `SelectionDAGBuilder::visit()` |
| — | (DAG combine, inside ppc-isel) | — | `T/PPC/PPCISelLowering.cpp` | `PPCTargetLowering::PerformDAGCombine()` |
| — | (Legalise, inside ppc-isel) | — | `lib/CodeGen/SelectionDAG/LegalizeDAG.cpp` | `SelectionDAGLegalize::LegalizeOp()` |
| — | (Generic ISel engine) | — | `lib/CodeGen/SelectionDAG/SelectionDAGISel.cpp` | `SelectionDAGISel::runOnMachineFunction()` |
| 37 | PowerPC CTR Loops Verify | `ppc-ctr-loops-verify` | `T/PPC/PPCCTRLoopsVerify.cpp` | `PPCCTRLoopsVerify::runOnMachineFunction()` |
| 38 | PowerPC VSX Copy Legalization | `ppc-vsx-copy` | `T/PPC/PPCVSXCopy.cpp` | `PPCVSXCopy::runOnMachineFunction()` |
| 39 | **Finalize ISel / expand pseudo-instrs** | `finalize-isel` | `lib/CodeGen/FinalizeMachineBundles.cpp` | `FinalizeMachineBundlesPass::runOnMachineFunction()` |
| 40 | PowerPC CTR loops generation | `ppc-ctrloops` | `T/PPC/PPCCTRLoops.cpp` | `PPCCTRLoops::runOnLoop()` |

---

## Phase 2 — Pre-RA Optimisation (MachineInstr, virtual regs)

| # | Pass Name | Pass ID | Source File | Entry Point |
|---|-----------|---------|-------------|-------------|
| 41 | Early Tail Duplication | `early-tailduplication` | `lib/CodeGen/TailDuplicator.cpp` | `TailDuplicator::tailDuplicateBlocks()` |
| 42 | Optimize machine PHIs | `opt-phis` | `lib/CodeGen/OptimizePHIs.cpp` | `OptimizePHIs::runOnMachineFunction()` |
| 43 | Slot index numbering | `slotindexes` | `lib/CodeGen/SlotIndexes.cpp` | `SlotIndexes::runOnMachineFunction()` |
| 44 | Merge disjoint stack slots | `stack-coloring` | `lib/CodeGen/StackColoring.cpp` | `StackColoring::runOnMachineFunction()` |
| 45 | Local Stack Slot Allocation | `localstackalloc` | `lib/CodeGen/LocalStackSlotAllocation.cpp` | `LocalStackSlotPass::runOnMachineFunction()` |
| 46 | Remove dead machine instrs | `dead-mi-elimination` | `lib/CodeGen/DeadMachineInstructionElim.cpp` | `DeadMachineInstrElim::run()` |
| 47 | Early If-Conversion | `early-ifcvt` | `lib/CodeGen/EarlyIfConversion.cpp` | `EarlyIfConverter::runOnMachineFunction()` |
| 48 | Machine InstCombiner | `machine-combiner` | `lib/CodeGen/MachineCombiner.cpp` | `MachineCombiner::runOnMachineFunction()` |
| 49 | Early Machine LICM | `early-machinelicm` | `lib/CodeGen/MachineLICM.cpp` | `MachineLICM::runOnMachineFunction()` |
| 50 | Machine CSE | `machine-cse` | `lib/CodeGen/MachineCSE.cpp` | `MachineCSE::runOnMachineFunction()` |
| 51 | Machine code sinking | `machine-sink` | `lib/CodeGen/MachineSink.cpp` | `MachineSinking::runOnMachineFunction()` |
| 52 | Peephole Optimizations | `peephole-opt` | `lib/CodeGen/PeepholeOptimizer.cpp` | `PeepholeOptimizer::runOnMachineFunction()` |
| 54 | PPC Reduce CR logical ops | `ppc-reduce-cr-ops` | `T/PPC/PPCReduceCRLogicals.cpp` | `PPCReduceCRLogicals::runOnMachineFunction()` |
| 57 | **PPC MI Peephole Optimization** | `ppc-mi-peepholes` | `T/PPC/PPCMIPeephole.cpp` | `PPCMIPeephole::runOnMachineFunction()` |
| 59 | PPC TOC Register Dependencies | `ppc-toc-reg-deps` | `T/PPC/PPCTOCRegDeps.cpp` | `PPCTOCRegDeps::runOnMachineFunction()` |
| 61 | Modulo Software Pipelining | `pipeliner` | `lib/CodeGen/MachinePipeliner.cpp` | `MachinePipeliner::runOnMachineFunction()` |
| 62 | Detect Dead Lanes | `detect-dead-lanes` | `lib/CodeGen/DetectDeadLanes.cpp` | `DetectDeadLanes::runOnMachineFunction()` |
| 63 | Init Undef Pass | `init-undef` | `lib/CodeGen/InitUndef.cpp` | `InitUndef::runOnMachineFunction()` |
| 64 | Process Implicit Definitions | `processimpdefs` | `lib/CodeGen/ProcessImplicitDefs.cpp` | `ProcessImplicitDefs::runOnMachineFunction()` |
| 66 | Live Variable Analysis | `livevars` | `lib/CodeGen/LiveVariables.cpp` | `LiveVariables::runOnMachineFunction()` |
| 67 | Eliminate PHI nodes for RA | `phi-node-elimination` | `lib/CodeGen/PHIElimination.cpp` | `PHIElimination::runOnMachineFunction()` |
| 68 | Two-Address instruction pass | `twoaddressinstruction` | `lib/CodeGen/TwoAddressInstructionPass.cpp` | `TwoAddressInstructionPass::runOnMachineFunction()` |
| 70 | Register Coalescer | `register-coalescer` | `lib/CodeGen/RegisterCoalescer.cpp` | `RegisterCoalescer::runOnMachineFunction()` |
| 71 | Rename Disconnected Subregs | `rename-independent-subregs` | `lib/CodeGen/RenameIndependentSubregs.cpp` | `RenameIndependentSubregs::runOnMachineFunction()` |
| 72 | Machine Instruction Scheduler | `machine-scheduler` | `lib/CodeGen/MachineScheduler.cpp` | `MachineScheduler::runOnMachineFunction()` |
| 73 | PowerPC VSX FMA Mutation | `ppc-vsx-fma-mutate` | `T/PPC/PPCVSXFMAMutate.cpp` | `PPCVSXFMAMutate::runOnMachineFunction()` |

---

## Phase 3 — Register Allocation

| # | Pass Name | Pass ID | Source File | Entry Point |
|---|-----------|---------|-------------|-------------|
| 74 | **Greedy Register Allocator** | `greedy` | `lib/CodeGen/RegAllocGreedy.cpp` | `RAGreedy::runOnMachineFunction()` |
| — | (spill store, called from greedy) | — | `T/PPC/PPCInstrInfo.cpp` | `PPCInstrInfo::storeRegToStackSlot()` |
| — | (spill load, called from greedy) | — | `T/PPC/PPCInstrInfo.cpp` | `PPCInstrInfo::loadRegFromStackSlot()` |
| — | (spill opcode lookup) | — | `T/PPC/PPCInstrInfo.cpp` | `PPCInstrInfo::getSpillIndex()` |
| — | (spill opcode table) | — | `T/PPC/PPCInstrInfo.h` | `Pwr8StoreOpcodes` / `Pwr8LoadOpcodes` macros |
| 75 | Virtual Register Rewriter | `virtregrewriter` | `lib/CodeGen/VirtRegMap.cpp` | `VirtRegRewriter::runOnMachineFunction()` |
| 76 | Register Allocation Scoring | `regallocscoringpass` | `lib/CodeGen/RegAllocScore.cpp` | scoring only |

---

## Phase 4 — Post-RA Passes

| # | Pass Name | Pass ID | Source File | Entry Point |
|---|-----------|---------|-------------|-------------|
| 77 | Stack Slot Coloring | `stack-slot-coloring` | `lib/CodeGen/StackSlotColoring.cpp` | `StackSlotColoring::runOnMachineFunction()` |
| 78 | Machine Copy Propagation | `machine-cp` | `lib/CodeGen/MachineCopyPropagation.cpp` | `MachineCopyPropagation::runOnMachineFunction()` |
| 79 | Machine LICM | `machinelicm` | `lib/CodeGen/MachineLICM.cpp` | `MachineLICM::runOnMachineFunction()` |
| 82 | PostRA Machine Sink | `postra-machine-sink` | `lib/CodeGen/MachineSink.cpp` | `MachineSinking::runOnMachineFunction()` |
| 83 | Shrink Wrapping | `shrink-wrap` | `lib/CodeGen/ShrinkWrap.cpp` | `ShrinkWrap::runOnMachineFunction()` |
| **84** | **Prologue/Epilogue Insertion** | `prologepilog` | `lib/CodeGen/PrologEpilogInserter.cpp` | `PEI::runOnMachineFunction()` |
| — | (PPC frame lowering, called from prologepilog) | — | `T/PPC/PPCFrameLowering.cpp` | `PPCFrameLowering::emitPrologue()` / `emitEpilogue()` |
| — | (FrameIndex elimination, called from prologepilog) | — | `T/PPC/PPCRegisterInfo.cpp` | `PPCRegisterInfo::eliminateFrameIndex()` ← **ImmToIdxMap bug site** |
| 85 | Machine Late Cleanup | `machine-latecleanup` | `lib/CodeGen/MachineLateInstrsCleanup.cpp` | `MachineLateInstrsCleanup::runOnMachineFunction()` |
| 86 | Branch Folder | `branch-folder` | `lib/CodeGen/BranchFolding.cpp` | `BranchFolder::OptimizeFunction()` |
| 87 | Tail Duplication | `tailduplication` | `lib/CodeGen/TailDuplicator.cpp` | `TailDuplicator::tailDuplicateBlocks()` |
| **89** | **Post-RA pseudo expansion** | `postrapseudos` | `lib/CodeGen/ExpandPostRAPseudos.cpp` | `ExpandPostRAPseudos::runOnMachineFunction()` |
| — | (PPC pseudo expansion, called from postrapseudos) | — | `T/PPC/PPCInstrInfo.cpp` | `PPCInstrInfo::expandPostRAPseudo()` ← **LI8_VDR / OR8_VDR expansion** |
| 90 | If Converter | `if-converter` | `lib/CodeGen/IfConversion.cpp` | `IfConverter::runOnMachineFunction()` |
| 91 | PostRA Machine Scheduler | `postmisched` | `lib/CodeGen/MachineScheduler.cpp` | `PostMachineScheduler::runOnMachineFunction()` |
| 93 | Branch Probability Block Placement | `block-placement` | `lib/CodeGen/MachineBlockPlacement.cpp` | `MachineBlockPlacement::runOnMachineFunction()` |

---

## Phase 5 — Late PPC-Specific Passes

| # | Pass Name | Pass ID | Source File | Entry Point |
|---|-----------|---------|-------------|-------------|
| 97 | PPC Pre-Emit Peephole | `ppc-pre-emit-peephole` | `T/PPC/PPCPreEmitPeephole.cpp` | `PPCPreEmitPeephole::runOnMachineFunction()` |
| 98 | PPC Early-Return Creation | `ppc-early-ret` | `T/PPC/PPCEarlyReturn.cpp` | `PPCEarlyReturn::runOnMachineFunction()` |
| 104 | Stack Frame Layout Analysis | `stack-frame-layout` | `lib/CodeGen/StackFrameLayoutAnalysisPass.cpp` | `StackFrameLayoutAnalysis::runOnMachineFunction()` |
| 105 | PowerPC Expand Atomic | `ppc-atomic-expand` | `T/PPC/PPCExpandAtomicPseudoInsts.cpp` | `PPCExpandAtomicPseudoInsts::runOnMachineFunction()` |
| 106 | PowerPC Branch Selector | `ppc-branch-select` | `T/PPC/PPCBranchSelector.cpp` | `PPCBSel::runOnMachineFunction()` |

---

## Phase 6 — Assembly / Object Emission

| # | Pass Name | Pass ID | Source File | Entry Point |
|---|-----------|---------|-------------|-------------|
| 107 | **Linux PPC Assembly Printer** | `ppc-linux-asm-printer` | `T/PPC/PPCAsmPrinter.cpp` | `PPCAsmPrinter::emitInstruction()` |
| — | (MC instruction encoding, -filetype=obj) | — | `T/PPC/MCTargetDesc/PPCMCCodeEmitter.cpp` | `PPCMCCodeEmitter::encodeInstruction()` |
| — | (MC instruction printing, -filetype=asm) | — | `T/PPC/MCTargetDesc/PPCInstPrinter.cpp` | `PPCInstPrinter::printInstruction()` |
| — | (Memory operand printing) | — | `T/PPC/MCTargetDesc/PPCInstPrinter.cpp` | `PPCInstPrinter::printMemRegImm()` |
| — | (D-form displacement encoding) | — | `T/PPC/MCTargetDesc/PPCMCCodeEmitter.cpp` | `PPCMCCodeEmitter::getDispRIEncoding()` ← **assert site for ImmToIdxMap bug** |

---

## Frequently Needed Files (Quick Access)

| File | When to look here |
|------|-------------------|
| `T/PPC/PPCISelLowering.cpp` | Wrong DAG node produced; wrong type legalisation; DAG combine not firing |
| `T/PPC/PPCISelDAGToDAG.cpp` | Wrong instruction selected; pattern not matching |
| `T/PPC/PPCInstrPPEVD.td` | Wrong encoding, wrong operand order in instruction def |
| `T/PPC/PPCRegisterInfo.cpp` | Wrong spill/reload format; frame offset wrong; reserved regs wrong |
| `T/PPC/PPCFrameLowering.cpp` | Prologue/epilogue wrong; frame size wrong |
| `T/PPC/PPCInstrInfo.cpp` | Wrong spill opcode; pseudo not expanding; wrong expansion sequence |
| `T/PPC/PPCInstrInfo.h` | Wrong opcode in spill array (`Pwr8StoreOpcodes`) |
| `T/PPC/PPCRegisterInfo.td` | Wrong register class; wrong allocation order |
| `T/PPC/MCTargetDesc/PPCMCCodeEmitter.cpp` | Encoding crash; wrong binary output |
| `T/PPC/MCTargetDesc/PPCInstPrinter.cpp` | Wrong assembly text output |
| `lib/CodeGen/RegAllocGreedy.cpp` | Spill not happening when expected; wrong register chosen |
| `lib/CodeGen/PrologEpilogInserter.cpp` | Frame index not resolved; wrong base register |
