; Space Invaders
; jbnunn Dec 2025
;
; Inspiration https://github.com/nanochess/Invaders and the book "Programming Boot Sector Games",
; by Oscar Toledo G.
;
; The original code and commments were optimized for size, and not for my sanity. Beginners like 
; me will become easily lost and frustrated trying to learn Assembly by reading the book code. So, 
; I have rewritten some of the confusing things, and left detailed comments to help others learn 
; the language. My changes also mean this game doesn't run in the boot sector anymore, and must be 
; run as a .com file. 

; To compile as a .com file:
;   nasm -f bin invaders.asm -o invaders.com
;
; To run in DOSBox:
;   dosbox invaders.com

; Note: see "???" for things I don't understand

base:           equ 0xFC80                  ; Memory base (same segment as video)

shots:          equ base + 0x00             ; Space to contain 4 shots. One shot will be for the player builet, and three will be
                                            ; for invdader bullets. We need 2 bytes to store the location of a pixel (eg 320x200=63999), 
                                            ; so every shot takes up two bytes. 
                                            ; Plus space for a ignored shot (full table)
                                            ; Notice (sprites + SPRITE_SIZE) - (shots + 2)
                                            ; must be divisible by SPRITE_SIZE.
old_time:       equ base + 0x0C             ; Old time
level:          equ base + 0x10             ; Current level number
lives:          equ base + 0x11             ; Current lives
sprites:        equ base + 0x12             ; Space to contain sprite table

X_WIDTH:        equ 0x140                   ; X-width of video (320 pixels)
ROW_STRIDE:     equ X_WIDTH * 2             ; The original author used the variable "OFFSET_X" which was enormously confusing.
                                            ; For one thing, it's not an X direction, but a Y direction we're offsetting. The meant
                                            ; it to represent how many X "columns" we needed to wrap to print the next pixel.    
                                            ; The sprites are drawn using 2x2 pixel blocks, so one row is actually two pixels tall.
                                            ; Thus, if the width of our screen is 320px, then each row is really 640px, thus
                                            ; this ROW_STRIDE value.   
SPRITE_SIZE:    equ 4                       ; Size of each sprite in bytes
SHIP_ROW:       equ 0x5C * ROW_STRIDE       ; Row of spaceship

; Set the colors for different objects
SPACESHIP_COLOR:            equ 0x04        ; Friends (ships, barriers) have a color less than 32 (0x1c = 28). Enemies (aliens) have 
                                            ; a color >= 32. This will be useful later when we're checking to see what a bullet hits.
                                            ; UPDATED: Changed to 0x04 (Red) for Christmas Theme!
BARRIER_COLOR:              equ 0x02
SHIP_EXPLOSION_COLOR:       equ 0x0E
INVADER_EXPLOSION_COLOR:    equ 0x0E
BULLET_COLOR:               equ 0x0C
START_COLOR:                equ ((sprites + SPRITE_SIZE - (shots + 2)) / SPRITE_SIZE + 0x20)        
                                            ; This was the author's way of optimizing how he'd find the alien's data in RAM based on 
                                            ; the color of the alien. It walks backwards to figure out exactly what color the FIRST 
                                            ; alien needs to be so the math for the rest lines up perfectly.
                                            ; eg:
                                            ;   Alien 0 has Color 32 (0x20)
                                            ;   Alien 1 has Color 33 (0x21)
                                            ;   ...and so on.
org 0x0100                      ; Start position for COM files

