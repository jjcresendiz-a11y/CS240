# =====================================================================
#  MIPS TIC-TAC-TOE  -  Module 4 game project
#  Written for MARS 4.5. Uses only basic console syscalls (print, read
#  string, exit) plus the Bitmap Display; no timing or random calls.
#
#  SETUP (Tools > Bitmap Display, then "Connect to MIPS"):
#         Unit Width in Pixels  : 4        Unit Height in Pixels : 4
#         Display Width         : 512      Display Height        : 256
#         Base address          : 0x10040000 (heap)
#  Assemble (F3), Run (F5), and type moves in the Run I/O console.
#
#  How it plays:
#    * You are X, the computer is O. Squares are numbered 1-9 (shown on
#      the bitmap in empty squares).  Type a square number to move.
#    * The computer wins if it can, blocks you if it must, otherwise
#      takes the centre, then a corner, then a side.
#    * Who moves first alternates each game.
#    * R = rules, Q = quit at the move prompt.
#
#  Screen layout (128 x 64 units): the board is 58 x 58 units centred
#  on the screen. After a game the three winning squares turn green and
#  the side panels turn gold (you won), red (computer won) or gray (tie).
#
#  board[i]: 0 empty, 1 = X (player), 2 = O (computer); i = 0..8
#  Register conventions: $a0-$a3 arguments, $v0-$v1 results, $t0-$t9
#  scratch, $s0-$s7 and $ra saved on the stack by any procedure that
#  uses them or calls another procedure.
# =====================================================================

        .eqv DISPLAY_BASE 0x10040000
        .eqv C_BG         0x00101050
        .eqv C_WHITE      0x00FFFFFF
        .eqv C_RED        0x00D00000
        .eqv C_CYAN       0x0000FFFF
        .eqv C_GOLD       0x00FFD700
        .eqv C_LGRAY      0x00C0C0C0
        .eqv C_HILITE     0x00206020
        .eqv C_NUM        0x00707090

        .data
pen:        .word 0                 # current drawing colour
board:      .word 0:9
winline:    .word -1                # index of winning line, -1 if none
result:     .word 0                 # 0 playing, 1 player, 2 computer, 3 tie
first:      .word 1                 # who moves first this game (1 or 2)
turn:       .word 1                 # whose turn it is (1 or 2)
wins:       .word 0
losses:     .word 0
ties:       .word 0
inbuf:      .space 32

# 3x5 pixel font for digits 0-9 (15 bits each, row 0 = top)
font:       .word 0x7B6F, 0x2C97, 0x73E7, 0x73CF, 0x5BC9
            .word 0x79CF, 0x79EF, 0x7249, 0x7BEF, 0x7BCF

# the 8 winning lines: 3 rows, 3 columns, 2 diagonals
lines:      .byte 0,1,2,  3,4,5,  6,7,8
            .byte 0,3,6,  1,4,7,  2,5,8
            .byte 0,4,8,  2,4,6
corners:    .byte 0,2,6,8
sides:      .byte 1,3,5,7

str_nl:     .asciiz "\n"
str_sep:    .asciiz "---+---+---\n"
str_title:  .asciiz "\n*********************************************\n*             TIC-TAC-TOE                   *\n*********************************************\n"
str_move:   .asciiz "Your move (1-9, R = rules, Q = quit): "
str_bad:    .asciiz "  Invalid input. Type a square number from 1 to 9.\n"
str_taken:  .asciiz "  That square is already taken. Choose another.\n"
str_firstp: .asciiz "\nNew game - you go first (you are X).\n"
str_firstc: .asciiz "\nNew game - the computer goes first (you are X).\n"
str_cpu:    .asciiz "Computer plays square "
msg_win:    .asciiz "\n*** You win! ***\n"
msg_lose:   .asciiz "\n*** The computer wins. ***\n"
msg_tie:    .asciiz "\n*** It's a tie! ***\n"
str_sc1:    .asciiz "Score - You: "
str_sc2:    .asciiz "   Computer: "
str_sc3:    .asciiz "   Ties: "
str_again:  .asciiz "Play again? (Y/N): "
str_bye:    .asciiz "\nThanks for playing!\n"

