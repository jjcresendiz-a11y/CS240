 li $t1, 1
li $t2, 101
li $t3, 0

loop1:
rem $t4, $t1, 2
bne $t4, $zero, not_even

add $t3, $t3, $t1

not_even:
addi $t1, $t1, 1
bne $t1, $t2, loop1

li $v0, 1
move $a0, $t3
syscall