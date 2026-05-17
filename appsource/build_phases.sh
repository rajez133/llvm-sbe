#!/bin/bash
set -e

# Create output directory
OUTPUT_DIR="./output"
mkdir -p "$OUTPUT_DIR"

echo "=== Step 1: Generate LLVM IR ==="
clang --target=powerpc-eabi -mcpu=ppe42 -O0 -S -emit-llvm ./test.c -o "$OUTPUT_DIR/test.ll"
echo "LLVM IR generated: $OUTPUT_DIR/test.ll"
cat "$OUTPUT_DIR/test.ll"
echo ""

echo "=== Step 2: Optimize LLVM IR ==="
opt -O0 "$OUTPUT_DIR/test.ll" -S -o "$OUTPUT_DIR/test-opt.ll"
echo "Optimized IR: $OUTPUT_DIR/test-opt.ll"

echo "=== Step 3: Generate Assembly ==="
llc -march=ppc32 -mcpu=ppe42 -O0 "$OUTPUT_DIR/test-opt.ll" -o "$OUTPUT_DIR/test.s" 2>&1
LLC_EXIT=$?
echo "LLC exit code: $LLC_EXIT"
if [ $LLC_EXIT -ne 0 ]; then
    echo "ERROR: LLC failed to generate assembly"
    exit 1
fi
echo ""
echo "=== Generated Assembly Code ==="
cat "$OUTPUT_DIR/test.s"
echo ""

echo "=== Step 4: Assemble to object file ==="
clang --target=powerpc-eabi -mcpu=ppe42 -c "$OUTPUT_DIR/test.s" -o "$OUTPUT_DIR/test.o"
echo "Object file generated: $OUTPUT_DIR/test.o"

echo "=== Step 5: Link if assembly succeeds ==="
clang --target=powerpc-eabi -mcpu=ppe42 -T ./linker -nostartfiles -nostdlib "$OUTPUT_DIR/test.o" ./startup.s -o "$OUTPUT_DIR/a.out"

llvm-objcopy -O binary "$OUTPUT_DIR/a.out" "$OUTPUT_DIR/a.bin"
hexdump -C "$OUTPUT_DIR/a.bin"
# printing disassembly
llvm-objdump -Sr "$OUTPUT_DIR/a.out" > "$OUTPUT_DIR/a.dis"
cat "$OUTPUT_DIR/a.dis"

# Made with Bob