rules_a:    .ascii "\n=============== TIC-TAC-TOE RULES ===============\n"
            .ascii " You are X. The computer is O.\n"
            .ascii " Squares are numbered like this (also drawn on the board):\n"
            .ascii "    1 | 2 | 3\n"
            .ascii "   ---+---+---\n"
            .ascii "    4 | 5 | 6\n"
            .ascii "   ---+---+---\n"
            .ascii "    7 | 8 | 9\n"
            .ascii " Type the number of an empty square to place your X.\n"
            .ascii " Three in a row (across, down or diagonal) wins.\n"
            .ascii " A full board with no line is a tie.\n"
            .ascii " Who moves first alternates each game.\n"
            .ascii " At the move prompt: R = show rules, Q = quit.\n"
            .asciiz "=================================================\n"

        .text
        .globl main

# =====================================================================
#  main
# =====================================================================
main:
        la   $a0, str_title
        li   $v0, 4
        syscall
        jal  show_rules

game_loop:
        jal  init_game
        jal  play_game             # $v0 = 1 if the player quit
        bnez $v0, quit_game
        jal  show_result
        lw   $t0, first            # alternate who starts
        li   $t1, 3
        sub  $t0, $t1, $t0
        sw   $t0, first
        la   $a0, str_again
        li   $v0, 4
        syscall
        jal  read_line
        jal  first_char
        li   $t0, 121              # 'y'
        beq  $v0, $t0, game_loop

quit_game:
        la   $a0, str_bye
        li   $v0, 4
        syscall
        li   $v0, 10               # exit
        syscall

# =====================================================================
#  GAME FLOW
# =====================================================================
# init_game: clear the board, pick who starts, draw the empty board
init_game:
        addi $sp, $sp, -4
        sw   $ra, 0($sp)
        li   $t0, 0
ig_clear:
        li   $t1, 9
        bge  $t0, $t1, ig_set
        la   $t2, board
        sll  $t3, $t0, 2
        add  $t2, $t2, $t3
        sw   $zero, 0($t2)
        addi $t0, $t0, 1
        j    ig_clear
ig_set:
        li   $t0, -1
        sw   $t0, winline
        sw   $zero, result
        lw   $t0, first
        sw   $t0, turn
        li   $t1, 1
        la   $a0, str_firstp
        beq  $t0, $t1, ig_say
        la   $a0, str_firstc
ig_say:
        li   $v0, 4
        syscall
        jal  draw_board
        lw   $ra, 0($sp)
        addi $sp, $sp, 4
        jr   $ra

# play_game: alternate turns until a win, a tie, or the player quits
#   returns $v0 = 0 (game finished, result stored) or 1 (player quit)
play_game:
        addi $sp, $sp, -8
        sw   $ra, 4($sp)
        sw   $s0, 0($sp)
pg_loop:
        lw   $t0, turn
        li   $t1, 1
        bne  $t0, $t1, pg_comp
        jal  print_board           # player's turn
        jal  get_move              # $v0 = square index 0..8 or -1 = quit
        bltz $v0, pg_quit
        move $a0, $v0
        li   $a1, 1
        jal  place_mark
        j    pg_after
pg_comp:                            # computer's turn
        jal  computer_move
        move $s0, $v0
        move $a0, $s0
        li   $a1, 2
        jal  place_mark
        la   $a0, str_cpu
        li   $v0, 4
        syscall
        addi $a0, $s0, 1
        li   $v0, 1
        syscall
        la   $a0, str_nl
        li   $v0, 4
        syscall
