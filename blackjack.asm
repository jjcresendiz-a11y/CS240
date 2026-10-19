# =====================================================================
#  MIPS BLACKJACK  -  Module 4 game project
#  Written for MARS 4.5 (uses MARS syscalls 30, 32, 40, 42).
#
#  SETUP (Tools menu in MARS):
#    1. Tools > Bitmap Display, then set:
#         Unit Width in Pixels  : 4
#         Unit Height in Pixels : 4
#         Display Width         : 512
#         Display Height        : 256
#         Base address          : 0x10040000 (heap)
#       and click "Connect to MIPS".
#    2. Assemble (F3) and Run (F5).
#    3. Type input in the MARS Run I/O console at the bottom.
#
#  Screen layout (128 x 64 units):
#    rows  3-15 : dealer's cards      rows 26-35 : result banner
#    rows 39-41 : gold bar = tokens (1 unit = 2 tokens)
#    rows 43-44 : red bar  = current bet
#    rows 46-58 : player's cards
#
#  Card id 0..51:  rank = id mod 13 (0=A,1..8=2..9,9=10,10=J,11=Q,12=K)
#                  suit = id / 13    (0 hearts,1 diamonds,2 clubs,3 spades)
#
#  Register conventions: $a0-$a3 arguments, $v0-$v1 results,
#  $t0-$t9 scratch (caller assumes clobbered), $s0-$s7 and $ra are saved
#  on the stack by any procedure that uses them or calls another procedure.
# =====================================================================

        .eqv DISPLAY_BASE 0x10040000
        .eqv C_FELT       0x00006400
        .eqv C_BLACK      0x00000000
        .eqv C_WHITE      0x00FFFFFF
        .eqv C_RED        0x00D00000
        .eqv C_BLUE       0x00000090
        .eqv C_LBLUE      0x006060FF
        .eqv C_GOLD       0x00FFD700

        .data
pen:        .word 0                 # current drawing colour
deck:       .word 0:52              # card ids in draw order
deckpos:    .word 0                 # index of next card to deal
decksize:   .word 0                 # number of valid cards in deck[]
phand:      .word 0:16              # player cards
pcount:     .word 0
dhand:      .word 0:16              # dealer cards
dcount:     .word 0
tokens:     .word 100
bet:        .word 0
inbuf:      .space 32               # console input buffer

# 3x5 pixel font, 15 bits per glyph (row 0 = top, 3 bits per row)
# index: 0-9 digits, 10 = A, 11 = J, 12 = Q, 13 = K
font:       .word 0x7B6F, 0x2C97, 0x73E7, 0x73CF, 0x5BC9
            .word 0x79CF, 0x79EF, 0x7249, 0x7BEF, 0x7BCF
            .word 0x2BED, 0x126A, 0x2B7B, 0x5BAD

# result banner colours: 0 lose, 1 win, 2 push, 3 blackjack
banner_colors: .word 0x00FF0000, 0x00FFD700, 0x00C0C0C0, 0x0000FFFF

suitnames:  .word s_hearts, s_diamonds, s_clubs, s_spades
res_msgs:   .word msg_lose, msg_win, msg_push, msg_bj

# 5x5 suit icons, one byte per row (bit 4 = leftmost pixel)
suitpat:    .byte 0x0A,0x1F,0x1F,0x0E,0x04      # hearts
            .byte 0x04,0x0E,0x1F,0x0E,0x04      # diamonds
            .byte 0x0E,0x0E,0x1F,0x1F,0x04      # clubs
            .byte 0x04,0x0E,0x1F,0x1F,0x04      # spades
facechars:  .ascii "JQK"

s_hearts:   .asciiz "Hearts"
s_diamonds: .asciiz "Diamonds"
s_clubs:    .asciiz "Clubs"
s_spades:   .asciiz "Spades"
str_of:     .asciiz " of "
str_nl:     .asciiz "\n"
str_hidden: .asciiz "[hidden card]"
str_comma:  .asciiz ", "
str_total1: .asciiz "   (Total: "
str_total2: .asciiz ")"
str_dealer: .asciiz "Dealer: "
str_player: .asciiz "Player: "

