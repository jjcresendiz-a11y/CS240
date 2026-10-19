# =====================================================================
#  MIPS BINGO  -  Module 4 game project (custom game)
#  Written for MARS 4.5 (uses MARS syscalls 30, 32, 40, 42).
#
#  SETUP (Tools menu in MARS) - same bitmap settings as the Blackjack game:
#    Tools > Bitmap Display:
#         Unit Width in Pixels  : 4        Unit Height in Pixels : 4
#         Display Width         : 512      Display Height        : 256
#         Base address          : 0x10040000 (heap)
#       then click "Connect to MIPS".
#    MODE 1 (real-time) ALSO needs Tools > Keyboard and Display MMIO
#       Simulator: click "Connect to MIPS" and type your keys into the
#       KEYBOARD box at the bottom of that window.
#    MODE 2 (console) needs only the console (Run I/O) for typing.
#
#  How it plays:
#    * A number is called every 5 seconds (bar at the bottom counts down).
#    * You mark your own card (left). The computer's card (right) is
#      marked automatically.
#    * Mode 1 keys:  W/A/S/D move the cyan cursor, Space marks/unmarks,
#                    B = call BINGO.
#    * Mode 2: after each 5-second display, type a number from your card
#      to mark/unmark it, B for Bingo, or just Enter for the next call.
#    * First full line (row, column or diagonal) of CALLED numbers wins.
#      The centre square is free.
#
#  Screen layout (128 x 64 units):
#    rows 2-6   : B I N G O column letters
#    rows 9-57  : two 5x5 cards (player x=3..51, computer x=76..124)
#    gutter     : last called letter and number (x=53..74)
#    rows 59-62 : countdown bar         rows 58-63: result bar at the end
#
#  Register conventions: $a0-$a3 arguments, $v0-$v1 results,
#  $t0-$t9 scratch, $s0-$s7 and $ra saved on the stack by any procedure
#  that uses them or calls another procedure.
# =====================================================================

        .eqv DISPLAY_BASE 0x10040000
        .eqv KBD_CTRL     0xffff0000    # keyboard ready flag (bit 0)
        .eqv KBD_DATA     0xffff0004    # keyboard data (last key typed)
        .eqv C_BG         0x00101050
        .eqv C_BLACK      0x00000000
        .eqv C_WHITE      0x00FFFFFF
        .eqv C_RED        0x00D00000
        .eqv C_GOLD       0x00FFD700
        .eqv C_CYAN       0x0000FFFF
        .eqv C_GRAY       0x00404040
        .eqv C_LGRAY      0x00C0C0C0

        .data
pen:        .word 0                 # current drawing colour
pcard:      .word 0:25              # player card numbers (index 12 = free = 0)
ccard:      .word 0:25              # computer card numbers
pmark:      .word 0:25              # 1 = marked
cmark:      .word 0:25
pool:       .word 0:75              # shuffled call order
poolpos:    .word 0
called:     .word 0:76              # called[n] = 1 once n has been called
tmp:        .word 0:75              # scratch for card building
lastcall:   .word 0
callnum:    .word 0
cursor:     .word 0                 # player's cursor cell 0..24
hilite:     .word -1                # cell to outline when drawing a grid
mode:       .word 1                 # 1 = real-time keys, 2 = console
winner:     .word 0                 # 1 player, 2 computer, 3 tie, 4 none
inbuf:      .space 32

# 3x5 pixel font, 15 bits per glyph (row 0 = top, 3 bits per row)
# index 0-9 = digits, 10 = B, 11 = I, 12 = N, 13 = G, 14 = O
font:       .word 0x7B6F, 0x2C97, 0x73E7, 0x73CF, 0x5BC9
            .word 0x79CF, 0x79EF, 0x7249, 0x7BEF, 0x7BCF
            .word 0x6BAE, 0x7497, 0x5FFD, 0x796F, 0x7B6F

# 5x5 diamond icon for the free square (one byte per row, bit 4 = left)
diamond:    .byte 0x04,0x0E,0x1F,0x0E,0x04

# the 12 winning lines (5 cell indexes each): rows, columns, diagonals
lines:      .byte 0,1,2,3,4,     5,6,7,8,9,     10,11,12,13,14
            .byte 15,16,17,18,19, 20,21,22,23,24
            .byte 0,5,10,15,20,  1,6,11,16,21,  2,7,12,17,22
            .byte 3,8,13,18,23,  4,9,14,19,24
            .byte 0,6,12,18,24,  4,8,12,16,20
bingostr:   .ascii "BINGO"