pg_after:
        jal  draw_board
        jal  check_winner          # $v0 = 0 none, 1 X, 2 O
        bnez $v0, pg_won
        jal  board_full
        bnez $v0, pg_tie
        lw   $t0, turn             # switch player
        li   $t1, 3
        sub  $t0, $t1, $t0
        sw   $t0, turn
        j    pg_loop
pg_won:
        sw   $v0, result
        li   $v0, 0
        j    pg_done
pg_tie:
        li   $t0, 3
        sw   $t0, result
        li   $v0, 0
        j    pg_done
pg_quit:
        li   $v0, 1
pg_done:
        lw   $ra, 4($sp)
        lw   $s0, 0($sp)
        addi $sp, $sp, 8
        jr   $ra

# place_mark($a0 = square index, $a1 = player 1 or 2)
place_mark:
        la   $t0, board
        sll  $t1, $a0, 2
        add  $t0, $t0, $t1
        sw   $a1, 0($t0)
        jr   $ra

# get_move -> $v0 = valid empty square index 0..8, or -1 if the player quits
get_move:
        addi $sp, $sp, -4
        sw   $ra, 0($sp)
gm_prompt:
        la   $a0, str_move
        li   $v0, 4
        syscall
        jal  read_line
        jal  first_char
        li   $t0, 113              # 'q'
        beq  $v0, $t0, gm_quit
        li   $t0, 114              # 'r'
        bne  $v0, $t0, gm_parse
        jal  show_rules
        j    gm_prompt
gm_parse:
        jal  parse_int
        bltz $v0, gm_bad
        beqz $v0, gm_bad           # squares are numbered 1..9
        li   $t0, 9
        bgt  $v0, $t0, gm_bad
        addi $v0, $v0, -1          # convert to index 0..8
        la   $t0, board
        sll  $t1, $v0, 2
        add  $t0, $t0, $t1
        lw   $t2, 0($t0)
        bnez $t2, gm_taken
        j    gm_done
gm_bad:
        la   $a0, str_bad
        li   $v0, 4
        syscall
        j    gm_prompt
gm_taken:
        la   $a0, str_taken
        li   $v0, 4
        syscall
        j    gm_prompt
gm_quit:
        li   $v0, -1
gm_done:
        lw   $ra, 0($sp)
        addi $sp, $sp, 4
        jr   $ra

# =====================================================================
#  GAME LOGIC
# =====================================================================
# check_winner -> $v0 = 1 or 2 if that player has three in a row, else 0
# (also stores the winning line number in winline)
check_winner:
        li   $t0, 0                # line number
        la   $t9, lines
        la   $t8, board
cw_loop:
        li   $t1, 8
        bge  $t0, $t1, cw_none
        li   $t2, 3
        mul  $t2, $t0, $t2
        add  $t2, $t2, $t9         # &lines[line*3]
        lbu  $t3, 0($t2)
        lbu  $t4, 1($t2)
        lbu  $t5, 2($t2)
        sll  $t3, $t3, 2
        add  $t3, $t3, $t8
        lw   $t3, 0($t3)           # board value of cell 1
        sll  $t4, $t4, 2
        add  $t4, $t4, $t8
        lw   $t4, 0($t4)
        sll  $t5, $t5, 2
        add  $t5, $t5, $t8
        lw   $t5, 0($t5)
        beqz $t3, cw_next
        bne  $t3, $t4, cw_next
        bne  $t3, $t5, cw_next
        sw   $t0, winline
        move $v0, $t3
        jr   $ra
cw_next:
        addi $t0, $t0, 1
        j    cw_loop
cw_none:
        li   $v0, 0
        jr   $ra

# board_full -> $v0 = 1 if no empty square is left
board_full:
        li   $v0, 1
        li   $t0, 0
bf_loop:
        li   $t1, 9
        bge  $t0, $t1, bf_done
        la   $t2, board
        sll  $t3, $t0, 2
        add  $t2, $t2, $t3
        lw   $t4, 0($t2)
        beqz $t4, bf_empty
        addi $t0, $t0, 1
        j    bf_loop
