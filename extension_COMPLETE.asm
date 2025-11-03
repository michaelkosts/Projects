.data
    scoreText:       .asciiz "Score: "
    gameover:        .asciiz "GAME OVER"
    finalScoreText:  .asciiz "Final Score: "
    newline:         .asciiz "\n"

.text
.globl main

main:
    li $v0, 40
    li $a0, 12345
    syscall		# Set PRNG seed syscall

    # Playable area: rows 1-5, columns 1-7

    li $t0, 0      	# initial Score: 0
    li $t1, 1      	# initial Player row: 1
    li $t2, 3      	# initial Player column: 3
    
    li $s0, 5      	# initial Reward row: 5
    li $s1, 4      	# initial Reward column: 4

    li $s5, 3      	# initial Enemy row: 3
    li $s6, 4      	# initial Enemy column: 4

    li $s3, 0		# initial clear_display counter (used later in the code to clear the display)

    jal display_game	# print initial game board to MMIO display

game_loop:
    # from MMIO simulator help manual: "While the tool is connected to MIPS, each keystroke in the text area causes the corresponding ASCII code to be placed in the Receiver Data register (low-order byte of memory word 0xffff0004), and the Ready bit to be set to 1 in the Receiver Control register (low-order bit of 0xffff0000)."
    li $t4, 0xFFFF0000   		# Keyboard Status Register
poll_keyboard:
    lw $t5, 0($t4)			# load ready bit into $t5
    beqz $t5, poll_keyboard   		# Wait until a key is pressed, if $t5 = 1 do not branch (if 0, go to poll loop)

    li $t4, 0xFFFF0004   		# Keyboard Data Register
    lw $t3, 0($t4)			# load ASCII character from 0xFFFF0004

    # Check movement keys
    li $t4, 'w'
    beq $t3, $t4, move_up
    li $t4, 's'
    beq $t3, $t4, move_down
    li $t4, 'a'
    beq $t3, $t4, move_left
    li $t4, 'd'
    beq $t3, $t4, move_right

    j game_loop         		# If character not in beq, loop back

move_up:
    subi $t1, $t1, 1    		# Player row--
    j update_position

move_down:
    addi $t1, $t1, 1    		# Player row++
    j update_position

move_left:
    subi $t2, $t2, 1    		# Player col--
    j update_position

move_right:
    addi $t2, $t2, 1    		# Player col++
    j update_position

update_position:
    # Check for wall collisions (walls at rows 0 and 6, cols 0 and 8)
    li $t4, 0
    beq $t1, $t4, game_over
    li $t4, 6
    beq $t1, $t4, game_over
    li $t4, 0
    beq $t2, $t4, game_over
    li $t4, 8
    beq $t2, $t4, game_over

    # Move enemy (enemy moves each time the player moves)
    jal enemy_move

    # Check if enemy collides with player (game over if so)
    bne $t1, $s5, check_reward_collision
    bne $t2, $s6, check_reward_collision
    j game_over

check_reward_collision:
    # Check if player reached the reward.
    bne $t1, $s0, continue_loop
    bne $t2, $s1, continue_loop
    j collect_reward

continue_loop:
    jal display_game
    j game_loop

collect_reward:
    addi $t0, $t0, 5   			# Increase score by 5
    li $t6, 100
    beq $t0, $t6, game_over   		# End game if score reaches 100
    j pick_new_reward

# Reward Generation Loop:
pick_new_reward:
pick_new_reward_loop:
    # Generate reward row: random number between 0 and 5 (0–4) then add 1 to offset to 1-5 to be in bounds of the grid
    li $v0, 42
    li $a0, 0
    li $a1, 5        			# generates 0-4
    syscall
    addi $s0, $a0, 1 			# s0 in 1–5

    # Generate reward column: random number between 0 and 7 (0–6) then offset to 1-7
    li $v0, 42
    li $a0, 0
    li $a1, 7        			# generates 0-6
    syscall
    addi $s1, $a0, 1 			# s1 in 1–7

    # Check reward does not spawn on the player
    # if row = row, or col = col, branch to re-generate new reward coordinates
    beq $s0, $t1, pick_new_reward_loop
    beq $s1, $t2, pick_new_reward_loop
    # Check reward does not spawn on the enemy
    beq $s0, $s5, pick_new_reward_loop
    beq $s1, $s6, pick_new_reward_loop

    jal display_game
    j game_loop