str_nl:     .asciiz "\n"
str_title:  .asciiz "\n*********************************************\n*               MIPS BINGO                  *\n*********************************************\n"
str_mode:   .asciiz "\nChoose a play mode:\n  1 = Real-time  (W/A/S/D + Space, needs the Keyboard MMIO tool)\n  2 = Console    (type the number you want to mark)\nEnter 1 or 2: "
str_mode_bad: .asciiz "  Invalid choice. Please type 1 or 2.\n"
str_rt_help:.asciiz "\nREAL-TIME SETUP:\n  1. Tools > Keyboard and Display MMIO Simulator > Connect to MIPS.\n  2. Click inside the KEYBOARD box (bottom of that window) and type there.\n  Keys: W/A/S/D = move cursor, Space = mark/unmark, B = call BINGO.\nPress Enter here in the console when both tools are connected... "
str_called1:.asciiz "\n>>> Number called: "
str_called2:.asciiz "   (call #"
str_called3:.asciiz ")\n"
str_prompt_c:.asciiz "Type a number to mark/unmark, B = Bingo, or Enter for next call: "
str_bad_c:  .asciiz "  Please type a number from 1 to 75, B, or just press Enter.\n"
str_notonc: .asciiz "  That number is not on your card.\n"
str_marked: .asciiz "  Marked.\n"
str_unmarked:.asciiz "  Unmarked.\n"
str_false:  .asciiz "  FALSE BINGO! You don't have a full line of called numbers. Keep playing.\n"
msg_win:    .asciiz "\n*** BINGO! You win! ***\n"
msg_lose:   .asciiz "\n*** The computer got BINGO first. You lose. ***\n"
msg_tie:    .asciiz "\n*** You both got BINGO on the same call - it's a tie! ***\n"
msg_none:   .asciiz "\nAll 75 numbers were called and nobody won.\n"
str_again:  .asciiz "\nPlay again? (Y/N): "
str_bye:    .asciiz "\nThanks for playing!\n"

rules_a:    .ascii "\n==================== BINGO RULES ====================\n"
            .ascii " CARD: 5x5 grid. Columns are B (1-15), I (16-30), N (31-45),\n"
            .ascii "   G (46-60), O (61-75). The centre square is a FREE space.\n"
            .ascii " CALLS: One number is called every 5 seconds. The latest call\n"
            .ascii "   shows in the middle of the screen with its letter.\n"
            .ascii " MARKING: YOU must mark your own card (left side). Squares you\n"
            .ascii "   mark turn red. The computer's card (right) marks itself.\n"
            .ascii " WINNING: First to complete a row, column or diagonal of five\n"
            .ascii "   called numbers (free space counts) and call BINGO wins.\n"
            .ascii " FALSE BINGO: If you call BINGO without a full line of numbers\n"
            .ascii "   that were really called, the call is rejected.\n"
            .ascii " TIE: If you and the computer finish on the same call, it's a tie.\n"
            .ascii " MODE 1 keys: W/A/S/D move cursor, Space mark/unmark, B = BINGO.\n"
            .ascii " MODE 2: type a number from your card, B for BINGO, Enter to skip.\n"
            .asciiz "======================================================\n"

        .text
        .globl main

# =====================================================================
#  main
# =====================================================================
main:
        li   $v0, 30                # time -> seed the random generator
        syscall
        move $a1, $a0
        li   $a0, 0
        li   $v0, 40
        syscall

        la   $a0, str_title
        li   $v0, 4
        syscall
        jal  show_rules
        jal  choose_mode

game_again:
        jal  init_game
        jal  play_game
        jal  show_result
        la   $a0, str_again
        li   $v0, 4
        syscall
        jal  read_line
        jal  first_char
        li   $t0, 121              # 'y'
        beq  $v0, $t0, game_again
        la   $a0, str_bye
        li   $v0, 4
        syscall
        li   $v0, 10               # exit
        syscall

# choose_mode: ask for mode 1 or 2 (re-asks on invalid input)
choose_mode:
        addi $sp, $sp, -4
        sw   $ra, 0($sp)
cm_prompt:
        la   $a0, str_mode
        li   $v0, 4
        syscall
        jal  read_line
        jal  parse_int
        li   $t0, 1
        beq  $v0, $t0, cm_ok
        li   $t0, 2
        beq  $v0, $t0, cm_ok
        la   $a0, str_mode_bad
        li   $v0, 4
        syscall
        j    cm_prompt
cm_ok:
        sw   $v0, mode
        li   $t0, 1
        bne  $v0, $t0, cm_done
        la   $a0, str_rt_help
        li   $v0, 4
        syscall
        jal  read_line             # wait for Enter
cm_done:
        lw   $ra, 0($sp)
        addi $sp, $sp, 4
        jr   $ra

# =====================================================================
#  GAME SETUP
# =====================================================================
# clear_array($a0 = address, $a1 = number of words)
clear_array:
        li   $t0, 0
ca_loop:
        bge  $t0, $a1, ca_done
        sll  $t1, $t0, 2
        add  $t1, $t1, $a0
        sw   $zero, 0($t1)
        addi $t0, $t0, 1
        j    ca_loop
ca_done:
        jr   $ra

# shuffle($a0 = array address, $a1 = n): Fisher-Yates
shuffle:
        addi $t0, $a1, -1          # i = n - 1
        move $t7, $a0              # keep base (syscall overwrites $a0)