.start:
    ; Initialize the video mode and game state
    mov ax, 0x0013      ; Set mode to 0x13 (320x200x256 VGA)
    int 0x10            ; BIOS interrupt that sets the video mode (https://en.wikipedia.org/wiki/INT_10H)
    cld                 ; Makes sure the direction flag is cleared (for STOSW etc.)

    ; CHRISTMAS THEME PALETTE SWAP
    ; ----------------------------
    ; We want red and green aliens, but we can't change their index numbers (32, 33...) because the collision logic uses those numbers 
    ; to identify WHICH alien was hit. So, instead of changing the numbers, we basically hack the video card (VGA) to display those 
    ; specific numbers as red and green.
    
    mov cx, 55                  ; There are 55 invaders to color.
    mov bl, START_COLOR         ; Start with the index of the first invader (e.g., 37).

.christmas_loop:
    mov dx, 0x3C8               ; Port 0x3C8 controls the "Palette Index Write". We tell the card hich color index we want to edit.
    mov al, bl                  ; Move the current invader's index (e.g. 37) into AL.
    out dx, al                  ; Send it to the video card port.

    inc dx                      ; Port 0x3C9 controls "Palette Data". We send RGB values (0-63) here, and just increment DX to get
                                ; to the next color

    test bl, 1                  ; Check if the index is Odd or Even.
    jz .make_green              ; If result is 0 (Even), jump to make it green.

.make_red:                      ; If result is 1 (Odd), we make it red.
    mov al, 63                  ; Set red to Max Intensity (63 is max in VGA, not 255).
    out dx, al                  ; Send red value.
    xor al, al                  ; Zero out AL (faster/smaller than mov al, 0).
    out dx, al                  ; Send green (0).
    out dx, al                  ; Send blue (0).
    jmp .next_color             ; Done with this color.

.make_green:
    xor al, al                  ; Zero out AL.
    out dx, al                  ; Send red (0).
    mov al, 63                  ; Set green to Max Intensity.
    out dx, al                  ; Send green value.
    xor al, al                  ; Zero out AL.
    out dx, al                  ; Send blue (0).

.next_color:
    inc bl                      ; Move to the next invader index.
    loop .christmas_loop        ; Decrement CX and loop until all 55 are colored.

.setup_graphics_address:
    mov ax, 0xA000              ; this is the segement address where VGA Mode video memory begins
    mov ds, ax                  ; Copies video memory segment address into the data segment (ds) register
    mov es, ax                  ; Do the same for extra segment (es) register. Now we can access the screen and game variables 
                                ; at the same address. 

    xor bp, bp                  ; Initialize Frame Counter (BP) to 0. 
                                ; I learned that in .COM files, BP is not guaranteed to be zero. Since we modified
                                ; this code to run outside the boot sector, we need to explicitly set that here.
                                ; Without this, our manual counter logic below (cmp bp, 8) might start at a high 
                                ; random number and run unthrottled 

    ; Initialize Lives (4) and Level (0)
    ; AH = 0x04 (Lives), AL = 0x00 (Level, implicitly from mode set, but let's be safe: mode set leaves AH=0? No, returns status?)
    ; Original code assumed AL=0. This should be fine.
    mov ah, 0x04        ; Number of lives is 4 as AH is now 0x0400 (AL is 0 from previous instruction)
    mov [level], ax     ; Writes lives (4) and level (0) to the address starting at `level` (base + 0x10).
                        ; Because lives was base + 0x11 (just one byte past level), we write both at once.
  

; This label is used to reset the game or after all aliens are destroyed to start the next wave.
restart_game:
    
    xor ax, ax          ; Clears the ax register
    mov cx, level/2     ; The cx register is used as a counter. 
                        ; `level` address is 0xFC90. `level/2` is 0x7E48 (32328).
                        ; Since we use STOSW (2 bytes), we clear 32328 * 2 = 64656 bytes.
                        ; This covers the Screen (64000 bytes) AND the Variables (up to FC90).
    
    xor di, di          ; Sets the Destination Index to 0 (Top-left pixel).

    rep                 ; Tells the CPU to repeat the next instruction over and over again, using cx as
                        ; the counter.
    stosw               ; This takes ax and stores it in RAM at es:[di]. It also increments di by 1. 
                        ; It takes 0 and puts it in every value of the Extra Segment at index di, thus
                        ; completely clearing the screen

    ; Setup descend state
    ; -------------------
    ; Invaders uses the DX register as a "steeing wheel" for the aliens. DL holds the current direction
    ; and DH holds the next direction. 
    ; The original code from the book uses 
    ; 0 = move aliens left
    ; 1 = move aliens right
    ; 2 = move aliens down one or more rows 
    
    mov ax, [di]        ; Reads from DI (which is now FC90, so it reads `level` and `lives`).
                        ; AL = Level, AH = Lives.
    inc ax              ; Add 1 to Level.
    inc ax              ; Add 1 to Level. (AL = Level + 2).
    stosw               ; Store updated descent value back to memory (at FC90, DI -> FC92).
                        ; So Level is now Level+2.

    mov ah, al          ; Copy descent value to AH
    xchg ax, dx         ; Setup DX with initial direction/state.

    ; Setup the spaceship
    ; Moves spaceship color, state, and position to the `sprites` aread of memory
    ; DI is now FC92.
    ; -------------------
    mov di, sprites                             ; Explicitly set DI to the start of the sprites memory area. Note this was
                                                ; not in the original code but I feel safer setting the index manually
                                                
    mov ax, SPACESHIP_COLOR * 0x0100 + 0x00     ; Add the spaceship color to the AH regiser, and 0 to the AL register.
                                                ; Later in the code, we'll see that 0 is a status code for the ship, meaning
                                                ; it is not in an exploded state.   
    stosw                                       ; Stores the value of AX at ES:DI. Remember we set the DI index to `sprites`, so this
                                                ; puts it at 0xFC80 + 0x12 (0xFC92), then increments DI by 2 bytes, making DI 0xFC94. 
    mov ax, SHIP_ROW + 0x4c * 2                 ; Stores the ships vertical position (row) and horizontal position
    stosw                                       ; Writes the spaceships initial position to the memory location immediately following
                                                ; its color/status position. This puts DI at 0xFC96 after DI is incremented by 2 bytes.
    ; Setup the invaders
    ; DI is now FC96. Start of Invader Table.
    
    ; Setup the invaders
    ; Prepares the program to draw the first row of invaders 
    ; ------------------
    mov ax, 0x08 * ROW_STRIDE + 0x28            ; Calculates the initial memory offset for the first invader. This is equivalent to
                                                ; Y pos = 8 big rows down, X pos = 40 (28 hex = 40 dec)
    mov bx, START_COLOR * 0x0100 + 0x10         ; Loads the color of the invader to BH, and a type for the invader in BL. Invaders have 
                                                ; ??? different sprites
    mov dh, 0x05                                ; Initialize the outer loop counter for 5 rows of invaders. In the original code, the 
                                                ; author had used a hacky comparison against the length of the color list in order
                                                ; to save some bytes, but I found it very undreadable and confusing. This line was
                                                ; not in his original code. 

; We loop to create 55 invaders (5 rows of 11).
; Original `cmp bh, START_COLOR+55` logic.
.invader_row_loop:
    ; An outer row for creating 5 rows of 11 invaders
    mov cl, 0x0B                                    ; Set number of invaders per row to 11 

.invader_col_loop:
    ; The inner loop here runs 11 times to create one row of invaders
    ; On entry, AX has the screen position and BX has the invader type/color 
    stosw                                           ; Store the invader's screen position. Writes AX to ES:[DI]; AL goes into ES:[DI] and AH goes into ES:[DI+1]
                                                    ; Then, DI is automatically incremented by 2 
    add ax, 0x0B * 2                                ; Calculate the screen position for the next invader (11 big pixels to the right, plus 11 more for a space in between) 
    xchg ax, bx                                     ; Swap AX (next position) with BX (current type/color). AX now holds type/color
    stosw                                           ; Stores the start color and invader state. AL (the invader type) goes into ES:[original DI+2], AH (the invader color)
                                                    ; goes into ES:[original DI+3], then DI is automatically incremented by 2 again.
    inc ah                                          ; Go to next color for the next invader
    xchg ax, bx                                     ; Swap back. AX now holds the position for the next invader. BX now holds type/color for the next invader. 
    loop .invader_col_loop

    add ax, 0x09 * ROW_STRIDE - (0x0B * 0x0B * 2)   ; After a row is complete, move to the start of the next row. To do this, we
                                                    ; go down 9 big rows and move left by 11 invader widths (plus the 11 big pixel space)
    
    cmp bh, START_COLOR + 55                        ; Have we created all 55 invaders?
    jne .invader_row_loop                           ; If not, continue


    ; BARRIER INITIALIZATION
    ; ----------------------
    ; Unlike the ship and invaders, barriers are "Static Sprites." We draw them once here during setup and NEVER redraw them in the main loop. This is why they 
    ; can be "damaged". Eg., when a bullet erases a piece of them, it stays erased.
    
    ; Calculate starting position: Y = 85 (85 * ROW_STRIDE = row 170), X = 16 (16 * 2 = 32)
    mov di, 0x55 * ROW_STRIDE + 0x10 * 2            
    mov cl, 5                                       ; Counter for 5 barriers

.draw_barriers:
    mov ax, BARRIER_COLOR * 0x0100 + 48             ; AH = Green, AL = 48 (Evergreen Tree bitmap offset)
    call draw_sprite                                ; Draw the barrier directly to the screen
    add di, 0x1E * 2                                ; Advance right 30 "big pixels" (60 bytes) for the next barrier
    loop .draw_barriers                             ; Loop until CL is 0

game_loop_start:                                    
    mov si, sprites + SPRITE_SIZE                   ; We've already setup the spaceship below (which was at the start of the `sprites`)
                                                    ; memory space. So, we advance 4 bytes past that (SPRITE_SIZE) to start the invaders
    ;
    ; Game loop
    ;
    ; Globals:
    ; SI = Next invader to animate
    ; DL = current direction (0=left, 1=right, >=2 down)
    ; DH = next direction
    ; CH = dead invaders
    ; BP = number of invaders processed 
    ;

check_invader_state:                               
    ; Check the invader state
    ; --- INVADER STATE CODES (stored at [SI+2]) ---
    ; 0x10:  Invader active, animation frame 1 (initial state)
    ; 0x18:  Invader active, animation frame 2 (toggled with 0x10 for animation)
    ; 0x20:  Invader hit, currently in explosion animation
    ; 0x28:  Invader destroyed ("cosmic debris"), no longer active or drawn
    ; -------------------------------------------------

    cmp byte [si+2], 0x20                           ; We know from when we setup the invaders above that si and si+1 hold the screen position, and
                                                    ; si+2 and s+3 hold the invader's state and color. Invader state (see table above) of 0x20 means 
                                                    ; the invader is currently exploding. 
    jc animate_invader                              ; if the invader state at si+2 is less than 0x20, the carry flag gets set, and we jump to animate_invader
    inc ch                                          ; Increment ch, which will track dead invaders
    cmp ch, 55                                      ; Are all invaders defeated?
    je restart_game                                 ; If yes, restart game, if not, contineu.

process_invader:
    lodsw                                           ; Load the word at [DS:SI] into AX, which gives us current invader's position, and advances SI by 2
    xchg ax, di                                     ; Swap the value of AX and DI. Now DI has the screen position (which will be needed for draw_sprite later)
                                                    ; AX just holds whatever was in DI, but it doesn't matter, we don't need it
    lodsw                                           ; Load the word at [DS:SI] into AX, which gives us the invader's state and color, and advances SI by 2 
    cmp al, 0x28                                    ; Check to see if invader is in the destroyed state
    je move_invader_swarm                           ; If yes, jump to move_invader_swarm
    cmp al, 0x20                                    ; Check to see if invader is in explosion animation state
    jne draw_invader                                ; If no, jump to draw_invader
    mov byte [si-2], 0x28                           ; Ok, so if we're here, the invader was just in an explosion state, and now we need to destroy it.
                                                    ; To set the destroy state, we need to go back a word, so we use [si-2], and write the 0x28 destroyed state.
draw_invader:   
    call draw_sprite                                ; Draw the invader using the type/color in AX and position in DI 

move_invader_swarm:   
    cmp si, sprites + 56 * SPRITE_SIZE              ; SI is a pointer that iterates through every invader in th sprites table. We start at sprites + SPRITE_SIZE
                                                    ; and we need to calculate the memory address immediately after the 55th invader. 
                                                    ; If we've finished processing all 55 invaders for this frame... 
    jne check_invader_state                         ; ... then we jump back to check_invader_state to process the next invader.

    ; We've processed all invaders on the row. Let's see what direction the swarm should be moving now
    mov al, dh                                      ; Take the next state value we put in DH and move it to Al
    sub al, 2                                       ; If the result is less than zero, we set the carry flag. So this basically sets the carry flag -- if AL
                                                    ; is less than 2, it's moving left or right. If Al is greater or equal to 2, we move down
    jc game_loop_start                              ; If we see a carry flag, then continue moving left or right 
    xor al, 1                                       ; Carry flag was not set, so AL was >= 2. This means the invaders have just finished moving down, and now
                                                    ; we need to switch their horizontal direction. XOR flips the bit, so if AL was 0, it becomes 1, and if
                                                    ; AL was 1, it becomes 0
    mov dl, al                                      ; Move the new direction to DL, whcih holds the current frame's direction
    mov dh, al                                      ; Move the new direction to DH, which becomes the next frame's direction 
    jmp game_loop_start                             ; back to game_loop_start

; FRAME SYNCHRONIZATION
; ---------------------
; A "Frame" is one pass through this loop. However, to keep the game speed consistent regardless of CPU speed, the OP 
; synchronized this with the BIOS timer, which apparently ticks ~18.2 times per second. I don't know enough about the BIOS 
; timer at this point in my journey so I'm leaving it as is for now. 

animate_invader:
    xor byte [si+2], 8                              ; The author's original comment here was insanely vague. Here's what's happening:
                                                    ; XOR is a logical operation. If you XOR a bit with 1, it flips it, eg 0->1, or 1->0.
                                                    ; But here we're XOR'ing a byte with 8, or 00001000 in binary. So, we're flipping the
                                                    ; 4th bit of the byte at [si + 2].
                                                    ; We do this because [si + 2] holds the invader's "Type" number (like 0x10 or 0x18), 
                                                    ; which are setup in the 'bitmaps' table below. By flipping this bit, we toggle the 
                                                    ; value between 0x10 (Frame 1) and 0x18 (Frame 2).
    ; The rest of animate invader was confusing. The author was doing some optimizations just keeping the last 3 bits of bp. It was hard
    ; to read, so I've broken that out here to make it more readable. 
    inc bp                                          ; Increment number of procssed invaders 
    cmp bp, 8                                       ; Have we processed 8 invaders?
    jne .skip_reset                                 ; If not, keep the current value
    mov bp, 0                                       ; If yes, reset counter to 0

    .skip_reset:                                    
      pusha                                         ; Save registers -- ??? but why

      cmp bp, 0                                     ; Is the counter at 0? (Meaning we just hit the 8th invader)
      jne handle_player_bullet                      ; If BP is NOT 0, skip the wait and jump to handle_player_bullet
                                                    ; If BP IS 0, fall through to the wait timer code...

wait_for_timer_tick:
    mov ah, 0x00                                    ; 0x00 in AH is "Read Real Time Clock" for the https://en.wikipedia.org/wiki/Real-time_clock
    int 0x1a                                        ; The BIOS interrupt for the timer. It returns CX:DX, or the number of ticks since midnight
                                                    ; We only care about the DX (the lower 16 bits) because it changes fastest
    cmp dx, [old_time]                              ; We compare the value placed in DX by calling the interrupt to value we saved last time the frame updated 
    je wait_for_timer_tick                          ; If DX is the same as old_time, no time has passed. Try again. 
    mov [old_time], dx                              ; ... else, a tick has happened so we update the old time  

; Note: I spent at least 4 hours on this part to really understand what the author was trying to do. 
handle_player_bullet:
    mov si, shots                                   ; Point the index to the memory space we've setup for shots. Remember, the player gets one shot at a time, and we store that location in the first two bytes. 
    mov cx, 4                                       ; Setup a counter for bullets. We only maintain space in memory for four shots so we must keep them under that limit
    lodsw                                           ; Takes the location in SI (where the player shot is) and loads int into AX
    cmp ax, X_WIDTH                                 ; The screen is 320 px wide. The pixel position can be anywhere between 0 and 63,999. So If AX < 320, the bullet has hit the top row. 
    xchg ax, di                                     ; We need the place in the DI where the pixel currently is...
    jc clear_bullet                                 ; ... so we can clear it
                                                    
    call zero                                       ; Zero out AX and clear the pixel from [DI] 
    sub di, X_WIDTH + 2                             ; There was no comment here by the OP, which is unfortunate, but here's what's happening:
                                                    ; We need the bullet to move "up" which means up in video memory too, so we need to subtract a "row"
                                                    ; ??? The "+2" is unclear to me, but I will experiment with this later   
    mov al, [di]                                    ; We move the current contents of the pixel at [di] into AL
    sub al, 0x20                                    ; Subtracts 32 from the pixel's color value. if the pixel color at DI was black (0), this would put al at -32, and would set the carry flag.
                                                    ; Since we also know black is a part of "space" and not an invader or barrier, the bullet can continue to be drawn.
                                                    ; No invader color, no barrier color.
    jc draw_bullet                                  ; If the carry bit is set, we draw the bullet

    ; if we fall through to this point, we've hit an alien (we'll handle hitting a barrier later)
    pusha                                           ; First lets save the current state of everything so we can finish this bullet and then continue the loop with the next
    mov ah, SPRITE_SIZE                             ; Load the 4-byte sprite size into AH. We'll need it to calculate what alien we're looking at 
    mul ah                                          ; AL containes the alien's index number. So if we hit alien 3, AX becomes 3 * 4 = 12  
    add si, ax                                      ; Add this number to SI, so that SI now points directly at the data for that alien
    lodsw                                           ; Load those two bytes (the position bytes) into AX, and increment SI by 2. SI contains the address for the state/color bytes now.
    xchg ax, di                                     ; Now we point at the place in the VRAM
    mov byte [si], 0x20                             ; Since we've hit the invader, we need to set the state for the invader to "exploding" which is 0x20. 
                                                    ; This is a much clearer comment than the original, which was just "Erase next time"
    mov ax, INVADER_EXPLOSION_COLOR * 0x0100 + 0x08 ; We put the INVADER_EXPLOSION_COLOR into AH by multipying it by 256 decimal (100 hex)
                                                    ; In the bitmaps table below, the explosion state starts at the 8th bit. So, we move 0x08 into AL. 
    call draw_sprite                                ; Now that AL has the index of the bitmap we need to draw, we can call it. 
    popa                                            ; Restore all our registers and prepare for the next loop
    jmp clear_bullet                                ; Clear the bullet after we've done everything in this loop

handle_invader_bullets:
    lodsw                                           ; SI was left pointing at slot 1 with our previous lodsw, so this reads slot 1 (which is the 1st of 3 invader bullets)
    or ax, ax                                       ; Check to see if ax is 0? If 0, it's non existent
    je handle_invader_bullets_loop                  ; if it's 0, then we want to move to the next slot, so we loop
    cmp ax, 0x60 * ROW_STRIDE                       ; The `cmp` instruction performs an implicit subtraction, but it doesn't save the result; it serves to affect the carry 
                                                    ; flag and zero flag in the CPU. If the result of the subtraction is negative, we set the Carry Flag to 1, else 0. If the 
                                                    ; result is 0, it would also set the Zero Flag to 1 
                                                    ; So in this cmp instruction, we're subtracting 0x60 * ROW_STRIDE (96 rows * 640 bytes per row = 61,440) from AX.
                                                    ; Scenario: if the bullet is relatively high on the screen, say row 50, then the bullet position is 50 * 640 = 32,000.                                                
                                                    ; The result of 32,000 - 61,440 is -29,440, thus the carry flag would be set. 
    xchg ax, di                                     ; Move the bullet position into DI for drawing
    jnc clear_bullet                                ; If the carry flag was not set, we clear the bullet 
    call zero                                       ; Remove the bullet from its current position. 
    add di, X_WIDTH - 2                             ; To move the bullet down one row, we normally add X_WIDTH (320) to DI. However, the 'big_pixel' function (called via 'zero') 
                                                    ; uses the 'stosw' instruction, which automatically increments DI by 2 bytes. We subtract 2 here to cancel that out and keep 
                                                    ; the bullet falling vertically

draw_bullet:
    mov ax, BULLET_COLOR * 0x0100 + BULLET_COLOR    ; Setup AX to draw the bullet. We put the bullet color in both AH and AL. When we use stosw later, this will write two pixelx
                                                    ; of this color side by side
    mov [si - 2], di                                ; Save the new bullet position (which is currently in DI) back into the bullet table
    cmp byte [di + X_WIDTH], BARRIER_COLOR          ; We're checking to see if the bullet hits a barrier. We have to use `cmp byte` to tell teh CPU to only read 1 byte from
                                                    ; memory. Without `byte` the CPU wouldn't know if we meant 8 bits or 16 bits. So, if the result is 0, the Zero Flag gets set.
    jne draw_bullet_pixel                           ; jne (jump not equal) means if the zero flag is 0, the colors didn't match so this is a miss. 
                                                    ; Thus, we're going to draw the bullet pixel 

clear_bullet:   
    xor ax, ax                                      ; Zeros out AX essentially drawing black
    mov [si - 2], ax                                ; Write 0 to the bullet table to mark it as dead/inactive

draw_bullet_pixel:    
    cmp byte [di], SPACESHIP_COLOR                  ; Check to see if the bullet's current pixel is the same as the ship color. If so, this is a hit. 
    jne draw_or_erase_bullet                        ; If the pixel is not the spaceship color, continue to draw the bullet
    mov word [sprites], SHIP_EXPLOSION_COLOR * 0X0100 + 0X38 
                                                    ; We overwrite the first entry in the sprites table (which is the player's ship)
                                                    ; AH = Explosion Color. AL = 0x38. This was confusing in the book/original code but it is a "State" value that acts as a countdown timer.
                                                    ; The game loop will increment this value every frame; when it wraps around to 0, the explosion is finished and the player loses a life.

draw_or_erase_bullet:
    call big_pixel                                  ; We loaded the memory space for the bullet with either black or the bullet color. Draw it. 

handle_invader_bullets_loop:   
    loop handle_invader_bullets                     ; Decrements the counter we set in handle player bullet above

handle_spaceship:
    mov si, sprites                                 ; Set the index back to the sprites
    lodsw                                           ; Load the current sprite into AX 
    or al, al                                       ; The `or` instruction will check to see if AL is 0. If so, we're in our normal (alive) state 
    je draw_spaceship                               ; Original comment was "If not, jump down to draw it", which is confusing since we're using a `je`
                                                    ; What we're saying is if it's 0, then we draw the spaceship as normal
    add al, 0x08                                    ; We fall here if the ship is hit. This is a very confusing part of the code because of the optimizations the OP
                                                    ; made to keep this in the boot sector. Basically, he's adding 8 to every frame to jump to various places in the
                                                    ; bitmap table to draw garbage as part of the explosion. I had to work with Gemini for a while to understand this
    jne draw_spaceship                              ; Checks the zero flag from the previous `add` instruction. If the result was not zero, the explosion animation is
                                                    ; still running. If it was zero, the zero flag is set to 1 and the code proceeds and we lose a life 
    mov ah, SPACESHIP_COLOR                         ; We're basically resetting the ship, so restore the color
    dec byte [lives]                                ; Remove one life
    js end_game                                     ; End the game if no lives remain 

; Note I broke this up a bit from the original book code. It nested some of the key checking. 
draw_spaceship:                                      
    mov [si - 2], ax                                ; Save the updated AX (color and frame/state) back into the sprite table so it persists for the next frame
    mov di, [si]                                    ; Load the ship's current screen position from memory into DI
    call draw_sprite                                ; Draw the ship (Red Base)
    
    ; CHECK EXPLOSION STATE (AGAIN)
    ; -----------------------------
    ; We check [si-2] (the state/frame) because 'draw_sprite' might have messed up our Flags.
    ; If the value is NOT 0, the ship is exploding.
    cmp byte [si - 2], 0                            
    jne end_game_loop                            ; If Exploding, skip the overlay and input.

    ; DRAW CHRISTMAS TRIM
    ; -------------------
    ; If we are here, the ship is healthy. Draw the White Trim on top!
    mov ax, 0x0F28                                  ; AH = 0x0F (White), AL = 0x28 (Offset for Trim Sprite)
    call draw_sprite_overlay                        ; Draw ONLY the white pixels
    
    ; READ KEYBOARD (DIRECT HARDWARE ACCESS - PORT 0x60)
    ; --------------------------------------------------
    ; Instead of asking the BIOS nicely ("Is a key pressed?"), we are going straight to the metal.
    ; Port 0x60 holds the "Scan Code" of the last key event (Press or Release) from the keyboard controller.
    ; This allows us to detect ANY key, not just the modifiers like Shift/Ctrl that the BIOS function 0x02 provided.
    
    in al, 0x60                                     ; Read the raw scan code byte from Port 0x60 into AL.

    cmp al, 0x01                                    ; Scan Code 0x01 is the 'Escape' key.
    je end_game                                     ; If Esc is pressed, jump immediately to the exit routine.

check_move_left:
    cmp al, 0x4B                                    ; Check for Left Arrow (Scan Code 0x4B).
    je .do_move_left                                ; If match, execute move left logic.
    
    cmp al, 0x1E                                    ; Check for 'A' key (Scan Code 0x1E) for WASD players.
    jne check_move_right                            ; If neither Left Arrow nor 'A', jump ahead to check right.

.do_move_left:
    dec di                                          ; Move the ship's memory pointer (DI) backwards by 1 byte...
    dec di                                          ; ...and another byte. Moving 2 bytes = 1 "fat" pixel left.

check_move_right:   
    cmp al, 0x4D                                    ; Check for Right Arrow (Scan Code 0x4D).
    je .do_move_right                               ; If match, execute move right logic.
    
    cmp al, 0x20                                    ; Check for 'D' key (Scan Code 0x20).
    jne check_shot                                  ; If neither Right Arrow nor 'D', jump ahead to check firing.

.do_move_right:
    inc di                                          ; Move the ship's memory pointer (DI) forward by 1 byte...
    inc di                                          ; ...and another byte. Moving 2 bytes = 1 "fat" pixel right.

check_shot:
    cmp al, 0x39                                    ; Check for Spacebar (Scan Code 0x39).
    jne check_bounds                                ; If not Space, skip the firing logic entirely.
    
    cmp word [shots], 0                             ; We found Space was pressed! Now, is the player's bullet slot empty?
                                                    ; We check the first 2 bytes of 'shots'. If 0, no bullet is active.
    jne check_bounds                                ; If not 0, a bullet is already on screen. We can't fire again yet.
    
    lea ax, [di + (0x04 * 2)]                       ; Calculate the spawn point. DI is ship's top-left.
                                                    ; We add 8 bytes (4 pixels * 2 bytes/pixel) to center the shot.
    mov [shots], ax                                 ; Write this position to the bullet table to make the shot "live".

 check_bounds:
    xchg ax, di                                     ; We need to validate the NEW position we just calculated (Left/Right moves). Currently, that new position is 
                                                    ; sitting in DI. We swap it into AX because we need to compare it against constant numbers (bounds)
                                                    ; If the move is valid, we'll need the value in a general register to write it to RAM later.

    cmp ax, SHIP_ROW - 2                            ; Check LEFT wall collision.
                                                    ; We compare our potential new position (AX) against the absolute left edge of the screen row. The '- 2' adds
                                                    ; a tiny buffer so we don't wrap around to the previous line.
    je end_game_loop                                ; If we ARE at the edge (ZF=1), we effectively "cancel" the move. We jump straight to 'end_player_frame'
                                                    ; skipping the line that saves this new position. The ship stays exactly where it was last frame.

    cmp ax, SHIP_ROW + 0x0132                       ; Check RIGHT wall collision.
                                                    ; We compare against the right edge limit.
    je end_game_loop                                ; Same logic: If we hit the wall, jump out and do NOT save the new position.
    mov [si],ax                                     ; Otherwise, valid move; update position

end_game_loop:                                   
    popa                                            ; Restore registers we saved to the stack at the beginning of the loop.
    mov ax, [si]                                    ; SI was saved by the previous `pusha` instruction, so it once agains holds the position of the invader we were
                                                    ; previously processing
    cmp dl, 1                                       ; DL contains the current swarm direction (0=left, 1=right, >=2=down). We do an implicit subtraction here and 
                                                    ; then check the carry flag or zero flag.
    jbe invader_move_horizontal                     ; `jbe` is Jump if Below or Equal. It checks both the Zero Flag and Carry Flag. It jumps if either are = 1.
                                                    ; So, based on the `cmp dl, 1`, if DL = 0, then 0 - 1 is negative, so CF = 1. We'd jump to 
                                                    ; `invader_move_horizontal`. If DL = 1, 1 - 1 is 0, so the ZF = 1 and we also jump. When DL is >=2, the result
                                                    ; is always positive, so we fall to the next instruction
    add ax, ROW_STRIDE                              ; We need to move down, so we add the ROW_STRIDE (640 decimal) to the invader position
    cmp ax, 0x55 * ROW_STRIDE                       ; Check to seee if the invader has hit the ground. 0x55 is 85 decimal -- and row 85 is the row just above our
                                                    ; barriers. If ax < (85 * 640), then we set the carry flag to 1
    jc update_invader_pos                           ; If the CF is set, we start the loop over! 

end_game:
    mov ax, 0x0003                                  ; We'll restore the user to text mode and send them back to the command prompt. AX is 00 (Set Video Mode) and
                                                    ; and Mode 03 (standard 80x25 text mode)
    int 0x10                                        ; BIOS Video Service interrupt A 
    int 0x20                                        ; Exit to DOS

; The core game loop (player movement, invader movement, bullets) is now finished for this frame. Everything below this point defines the helper routines 
; and grapics for the game.

invader_move_horizontal:
    dec ax                                          ; Move the invader one pixel left 
    dec ax                                          ; ... and one more
    jc calc_border_check                            ; See below
    add ax, 4                                       ; Moving to right

calc_border_check:                                  ; Renamed from `calc_invader_offset` as it was a confusing label. What we're really doing here is seeing if
                                                    ; the invader touched the edge. 
    push ax                                         ; Save the invader's potential new position (AX) to the stack. We'll need this position if the invader didn't
                                                    ; touch an edge
    push dx                                         ; SAVE DX! DX holds the Swarm Direction State (DL=Current, DH=Next).
                                                    ; We must preserve this because the DIV instruction below will overwrite DX.

    ; CALCULATE WHICH COLUMN THE INVADER IS IN
    ; -----------------------------------------
    xor dx, dx                                      ; CLEAR DX. Critical for 32-bit division (DX:AX / BX).
    
    mov bx, X_WIDTH                                 ; Load screen width (320).
    div bx                                          ; Divide position (AX) by 320.
                                                    ; DX now holds the REMAINDER (The Column Number, 0-319).
    
    ; CHECK IF WE HIT A BORDER
    ; ------------------------
    mov ax, dx                                      ; Move Column (Remainder) to AX.
    shr ax, 1                                       ; DIVIDE BY 2. Now range is 0-159.
                                                    ; This aligns with the author's original 'magic number' check.
                                                    
    dec al                                          ; Check left edge (0 -> 255).
    cmp al, 0x94                                    ; Check right edge (148).
                                                    ; Since we divided by 2, this really checks against column 296 (148*2).
    
    pop dx                                          ; RESTORE DX! We get our Swarm State back.
    pop ax                                          ; Restore the invader's original saved position.
    
    jb update_invader_pos                           ; `jb` is Jump if Below. This checks if the Carry Flag was NOT set by the cmp above. So, if we are NOT at a 
                                                    ; border, we jump and keep moving sideways.
    or dh, 22                                       ; We hit a border. Set the "move down" bits in DH, the "next move" register.

update_invader_pos:
    mov [si], ax                                    ; The border check passed. We save the invader's new valid position (from AX) back into its sprite data table 
                                                    ; at [si].
    add ax, 0x06 * ROW_STRIDE + 0x03 * 2            ; This calculates the position for a potential bullet. It takes the invader's position (AX) and adds a vertical 
                                                    ; offse(6 "fat" rows down) and a horizontal offset (3 pixels right) to make the bullet appear from the invader's 
                                                    ; "mouth".
    xchg ax, bx                                     ; Swap AX and BX so that BX holds the calculated bullet position. AX holds the invader's Type/Color (which was 
                                                    ; in BX), but we actually don't need it here.
    mov cx, 3                                       ; Remember that we have 3 bullet slots for invaders. This sets CX as our loop counter for those bullets

should_invader_shoot:                               ; This is a new label that the OP didn't use. I liked being able to see where we decide if an invader should shoot
    in al, (0x40)                                   ; Read from IO port 40h, which is the 8253/8254 PIT we used early on (Programmable Interval Timer). This gives us
                                                    ; a value between 0 and 255.
    cmp al, 0xF8                                    ; Compare the random number from the PIT against 248. This was originally 0xFC (252) but that ws too slow :)
    jc skip_invader_shot                            ; Jump if Carry (if AL < 248). If the number from PIT is larger than this, a shot is fired. 
                                                    ; This helps throttle the shots.
    mov di, shots + 2                               ; If we reach here, the invader is shooting. Point DI to the first invader bullet slot.

