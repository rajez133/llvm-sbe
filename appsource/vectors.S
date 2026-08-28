.section    .vectors, "ax", @progbits

.global __vectors
__vectors:
        b   __machine_check

/* __set_msr becomes the PPE idle address
   when the corresponding msr bit is set */

.global __set_msr
.org    __vectors + 0x0010
__set_msr:
    mtmsr   %r3
    blr

.global __machine_check
.org    __vectors + 0x0020
__machine_check:
    b $

.global __system_reset
.org    __vectors + 0x0040
__system_reset:
    b __runtime_start

.global __data_storage
.org    __vectors + 0x0060
__data_storage:
    b $

.global __instruction_storage
.org    __vectors + 0x0080
__instruction_storage:
    b $

.global __external_interrupt
.org    __vectors + 0x00a0
__external_interrupt:
    b $

.global __alignment_exception
.org    __vectors + 0x00c0
__alignment_exception:
    b $

.global __program_exception
.org    __vectors + 0x00e0
__program_exception:
    b $

.global __dec_interrupt
.org    __vectors + 0x0100
__dec_interrupt:
    b $

.global __fit_interrupt
.org    __vectors + 0x0120
__fit_interrupt:
    b $

.global __watchdog_interrupt
.org    __vectors + 0x0140
__watchdog_interrupt:
    b $

.global __virtual_exception
.org    __vectors + 0x0160
__virtual_exception:
    b $