sh_loop:
        blez $t0, sh_done
        li   $v0, 42               # random int in [0, upper)
        li   $a0, 0
        addi $a1, $t0, 1
        syscall                    # $a0 = j
        move $t1, $a0
        sll  $t3, $t0, 2
        add  $t3, $t3, $t7         # &a[i]
        sll  $t4, $t1, 2
        add  $t4, $t4, $t7         # &a[j]
        lw   $t5, 0($t3)
        lw   $t6, 0($t4)
        sw   $t6, 0($t3)
        sw   $t5, 0($t4)
        addi $t0, $t0, -1
        j    sh_loop
sh_done:
        jr   $ra

# make_card($a0 = card address): each column gets 5 unique numbers
# from its own range of 15; centre (index 12) is the free space (0)
make_card:
        addi $sp, $sp, -20
        sw   $ra, 16($sp)
        sw   $s0, 12($sp)
        sw   $s1, 8($sp)
        sw   $s2, 4($sp)
        sw   $s3, 0($sp)
        move $s0, $a0              # card address
        li   $s1, 0                # column
mc_col:
        li   $t0, 5
        bge  $s1, $t0, mc_done
        li   $t1, 15
        mul  $s3, $s1, $t1
        addi $s3, $s3, 1           # first number of this column's range
        li   $t2, 0
mc_fill:                            # tmp[0..14] = range
        li   $t3, 15
        bge  $t2, $t3, mc_shuf
        add  $t4, $s3, $t2
        la   $t5, tmp
        sll  $t6, $t2, 2
        add  $t5, $t5, $t6
        sw   $t4, 0($t5)
        addi $t2, $t2, 1
        j    mc_fill
mc_shuf:
        la   $a0, tmp
        li   $a1, 15
        jal  shuffle
        li   $t2, 0
mc_copy:                            # card[row*5+col] = tmp[row]
        li   $t3, 5
        bge  $t2, $t3, mc_next
        la   $t5, tmp
        sll  $t6, $t2, 2
        add  $t5, $t5, $t6
        lw   $t4, 0($t5)
        li   $t7, 5
        mul  $t7, $t2, $t7
        add  $t7, $t7, $s1
        sll  $t7, $t7, 2
        add  $t7, $t7, $s0
        sw   $t4, 0($t7)
        addi $t2, $t2, 1
        j    mc_copy
mc_next:
        addi $s1, $s1, 1
        j    mc_col
mc_done:
        sw   $zero, 48($s0)        # index 12 = free space
        lw   $ra, 16($sp)
        lw   $s0, 12($sp)
        lw   $s1, 8($sp)
        lw   $s2, 4($sp)
        lw   $s3, 0($sp)
        addi $sp, $sp, 20
        jr   $ra

# init_game: reset all state, build the call pool and both cards
init_game:
        addi $sp, $sp, -4
        sw   $ra, 0($sp)
        la   $a0, pmark
        li   $a1, 25
        jal  clear_array
        la   $a0, cmark
        li   $a1, 25
        jal  clear_array
        la   $a0, called
        li   $a1, 76
        jal  clear_array
        li   $t0, 1                # free square counts as marked
        la   $t1, pmark
        sw   $t0, 48($t1)
        la   $t1, cmark
        sw   $t0, 48($t1)
        li   $t0, 0                # pool[i] = i + 1
        la   $t1, pool
ig_pool:
        li   $t2, 75
        bge  $t0, $t2, ig_shuf
        addi $t3, $t0, 1
        sll  $t4, $t0, 2
        add  $t4, $t4, $t1
        sw   $t3, 0($t4)
        addi $t0, $t0, 1
        j    ig_pool
ig_shuf:
        la   $a0, pool
        li   $a1, 75
        jal  shuffle
        sw   $zero, poolpos
        sw   $zero, callnum
        sw   $zero, lastcall
        sw   $zero, winner
        sw   $zero, cursor
        la   $a0, pcard
        jal  make_card
        la   $a0, ccard
        jal  make_card
        lw   $ra, 0($sp)
        addi $sp, $sp, 4
        jr   $ra

# =====================================================================
#  GAME LOOP
# =====================================================================
# play_game: call a number every 5 seconds until someone wins
#   $s0 = number just called
play_game:
        addi $sp, $sp, -8
        sw   $ra, 4($sp)
        sw   $s0, 0($sp)
pg_loop:
        jal  call_next             # $v0 = number, 0 if none left
        beqz $v0, pg_nonum
        move $s0, $v0
        move $a0, $s0
        jal  computer_mark
        jal  draw_all
        la   $a0, str_called1
        li   $v0, 4
        syscall
        move $a0, $s0
        jal  print_call
        la   $a0, str_called2
        li   $v0, 4
        syscall
        lw   $a0, callnum
        li   $v0, 1
        syscall
        la   $a0, str_called3
        li   $v0, 4
        syscall

        lw   $t0, mode
        li   $t1, 1
        bne  $t0, $t1, pg_console
        jal  wait_window_rt        # 5 s window, keys polled
        j    pg_after
pg_console:
        jal  wait_window_console   # 5 s display, then typed marking