find_invader_bullet_slot:
    cmp word [di], 0                                ; We look to see if the memory at di is 0, which means the "bullet slot" is empty. A non-zero result means we 
                                                    ; have a bullet on screen for this shot
    je fire_invader_bullet                          ; If it's zero (ZF=1), we found a free slot. JUMP to fire.
    add di, 2                                       ; The author originally used a `scasw` instruction here to save space. One of the side effects of `scasw` is to 
                                                    ; increment DI by 2, but since that instruction was new to me, it turns out just adding 2 to DI with an `add`
                                                    ; instruction also works and is more clear
    loop find_invader_bullet_slot                   ; Decrement CX and loop back if we haven't checked all 3 slots.

fire_invader_bullet:
    mov [di], bx                                    ; Since we have a free slot at DI we store the bullet's calculated starting position (which we saved in BX earlier)
                                                    ; The bullet is now "live" and will be processed next frame.
skip_invader_shot:
    jmp process_invader                             ; Whether we fired or not, our work for this specific invader is done. Jump back to the main processing loop to 
                                                    ; handle the next invader.

bitmaps:
    db 0x1C,0x3E,0x00,0x7E,0x00,0x00,0x00,0x00      ; Santa Base (Red: Hat Body & Solid Face)
    db 0x00,0x80,0x42,0x18,0x10,0x48,0x82,0x01      ; Explosion
    db 0x00,0xbd,0xdb,0x7e,0x24,0x3c,0x66,0xc3      ; Alien (frame 1)
    db 0x00,0x3c,0x5a,0xff,0xa5,0x3c,0x66,0x66      ; Alien (frame 2)
    db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00      ; Erase
    db 0x20,0x00,0x7E,0x24,0xFF,0x7E,0x3C,0x18      ; Santa Trim (White: Pom-pom, Brim, Eyes, & Beard)
    db 0x08,0x1C,0x3E,0x1C,0x3E,0x7F,0x08,0x08      ; Evergreen Tree (Barrier Shape)