str_title:  .asciiz "\n*********************************************\n*           MIPS BLACKJACK  (21)            *\n*********************************************\n"
str_bet1:   .asciiz "\nTokens: "
str_bet2:   .asciiz "   Enter your bet (R = rules, Q = quit): "
str_bad_num:.asciiz "  Invalid input. Please type a whole number like 25.\n"
str_zero:   .asciiz "  Your bet must be at least 1 token.\n"
str_toomuch:.asciiz "  You don't have that many tokens.\n"
str_action: .asciiz "Your move - [H]it, [S]tand, [R]ules: "
str_bad_act:.asciiz "  Invalid input. Type H to hit or S to stand.\n"
str_reshuf: .asciiz "  *** Shuffling the deck ***\n"
str_bust:   .asciiz "  BUST! Your total is over 21.\n"
str_dbj:    .asciiz "  Dealer has Blackjack.\n"
msg_lose:   .asciiz "  RESULT: You lose your bet.\n"
msg_win:    .asciiz "  RESULT: You win! Paid 1:1.\n"
msg_push:   .asciiz "  RESULT: Push (tie) - your bet is returned.\n"
msg_bj:     .asciiz "  RESULT: BLACKJACK! Paid 3:2.\n"
str_now:    .asciiz "  Tokens now: "
str_broke:  .asciiz "\nYou are out of tokens! Start over with 100 tokens? (Y/N): "
str_bye:    .asciiz "\nThanks for playing! Final tokens: "

rules_a:    .ascii "\n================= BLACKJACK RULES =================\n"
            .ascii " GOAL: Get closer to 21 than the dealer without going over.\n"
            .ascii " CARDS: 2-10 are face value, J/Q/K = 10, Ace = 1 or 11.\n"
            .ascii " DEAL: You and the dealer get 2 cards. One dealer card is hidden.\n"
            .ascii " YOUR TURN: Hit (H) to take a card, Stand (S) to stop.\n"
            .ascii "   Going over 21 is a BUST and you lose immediately.\n"
            .ascii " DEALER: Reveals the hidden card and hits until 17 or more.\n"
            .ascii "   The dealer stands on all 17s.\n"
            .ascii " PAYOUTS: Win = 1:1.  Push (tie) = bet returned.\n"
            .ascii "   Blackjack (Ace + 10-value card on the first 2 cards)\n"
            .ascii "   pays 3:2 (rounded down to a whole token).\n"
            .ascii "   If you both have Blackjack it is a push.\n"
            .ascii " TOKENS: You start with 100. Bet any whole amount you have.\n"
            .ascii " DECK: One 52-card deck, reshuffled when every card is used.\n"
            .ascii "   (Cards still in play are kept out of the reshuffle.)\n"
            .ascii " BANNER COLOURS: gold = win, cyan = blackjack,\n"
            .ascii "   red = lose, gray = push.\n"
            .ascii " BARS: gold bar = your tokens, red bar = your bet.\n"
            .asciiz "====================================================\n"

        .text
        .globl main

# =====================================================================
#  main
# =====================================================================
main:
        li   $v0, 30                # system time -> $a0 (low 32 bits)
        syscall
        move $a1, $a0              # seed value
        li   $a0, 0                # generator id 0
        li   $v0, 40               # set seed
        syscall

        li   $t0, 100
        sw   $t0, tokens

        la   $a0, str_title
        li   $v0, 4
        syscall
        jal  show_rules

        li   $a0, 0
        jal  draw_table            # empty table so the display isn't blank

game_loop:
        lw   $t0, tokens
        blez $t0, broke
        jal  get_bet               # $v0 = bet, or -1 to quit
        bltz $v0, quit_game
        sw   $v0, bet
        jal  play_round
        j    game_loop

broke:
        la   $a0, str_broke
        li   $v0, 4
        syscall
        jal  read_line
        jal  first_char
        li   $t0, 121              # 'y'
        bne  $v0, $t0, quit_game
        li   $t0, 100
        sw   $t0, tokens
        li   $a0, 0
        jal  draw_table
        j    game_loop

quit_game:
        la   $a0, str_bye
        li   $v0, 4
        syscall
        lw   $a0, tokens
        li   $v0, 1
        syscall
        la   $a0, str_nl
        li   $v0, 4
        syscall
        li   $v0, 10               # exit
        syscall

# =====================================================================
#  GAME ROUND
# =====================================================================
# play_round: one complete hand. Uses globals bet and tokens.
#   $s0 = outcome (0 lose, 1 win, 2 push, 3 blackjack)
#   $s1 = player total, $s2 = dealer total
play_round:
        addi $sp, $sp, -16
        sw   $ra, 12($sp)
        sw   $s0, 8($sp)
        sw   $s1, 4($sp)
        sw   $s2, 0($sp)

        sw   $zero, pcount
        sw   $zero, dcount

        la   $a0, phand            # initial deal: P, D, P, D
        la   $a1, pcount
        jal  deal_to
        la   $a0, dhand
        la   $a1, dcount
        jal  deal_to
        la   $a0, phand
        la   $a1, pcount
        jal  deal_to
        la   $a0, dhand
        la   $a1, dcount
        jal  deal_to

        la   $a0, phand
        lw   $a1, pcount
        jal  hand_value
        move $s1, $v0
        la   $a0, dhand
        lw   $a1, dcount
        jal  hand_value
        move $s2, $v0

        li   $t0, 21
        beq  $s1, $t0, pr_player21
        beq  $s2, $t0, pr_dealer21

        li   $a0, 1                # normal start: hide dealer's 2nd card
        jal  refresh_screen
        j    pr_player_turn