pg_after:
        beqz $v0, pg_cpu           # player did not claim a valid BINGO
        la   $a0, ccard            # player won - did computer finish too?
        la   $a1, cmark
        jal  validate_line
        li   $t0, 1
        beqz $v0, pg_set
        li   $t0, 3                # both completed: tie
pg_set:
        sw   $t0, winner
        j    pg_done
pg_cpu:
        la   $a0, ccard
        la   $a1, cmark
        jal  validate_line
        beqz $v0, pg_loop          # nobody yet: next call
        li   $t0, 2
        sw   $t0, winner
        j    pg_done
pg_nonum:
        li   $t0, 4
        sw   $t0, winner
pg_done:
        lw   $ra, 4($sp)
        lw   $s0, 0($sp)
        addi $sp, $sp, 8
        jr   $ra

# call_next -> $v0 = next number from the pool (0 if all 75 used)
call_next:
        lw   $t0, poolpos
        li   $t1, 75
        bge  $t0, $t1, cn_none
        la   $t2, pool
        sll  $t3, $t0, 2
        add  $t2, $t2, $t3
        lw   $v0, 0($t2)
        addi $t0, $t0, 1
        sw   $t0, poolpos
        la   $t4, called
        sll  $t5, $v0, 2
        add  $t4, $t4, $t5
        li   $t6, 1
        sw   $t6, 0($t4)           # called[n] = 1
        sw   $v0, lastcall
        lw   $t7, callnum
        addi $t7, $t7, 1
        sw   $t7, callnum
        jr   $ra
cn_none:
        li   $v0, 0
        jr   $ra

# find_number($a0 = card address, $a1 = number) -> $v0 = index 0..24 or -1
find_number:
        li   $t0, 0
fn_loop:
        li   $t1, 25
        bge  $t0, $t1, fn_none
        sll  $t2, $t0, 2
        add  $t2, $t2, $a0
        lw   $t3, 0($t2)
        beq  $t3, $a1, fn_found
        addi $t0, $t0, 1
        j    fn_loop
fn_found:
        move $v0, $t0
        jr   $ra
fn_none:
        li   $v0, -1
        jr   $ra

# computer_mark($a0 = number): computer stamps the number if it has it
computer_mark:
        addi $sp, $sp, -4
        sw   $ra, 0($sp)
        move $a1, $a0
        la   $a0, ccard
        jal  find_number
        bltz $v0, cmk_done
        la   $t0, cmark
        sll  $t1, $v0, 2
        add  $t0, $t0, $t1
        li   $t2, 1
        sw   $t2, 0($t0)
cmk_done:
        lw   $ra, 0($sp)
        addi $sp, $sp, 4
        jr   $ra

# validate_line($a0 = card, $a1 = marks) -> $v0 = 1 if some line has all five
# squares marked AND (except the free centre) really called
validate_line:
        li   $t0, 0                # line number
        la   $t9, lines
vl_line:
        li   $t1, 12
        bge  $t0, $t1, vl_no
        li   $t2, 0                # position in line
        li   $t3, 5
        mul  $t4, $t0, $t3         # line * 5
vl_cell:
        bge  $t2, $t3, vl_yes
        add  $t5, $t4, $t2
        add  $t5, $t5, $t9
        lbu  $t5, 0($t5)           # cell index
        sll  $t6, $t5, 2
        add  $t7, $t6, $a1
        lw   $t7, 0($t7)           # mark
        beqz $t7, vl_next
        li   $t8, 12
        beq  $t5, $t8, vl_ok       # free centre needs no number check
        add  $t7, $t6, $a0
        lw   $t7, 0($t7)           # number on that square
        la   $t8, called
        sll  $t7, $t7, 2
        add  $t8, $t8, $t7
        lw   $t8, 0($t8)           # was it called?
        beqz $t8, vl_next
vl_ok:
        addi $t2, $t2, 1
        j    vl_cell
vl_next:
        addi $t0, $t0, 1
        j    vl_line
vl_yes:
        li   $v0, 1
        jr   $ra
vl_no:
        li   $v0, 0
        jr   $ra

# toggle_mark($a0 = cell index): flip the player's mark (centre is ignored)
toggle_mark:
        li   $t0, 12
        beq  $a0, $t0, tm_done
        bltz $a0, tm_done
        li   $t0, 25
        bge  $a0, $t0, tm_done
        la   $t1, pmark
        sll  $t2, $a0, 2
        add  $t1, $t1, $t2
        lw   $t3, 0($t1)
        xori $t3, $t3, 1
        sw   $t3, 0($t1)
tm_done:
        jr   $ra

# claim_bingo -> $v0 = 1 if the player's card has a valid line, else 0
claim_bingo:
        addi $sp, $sp, -4
        sw   $ra, 0($sp)
        la   $a0, pcard
        la   $a1, pmark
        jal  validate_line
        bnez $v0, cb_done
        la   $a0, str_false
        li   $v0, 4
        syscall
        li   $v0, 0
cb_done:
        lw   $ra, 0($sp)
        addi $sp, $sp, 4
        jr   $ra

# =====================================================================
#  5-SECOND WINDOWS
# =====================================================================
# get_ms -> $v0 = system time in milliseconds (low 32 bits)
get_ms:
        li   $v0, 30
        syscall
        move $v0, $a0
        jr   $ra

