#!/bin/bash

# Test script for basic 64-bit C code compilation
# Tests if LLVM can generate LVD/STVD instructions for normal C operations

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Use installed LLVM from /opt/llvm-install (inside Docker container)
CLANG="/opt/llvm-install/bin/clang"
LLC="/opt/llvm-install/bin/llc"
LLVM_AS="/opt/llvm-install/bin/llvm-as"
OPT="/opt/llvm-install/bin/opt"
LLVM_DIS="/opt/llvm-install/bin/llvm-dis"
POWERPC_AS="/opt/llvm-install/bin/llvm-mc"
POWERPC_LD="/opt/llvm-install/bin/ld.lld"
POWERPC_OBJDUMP="/opt/llvm-install/bin/llvm-objdump"

# Output directory
OUTPUT_DIR="${SCRIPT_DIR}/../output/test_c"
mkdir -p "${OUTPUT_DIR}"

# Use common startup.s and linker from parent directory
STARTUP_S="${SCRIPT_DIR}/../startup.s"
LINKER_SCRIPT="${SCRIPT_DIR}/../linker"

echo "=== PPE42 64-bit C Test Compilation ==="
echo "Working directory: ${SCRIPT_DIR}"
echo "Output directory: ${OUTPUT_DIR}"
echo ""

# Step 1: Compile C to LLVM IR
echo "Step 1: Compiling test.c to LLVM IR..."
${CLANG} -target powerpc-unknown-linux-gnu \
    -mcpu=ppe42 \
    -O2 \
    -S -emit-llvm \
    -o ${OUTPUT_DIR}/test.ll \
    ${SCRIPT_DIR}/test.c
echo "  Generated: ${OUTPUT_DIR}/test.ll"
echo ""

# Step 2: Optimize IR
echo "Step 2: Optimizing LLVM IR..."
${OPT} -O2 -S ${OUTPUT_DIR}/test.ll -o ${OUTPUT_DIR}/test-opt.ll
echo "  Generated: ${OUTPUT_DIR}/test-opt.ll"
echo ""

# Step 3a: Generate assembly with all pass outputs for documentation (run first to capture debug on crash)
echo "Step 3a: Generating assembly with debug output (all passes)..."
${LLC} -march=ppc32 \
    -mcpu=ppe42 \
    -O2 \
    -filetype=asm \
    -ppc-asm-full-reg-names \
    -print-after-all \
    ${OUTPUT_DIR}/test-opt.ll \
    -o /dev/null \
    2>&1 | tee ${OUTPUT_DIR}/llc-debug-all-passes.txt || true
echo "  Generated: ${OUTPUT_DIR}/llc-debug-all-passes.txt"
echo ""

# Step 3: Generate assembly (for inspection)
echo "Step 3: Generating PowerPC assembly (for inspection)..."
${LLC} -march=ppc32 \
    -mcpu=ppe42 \
    -O2 \
    -filetype=asm \
    -ppc-asm-full-reg-names \
    ${OUTPUT_DIR}/test-opt.ll \
    -o ${OUTPUT_DIR}/test.s
echo "  Generated: ${OUTPUT_DIR}/test.s"
echo ""

# Step 3b: Generate SelectionDAG debug output
# Note: Requires LLVM built with LLVM_ENABLE_ASSERTIONS=ON
echo "Step 3b: Generating SelectionDAG debug output..."
${LLC} -march=ppc32 \
    -mcpu=ppe42 \
    -filetype=asm \
    -ppc-asm-full-reg-names \
    -debug-only=isel \
    ${OUTPUT_DIR}/test-opt.ll \
    -o /dev/null \
    > ${OUTPUT_DIR}/llc-debug-isel.txt 2>&1

echo "  Generated: ${OUTPUT_DIR}/llc-debug-isel.txt"
echo ""

# Check if LVD/STVD instructions were generated
echo "Checking for LVD/STVD instructions in generated assembly..."
if grep -q "lvd\|stvd" ${OUTPUT_DIR}/test.s; then
    echo "  ✓ Found LVD/STVD instructions!"
    grep "lvd\|stvd" ${OUTPUT_DIR}/test.s | head -5
else
    echo "  ✗ No LVD/STVD instructions found"
    echo "  Generated assembly uses:"
    grep -E "^\s+(lwz|stw|ld|std)" ${OUTPUT_DIR}/test.s | head -5 || echo "  (no load/store instructions found)"
fi
echo ""

# Step 3c: Test llvm-mc assembly parsing of the generated .s
echo "Step 3c: Testing assembly parsing via llvm-mc..."
if ${POWERPC_AS} -triple=powerpc-unknown-linux-gnu \
    -mcpu=ppe42 \
    -filetype=obj \
    ${OUTPUT_DIR}/test.s \
    -o ${OUTPUT_DIR}/test-from-asm.o 2>${OUTPUT_DIR}/llvm-mc-errors.txt; then
    echo "  ✓ llvm-mc assembled test.s successfully (P1-E resolved)"
else
    echo "  ✗ llvm-mc failed to assemble test.s (P1-E still present)"
    echo "  Errors:"
    head -10 ${OUTPUT_DIR}/llvm-mc-errors.txt
fi
echo ""

# Step 3d: Generate object file directly from LLVM IR (fallback / compare)
echo "Step 3d: Generating object file directly from LLVM IR..."
${LLC} -march=ppc32 \
    -mcpu=ppe42 \
    -O2 \
    -filetype=obj \
    ${OUTPUT_DIR}/test-opt.ll \
    -o ${OUTPUT_DIR}/test.o
echo "  Generated: ${OUTPUT_DIR}/test.o (directly from IR)"
echo ""

# Step 4: Assemble startup code
echo "Step 4: Assembling startup.s..."
${POWERPC_AS} -triple=powerpc-unknown-linux-gnu \
    -mcpu=ppe42 \
    -filetype=obj \
    ${STARTUP_S} \
    -o ${OUTPUT_DIR}/startup.o
echo "  Generated: ${OUTPUT_DIR}/startup.o"
echo ""

# Step 5: Link
echo "Step 5: Linking..."
${POWERPC_LD} -T ${LINKER_SCRIPT} \
    ${OUTPUT_DIR}/startup.o ${OUTPUT_DIR}/test.o \
    -o ${OUTPUT_DIR}/a.out
echo "  Generated: ${OUTPUT_DIR}/a.out"
echo ""

# Step 6: Disassemble
echo "Step 6: Disassembling final binary..."
${POWERPC_OBJDUMP} -d --mcpu=ppe42 ${OUTPUT_DIR}/a.out > ${OUTPUT_DIR}/a.dis
echo "  Generated: ${OUTPUT_DIR}/a.dis"
echo ""

# Check disassembly for LVD/STVD
echo "Checking disassembly for LVD/STVD instructions..."
if grep -q "lvd\|stvd" ${OUTPUT_DIR}/a.dis; then
    echo "  ✓ Found LVD/STVD in disassembly!"
    grep "lvd\|stvd" ${OUTPUT_DIR}/a.dis | head -5
else
    echo "  ✗ No LVD/STVD instructions in final binary"
fi
echo ""

echo "=== Compilation Complete ==="
echo "All output files in: ${OUTPUT_DIR}"
echo "  - test.ll (LLVM IR)"
echo "  - test-opt.ll (Optimized IR)"
echo "  - test.s (Assembly)"
echo "  - test.o (Object file)"
echo "  - a.out (Linked binary)"
echo "  - a.dis (Disassembly)"

# Made with Bob
