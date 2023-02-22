.section .text.first
.globl _entry
_entry:
1:
    la sp, _stack_start
    li a0, 0x1000
    // csrr a1, mhartid
    // addi a1, a1, 1
    // mul a0, a0, a1
    add sp, sp, a0
2:
    la a1, _bss_start
    la a2, _bss_end
    sub a2, a2, a1
    li a3, 3
    srl a2, a2, a3 // divide by 8
    li a3, 0
3:
    beq a2, a3, 4f // if a2 == a3 go to 4

    sd a3, 0(a1) // *a1 = 0
    addi a1, a1, 8
    addi a2, a2, -1 // a2 is remaining bytes

    bne a2, a3, 3b // if a2 != a3 go to 3
4:
    j start