bf_empty:
        li   $v0, 0
bf_done:
        jr   $ra

# find_win($a0 = player) -> $v0 = empty square that completes a line for
# that player (two of their marks and one empty), or -1
find_win:
        li   $t0, 0
        la   $t9, lines
        la   $t8, board
fw_loop:
        li   $t1, 8
        bge  $t0, $t1, fw_none
        li   $t2, 3
        mul  $t2, $t0, $t2
        add  $t2, $t2, $t9
        lbu  $t3, 0($t2)
        lbu  $t4, 1($t2)
        lbu  $t5, 2($t2)
        li   $t6, 0                # marks owned by the player
        li   $t7, -1               # an empty square in this line
        sll  $t1, $t3, 2           # cell 1
        add  $t1, $t1, $t8
        lw   $t1, 0($t1)
        bne  $t1, $a0, fw_a_np
        addi $t6, $t6, 1
        j    fw_b
fw_a_np:
        bnez $t1, fw_b
        move $t7, $t3
fw_b:
        sll  $t1, $t4, 2           # cell 2
        add  $t1, $t1, $t8
        lw   $t1, 0($t1)
        bne  $t1, $a0, fw_b_np
        addi $t6, $t6, 1
        j    fw_c
fw_b_np:
        bnez $t1, fw_c
        move $t7, $t4
fw_c:
        sll  $t1, $t5, 2           # cell 3
        add  $t1, $t1, $t8
        lw   $t1, 0($t1)
        bne  $t1, $a0, fw_c_np
        addi $t6, $t6, 1
        j    fw_chk
fw_c_np:
        bnez $t1, fw_chk
        move $t7, $t5
fw_chk:
        li   $t1, 2
        bne  $t6, $t1, fw_next
        bltz $t7, fw_next
        move $v0, $t7
        jr   $ra
fw_next:
        addi $t0, $t0, 1
        j    fw_loop
fw_none:
        li   $v0, -1
        jr   $ra

# first_empty($a0 = byte list of squares, $a1 = length) -> $v0 = first empty
# square in the list, or -1
first_empty:
        li   $t0, 0
fe_loop:
        bge  $t0, $a1, fe_none
        add  $t1, $a0, $t0
        lbu  $t1, 0($t1)           # square index
        la   $t2, board
        sll  $t3, $t1, 2
        add  $t2, $t2, $t3
        lw   $t4, 0($t2)
        beqz $t4, fe_found
        addi $t0, $t0, 1
        j    fe_loop
fe_found:
        move $v0, $t1
        jr   $ra
fe_none:
        li   $v0, -1
        jr   $ra

# computer_move -> $v0 = square index (0..8) for the computer (O)
# priority: win, block, centre, corner, side
computer_move:
        addi $sp, $sp, -4
        sw   $ra, 0($sp)
        li   $a0, 2
        jal  find_win              # can the computer win now?
        bgez $v0, cmv_done
        li   $a0, 1
        jal  find_win              # must it block the player?
        bgez $v0, cmv_done
        la   $t0, board
        lw   $t1, 16($t0)          # board[4] = centre
        bnez $t1, cmv_corner
        li   $v0, 4
        j    cmv_done
cmv_corner:
        la   $a0, corners
        li   $a1, 4
        jal  first_empty
        bgez $v0, cmv_done
        la   $a0, sides
        li   $a1, 4
        jal  first_empty
cmv_done:
        lw   $ra, 0($sp)
        addi $sp, $sp, 4
        jr   $ra

# in_win_line($a0 = square index) -> $v0 = 1 if it is in the winning line
in_win_line:
        lw   $t0, winline
        bltz $t0, iw_no
        la   $t1, lines
        li   $t2, 3
        mul  $t2, $t0, $t2
        add  $t1, $t1, $t2
        lbu  $t3, 0($t1)
        beq  $t3, $a0, iw_yes
        lbu  $t3, 1($t1)
        beq  $t3, $a0, iw_yes
        lbu  $t3, 2($t1)
        beq  $t3, $a0, iw_yes