pr_player21:                        # player has blackjack
        li   $a0, 0
        jal  refresh_screen
        li   $t0, 21
        beq  $s2, $t0, pr_push_nat
        li   $s0, 3
        j    pr_settle
pr_push_nat:
        li   $s0, 2
        j    pr_settle

pr_dealer21:                        # dealer has blackjack, player does not
        li   $a0, 0
        jal  refresh_screen
        la   $a0, str_dbj
        li   $v0, 4
        syscall
        li   $s0, 0
        j    pr_settle

pr_player_turn:
        jal  get_action            # $v0 = 1 hit, 0 stand
        beqz $v0, pr_dealer_turn
        la   $a0, phand
        la   $a1, pcount
        jal  deal_to
        la   $a0, phand
        lw   $a1, pcount
        jal  hand_value
        move $s1, $v0
        li   $a0, 1
        jal  refresh_screen
        li   $t0, 21
        bgt  $s1, $t0, pr_bust
        beq  $s1, $t0, pr_dealer_turn   # 21: stand automatically
        j    pr_player_turn

pr_bust:
        la   $a0, str_bust
        li   $v0, 4
        syscall
        li   $s0, 0
        j    pr_settle

pr_dealer_turn:
        li   $a0, 0                # reveal hidden card
        jal  refresh_screen
        jal  pause
pr_dloop:
        la   $a0, dhand
        lw   $a1, dcount
        jal  hand_value
        move $s2, $v0
        li   $t0, 17
        bge  $s2, $t0, pr_compare  # dealer stands on 17 or more
        la   $a0, dhand
        la   $a1, dcount
        jal  deal_to
        li   $a0, 0
        jal  refresh_screen
        jal  pause
        j    pr_dloop

pr_compare:
        li   $t0, 21
        bgt  $s2, $t0, pr_win      # dealer busted
        bgt  $s1, $s2, pr_win
        blt  $s1, $s2, pr_lose
        li   $s0, 2                # equal totals: push
        j    pr_settle
pr_win:
        li   $s0, 1
        j    pr_settle
pr_lose:
        li   $s0, 0

pr_settle:                          # update tokens from outcome in $s0
        lw   $t0, tokens
        lw   $t1, bet
        li   $t2, 1
        beq  $s0, $t2, ps_win
        li   $t2, 3
        beq  $s0, $t2, ps_bj
        beqz $s0, ps_lose
        j    ps_apply              # push: no change
ps_win:
        add  $t0, $t0, $t1
        j    ps_apply
ps_bj:
        li   $t3, 3
        mul  $t3, $t1, $t3         # bet * 3
        srl  $t3, $t3, 1           # / 2, rounded down
        add  $t0, $t0, $t3
        j    ps_apply
ps_lose:
        sub  $t0, $t0, $t1
ps_apply:
        sw   $t0, tokens

        li   $a0, 0                # final redraw with updated token bar
        jal  refresh_screen
        la   $t0, banner_colors
        sll  $t1, $s0, 2
        add  $t0, $t0, $t1
        lw   $a0, 0($t0)
        jal  draw_banner

        la   $t0, res_msgs
        sll  $t1, $s0, 2
        add  $t0, $t0, $t1
        lw   $a0, 0($t0)
        li   $v0, 4
        syscall
        la   $a0, str_now
        li   $v0, 4
        syscall
        lw   $a0, tokens
        li   $v0, 1
        syscall
        la   $a0, str_nl
        li   $v0, 4
        syscall

        lw   $ra, 12($sp)
        lw   $s0, 8($sp)
        lw   $s1, 4($sp)
        lw   $s2, 0($sp)
        addi $sp, $sp, 16
        jr   $ra

# pause: short delay so dealer draws are visible
pause:
        li   $a0, 700
        li   $v0, 32
        syscall
        jr   $ra

# =====================================================================
#  DECK AND HAND LOGIC
# =====================================================================
# in_hand($a0 = card, $a1 = hand address, $a2 = count) -> $v0 = 1 if found
in_hand:
        li   $v0, 0
        li   $t0, 0
ih_loop:
        bge  $t0, $a2, ih_done
        sll  $t1, $t0, 2
        add  $t1, $t1, $a1
        lw   $t2, 0($t1)
        beq  $t2, $a0, ih_yes
        addi $t0, $t0, 1
        j    ih_loop
