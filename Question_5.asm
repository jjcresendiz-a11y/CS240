.data
fizz_str:     .asciiz "Fizz\n"
buzz_str:     .asciiz "Buzz\n"
fizzbuzz_str: .asciiz "FizzBuzz\n"
newline:      .asciiz "\n"

.text

li $s0, 1
li $s1, 101

loop:
    beq $s0, $s1, exit

    li $t0, 15
    div $s0, $t0
    mfhi $t1
    beq $t1, $zero, print_fizzbuzz

    li $t0, 3
    div $s0, $t0
    mfhi $t1
    beq $t1, $zero, print_fizz

    li $t0, 5
    div $s0, $t0
    mfhi $t1
    beq $t1, $zero, print_buzz

    move $a0, $s0
    li $v0, 1
    syscall

    la $a0, newline
    li $v0, 4
    syscall

    j next_iter

print_fizzbuzz:
    la $a0, fizzbuzz_str
    li $v0, 4
    syscall
    j next_iter

print_fizz:
    la $a0, fizz_str
    li $v0, 4
    syscall
    j next_iter

print_buzz:
    la $a0, buzz_str
    li $v0, 4
    syscall

next_iter:
    addi $s0, $s0, 1
    j loop

exit:
    li $v0, 10
    syscall