iw_no:
        li   $v0, 0
        jr   $ra
iw_yes:
        li   $v0, 1
        jr   $ra

# =====================================================================
#  INPUT HELPERS
# =====================================================================
# read_line: read a line from the console into inbuf
read_line:
        la   $a0, inbuf
        li   $a1, 32
        li   $v0, 8
        syscall
        jr   $ra

# first_char -> $v0 = first non-blank char of inbuf, lower-cased (0 if none)
first_char:
        la   $t0, inbuf
fc_skip:
        lbu  $v0, 0($t0)
        li   $t1, 32
        beq  $v0, $t1, fc_next
        li   $t1, 9
        beq  $v0, $t1, fc_next
        j    fc_chk
fc_next:
        addi $t0, $t0, 1
        j    fc_skip
fc_chk:
        li   $t1, 65
        blt  $v0, $t1, fc_ret
        li   $t1, 90
        bgt  $v0, $t1, fc_ret
        addi $v0, $v0, 32
fc_ret:
        jr   $ra

# parse_int -> $v0 = non-negative integer in inbuf, or -1 if invalid
parse_int:
        la   $t0, inbuf
pi_skip:
        lbu  $t1, 0($t0)
        li   $t2, 32
        beq  $t1, $t2, pi_skipnext
        li   $t2, 9
        beq  $t1, $t2, pi_skipnext
        j    pi_digits
pi_skipnext:
        addi $t0, $t0, 1
        j    pi_skip
pi_digits:
        li   $v0, 0
        li   $t3, 0                # digit count
pi_loop:
        lbu  $t1, 0($t0)
        li   $t2, 48
        blt  $t1, $t2, pi_end
        li   $t2, 57
        bgt  $t1, $t2, pi_end
        addi $t1, $t1, -48
        li   $t4, 10
        mul  $v0, $v0, $t4
        add  $v0, $v0, $t1
        addi $t3, $t3, 1
        addi $t0, $t0, 1
        li   $t4, 9
        bgt  $t3, $t4, pi_bad      # more than 9 digits: reject
        j    pi_loop
pi_end:
        beqz $t3, pi_bad           # no digits
pi_tail:                            # only blanks / end of line may follow
        lbu  $t1, 0($t0)
        beqz $t1, pi_ok
        li   $t2, 10
        beq  $t1, $t2, pi_ok
        li   $t2, 13
        beq  $t1, $t2, pi_ok
        li   $t2, 32
        beq  $t1, $t2, pi_tailnext
        li   $t2, 9
        beq  $t1, $t2, pi_tailnext
        j    pi_bad
pi_tailnext:
        addi $t0, $t0, 1
        j    pi_tail
pi_ok:
        jr   $ra
pi_bad:
        li   $v0, -1
        jr   $ra

# =====================================================================
#  CONSOLE OUTPUT
# =====================================================================
# show_rules: print the rules sheet
show_rules:
        la   $a0, rules_a
        li   $v0, 4
        syscall
        jr   $ra

# print_board: draw the board in the console (X, O, or the square number)
print_board:
        la   $a0, str_nl
        li   $v0, 4
        syscall
        li   $t0, 0
pb_loop:
        li   $t1, 9
        bge  $t0, $t1, pb_done
        la   $t2, board
        sll  $t3, $t0, 2
        add  $t2, $t2, $t3
        lw   $t4, 0($t2)
        li   $a0, 32
        li   $v0, 11
        syscall
        addi $a0, $t0, 49          # default: '1' + index
        li   $t6, 1
        bne  $t4, $t6, pb_o
        li   $a0, 88               # 'X'
        j    pb_out
pb_o:
        li   $t6, 2
        bne  $t4, $t6, pb_out
        li   $a0, 79               # 'O'
