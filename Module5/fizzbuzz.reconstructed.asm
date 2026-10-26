# Reconstructed by Disassembler.java
# Labels, formatting and pseudoinstructions are regenerated, not recovered.

.data
str_0: .asciiz "Fizz"
str_1: .asciiz "Buzz"

.text
.globl main

main:
    addiu $t1, $zero, 1
    addiu $t2, $zero, 101
L_00400008:
    jal L_0040001c
    jal L_0040009c
    addi $t1, $t1, 1
    bne $t1, $t2, L_00400008
    jal L_004000ac
L_0040001c:
    addi $sp, $sp, -8
    sw $ra, 0($sp)
    addiu $at, $zero, 3
    div $t1, $at
    mfhi $t3
    addiu $at, $zero, 5
    div $t1, $at
    mfhi $t4
    bne $t3, $zero, L_00400044
    jal L_00400064
L_00400044:
    bne $t4, $zero, L_00400050
    jal L_00400078
    j L_00400058
L_00400050:
    beq $t3, $zero, L_00400058
    jal L_0040008c
L_00400058:
    lw $ra, 0($sp)
    addi $sp, $sp, 8
    jr $ra
L_00400064:
    addiu $v0, $zero, 4
    la $a0, str_0
    syscall
    jr $ra
L_00400078:
    addiu $v0, $zero, 4
    la $a0, str_1
    syscall
    jr $ra
L_0040008c:
    addiu $v0, $zero, 1
    addu $a0, $t1, $zero
    syscall
    jr $ra
L_0040009c:
    addiu $v0, $zero, 11
    addiu $a0, $zero, 10
    syscall
    jr $ra
L_004000ac:
    addiu $v0, $zero, 10
    syscall