ih_yes:
        li   $v0, 1
ih_done:
        jr   $ra

# shuffle_deck($a0 = n): Fisher-Yates shuffle of deck[0..n-1]
shuffle_deck:
        addi $t0, $a0, -1          # i = n - 1
sd_loop:
        blez $t0, sd_done
        li   $v0, 42               # random int in [0, upper)
        li   $a0, 0
        addi $a1, $t0, 1           # upper bound = i + 1
        syscall                    # $a0 = j
        move $t1, $a0
        la   $t2, deck
        sll  $t3, $t0, 2
        add  $t3, $t3, $t2         # &deck[i]
        sll  $t4, $t1, 2
        add  $t4, $t4, $t2         # &deck[j]
        lw   $t5, 0($t3)
        lw   $t6, 0($t4)
        sw   $t6, 0($t3)
        sw   $t5, 0($t4)
        addi $t0, $t0, -1
        j    sd_loop
sd_done:
        jr   $ra

# reshuffle_deck: rebuild deck from all cards NOT in either hand, shuffle it
reshuffle_deck:
        addi $sp, $sp, -16
        sw   $ra, 12($sp)
        sw   $s0, 8($sp)
        sw   $s1, 4($sp)
        sw   $s2, 0($sp)
        li   $s0, 0                # card id
        li   $s1, 0                # cards placed in deck
rs_loop:
        li   $t0, 52
        bge  $s0, $t0, rs_done
        move $a0, $s0
        la   $a1, phand
        lw   $a2, pcount
        jal  in_hand
        bnez $v0, rs_next
        move $a0, $s0
        la   $a1, dhand
        lw   $a2, dcount
        jal  in_hand
        bnez $v0, rs_next
        la   $t0, deck
        sll  $t1, $s1, 2
        add  $t0, $t0, $t1
        sw   $s0, 0($t0)
        addi $s1, $s1, 1
rs_next:
        addi $s0, $s0, 1
        j    rs_loop
rs_done:
        sw   $s1, decksize
        sw   $zero, deckpos
        move $a0, $s1
        jal  shuffle_deck
        lw   $ra, 12($sp)
        lw   $s0, 8($sp)
        lw   $s1, 4($sp)
        lw   $s2, 0($sp)
        addi $sp, $sp, 16
        jr   $ra

# deal_card -> $v0 = next card id (reshuffles when the deck is used up)
deal_card:
        addi $sp, $sp, -4
        sw   $ra, 0($sp)
        lw   $t0, deckpos
        lw   $t1, decksize
        blt  $t0, $t1, dc_ok
        la   $a0, str_reshuf
        li   $v0, 4
        syscall
        jal  reshuffle_deck
dc_ok:
        lw   $t0, deckpos
        la   $t1, deck
        sll  $t2, $t0, 2
        add  $t1, $t1, $t2
        lw   $v0, 0($t1)
        addi $t0, $t0, 1
        sw   $t0, deckpos
        lw   $ra, 0($sp)
        addi $sp, $sp, 4
        jr   $ra

# add_to_hand($a0 = hand address, $a1 = address of count, $a2 = card)
add_to_hand:
        lw   $t0, 0($a1)
        sll  $t1, $t0, 2
        add  $t1, $t1, $a0
        sw   $a2, 0($t1)
        addi $t0, $t0, 1
        sw   $t0, 0($a1)
        jr   $ra

# deal_to($a0 = hand address, $a1 = address of count): deal one card
deal_to:
        addi $sp, $sp, -12
        sw   $ra, 8($sp)
        sw   $s0, 4($sp)
        sw   $s1, 0($sp)
        move $s0, $a0
        move $s1, $a1
        jal  deal_card
        move $a2, $v0
        move $a0, $s0
        move $a1, $s1
        jal  add_to_hand
        lw   $ra, 8($sp)
        lw   $s0, 4($sp)
        lw   $s1, 0($sp)
        addi $sp, $sp, 12
        jr   $ra

# hand_value($a0 = hand address, $a1 = count) -> $v0 = best total <= 21 if possible
hand_value:
        li   $t0, 0                # i
        li   $t1, 0                # sum (aces counted as 1)
        li   $t2, 0                # number of aces
hv_loop:
        bge  $t0, $a1, hv_adjust
        sll  $t3, $t0, 2
        add  $t3, $t3, $a0
        lw   $t4, 0($t3)
        li   $t5, 13
        div  $t4, $t5
        mfhi $t4                   # rank 0..12
        addi $t4, $t4, 1           # 1..13
        li   $t6, 10
        ble  $t4, $t6, hv_pts
        li   $t4, 10               # J, Q, K = 10