pb_out:
        li   $v0, 11
        syscall
        li   $a0, 32
        li   $v0, 11
        syscall
        li   $t6, 3
        div  $t0, $t6
        mfhi $t7
        li   $t6, 2
        beq  $t7, $t6, pb_eol
        li   $a0, 124              # '|'
        li   $v0, 11
        syscall
        j    pb_next
pb_eol:
        la   $a0, str_nl
        li   $v0, 4
        syscall
        li   $t6, 8
        bge  $t0, $t6, pb_next
        la   $a0, str_sep
        li   $v0, 4
        syscall
pb_next:
        addi $t0, $t0, 1
        j    pb_loop
pb_done:
        jr   $ra

# show_result: announce the result, update the score, colour the side panels
show_result:
        addi $sp, $sp, -4
        sw   $ra, 0($sp)
        jal  print_board
        lw   $t0, result
        li   $t1, 1
        beq  $t0, $t1, sr_win
        li   $t1, 2
        beq  $t0, $t1, sr_lose
        lw   $t2, ties
        addi $t2, $t2, 1
        sw   $t2, ties
        la   $a0, msg_tie
        li   $t9, C_LGRAY
        j    sr_print
sr_win:
        lw   $t2, wins
        addi $t2, $t2, 1
        sw   $t2, wins
        la   $a0, msg_win
        li   $t9, C_GOLD
        j    sr_print
sr_lose:
        lw   $t2, losses
        addi $t2, $t2, 1
        sw   $t2, losses
        la   $a0, msg_lose
        li   $t9, C_RED
sr_print:
        li   $v0, 4
        syscall
        la   $a0, str_sc1
        li   $v0, 4
        syscall
        lw   $a0, wins
        li   $v0, 1
        syscall
        la   $a0, str_sc2
        li   $v0, 4
        syscall
        lw   $a0, losses
        li   $v0, 1
        syscall
        la   $a0, str_sc3
        li   $v0, 4
        syscall
        lw   $a0, ties
        li   $v0, 1
        syscall
        la   $a0, str_nl
        li   $v0, 4
        syscall
        move $a0, $t9              # coloured panels left and right of the board
        jal  set_pen
        li   $a0, 3
        li   $a1, 3
        li   $a2, 28
        li   $a3, 58
        jal  fill_rect
        li   $a0, 97
        li   $a1, 3
        li   $a2, 28
        li   $a3, 58
        jal  fill_rect
        lw   $ra, 0($sp)
        addi $sp, $sp, 4
        jr   $ra

# =====================================================================
#  BITMAP DISPLAY  (128 x 64 units, unit = 4x4 pixels)
# =====================================================================
# set_pen($a0 = colour)
set_pen:
        sw   $a0, pen
        jr   $ra

# put_pixel($a0 = x, $a1 = y): plot one unit in the current pen colour
put_pixel:
        bltz $a0, pp_done
        li   $t0, 128
        bge  $a0, $t0, pp_done
        bltz $a1, pp_done
        li   $t0, 64
        bge  $a1, $t0, pp_done
        sll  $t0, $a1, 7           # y * 128
        add  $t0, $t0, $a0
        sll  $t0, $t0, 2           # * 4 bytes per word
        li   $t1, DISPLAY_BASE
        add  $t0, $t0, $t1
        lw   $t2, pen
        sw   $t2, 0($t0)
pp_done:
        jr   $ra

# fill_rect($a0 = x, $a1 = y, $a2 = width, $a3 = height) in the pen colour
# (caller keeps the rectangle inside the 128 x 64 screen)
fill_rect:
        lw   $t0, pen
        li   $t1, DISPLAY_BASE
        li   $t2, 0
fr_row:
        bge  $t2, $a3, fr_done
        add  $t3, $a1, $t2
        sll  $t3, $t3, 7
        add  $t3, $t3, $a0
        sll  $t3, $t3, 2
        add  $t3, $t3, $t1
        li   $t4, 0