# poll_key -> $v0 = key typed in the Keyboard MMIO tool, or 0 if none
poll_key:
        li   $t0, KBD_CTRL
        lw   $t1, 0($t0)
        andi $t1, $t1, 1           # ready bit
        beqz $t1, pk_none
        li   $t0, KBD_DATA
        lw   $v0, 0($t0)           # reading clears the ready bit
        jr   $ra
pk_none:
        li   $v0, 0
        jr   $ra

# handle_key($a0 = key) -> $v0 = 1 if the player made a valid BINGO claim
handle_key:
        addi $sp, $sp, -4
        sw   $ra, 0($sp)
        li   $t0, 65               # upper -> lower case
        blt  $a0, $t0, hk_go
        li   $t0, 90
        bgt  $a0, $t0, hk_go
        addi $a0, $a0, 32
hk_go:
        li   $t0, 119              # 'w'
        beq  $a0, $t0, hk_up
        li   $t0, 115              # 's'
        beq  $a0, $t0, hk_down
        li   $t0, 97               # 'a'
        beq  $a0, $t0, hk_left
        li   $t0, 100              # 'd'
        beq  $a0, $t0, hk_right
        li   $t0, 32               # space
        beq  $a0, $t0, hk_mark
        li   $t0, 109              # 'm' also marks
        beq  $a0, $t0, hk_mark
        li   $t0, 98               # 'b'
        beq  $a0, $t0, hk_bingo
        j    hk_none
hk_up:
        lw   $t1, cursor
        li   $t2, 5
        blt  $t1, $t2, hk_none     # already on the top row
        sub  $t1, $t1, $t2
        sw   $t1, cursor
        j    hk_redraw
hk_down:
        lw   $t1, cursor
        li   $t2, 20
        bge  $t1, $t2, hk_none     # already on the bottom row
        addi $t1, $t1, 5
        sw   $t1, cursor
        j    hk_redraw
hk_left:
        lw   $t1, cursor
        li   $t2, 5
        div  $t1, $t2
        mfhi $t3
        beqz $t3, hk_none          # already in the left column
        addi $t1, $t1, -1
        sw   $t1, cursor
        j    hk_redraw
hk_right:
        lw   $t1, cursor
        li   $t2, 5
        div  $t1, $t2
        mfhi $t3
        li   $t4, 4
        beq  $t3, $t4, hk_none     # already in the right column
        addi $t1, $t1, 1
        sw   $t1, cursor
        j    hk_redraw
hk_mark:
        lw   $a0, cursor
        jal  toggle_mark
        j    hk_redraw
hk_bingo:
        jal  claim_bingo           # result stays in $v0
        j    hk_ret
hk_redraw:
        jal  draw_all
hk_none:
        li   $v0, 0
hk_ret:
        lw   $ra, 0($sp)
        addi $sp, $sp, 4
        jr   $ra

# wait_window_rt -> $v0 = 1 if the player claimed a valid BINGO in the window
# Polls the keyboard for 5000 ms without blocking.
wait_window_rt:
        addi $sp, $sp, -16
        sw   $ra, 12($sp)
        sw   $s0, 8($sp)           # start time
        sw   $s1, 4($sp)           # result
        sw   $s2, 0($sp)           # elapsed ms
        jal  get_ms
        move $s0, $v0
        li   $s1, 0
wr_loop:
        jal  get_ms
        subu $s2, $v0, $s0
        sltiu $t0, $s2, 5000
        beqz $t0, wr_done          # 5 seconds are up
        move $a0, $s2
        jal  draw_timer_bar
        jal  poll_key
        beqz $v0, wr_sleep
        move $a0, $v0
        jal  handle_key
        beqz $v0, wr_sleep
        li   $s1, 1                # valid BINGO claim
        j    wr_done
wr_sleep:
        li   $a0, 30               # short sleep so we don't spin
        li   $v0, 32
        syscall
        j    wr_loop
wr_done:
        move $v0, $s1
        lw   $ra, 12($sp)
        lw   $s0, 8($sp)
        lw   $s1, 4($sp)
        lw   $s2, 0($sp)
        addi $sp, $sp, 16
        jr   $ra

# wait_window_console -> $v0 = 1 if the player claimed a valid BINGO
# Shows the number for 5 seconds (20 x 250 ms), then takes typed input.
wait_window_console:
        addi $sp, $sp, -8
        sw   $ra, 4($sp)
        sw   $s0, 0($sp)
        li   $s0, 0
wc_wait:
        li   $t0, 20
        bge  $s0, $t0, wc_clear
        li   $t1, 250
        mul  $a0, $s0, $t1
        jal  draw_timer_bar
        li   $a0, 250
        li   $v0, 32
        syscall
        addi $s0, $s0, 1
        j    wc_wait
wc_clear:
        li   $a0, 5000
        jal  draw_timer_bar        # empty bar