hv_pts:
        li   $t6, 1
        bne  $t4, $t6, hv_add
        addi $t2, $t2, 1
hv_add:
        add  $t1, $t1, $t4
        addi $t0, $t0, 1
        j    hv_loop
hv_adjust:
        beqz $t2, hv_ret
        addi $t3, $t1, 10          # try counting one ace as 11
        li   $t6, 21
        bgt  $t3, $t6, hv_ret
        move $t1, $t3
hv_ret:
        move $v0, $t1
        jr   $ra

# =====================================================================
#  INPUT
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
        addi $v0, $v0, 32          # upper -> lower case
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
        beqz $t3, pi_bad           # no digits at all
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

# get_bet -> $v0 = valid bet (1..tokens), or -1 if the player quits
get_bet:
        addi $sp, $sp, -4
        sw   $ra, 0($sp)
gb_prompt:
        la   $a0, str_bet1
        li   $v0, 4
        syscall
        lw   $a0, tokens
        li   $v0, 1
        syscall
        la   $a0, str_bet2
        li   $v0, 4
        syscall
        jal  read_line
        jal  first_char
        li   $t0, 113              # 'q'
        beq  $v0, $t0, gb_quit
        li   $t0, 114              # 'r'
        bne  $v0, $t0, gb_parse
        jal  show_rules
        j    gb_prompt
gb_parse:
        jal  parse_int
        bltz $v0, gb_invalid
        beqz $v0, gb_zero
        lw   $t0, tokens
        bgt  $v0, $t0, gb_toomuch
        j    gb_done
gb_invalid:
        la   $a0, str_bad_num
        li   $v0, 4
        syscall
        j    gb_prompt
gb_zero:
        la   $a0, str_zero
        li   $v0, 4
        syscall
        j    gb_prompt
gb_toomuch:
        la   $a0, str_toomuch
        li   $v0, 4
        syscall
        j    gb_prompt
gb_quit:
        li   $v0, -1
gb_done:
        lw   $ra, 0($sp)
        addi $sp, $sp, 4
        jr   $ra

# get_action -> $v0 = 1 (hit) or 0 (stand)
get_action:
        addi $sp, $sp, -4
        sw   $ra, 0($sp)
ga_prompt:
        la   $a0, str_action
        li   $v0, 4
        syscall
        jal  read_line
        jal  first_char
        li   $t0, 104              # 'h'
        beq  $v0, $t0, ga_hit
        li   $t0, 115              # 's'
        beq  $v0, $t0, ga_stand
        li   $t0, 114              # 'r'
        bne  $v0, $t0, ga_invalid
        jal  show_rules
        j    ga_prompt
ga_invalid:
        la   $a0, str_bad_act
        li   $v0, 4
        syscall
        j    ga_prompt
ga_hit:
        li   $v0, 1
        j    ga_done
ga_stand:
        li   $v0, 0
ga_done:
        lw   $ra, 0($sp)
        addi $sp, $sp, 4
        jr   $ra

# show_rules: print the rules sheet
show_rules:
        la   $a0, rules_a
        li   $v0, 4
        syscall
        jr   $ra

# =====================================================================
#  CONSOLE OUTPUT
# =====================================================================
# print_card($a0 = card id): e.g. "A of Spades"
print_card:
        addi $sp, $sp, -12
        sw   $ra, 8($sp)
        sw   $s0, 4($sp)
        sw   $s1, 0($sp)
        li   $t0, 13
        div  $a0, $t0
        mfhi $s0                   # rank
        mflo $s1                   # suit
        beqz $s0, pc_ace
        li   $t0, 10
        bge  $s0, $t0, pc_face
        addi $a0, $s0, 1           # ranks 1..9 -> 2..10
        li   $v0, 1
        syscall
        j    pc_suit
pc_ace:
        li   $a0, 65               # 'A'
        li   $v0, 11
        syscall
        j    pc_suit
pc_face:
        la   $t1, facechars
        addi $t2, $s0, -10
        add  $t1, $t1, $t2
        lbu  $a0, 0($t1)
        li   $v0, 11
        syscall
pc_suit:
        la   $a0, str_of
        li   $v0, 4
        syscall
        la   $t0, suitnames
        sll  $t1, $s1, 2
        add  $t0, $t0, $t1
        lw   $a0, 0($t0)
        li   $v0, 4
        syscall
        lw   $ra, 8($sp)
        lw   $s0, 4($sp)
        lw   $s1, 0($sp)
        addi $sp, $sp, 12
        jr   $ra

