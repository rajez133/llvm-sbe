#!/bin/bash

# Script to compile startup.s and test_simple.s using LLVM assembler and linker
# This tests LVD/STVD instruction encoding directly

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPSOURCE_DIR="$(dirname "${SCRIPT_DIR}")"
OUTPUT_DIR="${APPSOURCE_DIR}/output/simple_test_assembly"

# Create output directory if it doesn't exist
mkdir -p "${OUTPUT_DIR}"

echo "=== Compiling Assembly Files ==="

# Step 1: Assemble startup.s
echo "Step 1a: Assembling startup.s..."
llvm-mc -triple=powerpc-unknown-elf -mcpu=ppe42 -filetype=obj \
    -o "${OUTPUT_DIR}/startup.o" \
    "${APPSOURCE_DIR}/startup.s"

if [ $? -eq 0 ]; then
    echo "✓ Assembly successful: ${OUTPUT_DIR}/startup.o"
else
    echo "✗ Assembly of startup.s failed"
    exit 1
fi

# Step 1b: Assemble test_simple.s
echo "Step 1b: Assembling test_simple.s..."
llvm-mc -triple=powerpc-unknown-elf -mcpu=ppe42 -filetype=obj \
    -o "${OUTPUT_DIR}/test_simple.o" \
    "${SCRIPT_DIR}/test_simple.s"

if [ $? -eq 0 ]; then
    echo "✓ Assembly successful: ${OUTPUT_DIR}/test_simple.o"
else
    echo "✗ Assembly of test_simple.s failed"
    exit 1
fi

# Step 2: Link the object files
echo "Step 2: Linking startup.o and test_simple.o..."
ld.lld -T "${APPSOURCE_DIR}/linker" \
    "${OUTPUT_DIR}/startup.o" \
    "${OUTPUT_DIR}/test_simple.o" \
    -o "${OUTPUT_DIR}/test_simple.elf"

if [ $? -eq 0 ]; then
    echo "✓ Linking successful: ${OUTPUT_DIR}/test_simple.elf"
else
    echo "✗ Linking failed"
    exit 1
fi

# Step 3: Generate binary
echo "Step 3: Generating binary..."
llvm-objcopy -O binary \
    "${OUTPUT_DIR}/test_simple.elf" \
    "${OUTPUT_DIR}/test_simple.bin"

if [ $? -eq 0 ]; then
    echo "✓ Binary generated: ${OUTPUT_DIR}/test_simple.bin"
else
    echo "✗ Binary generation failed"
    exit 1
fi

# Step 4: Disassemble for verification
echo "Step 4: Disassembling for verification..."
llvm-objdump -d --mcpu=ppe42 "${OUTPUT_DIR}/test_simple.elf" \
    > "${OUTPUT_DIR}/test_simple.dis"

if [ $? -eq 0 ]; then
    echo "✓ Disassembly generated: ${OUTPUT_DIR}/test_simple.dis"
    echo ""
    echo "=== Disassembly Output ==="
    cat "${OUTPUT_DIR}/test_simple.dis"
else
    echo "✗ Disassembly failed"
    exit 1
fi

echo ""
echo "=== Assembly Test Complete ==="
echo "All files generated in: ${OUTPUT_DIR}/"

# Made with Bob
