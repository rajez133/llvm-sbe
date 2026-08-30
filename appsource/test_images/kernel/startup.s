/* PPE42 freestanding C runtime entry. */
        .section .text.startup, "ax", @progbits
        .globl __runtime_start
        .type __runtime_start, @function
__runtime_start:
        lis 3, 0xc000
        ori 3, 3, 0x0160
        lis 4, _VECTOR_START@ha
        addi 4, 4, _VECTOR_START@l
        li 5, 0
        stvd 4, 0(3)

        lis 2, _SDA2_BASE_@ha
        addi 2, 2, _SDA2_BASE_@l
        lis 13, _SDA_BASE_@ha
        addi 13, 13, _SDA_BASE_@l

        lis 3, _SRAM_CLEAR_START@ha
        addi 3, 3, _SRAM_CLEAR_START@l
        lis 4, _STACK_LIMIT@ha
        addi 4, 4, _STACK_LIMIT@l
.Lclear_bss:
        cmplw 3, 4
        bge .Lbss_done
        li 5, 0
        stw 5, 0(3)
        addi 3, 3, 4
        b .Lclear_bss
.Lbss_done:
        lis 1, _STACK@ha
        addi 1, 1, _STACK@l
        li 0, 0
        stwu 0, -8(1)
        bl main
.Lhalt:
        b .Lhalt
        .size __runtime_start, .-__runtime_start

        .globl __eabi
__eabi:
        blr