# print_hand($a0 = hand, $a1 = count, $a2 = hide second card)
print_hand:
        addi $sp, $sp, -20
        sw   $ra, 16($sp)
        sw   $s0, 12($sp)
        sw   $s1, 8($sp)
        sw   $s2, 4($sp)
        sw   $s3, 0($sp)
        move $s0, $a0
        move $s1, $a1
        move $s2, $a2
        li   $s3, 0
ph_loop:
        bge  $s3, $s1, ph_done
        beqz $s3, ph_nocomma
        la   $a0, str_comma
        li   $v0, 4
        syscall
ph_nocomma:
        beqz $s2, ph_show
        li   $t0, 1
        bne  $s3, $t0, ph_show
        la   $a0, str_hidden
        li   $v0, 4
        syscall
        j    ph_next
ph_show:
        sll  $t0, $s3, 2
        add  $t0, $t0, $s0
        lw   $a0, 0($t0)
        jal  print_card
ph_next:
        addi $s3, $s3, 1
        j    ph_loop
ph_done:
        lw   $ra, 16($sp)
        lw   $s0, 12($sp)
        lw   $s1, 8($sp)
        lw   $s2, 4($sp)
        lw   $s3, 0($sp)
        addi $sp, $sp, 20
        jr   $ra

# print_hand_line($a0 = label string, $a1 = hand, $a2 = count, $a3 = hide)
print_hand_line:
        addi $sp, $sp, -16
        sw   $ra, 12($sp)
        sw   $s0, 8($sp)
        sw   $s1, 4($sp)
        sw   $s2, 0($sp)
        move $s0, $a1
        move $s1, $a2
        move $s2, $a3
        li   $v0, 4                # print label (already in $a0)
        syscall
        move $a0, $s0
        move $a1, $s1
        move $a2, $s2
        jal  print_hand
        bnez $s2, phl_nl           # no total while a card is hidden
        la   $a0, str_total1
        li   $v0, 4
        syscall
        move $a0, $s0
        move $a1, $s1
        jal  hand_value
        move $a0, $v0
        li   $v0, 1
        syscall
        la   $a0, str_total2
        li   $v0, 4
        syscall
phl_nl:
        la   $a0, str_nl
        li   $v0, 4
        syscall
        lw   $ra, 12($sp)
        lw   $s0, 8($sp)
        lw   $s1, 4($sp)
        lw   $s2, 0($sp)
        addi $sp, $sp, 16
        jr   $ra

# refresh_screen($a0 = hide dealer's second card): redraw bitmap + print hands
refresh_screen:
        addi $sp, $sp, -8
        sw   $ra, 4($sp)
        sw   $s0, 0($sp)
        move $s0, $a0
        move $a0, $s0
        jal  draw_table
        la   $a0, str_nl
        li   $v0, 4
        syscall
        la   $a0, str_dealer
        la   $a1, dhand
        lw   $a2, dcount
        move $a3, $s0
        jal  print_hand_line
        la   $a0, str_player
        la   $a1, phand
        lw   $a2, pcount
        li   $a3, 0
        jal  print_hand_line
        lw   $ra, 4($sp)
        lw   $s0, 0($sp)
        addi $sp, $sp, 8
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
        add  $t0, $t0, $a0         # + x
        sll  $t0, $t0, 2           # * 4 bytes per word
        li   $t1, DISPLAY_BASE
        add  $t0, $t0, $t1
        lw   $t2, pen
        sw   $t2, 0($t0)
pp_done:
        jr   $ra

# fill_rect($a0 = x, $a1 = y, $a2 = width, $a3 = height): current pen colour
# (caller must keep the rectangle inside the 128 x 64 screen)
fill_rect:
        lw   $t0, pen
        li   $t1, DISPLAY_BASE
        li   $t2, 0                # row counter
fr_row:
        bge  $t2, $a3, fr_done
        add  $t3, $a1, $t2
        sll  $t3, $t3, 7
        add  $t3, $t3, $a0
        sll  $t3, $t3, 2
        add  $t3, $t3, $t1         # address of first pixel in this row
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

# draw_glyph($a0 = x, $a1 = y, $a2 = 15-bit glyph): 3x5 pixels, current pen
draw_glyph:
        addi $sp, $sp, -20
        sw   $ra, 16($sp)
        sw   $s0, 12($sp)
        sw   $s1, 8($sp)
        sw   $s2, 4($sp)
        sw   $s3, 0($sp)
        move $s0, $a0
        move $s1, $a1
        move $s2, $a2
        li   $s3, 0                # bit index 0..14