zero:
    xor ax, ax                                      ; Zero out AX. This is faster and smaller than `mov ax, 0`. When anything jumps to `zero` we fall through from here directly into 
                                                    ; big_pixel to draw the black pixel.
big_pixel:
    mov [di + X_WIDTH], ax                          ; Draw the bottom row of the 2x2 pixel. This takes the color value in AX and writes it to the memory location one full screen-width 
                                                    ; "down" from our current DI position.

    stosw                                           ; Store String Word. This instruction does two things:
                                                    ; 1. Writes the 16-bit value in AX to the memory location [ES:DI].
                                                    ;    This draws the top row of our 2x2 pixel.
                                                    ; 2. Automatically increments DI by 2.

    ret                                             ; Returns back to caller 


; Inputs:
; AH = Color of the sprite
; AL = Sprite offset (Index * 8)
; DI = Screen position
;
draw_sprite:
    pusha                                           ; Save all registers to the stack so we don't mess up the game loop state
    mov si, ax                                      ; AH holds the color and AL holds the sprite offset. We move this to SI, so that SI now points to the correct byte in the
                                                    ; bitmaps table
    mov dl, ah                                      ; Save the color to DL (basically the author used this to temporarily store the color in a safe place) 
    and si, 0xFF                                    ; This zeroes out the upper byte of SI. Now SI just holds the byte of the offset in the bitmaps table. Eg., if AL was 0x28,
                                                    ; SI would be 0x0028.

