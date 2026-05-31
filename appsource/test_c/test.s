	.file	"test.c"
	.text
	.globl	main                            # -- Begin function main
	.p2align	2
	.type	main,@function
main:                                   # @main
.Lfunc_begin0:
	.cfi_startproc
# %bb.0:
	stwu r1, -32(r1)
	stw r31, 28(r1)
	.cfi_def_cfa_offset 32
	.cfi_offset r31, -4
	mr	r31, r1
	.cfi_def_cfa_register r31
	li r3, 0
	stw r3, 24(r31)
	lis r3, 5
	stw r3, 20(r31)
	lwz r3, 20(r31)
	lwz r4, 0(r3)
	lwz r3, 4(r3)
	stw r3, 12(r31)
	stw r4, 8(r31)
	lwz r3, 12(r31)
	lwz r4, 8(r31)
	oris r4, r4, 32768
	stw r3, 12(r31)
	stw r4, 8(r31)
	lwz r3, 8(r31)
	lwz r4, 12(r31)
	lwz r5, 20(r31)
	stw r4, 4(r5)
	stw r3, 0(r5)
	b .LBB0_1
.LBB0_1:                                # =>This Inner Loop Header: Depth=1
	b .LBB0_1
.Lfunc_end0:
	.size	main, .Lfunc_end0-.Lfunc_begin0
	.cfi_endproc
                                        # -- End function
	.ident	"clang version 21.1.4 (/root/llvm-project/llvm/llvm 05b4df7ad6fdff0f029951a5b3fe2b3fa4cd20e9)"
	.section	".note.GNU-stack","",@progbits