dg_loop:
        li   $t0, 15
        bge  $s3, $t0, dg_done
        li   $t1, 14
        sub  $t1, $t1, $s3
        srlv $t2, $s2, $t1
        andi $t2, $t2, 1
        beqz $t2, dg_skip
        li   $t3, 3
        div  $s3, $t3
        mfhi $t4                   # column
        mflo $t5                   # row
        add  $a0, $s0, $t4
        add  $a1, $s1, $t5
        jal  put_pixel
dg_skip:
        addi $s3, $s3, 1
        j    dg_loop
dg_done:
        lw   $ra, 16($sp)
        lw   $s0, 12($sp)
        lw   $s1, 8($sp)
        lw   $s2, 4($sp)
        lw   $s3, 0($sp)
        addi $sp, $sp, 20
        jr   $ra

# draw_suit($a0 = x, $a1 = y, $a2 = suit): 5x5 icon (red or black)
draw_suit:
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
        slti $t1, $a2, 2           # hearts/diamonds -> red
        li   $t2, C_RED
        bnez $t1, ds_setc
        li   $t2, C_BLACK
ds_setc:
        sw   $t2, pen
        la   $s2, suitpat
        li   $t3, 5
        mul  $t3, $a2, $t3
        add  $s2, $s2, $t3         # address of this suit's first row
        li   $s3, 0                # row
ds_row:
        li   $t0, 5
        bge  $s3, $t0, ds_done
        add  $t1, $s2, $s3
        lbu  $s4, 0($t1)           # row bits
        li   $s5, 0                # column
ds_col:
        li   $t0, 5
        bge  $s5, $t0, ds_nextrow
        li   $t1, 4
        sub  $t1, $t1, $s5
        srlv $t2, $s4, $t1
        andi $t2, $t2, 1
        beqz $t2, ds_skip
        add  $a0, $s0, $s5
        add  $a1, $s1, $s3
        jal  put_pixel
ds_skip:
        addi $s5, $s5, 1
        j    ds_col
ds_nextrow:
        addi $s3, $s3, 1
        j    ds_row
ds_done:
        lw   $ra, 24($sp)
        lw   $s0, 20($sp)
        lw   $s1, 16($sp)
        lw   $s2, 12($sp)
        lw   $s3, 8($sp)
        lw   $s4, 4($sp)
        lw   $s5, 0($sp)
        addi $sp, $sp, 28
        jr   $ra

# draw_rank($a0 = x, $a1 = y, $a2 = rank 0..12): rank label in black
draw_rank:
        addi $sp, $sp, -16
        sw   $ra, 12($sp)
        sw   $s0, 8($sp)
        sw   $s1, 4($sp)
        sw   $s2, 0($sp)
        move $s0, $a0
        move $s1, $a1
        move $s2, $a2
        li   $a0, C_BLACK
        jal  set_pen
        li   $t0, 9
        beq  $s2, $t0, dr_ten
        beqz $s2, dr_ace
        addi $t1, $s2, 1           # glyph index = rank + 1 (2-9, J, Q, K)
        j    dr_draw
dr_ace:
        li   $t1, 10               # glyph 'A'
dr_draw:
        la   $t2, font
        sll  $t3, $t1, 2
        add  $t2, $t2, $t3
        lw   $a2, 0($t2)
        move $a0, $s0
        move $a1, $s1
        jal  draw_glyph
        j    dr_done
dr_ten:                             # "10" = glyph '1' then glyph '0'
        la   $t2, font
        lw   $a2, 4($t2)
        addi $a0, $s0, -1
        move $a1, $s1
        jal  draw_glyph
        la   $t2, font
        lw   $a2, 0($t2)
        addi $a0, $s0, 3
        move $a1, $s1
        jal  draw_glyph
dr_done:
        lw   $ra, 12($sp)
        lw   $s0, 8($sp)
        lw   $s1, 4($sp)
        lw   $s2, 0($sp)
        addi $sp, $sp, 16
        jr   $ra

# draw_card($a0 = x, $a1 = y, $a2 = card id, $a3 = 1 face up / 0 face down)
# A card is 9 x 13 units.
draw_card:
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
        li   $a0, C_BLACK          # black border
        jal  set_pen
        move $a0, $s0
        move $a1, $s1
        li   $a2, 9
        li   $a3, 13
        jal  fill_rect
        beqz $s3, dc_back
        li   $a0, C_WHITE          # white face
        jal  set_pen
        addi $a0, $s0, 1
        addi $a1, $s1, 1
        li   $a2, 7
        li   $a3, 11
        jal  fill_rect
        li   $t0, 13
        div  $s2, $t0
        mflo $s2                   # suit
        mfhi $a2                   # rank
        addi $a0, $s0, 2
        addi $a1, $s1, 2
        jal  draw_rank
        addi $a0, $s0, 2
        addi $a1, $s1, 7
        move $a2, $s2
        jal  draw_suit
        j    dc_done