fr_col:
        bge  $t4, $a2, fr_next
        sw   $t0, 0($t3)
        addi $t3, $t3, 4
        addi $t4, $t4, 1
        j    fr_col
fr_next:
        addi $t2, $t2, 1
        j    fr_row
fr_done:
        jr   $ra

# draw_glyph($a0 = x, $a1 = y, $a2 = 15-bit glyph, $a3 = scale)
# 3x5 glyph, each pixel drawn as scale x scale units in the pen colour
draw_glyph:
        addi $sp, $sp, -24
        sw   $ra, 20($sp)
        sw   $s0, 16($sp)
        sw   $s1, 12($sp)
        sw   $s2, 8($sp)
        sw   $s3, 4($sp)
        sw   $s4, 0($sp)
        move $s0, $a0
        move $s1, $a1
        move $s2, $a2
        move $s3, $a3
        li   $s4, 0                # bit index 0..14
dg_loop:
        li   $t0, 15
        bge  $s4, $t0, dg_done
        li   $t1, 14
        sub  $t1, $t1, $s4
        srlv $t2, $s2, $t1
        andi $t2, $t2, 1
        beqz $t2, dg_skip
        li   $t3, 3
        div  $s4, $t3
        mfhi $t4                   # column
        mflo $t5                   # row
        mul  $t4, $t4, $s3
        mul  $t5, $t5, $s3
        add  $a0, $s0, $t4
        add  $a1, $s1, $t5
        move $a2, $s3
        move $a3, $s3
        jal  fill_rect
dg_skip:
        addi $s4, $s4, 1
        j    dg_loop
dg_done:
        lw   $ra, 20($sp)
        lw   $s0, 16($sp)
        lw   $s1, 12($sp)
        lw   $s2, 8($sp)
        lw   $s3, 4($sp)
        lw   $s4, 0($sp)
        addi $sp, $sp, 24
        jr   $ra

# draw_x($a0 = cell x, $a1 = cell y): red X inside an 18 x 18 cell
draw_x:
        addi $sp, $sp, -16
        sw   $ra, 12($sp)
        sw   $s0, 8($sp)
        sw   $s1, 4($sp)
        sw   $s2, 0($sp)
        move $s0, $a0
        move $s1, $a1
        li   $a0, C_RED
        jal  set_pen
        li   $s2, 0                # step 0..11 along both diagonals
dx_loop:
        li   $t0, 12
        bge  $s2, $t0, dx_done
        addi $t1, $s2, 3
        add  $a0, $s0, $t1         # "\" diagonal
        add  $a1, $s1, $t1
        li   $a2, 2
        li   $a3, 2
        jal  fill_rect
        li   $t1, 13
        sub  $t1, $t1, $s2
        add  $a0, $s0, $t1         # "/" diagonal
        addi $t2, $s2, 3
        add  $a1, $s1, $t2
        li   $a2, 2
        li   $a3, 2
        jal  fill_rect
        addi $s2, $s2, 1
        j    dx_loop
dx_done:
        lw   $ra, 12($sp)
        lw   $s0, 8($sp)
        lw   $s1, 4($sp)
        lw   $s2, 0($sp)
        addi $sp, $sp, 16
        jr   $ra

# draw_o($a0 = cell x, $a1 = cell y): cyan ring (circle) in an 18 x 18 cell
# A pixel is on the ring when 81 <= dx*dx + dy*dy <= 196, where dx and dy
# are measured from the cell centre in half-units.
draw_o:
        addi $sp, $sp, -20
        sw   $ra, 16($sp)
        sw   $s0, 12($sp)
        sw   $s1, 8($sp)
        sw   $s2, 4($sp)
        sw   $s3, 0($sp)
        move $s0, $a0
        move $s1, $a1
        li   $a0, C_CYAN
        jal  set_pen
        li   $s2, 0                # y
