	.text
	.globl	_start
	.type	_start, @function
_start:
	# Load address 0x50009 into r3
	lis	3, 5
	ori	3, 3, 9

	# Load 64-bit value from address in r3 using lvd into d4 (VD4 = R4:R5)
	lvd	4, 0(3)

	# Set bit 0 (MSB) of the high word (r4)
	# In PowerPC, bit 0 is the MSB, so we OR with 0x80000000
	lis	6, -32768      # Load 0x8000 into upper half of r6
	or	4, 4, 6        # Set MSB of r4

	# Store 64-bit value from d4 (R4:R5) back to address in r3
	stvd	4, 0(3)

	# Test VD31 register (R31:R0 wrap-around)
	# Load into d31 (VD31 = R31:R0)
	lvd	31, 8(3)

	# Store from d31 back to memory
	stvd	31, 16(3)

	# Infinite loop
.L_loop:
	b	.L_loop

	.size	_start, .-_start

# Made with Bob
