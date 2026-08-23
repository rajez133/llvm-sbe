#!/bin/bash

# Test script for PPE42 register pressure test (P1-D prerequisite)
# Compiles a function with 8 simultaneous live 64-bit VDR values to force
# the allocator into R11/R12, which do not exist on PPE42 hardware.
#
# NOTE (P1-C workaround — PPCAsmParser bug):
#   llvm-mc rejects syntactically valid PPC assembly produced by llc when
#   -mcpu=ppe42 is used (register names without '%' prefix are mis-parsed).
#   Workaround: compile directly from LLVM IR to object with llc -filetype=obj,
#   the same approach used in test_c/test_c.sh.  See TODO_PPE42_BACKEND.md P1-C.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLANG="/opt/llvm-install/bin/clang"
LLC="/opt/llvm-install/bin/llc"
OPT="/opt/llvm-install/bin/opt"
POWERPC_AS="/opt/llvm-install/bin/llvm-mc"
POWERPC_LD="/opt/llvm-install/bin/ld.lld"
POWERPC_OBJDUMP="/opt/llvm-install/bin/llvm-objdump"

OUTPUT_DIR="${SCRIPT_DIR}/../output/test_c_register_pressure"
mkdir -p "${OUTPUT_DIR}"

STARTUP_S="${SCRIPT_DIR}/../startup.s"
LINKER_SCRIPT="${SCRIPT_DIR}/../linker"

echo "=== PPE42 Register Pressure Test (P1-D prerequisite) ==="
echo ""

# Step 1: Compile C to LLVM IR
echo "Step 1: Compiling test.c to LLVM IR..."
${CLANG} -target powerpc-unknown-linux-gnu \
    -mcpu=ppe42 -O2 -S -emit-llvm \
    -o ${OUTPUT_DIR}/test.ll \
    ${SCRIPT_DIR}/test.c
echo "  Generated: ${OUTPUT_DIR}/test.ll"

# Step 2: Optimize IR
echo "Step 2: Optimizing LLVM IR..."
${OPT} -O2 -S ${OUTPUT_DIR}/test.ll -o ${OUTPUT_DIR}/test-opt.ll
echo "  Generated: ${OUTPUT_DIR}/test-opt.ll"

# Step 3: Generate assembly + capture full pass dump
# NOTE: Previously crashed before the spill opcode was registered (SOK_VDRSpill).
#       Now succeeds but may emit stvd/lvd with wrong operand order — see Bug 1
#       description in TODO_PPE42_BACKEND.md (ImmToIdxMap missing LVD/STVD).
echo "Step 3: Generating assembly (with full pass debug dump)..."
${LLC} -march=ppc32 -mcpu=ppe42 -O2 -filetype=asm \
    -print-after-all \
    ${OUTPUT_DIR}/test-opt.ll \
    -o ${OUTPUT_DIR}/test.s \
    2>${OUTPUT_DIR}/llc-debug-all-passes.txt || LLC_EXIT=$?

if [ -n "${LLC_EXIT}" ]; then
    echo "  ✗ CRASH (exit ${LLC_EXIT}): llc aborted during code generation."
    echo "    See last lines of llc-debug-all-passes.txt for the stack trace."
    tail -6 ${OUTPUT_DIR}/llc-debug-all-passes.txt
    echo ""
    echo "=== Done (crash captured). Output in: ${OUTPUT_DIR} ==="
    exit 1
fi
echo "  Generated: ${OUTPUT_DIR}/test.s"
echo "  Generated: ${OUTPUT_DIR}/llc-debug-all-passes.txt"

# -----------------------------------------------------------------------
# P1-D BUG CHECK — inspect the assembly for invalid registers.
# (The .s file is for inspection only; object file is compiled below.)
# PPE42 valid GPRs:   r0-r10, r13, r28-r31
# Invalid GPRs:       r11, r12, r14-r27  (hardware does not have these)
# -----------------------------------------------------------------------
echo ""
echo "=== P1-D Register Allocation Check (assembly inspection) ==="
echo "  Valid PPE42 GPRs : r0-r10, r13, r28-r31"
echo "  Invalid GPRs     : r11, r12, r14-r27"
echo ""

INVALID=0
for REG in r11 r12 $(seq 14 27 | sed 's/^/r/'); do
    if grep -qE "\b${REG}\b" ${OUTPUT_DIR}/test.s; then
        echo "  ✗ BUG: invalid register '${REG}' found in assembly:"
        grep -nE "\b${REG}\b" ${OUTPUT_DIR}/test.s | head -3
        INVALID=1
    fi
done

if [ "${INVALID}" -eq 0 ]; then
    echo "  ✓ No invalid registers — P1-D fix is in effect."
else
    echo ""
    echo "  ↑ P1-D not yet implemented: restrict GPRC allocation order"
    echo "    to r0-r10, r13, r28-r31 when isPPE42()."
fi

echo ""
echo "=== Register Usage Summary (from .s, inspection only) ==="
grep -oE '\br[0-9]+\b' ${OUTPUT_DIR}/test.s | sort -t'r' -k2 -n | uniq -c | sort -rn
echo ""

# Step 4: Generate object file directly from LLVM IR
# Bypasses llvm-mc and the broken PPCAsmParser (P1-C workaround).
echo "Step 4: Generating object file directly from LLVM IR..."
${LLC} -march=ppc32 \
    -mcpu=ppe42 \
    -O2 \
    -filetype=obj \
    ${OUTPUT_DIR}/test-opt.ll \
    -o ${OUTPUT_DIR}/test.o
echo "  Generated: ${OUTPUT_DIR}/test.o (directly from IR)"

# Step 5: Assemble startup code
echo "Step 5: Assembling startup.s..."
${POWERPC_AS} -triple=powerpc-unknown-linux-gnu \
    -mcpu=ppe42 \
    -filetype=obj \
    ${STARTUP_S} \
    -o ${OUTPUT_DIR}/startup.o
echo "  Generated: ${OUTPUT_DIR}/startup.o"

# Step 6: Link
echo "Step 6: Linking..."
${POWERPC_LD} -T ${LINKER_SCRIPT} \
    ${OUTPUT_DIR}/startup.o ${OUTPUT_DIR}/test.o \
    -o ${OUTPUT_DIR}/a.out
echo "  Generated: ${OUTPUT_DIR}/a.out"

# Step 7: Disassemble
echo "Step 7: Disassembling..."
${POWERPC_OBJDUMP} -d --mcpu=ppe42 ${OUTPUT_DIR}/a.out > ${OUTPUT_DIR}/a.dis
echo "  Generated: ${OUTPUT_DIR}/a.dis"
echo ""

# Check disassembly for LVD/STVD
echo "=== Final Binary Check ==="
if grep -q "lvd\|stvd" ${OUTPUT_DIR}/a.dis; then
    echo "  ✓ Found LVD/STVD instructions in disassembly!"
    grep "lvd\|stvd" ${OUTPUT_DIR}/a.dis | head -5
else
    echo "  ✗ No LVD/STVD instructions in final binary"
fi

echo ""
echo "=== Done. Output in: ${OUTPUT_DIR} ==="
echo "  - test.ll     (LLVM IR)"
echo "  - test-opt.ll (Optimized IR)"
echo "  - test.s      (Assembly — inspection only, not assembled via llvm-mc)"
echo "  - test.o      (Object file — compiled directly from IR by llc)"
echo "  - a.out       (Linked binary)"
echo "  - a.dis       (Disassembly)"

# Made with Bob