dc_back:                            # face-down card
        li   $a0, C_BLUE
        jal  set_pen
        addi $a0, $s0, 1
        addi $a1, $s1, 1
        li   $a2, 7
        li   $a3, 11
        jal  fill_rect
        li   $a0, C_LBLUE
        jal  set_pen
        addi $a0, $s0, 2
        addi $a1, $s1, 2
        li   $a2, 5
        li   $a3, 9
        jal  fill_rect
dc_done:
        lw   $ra, 16($sp)
        lw   $s0, 12($sp)
        lw   $s1, 8($sp)
        lw   $s2, 4($sp)
        lw   $s3, 0($sp)
        addi $sp, $sp, 20
        jr   $ra

# draw_hand($a0 = hand, $a1 = count, $a2 = y, $a3 = hide second card)
draw_hand:
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
        li   $s4, 0
dh_loop:
        bge  $s4, $s1, dh_done
        li   $t0, 10
        mul  $t1, $s4, $t0
        addi $a0, $t1, 4           # x = 4 + 10 * i
        move $a1, $s2
        sll  $t2, $s4, 2
        add  $t2, $t2, $s0
        lw   $a2, 0($t2)           # card id
        li   $a3, 1                # face up unless hidden
        beqz $s3, dh_draw
        li   $t3, 1
        bne  $s4, $t3, dh_draw
        li   $a3, 0                # second card hidden
dh_draw:
        jal  draw_card
        addi $s4, $s4, 1
        j    dh_loop
dh_done:
        lw   $ra, 20($sp)
        lw   $s0, 16($sp)
        lw   $s1, 12($sp)
        lw   $s2, 8($sp)
        lw   $s3, 4($sp)
        lw   $s4, 0($sp)
        addi $sp, $sp, 24
        jr   $ra

# draw_bar($a0 = amount, $a1 = y, $a2 = height, $a3 = colour)
# length in units = (amount + 1) / 2, capped at 120
draw_bar:
        addi $sp, $sp, -16
        sw   $ra, 12($sp)
        sw   $s0, 8($sp)
        sw   $s1, 4($sp)
        sw   $s2, 0($sp)
        move $s0, $a0
        move $s1, $a1
        move $s2, $a2
        move $a0, $a3
        jal  set_pen
        addi $t0, $s0, 1
        srl  $t0, $t0, 1
        li   $t1, 120
        ble  $t0, $t1, db_ok
        li   $t0, 120
db_ok:
        li   $a0, 4
        move $a1, $s1
        move $a2, $t0
        move $a3, $s2
        jal  fill_rect
        lw   $ra, 12($sp)
        lw   $s0, 8($sp)
        lw   $s1, 4($sp)
        lw   $s2, 0($sp)
        addi $sp, $sp, 16
        jr   $ra

# draw_table($a0 = hide dealer's second card): felt, both hands, token bars
draw_table:
        addi $sp, $sp, -8
        sw   $ra, 4($sp)
        sw   $s0, 0($sp)
        move $s0, $a0
        li   $a0, C_FELT
        jal  set_pen
        li   $a0, 0
        li   $a1, 0
        li   $a2, 128
        li   $a3, 64
        jal  fill_rect
        la   $a0, dhand
        lw   $a1, dcount
        li   $a2, 3
        move $a3, $s0
        jal  draw_hand
        la   $a0, phand
        lw   $a1, pcount
        li   $a2, 46
        li   $a3, 0
        jal  draw_hand
        lw   $a0, tokens           # gold bar: tokens
        li   $a1, 39
        li   $a2, 3
        li   $a3, C_GOLD
        jal  draw_bar
        lw   $a0, bet              # red bar: current bet
        li   $a1, 43
        li   $a2, 2
        li   $a3, C_RED
        jal  draw_bar
        lw   $ra, 4($sp)
        lw   $s0, 0($sp)
        addi $sp, $sp, 8
        jr   $ra

# draw_banner($a0 = colour): result banner across the middle of the table
draw_banner:
        addi $sp, $sp, -8
        sw   $ra, 4($sp)
        sw   $s0, 0($sp)
        move $s0, $a0
        li   $a0, C_BLACK
        jal  set_pen
        li   $a0, 23
        li   $a1, 25
        li   $a2, 82
        li   $a3, 12
        jal  fill_rect
        move $a0, $s0
        jal  set_pen
        li   $a0, 24
        li   $a1, 26
        li   $a2, 80
        li   $a3, 10
        jal  fill_rect
        lw   $ra, 4($sp)
        lw   $s0, 0($sp)
        addi $sp, $sp, 8
        jr   $ra