wc_prompt:
        la   $a0, str_prompt_c
        li   $v0, 4
        syscall
        jal  read_line
        jal  first_char
        li   $t0, 10
        beq  $v0, $t0, wc_skip     # just Enter: next call
        beqz $v0, wc_skip
        li   $t0, 98               # 'b'
        beq  $v0, $t0, wc_bingo
        jal  parse_int
        bltz $v0, wc_bad
        beqz $v0, wc_bad
        li   $t0, 75
        bgt  $v0, $t0, wc_bad
        move $a1, $v0
        la   $a0, pcard
        jal  find_number
        bltz $v0, wc_notfound
        move $s0, $v0              # cell index
        move $a0, $s0
        jal  toggle_mark
        jal  draw_all
        la   $t0, pmark
        sll  $t1, $s0, 2
        add  $t0, $t0, $t1
        lw   $t2, 0($t0)
        beqz $t2, wc_unm
        la   $a0, str_marked
        j    wc_say
wc_unm:
        la   $a0, str_unmarked
wc_say:
        li   $v0, 4
        syscall
        j    wc_prompt
wc_bad:
        la   $a0, str_bad_c
        li   $v0, 4
        syscall
        j    wc_prompt
wc_notfound:
        la   $a0, str_notonc
        li   $v0, 4
        syscall
        j    wc_prompt
wc_bingo:
        jal  claim_bingo
        beqz $v0, wc_prompt        # false claim: keep playing
        j    wc_ret                # $v0 = 1
wc_skip:
        li   $v0, 0
wc_ret:
        lw   $ra, 4($sp)
        lw   $s0, 0($sp)
        addi $sp, $sp, 8
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

# print_call($a0 = number): prints like "N-42"
print_call:
        addi $t0, $a0, -1
        li   $t1, 15
        div  $t0, $t1
        mflo $t2                   # 0..4 -> B I N G O
        move $t3, $a0
        la   $t4, bingostr
        add  $t4, $t4, $t2
        lbu  $a0, 0($t4)
        li   $v0, 11
        syscall
        li   $a0, 45               # '-'
        li   $v0, 11
        syscall
        move $a0, $t3
        li   $v0, 1
        syscall
        jr   $ra

# show_result: announce the winner in the console and on the bitmap
show_result:
        addi $sp, $sp, -4
        sw   $ra, 0($sp)
        jal  draw_all
        lw   $t0, winner
        li   $t1, 1
        beq  $t0, $t1, sr_win
        li   $t1, 2
        beq  $t0, $t1, sr_lose
        li   $t1, 3
        beq  $t0, $t1, sr_tie
        la   $a0, msg_none
        li   $t9, C_LGRAY          # result bar colour (no calls before it is used)
        j    sr_print
sr_win:
        la   $a0, msg_win
        li   $t9, C_GOLD
        j    sr_print
sr_lose:
        la   $a0, msg_lose
        li   $t9, C_RED
        j    sr_print
sr_tie:
        la   $a0, msg_tie
        li   $t9, C_LGRAY
sr_print:
        li   $v0, 4
        syscall
        move $a0, $t9              # coloured result bar across the bottom
        jal  set_pen
        li   $a0, 0
        li   $a1, 58
        li   $a2, 128
        li   $a3, 6
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

# fill_rect($a0 = x, $a1 = y, $a2 = width, $a3 = height) in the pen colour
# (caller keeps the rectangle inside the 128 x 64 screen)
fill_rect:
        lw   $t0, pen
        li   $t1, DISPLAY_BASE
        li   $t2, 0                # row counter
fr_row:
        bge  $t2, $a3, fr_done
        add  $t3, $a1, $t2
        sll  $t3, $t3, 7           # * 128
        add  $t3, $t3, $a0
        sll  $t3, $t3, 2           # * 4 bytes
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

# draw_number($a0 = x, $a1 = y, $a2 = number 0..99, $a3 = scale)
# one or two digits, left-aligned at x, in the pen colour
draw_number:
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
        li   $t0, 10
        blt  $s2, $t0, dn_ones_only
        div  $s2, $t0
        mflo $t1                   # tens digit
        mfhi $s4                   # ones digit
        la   $t2, font
        sll  $t3, $t1, 2
        add  $t2, $t2, $t3
        lw   $a2, 0($t2)
        move $a0, $s0
        move $a1, $s1
        move $a3, $s3
        jal  draw_glyph
        sll  $t0, $s3, 2           # advance 4 * scale
        add  $s0, $s0, $t0
        j    dn_ones
dn_ones_only:
        move $s4, $s2
dn_ones:
        la   $t2, font
        sll  $t3, $s4, 2
        add  $t2, $t2, $t3
        lw   $a2, 0($t2)
        move $a0, $s0
        move $a1, $s1
        move $a3, $s3
        jal  draw_glyph
        lw   $ra, 20($sp)
        lw   $s0, 16($sp)
        lw   $s1, 12($sp)
        lw   $s2, 8($sp)
        lw   $s3, 4($sp)
        lw   $s4, 0($sp)
        addi $sp, $sp, 24
        jr   $ra