do_y:
        li   $t0, 18
        bge  $s2, $t0, do_done
        li   $s3, 0                # x
do_x:
        li   $t0, 18
        bge  $s3, $t0, do_ny
        sll  $t1, $s3, 1
        addi $t1, $t1, -17         # dx
        sll  $t2, $s2, 1
        addi $t2, $t2, -17         # dy
        mul  $t1, $t1, $t1
        mul  $t2, $t2, $t2
        add  $t3, $t1, $t2
        li   $t4, 81
        blt  $t3, $t4, do_skip
        li   $t4, 196
        bgt  $t3, $t4, do_skip
        add  $a0, $s0, $s3
        add  $a1, $s1, $s2
        jal  put_pixel
do_skip:
        addi $s3, $s3, 1
        j    do_x
do_ny:
        addi $s2, $s2, 1
        j    do_y
do_done:
        lw   $ra, 16($sp)
        lw   $s0, 12($sp)
        lw   $s1, 8($sp)
        lw   $s2, 4($sp)
        lw   $s3, 0($sp)
        addi $sp, $sp, 20
        jr   $ra

# draw_board: redraw the whole screen from the board array
#   grid lines are the white gaps between the 18 x 18 cells
draw_board:
        addi $sp, $sp, -20
        sw   $ra, 16($sp)
        sw   $s0, 12($sp)          # cell index
        sw   $s1, 8($sp)           # cell x
        sw   $s2, 4($sp)           # cell y
        sw   $s3, 0($sp)           # cell value
        li   $a0, C_BG
        jal  set_pen
        li   $a0, 0
        li   $a1, 0
        li   $a2, 128
        li   $a3, 64
        jal  fill_rect             # clear the screen
        li   $a0, C_WHITE
        jal  set_pen
        li   $a0, 35
        li   $a1, 3
        li   $a2, 58
        li   $a3, 58
        jal  fill_rect             # white board area (shows as grid lines)
        li   $s0, 0
dbd_loop:
        li   $t0, 9
        bge  $s0, $t0, dbd_done
        li   $t1, 3
        div  $s0, $t1
        mflo $t2                   # row
        mfhi $t3                   # column
        li   $t4, 20
        mul  $t3, $t3, $t4
        addi $s1, $t3, 35          # cell x
        mul  $t2, $t2, $t4
        addi $s2, $t2, 3           # cell y
        move $a0, $s0
        jal  in_win_line
        li   $a0, C_BG             # winning cells get a green background
        beqz $v0, dbd_bg
        li   $a0, C_HILITE
dbd_bg:
        jal  set_pen
        move $a0, $s1
        move $a1, $s2
        li   $a2, 18
        li   $a3, 18
        jal  fill_rect
        la   $t0, board
        sll  $t1, $s0, 2
        add  $t0, $t0, $t1
        lw   $s3, 0($t0)
        li   $t0, 1
        beq  $s3, $t0, dbd_x
        li   $t0, 2
        beq  $s3, $t0, dbd_o
        li   $a0, C_NUM            # empty square: show its number
        jal  set_pen
        la   $t0, font
        addi $t1, $s0, 1
        sll  $t1, $t1, 2
        add  $t0, $t0, $t1
        lw   $a2, 0($t0)
        addi $a0, $s1, 6
        addi $a1, $s2, 4
        li   $a3, 2
        jal  draw_glyph
        j    dbd_next
dbd_x:
        move $a0, $s1
        move $a1, $s2
        jal  draw_x
        j    dbd_next
dbd_o:
        move $a0, $s1
        move $a1, $s2
        jal  draw_o
dbd_next:
        addi $s0, $s0, 1
        j    dbd_loop
dbd_done:
        lw   $ra, 16($sp)
        lw   $s0, 12($sp)
        lw   $s1, 8($sp)
        lw   $s2, 4($sp)
        lw   $s3, 0($sp)
        addi $sp, $sp, 20
        jr   $ra