.draw_row:
    push di                                         ; Save the starting screen memory address for this row
    mov bl, [cs:bitmaps + si]                       ; CS is the Code Segement, where `bitmaps` lives. This loads one byte of pixel data for the current bitmaps row into DI.  
                                                    ; This byte, BL, now contains the eight individual pixels for this row
    inc si                                          ; Point to the next row's pixel data byte in the bitmaps table  
    mov ah, 0                                       ; Every sprite is drawn with a 1-pixel black border on the left and the right, to help erase any old pixels from the sprite's
                                                    ; previous position. This instruction first sets the color to black...
    call draw_single_pixel_helper                   ; ... then, this draws the 2x2 pixel and advances DI by 2
    mov cx, 8                                       ; Before we get into the loop to draw 8 pixels for the row, we set the counter to 8

.pixel_loop:
    shl bl, 1                                       ; Shift left moves the leftmost bit into the carry flag., eg., if BL was 1011011, after SHL it's 0110110, and that would 
                                                    ; makes the CF=1
    jc .set_color                                   ; If the CF is  1, we need to draw the sprite's color.
    mov ah, 0                                       ; But if the CF is 0, meaning left most bit was 0, we fall through here and color the pixel black 
    jmp .draw_it

.set_color:
    mov ah, dl                                      ; The CF from the shift left was 1 -- so we set the color to the sprite's intended color (which was saved in DL)