# draw_diamond($a0 = x, $a1 = y): 5x5 diamond in the pen colour (free square)
draw_diamond:
        addi $sp, $sp, -28
        sw   $ra, 24($sp)
        sw   $s0, 20($sp)
        sw   $s1, 16($sp)
        sw   $s2, 12($sp)
        sw   $s3, 8($sp)
        sw   $s4, 4($sp)
        sw   $s5, 0($sp)
        move $s0, $a0
        move $s1, $a1
        li   $s3, 0                # row
dd_row:
        li   $t0, 5
        bge  $s3, $t0, dd_done
        la   $t1, diamond
        add  $t1, $t1, $s3
        lbu  $s4, 0($t1)           # row bits
        li   $s5, 0                # column
dd_col:
        li   $t0, 5
        bge  $s5, $t0, dd_nextrow
        li   $t1, 4
        sub  $t1, $t1, $s5
        srlv $t2, $s4, $t1
        andi $t2, $t2, 1
        beqz $t2, dd_skip
        add  $a0, $s0, $s5
        add  $a1, $s1, $s3
        li   $a2, 1
        li   $a3, 1
        jal  fill_rect
dd_skip:
        addi $s5, $s5, 1
        j    dd_col
dd_nextrow:
        addi $s3, $s3, 1
        j    dd_row
dd_done:
        lw   $ra, 24($sp)
        lw   $s0, 20($sp)
        lw   $s1, 16($sp)
        lw   $s2, 12($sp)
        lw   $s3, 8($sp)
        lw   $s4, 4($sp)
        lw   $s5, 0($sp)
        addi $sp, $sp, 28
        jr   $ra

# draw_cell($a0 = x, $a1 = y, $a2 = number, $a3 = state)
# state bits: 1 = marked, 2 = cursor here, 4 = free square. Cell is 9 x 9.
draw_cell:
        addi $sp, $sp, -20
        sw   $ra, 16($sp)
        sw   $s0, 12($sp)
        sw   $s1, 8($sp)
        sw   $s2, 4($sp)
        sw   $s3, 0($sp)
        move $s0, $a0
        move $s1, $a1
        move $s2, $a2
        move $s3, $a3
        andi $t0, $s3, 2           # border: cyan if cursor, else dark gray
        li   $a0, C_GRAY
        beqz $t0, dcl_b
        li   $a0, C_CYAN
dcl_b:
        jal  set_pen
        move $a0, $s0
        move $a1, $s1
        li   $a2, 9
        li   $a3, 9
        jal  fill_rect
        andi $t0, $s3, 4           # body: gold free, red marked, white plain
        li   $a0, C_GOLD
        bnez $t0, dcl_body
        andi $t0, $s3, 1
        li   $a0, C_RED
        bnez $t0, dcl_body
        li   $a0, C_WHITE
dcl_body:
        jal  set_pen
        addi $a0, $s0, 1
        addi $a1, $s1, 1
        li   $a2, 7
        li   $a3, 7
        jal  fill_rect
        andi $t0, $s3, 4
        bnez $t0, dcl_free
        andi $t0, $s3, 1           # digits: white on red, black on white
        li   $a0, C_WHITE
        bnez $t0, dcl_num
        li   $a0, C_BLACK
dcl_num:
        jal  set_pen
        addi $a0, $s0, 3           # one digit: centred
        li   $t0, 10
        blt  $s2, $t0, dcl_x
        addi $a0, $s0, 1           # two digits: fill the cell
dcl_x:
        addi $a1, $s1, 2
        move $a2, $s2
        li   $a3, 1
        jal  draw_number
        j    dcl_done
dcl_free:
        li   $a0, C_RED
        jal  set_pen
        addi $a0, $s0, 2
        addi $a1, $s1, 2
        jal  draw_diamond
dcl_done:
        lw   $ra, 16($sp)
        lw   $s0, 12($sp)
        lw   $s1, 8($sp)
        lw   $s2, 4($sp)
        lw   $s3, 0($sp)
        addi $sp, $sp, 20
        jr   $ra

# draw_grid($a0 = x0, $a1 = y0, $a2 = card, $a3 = marks)
# draws all 25 cells; the cell whose index equals global hilite gets the cursor
draw_grid:
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
        li   $s4, 0                # cell index
dgr_loop:
        li   $t0, 25
        bge  $s4, $t0, dgr_done
        li   $t1, 5
        div  $s4, $t1
        mflo $t2                   # row
        mfhi $t3                   # column
        li   $t4, 10
        mul  $t3, $t3, $t4
        add  $a0, $s0, $t3         # cell x
        mul  $t2, $t2, $t4
        add  $a1, $s1, $t2         # cell y
        sll  $t5, $s4, 2
        add  $t6, $t5, $s2
        lw   $a2, 0($t6)           # number
        add  $t6, $t5, $s3
        lw   $t7, 0($t6)
        andi $t7, $t7, 1           # marked bit
        lw   $t8, hilite
        bne  $t8, $s4, dgr_nc
        ori  $t7, $t7, 2           # cursor bit
dgr_nc:
        li   $t8, 12
        bne  $s4, $t8, dgr_go
        ori  $t7, $t7, 4           # free square bit
