#!/bin/bash
set -e

echo "=== Step 1: Generate LLVM IR ==="
clang --target=powerpc-eabi -mcpu=ppe42 -Os -S -emit-llvm ./test.c -o test.ll
echo "LLVM IR generated: test.ll"
cat test.ll
echo ""

echo "=== Step 2: Optimize LLVM IR ==="
opt -O2 test.ll -S -o test-opt.ll
echo "Optimized IR: test-opt.ll"

echo "=== Step 3: Generate Assembly with debug ==="
llc -march=ppc32 -mcpu=ppe42 -O2 test-opt.ll -o test.s -print-after-all 2>&1 | head -200
echo "Assembly generated: test.s"
cat test.s
echo ""

echo "=== Step 4: Assemble to object file ==="
clang --target=powerpc-eabi -mcpu=ppe42 -c test.s -o test.o
echo "Object file generated: test.o"

echo "=== Step 5: Link if assembly succeeds ==="
clang --target=powerpc-eabi -mcpu=ppe42 -T ./linker -nostartfiles -nostdlib test.o ./startup.s -o a.out

llvm-objcopy -O binary a.out a.bin
hexdump -C a.bin
# printing disassembly
llvm-objdump -Sr a.out > a.dis
cat a.dis

# Made with Bob