# Enemy Movement extension

enemy_move:
    # Check if player is on the same row as the enemy
    beq $t1, $s5, enemy_move_horizontal
    # Otherwise, check if the player is on the same column
    beq $t2, $s6, enemy_move_vertical
    # If not aligned on either, do not move
    jr $ra

enemy_move_horizontal:
    # Enemy is on the same row as the player; move horizontally
    # Enemy's row should remain unchanged
    blt $t2, $s6, enemy_move_left_horiz  	# If player's col is less than enemy's col, move left
    bgt $t2, $s6, enemy_move_right_horiz 	# If player's col is greater, move right
    jr $ra

enemy_move_left_horiz:
    li $t7, 1          				# Left boundary for columns
    ble $s6, $t7, enemy_move_end_no_move  	# If enemy is at leftmost allowed col, do not move
    subi $s6, $s6, 1   				# Move enemy left
    jr $ra

enemy_move_right_horiz:
    li $t7, 7          				# Right boundary for columns
    bge $s6, $t7, enemy_move_end_no_move  	# If enemy is at rightmost allowed col, do not move
    addi $s6, $s6, 1   				# Move enemy right
    jr $ra

enemy_move_vertical:
    # Enemy is on the same column as the player; move vertically
    # Enemy's column remains unchanged
    blt $t1, $s5, enemy_move_up_vert   	# If player's row is less than enemy's row, move up
    bgt $t1, $s5, enemy_move_down_vert 	# If player's row is greater, move down
    jr $ra

enemy_move_up_vert:
    li $t7, 1          				# Top boundary for rows
    ble $s5, $t7, enemy_move_end_no_move  	# If enemy is at top, do not move
    subi $s5, $s5, 1   				# Move enemy up
    jr $ra

enemy_move_down_vert:
    li $t7, 5          				# Bottom boundary for rows
    bge $s5, $t7, enemy_move_end_no_move  	# If enemy is at bottom, do not move
    addi $s5, $s5, 1   				# Move enemy down
    jr $ra

enemy_move_end_no_move:
    jr $ra

# GAME OVER

game_over:
# from MMIO simulator help manual: "A program may write to the display area by detecting the Ready bit set (1) in the Transmitter Control register (low-order bit of memory word 0xffff0008), then storing the ASCII code of the character to be displayed in the Transmitter Data register (low-order byte of 0xffff000c) using a 'sw' instruction."
    li $t4, 0xFFFF0008   # Load address of display control register
    li $t5, 1
    sw $t5, 0($t4)       # Enable display
    li $t4, 0xFFFF000C   # Load address of display data register
    li $t6, 0            # Initialize counter for clearing display
clear_display_loop:
    li $t7, 32           			# ASCII code for space
    sw $t7, 0($t4)       			# Print a space to clear part of display
    addi $t6, $t6, 1    			# Increment counter
    li $t5, 80           			# Assume 80 spaces per line
    bge $t6, $t5, clear_display_newline  	# Once a line is cleared, print newline
    j clear_display_loop

clear_display_newline:
    li $t7, 10           		# ASCII code for newline
    sw $t7, 0($t4)       		# Print newline
    li $t6, 0            		# Reset counter for next line
    addi $s3, $s3, 1     		# Increment line counter
    li $s4, 25          		# Total number of lines to clear
    blt $s3, $s4, clear_display_loop  	# Loop until 25 lines cleared
    move $s3, $zero      		# Reset the clear display counter

    # Print "GAME OVER" message
    la $t6, gameover     		# Load address of "GAME OVER" string
print_gameover_loop:
    lb $t7, 0($t6)       		# Load current character
    beqz $t7, gameover_newline  	# If end-of-string (null terminator), branch
    sw $t7, 0($t4)       		# Print character to display
    addi $t6, $t6, 1     		# Move to next character
    j print_gameover_loop

gameover_newline:
    li $t7, 10
    sw $t7, 0($t4)       # Print newline

    # Print "Final Score: " message
    la $t6, finalScoreText