dgr_go:
        move $a3, $t7
        jal  draw_cell
        addi $s4, $s4, 1
        j    dgr_loop
dgr_done:
        lw   $ra, 20($sp)
        lw   $s0, 16($sp)
        lw   $s1, 12($sp)
        lw   $s2, 8($sp)
        lw   $s3, 4($sp)
        lw   $s4, 0($sp)
        addi $sp, $sp, 24
        jr   $ra

# draw_headers($a0 = x0): the letters B I N G O above a card's columns
draw_headers:
        addi $sp, $sp, -12
        sw   $ra, 8($sp)
        sw   $s0, 4($sp)
        sw   $s1, 0($sp)
        move $s0, $a0
        li   $s1, 0
dhd_loop:
        li   $t0, 5
        bge  $s1, $t0, dhd_done
        la   $t1, font
        addi $t2, $s1, 10          # glyph 10..14 = B I N G O
        sll  $t2, $t2, 2
        add  $t1, $t1, $t2
        lw   $a2, 0($t1)
        li   $t3, 10
        mul  $t3, $s1, $t3
        add  $a0, $s0, $t3
        addi $a0, $a0, 3
        li   $a1, 2
        li   $a3, 1
        jal  draw_glyph
        addi $s1, $s1, 1
        j    dhd_loop
dhd_done:
        lw   $ra, 8($sp)
        lw   $s0, 4($sp)
        lw   $s1, 0($sp)
        addi $sp, $sp, 12
        jr   $ra

# draw_gutter: the last called number, big (2x), between the two cards
draw_gutter:
        addi $sp, $sp, -8
        sw   $ra, 4($sp)
        sw   $s0, 0($sp)
        lw   $s0, lastcall
        blez $s0, dgu_done
        li   $a0, C_GOLD
        jal  set_pen
        addi $t0, $s0, -1
        li   $t1, 15
        div  $t0, $t1
        mflo $t2                   # column letter 0..4
        addi $t2, $t2, 10
        la   $t3, font
        sll  $t2, $t2, 2
        add  $t3, $t3, $t2
        lw   $a2, 0($t3)
        li   $a0, 61
        li   $a1, 17
        li   $a3, 2
        jal  draw_glyph
        li   $a0, C_WHITE
        jal  set_pen
        li   $a0, 61               # one digit
        li   $t0, 10
        blt  $s0, $t0, dgu_one
        li   $a0, 58               # two digits
dgu_one:
        li   $a1, 28
        move $a2, $s0
        li   $a3, 2
        jal  draw_number
dgu_done:
        lw   $ra, 4($sp)
        lw   $s0, 0($sp)
        addi $sp, $sp, 8
        jr   $ra

# draw_timer_bar($a0 = elapsed ms): gold bar that shrinks over 5000 ms
draw_timer_bar:
        addi $sp, $sp, -8
        sw   $ra, 4($sp)
        sw   $s0, 0($sp)
        move $s0, $a0
        li   $a0, C_BG             # clear the bar area
        jal  set_pen
        li   $a0, 0
        li   $a1, 59
        li   $a2, 128
        li   $a3, 4
        jal  fill_rect
        li   $a0, C_GOLD
        jal  set_pen
        li   $t0, 5000
        sub  $t0, $t0, $s0         # time left
        blez $t0, dtb_done
        li   $t1, 3
        mul  $t0, $t0, $t1
        li   $t1, 125
        div  $t0, $t1              # left * 3 / 125 = up to 120 units
        mflo $a2
        blez $a2, dtb_done
        li   $a0, 4
        li   $a1, 60
        li   $a3, 2
        jal  fill_rect
dtb_done:
        lw   $ra, 4($sp)
        lw   $s0, 0($sp)
        addi $sp, $sp, 8
        jr   $ra

# draw_all: redraw the whole screen from the current game state
draw_all:
        addi $sp, $sp, -4
        sw   $ra, 0($sp)
        li   $a0, C_BG
        jal  set_pen
        li   $a0, 0
        li   $a1, 0
        li   $a2, 128
        li   $a3, 64
        jal  fill_rect
        li   $a0, C_WHITE
        jal  set_pen
        li   $a0, 3
        jal  draw_headers          # player's column letters
        li   $a0, 76
        jal  draw_headers          # computer's column letters
        lw   $t0, mode             # cursor only shown in real-time mode
        li   $t1, 1
        bne  $t0, $t1, da_nocur
        lw   $t2, cursor
        j    da_set
da_nocur:
        li   $t2, -1
da_set:
        sw   $t2, hilite
        li   $a0, 3
        li   $a1, 9
        la   $a2, pcard
        la   $a3, pmark
        jal  draw_grid             # player's card (left)
        li   $t2, -1
        sw   $t2, hilite
        li   $a0, 76
        li   $a1, 9
        la   $a2, ccard
        la   $a3, cmark
        jal  draw_grid             # computer's card (right)
        jal  draw_gutter
        lw   $ra, 0($sp)
        addi $sp, $sp, 4
        jr   $ra
