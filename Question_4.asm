# Set-up
li $t0, 268500992

li $t2, 8
li $t3, 7
sw $t2, 0($t0)
sw $t3, 4($t0)

# Clear
li $t0, 0
li $t1, 0
li $t2, 0
li $t3, 0

# Program
li $t0, 268500992

lw $t3, 0($t0)
lw $t4, 4($t0)

add $t5, $t3, $t4

sw $t5, 8($t0)