.draw_it:
    call draw_single_pixel_helper                   ; Draw a 2x2 pixel using the color in AH, and advances DI by 2
    loop .pixel_loop                                ; Decrement CX counter. If CX is not zero, we jump back to .pixel_loop. 
                                                    ; After 8 interations, CX becomes 0 and we exit the loop. All 8 pixels for this row have been processed
    mov ah, 0                                       ; Set the color to black 
    call draw_single_pixel_helper                   ; Draw a 2x2 black pixel and advance DI by 2
    pop di                                          ; We pop DI off the stack so that DI is now restored to this row's screen address 
    add di, ROW_STRIDE                              ; Add the ROW_STRIDE (280) to DI so we move to the next vertical screen row. 
    test si, 7                                      ; `test` is still relatively unfamiliar to me, but what it does is performs a bitwise AND of SI with 7 (00000111). This
                                                    ; checks the last 3 bits of SI. If SI is a multiple of 8 (meaning we've processed all 8 bytes/rows of the sprite),
                                                    ; then the result of the TEST will be 0, and the Zero Flag (ZF) will be set to 1.
    jnz .draw_row                                   ; If SI is NOT a multiple of 8, the ZF will be set to 0, and we jump to draw_row. Otherwise we fall through (meaning the
                                                    ; entire 8x8 sprite is drawn)

    popa                                            ; Restore all registers we saved at the very beginning
    ret


; Inputs: Same as draw_sprite (AH=Color, AL=Sprite Offset, DI=Screen Pos)
; This routine is a specialized version of draw_sprite used for Christmas themes. It acts like a 
; stencil or an "Overlay". Unlike the regular draw_sprite, this one ONLY draws the colored pixels (1 bits).
; If a bit is 0, it does NOTHING (skips it), which preserves whatever color was already on the screen
; at that location. This is what allows us to draw Santa's white beard on top of his red face!

draw_sprite_overlay:
    pusha                                           ; Save all registers to the stack so we don't mess up the game loop state
    mov si, ax                                      ; AH holds the color and AL holds the sprite offset. Move to SI to index bitmaps.
    mov dl, ah                                      ; Save the color to DL for safe-keeping during the loop
    and si, 0xFF                                    ; Zero out the upper byte of SI so it holds just the byte offset (0-255)

.draw_row_overlay:
    push di                                         ; Save the starting screen address for this row
    mov bl, [cs:bitmaps + si]                       ; Load one byte of pixel data (8 pixels) from the Code Segment
    inc si                                          ; Increment SI to point to the next row's data for the next iteration

    ; SKIP LEFT PADDING
    ; -----------------
    ; In the normal draw_sprite, we draw a black pixel here. In overlay mode, we just advance DI
    ; without drawing anything, keeping the background intact.
    add di, 2                                       ; Move DI forward by 2 bytes (one fat pixel width)

    mov cx, 8                                       ; Prepare to process all 8 bits in the current bitmap byte

.pixel_loop_overlay:
    shl bl, 1                                       ; Shift the leftmost bit into the Carry Flag (CF)
    jnc .skip_pixel                                 ; Jump if Not Carry (CF=0). This means the pixel is empty/transparent.
                                                    ; We jump to skip the drawing code entirely.

    mov ah, dl                                      ; The bit was 1! Load the overlay color into AH
    call draw_single_pixel_helper                   ; Draw the 2x2 fat pixel at ES:[DI] and advance DI by 2
    jmp .next_pixel                                 ; Move to the next bit

.skip_pixel:
    add di, 2                                       ; The pixel was transparent, so we just advance DI manually to stay in sync
                                                    ; with the sprite's shape, without writing anything to VRAM.

.next_pixel:
    loop .pixel_loop_overlay                        ; Decrement CX and loop until all 8 pixels in the row are processed

    ; SKIP RIGHT PADDING
    add di, 2                                       ; Advance DI past the right padding area without drawing black

    pop di                                          ; Restore DI to the start of this row's screen address
    add di, ROW_STRIDE                              ; Move DI down to the next vertical screen row (640 bytes down)
    
    test si, 7                                      ; Check if we've finished all 8 rows of the sprite
    jnz .draw_row_overlay                           ; If result is not 0 (ZF=0), we have more rows. Loop back.

    popa                                            ; Restore all registers to their original state
    ret                                             ; Return to caller

; Helper to draw one 2x2 pixel block and advance DI
; Inputs: AH = Color, DI = Screen Address
draw_single_pixel_helper:
    mov [di], ah                                    ; Top-Left: Take the color in AH and write it to the memory location pointed to by DI. This is the top-left pixel of our 2x2 block.
    mov [di + 1], ah                                ; Top-Right: Write the same color to the adjacent byte in memory.
    mov [di + 0x140], ah                            ; Bottom-Left: Write the color to the memory address one full screen width down from DI (X_WIDTH = 320 = 0x140).
    mov [di + 0x140 + 1], ah                        ; Bottom-Right: Write the color to the adjacent byte on the bottom row.
    add di, 2                                       ; Advance DI by 2 bytes. This is critical for the 'draw_sprite' loop, which expects DI to move horizontally across the 
                                                    ; screen as it draws each fat pixel in a row.
    ret                                             ; Return from subroutine.