print_fscore_msg:
    lb $t7, 0($t6)
    beqz $t7, print_final_score  # If end-of-string, branch to score printing
    sw $t7, 0($t4)
    addi $t6, $t6, 1
    j print_fscore_msg

print_final_score:
    beqz $t0, print_final_score_zero  	# If score is 0, branch to print 0
    addi $sp, $sp, -8    		# Allocate 8 bytes on stack
    sw $ra, 4($sp)       		# Save return address
    sw $t3, 0($sp)       		# Save $t3 (used later)
    move $t8, $t0        		# Copy score into $t8 for conversion
    move $t9, $zero      		# Initialize digit counter

print_final_loop:
    beqz $t8, print_final_output  	# If no more digits, branch to output digits
    li $a2, 10         			# Load divisor 10 into $a2
    div $t8, $a2       			# Divide $t8 by 10 (quotient in LO, remainder in HI)
    mflo $t8           			# Get quotient back into $t8
    mfhi $s2           			# Get remainder (digit) into $s2
    addi $s2, $s2, 48  			# Convert digit to ASCII (by adding 48)
    addi $t9, $t9, 1   			# Increment digit counter
    addi $sp, $sp, -1  			# Allocate 1 byte on stack for digit
    sb $s2, 0($sp)     			# Store the ASCII digit on the stack
    b print_final_loop

print_final_output:
    beqz $t9, print_final_score_zero  # If no digits were stored, print 0

print_final_out_loop:
    lb $s2, 0($sp)     # Load a digit from the stack
    sw $s2, 0($t4)     # Print the digit (stored in $s2) to display
    addi $sp, $sp, 1   # Pop the digit off the stack
    addi $t9, $t9, -1  # Decrement digit counter
    bgtz $t9, print_final_out_loop  # Loop until all digits printed

    lw $t3, 0($sp)     # Restore $t3
    lw $ra, 4($sp)     # Restore return address
    addi $sp, $sp, 8   # Deallocate the 8 bytes used on the stack
    j print_final_newline

print_final_score_zero:
    li $s2, '0'
    sw $s2, 0($t4)     # If score is 0, print character '0'
    
print_final_newline:
    li $t7, 10
    sw $t7, 0($t4)     # Print newline after final score
    j exit

exit:
    li $v0, 10
    syscall

# Start of display_game function:
# Prints "Score: {counter}" and the grid (walls '#', player 'P', reward 'R', enemy '*')

display_game:
    li $t4, 0xFFFF0008	
    li $t5, 1
    sw $t5, 0($t4)			# enable display
    					# help section in MMIO simulator: "A program may write to the display area by detecting the Ready bit set (1) in the Transmitter Control register (low-order bit of memory word 0xffff0008)"
    li $t4, 0xFFFF000C			# store character in $t4
    					# help section in MMIO simulator: " storing the ASCII code of the character to be displayed in the Transmitter Data register (low-order byte of 0xffff000c)"
    la $t6, scoreText

print_score_loop:
    lb $t7, 0($t6)			# $t6 has address of scoreText, now load current character into $t7
    beqz $t7, print_score_value	# if $t7 = 0, then jump to print score value (as it's the end of the "Score: " string)
    sw $t7, 0($t4)			# store character (which is in $t7) into address 0xFFFF000C
    addi $t6, $t6, 1			# increment counter, therefore getting next character
    j print_score_loop

print_score_value:
    beqz $t0, print_score_zero		# base check, if score counter = 0 just jump to print 0
    addi $sp, $sp, -8
    sw $ra, 4($sp)
    sw $t3, 0($sp)			# allocate space in stack
    move $t8, $t0			# copy $t0 to $t8, used later for decimal conversion
    move $t9, $zero			# initialize counter, used for counting digits

print_decimal_loop:
    beqz $t8, print_decimal_output	# if #t8 = 0, no more digits left to convert so jump to output
    
    # Method to convert decimal to ASCII: (https://dev.to/ilihub/how-to-convert-decimal-to-ascii-4hh7)
    li $a2, 10				# load 10 into $a2  
    div $t8, $a2			# divide $t8 by 10 ($t8 holds value of score)
    
    # "The result of the division is stored in two special registers, the HI and LO registers. The HI register contains the remainder of the division, and the LO register contains the quotient." (https://brainly.com/question/30764327)
    mflo $t8				# move quotient to $t8 from LO			
    mfhi $s2				# move remainder to $s2 from HI (code taken from https://brainly.com/question/30764327)
    addi $s2, $s2, 48			# "Add 48 to each digit in turn, that's your ASCII conversion." (https://www.quora.com/What-is-the-method-of-converting-the-decimal-number-to-ASCII-code)
    addi $t9, $t9, 1			# increment counter to track digits (used later)
    addi $sp, $sp, -1			
    sb $s2, 0($sp)			# allocate 1 byte in stack and store ASCII value (ASCII is 8 bits, so 1 byte)
    b print_decimal_loop

print_decimal_output:
    beqz $t9, print_score_zero		# if $t9 = 0, print 0

print_decimalOutput_loop:
    lb $s2, 0($sp)			# load ASCII character from stack
    sw $s2, 0($t4)			# store character to 0xFFFF000C, which prints character to display
    addi $sp, $sp, 1			# decrease stack
    addi $t9, $t9, -1			# decrease digit counter
    bgtz $t9, print_decimalOutput_loop	# if digit counter > 0, loop again (this counter is now useful, as it prints out all our stored ASCII chars and decrements stack)
    lw $t3, 0($sp)
    lw $ra, 4($sp)
    addi $sp, $sp, 8			# restore values from stack and decrement
    j print_score_newline

print_score_zero:
    li $s2, '0'
    sw $s2, 0($t4)			# prints 0
    j print_score_newline

print_score_newline:
    la $t7, newline			# load address of newline into $t7
    lb $t7, 0($t7)			# then load byte into $t7, so $t7 now holds ASCII value of \n
    sw $t7, 0($t4)			# print \n to display ($t4 = 0xFFFF000C)

# Grid begins here
# nested loop, build_grid_col is inside build_grid_row, therefore we iterate through every col in a row
    li $t8, 0   			# initialize row counter, not inside loop to avoid re initializing it to 0 again
build_grid_row:
    bgt $t8, 6, return_display		# if row > 6, go to return_display

    li $t9, 0   			# initialize column counter
build_grid_col:
    bgt $t9, 8, print_newline		# if column counter > 8, print newline as that means the end of the row has been reached
    
    # Begin printing walls
    beq $t8, 0, print_wall		# print '#' at row 0
    beq $t8, 6, print_wall		# print '#' at row 6
    beq $t9, 0, print_wall		# print '#' at col 0
    beq $t9, 8, print_wall		# print '#' at col 8
    
    # Check for Player position:
    # Player row stored in $t1 and col stored in $t2
    bne $t8, $t1, not_player_cell	# compares current row to player row
    bne $t9, $t2, not_player_cell	# compares current col to player col
    					# if none are equal, jump as player is not located there
    j print_player

not_player_cell:
    # Check for Enemy position:
    # Enemy row stored in $s5 and col stored in $s6
    bne $t8, $s5, not_enemy_cell	
    bne $t9, $s6, not_enemy_cell	
    					# same logic as above
    j print_enemy

not_enemy_cell:
    # Check for Reward position:
    # Reward row stored in $s0 and col stored in $s1
    bne $t8, $s0, print_regular_space
    bne $t9, $s1, print_regular_space	
    					# same logic again, but print space as Reward isn't present
    j print_reward

# All below functions load ASCII value into $t7
print_regular_space:
    li $t7, 32
    j output_char

print_wall:
    li $t7, 35
    j output_char

print_player:
    li $t7, 'P'
    j output_char

print_enemy:
    li $t7, '*'
    j output_char

print_reward:
    li $t7, 'R'
    j output_char

output_char:
    sw $t7, 0($t4)			# $t7 stores current ASCII value (assigned above), and prints to display
    addi $t9, $t9, 1			# increment col
    j build_grid_col			# jump back to build_grid_col, now next spot in the current row can be looped

print_newline:
    la $t7, newline
    lb $t7, 0($t7)			
    sw $t7, 0($t4)			# load address of \n to $t7, load byte of ASCII \n into $t7 and print it to display
    addi $t8, $t8, 1			# increment row counter
    j build_grid_row			# jump to start of nested loop

return_display:
    jr $ra				# go back to display_game
