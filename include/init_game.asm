; init_game.asm

; Initialize the game state
base:               equ 0xFC80              ; Base location for game state
shots:              equ base + 0x00
old_time:           equ base + 0x0C         ; 12 bytes past the base address
level:              equ base + 0x10         ; 16 bytes past the base address
lives:              equ base + 0x11         ; 17 bytes past the base, 1 byte past level
sprites:            equ base + 0x12         ; 18 bytes past the base, 1 bytes past lives, 2 bytes past level

; Initialize constants
X_WIDTH:            equ 0x140               ; 0x140 = 320 decimal. Width of screen.
ROW_STRIDE:         equ X_WIDTH * 2         ; The original author used the variable "OFFSET_X" which was maddeningly confusing.
                                            ;   For one thing, it's not an X direction, but a Y direction we're offsetting.
                                            ;   The sprites are drawn using 2x2 pixel blocks, so one row is actually two pixels tall.
                                            ;   Thus, if the width of our screen is 320px, then each row is really 640px, thus
                                            ;   this ROW_STRIDE value.   

SHIP_ROW:           equ 0x5C * ROW_STRIDE   ; 0x5c = 92 decimal. Row we place the space ship on
SPRITE_SIZE:        equ 4                   ; 4 bytes for each sprite

; Colors - see https://en.wikipedia.org/wiki/Mode_13h
SPACESHIP_COLOR:          equ 0x1C          ; color 28 - white/gray? 
BARRIER_COLOR:            equ 0x0B
SHIP_EXPLOSION_COLOR:     equ 0x0A
INVADER_EXPLOSION_COLOR:  equ 0x0E
BULLET_COLOR:             equ 0x0C
START_COLOR:              equ ((sprites+SPRITE_SIZE-(shots+2))/SPRITE_SIZE+0x20) ; ??? wth does this mean?!

; Init game
mov ax, 0x013       ; Set mode to 0x13 (320x200x256 VGA)
int 0x10            ; BIOS interrupt that sets the video mode (https://en.wikipedia.org/wiki/INT_10H)
cld                 ; Makes sure the direction flag is cleared
mov ax, 0xA000      ; this is the segement address where VGA Mode video memory begins, targeting the first
                    ;   pixel of the screen
mov ds, ax          ; Copies video memory segment address indo the data segement (ds) register
mov es, ax          ; Do the same for extra segment (es) register. Now we can access the screen and
                    ;   game variables at the same address
mov ah, 0x04        ; Number of lives is 4 as AH is now 0x0400
mov [level], ax     ; Writes lives (4) and level (0) to the address starting at `level`, which was
                    ;   base + 0x10. Because lives was base + 0x11 (just one byte past level), we
                    ;   are able to write both at the same time

restart_game:           ; ??? This is a confusing label. It implies a full reset, but it is also used
                        ;   after all aliens are destroyed. Will change to start_next_wave once I'm sure
                        ;   I've understood everything
  xor ax, ax            ; Clears the ax register
  mov cx, level/2       ; The cx register is generally used as a counter for loops (think of the `c` 
                        ;   in `cx` as "counter"). When a `loop <some_label>` is executed, the CPU
                        ;   decrements cx by 1. If cx is not 0, it jumps to <some_label>. If cx is 0,
                        ;   then we move to the next line. 
  xor di, di            ; Sets the Destiniation Index register to 0. Setting `di` to 0 lets us point to
                        ;   the first pixel of the screen.
  rep                   ; Tells the CPU to repeat the next instruction over and over again, using cx as
                        ;   the counter.
  stosw                 ; This takes ax and stores it in RAM at es:[di]. It also increments di by 1. 
                        ;   So, it takes 0 and puts it in every value of the Extra Segment at index di.  

  ; Invaders uses the DX register as a "steeing wheel" for the aliens. DL holds the current direction
  ; and DH holds the next direction. 
  ; The original code from the book uses 
  ; 0 = move aliens left
  ; 1 = move aliens right
  ; 2 = move aliens down one or more rows 

  ; The next bit of code determines the descent value based on the current level, and then loads it into both
  ; DL and DH. The formula is simple, we just add 2 to the current level
  mov ax, [level]         ; Loads the level into AL, and lives into AH. The book used `mov ax, [di]` but I think
                          ; [level] is more readable and accomplishes the same thing
  inc ax                  ; Add 1 to the level value in AL. On level 0, AX becomes 0x0401.
  inc ax                  ; Add 1 again. On level 0, AX becomes 0x0402. AL now holds the descent value (2).
  stosw                   ; Store AX into ram at ES:DI so we have a durable copy there
  mov ah, al              ; AX becomes 0x0202 on first run (Why though ... will it be used later ???)
  xchg ax, dx             ; Copies dx to ax and ax to dx. On first run, DX holds 2, which will move the aliens down
                          ;   The only reason I can figure that the author used `xchg` here instead of `mov` was to 
                          ;   make sure that the value of DX is preserved. A mov dx, ax would destroy the old value
                          ;   of DX forever. I may switch this to a `mov` command as an experiment later. 
  
  ; Setup the spaceship
  ; Moves spaceship color, state, and position to the `sprites` aread of memory
  mov di, sprites                             ; Explicitly set DI to the start of the sprites memory area. Note this was
                                              ; not in the original code but I feel safer setting the index manually
                                              
  mov ax, SPACESHIP_COLOR * 0x0100 + 0x00     ; Add the spaceship color to the AH regiser, and 0 to the AL register.
                                              ;   Later in the code, we'll see that 0 is a status code for the ship, meaning
                                              ;   it is not in an exploded state.   
  stosw                                       ; Stores the value of AX at ES:DI. Remember we set the DI index to `sprites`, so this
                                              ;   puts it at 0xFC80 + 0x12 (0xFC92), then increments DI by 2 bytes, making DI 0xFC94. 
  mov ax, SHIP_ROW + 0x4c * 2                 ; Stores the ships vertical position (row) and horizontal position
  stosw                                       ; Writes the spaceships initial position to the memory location immediately following
                                              ;   its color/status position. This puts DI at 0xFC96 after DI is incremented by 2 bytes.

  ; Setup the invaders
  ; Prepares the program to draw the first row of invaders 
  mov ax, 0x08 * ROW_STRIDE + 0x28            ; Calculates the initial memory offset for the first invader. This is equivalent to
                                              ;   Y pos = 8 big rows down, X pos = 40 (28 hex = 40 dec)
  mov bx, START_COLOR * 0x0100 + 0x10         ; Loads the color of the invader to BH, and a type for the invader in BL. Invaders have 
                                              ;   ??? different sprites

  mov dh, 0x05                                ; Initialize the outer loop counter for 5 rows of invaders. In the original code, the 
                                              ;   author had used a hacky comparison against the length of the color list in order
                                              ;   to save some bytes, but I found it very undreadable and confusing. This line was
                                              ;   n eot in his original code. 
reset_invader_rows:
  ; An outer loop for creating 5 rows of 11 invaders
  mov cl, 0x0B            ; Reset number of invaders per row to 11

  set_invader_positions:
    ; The inner loop here runs 11 times to create one row of invaders
    ; On entry, AX has the screen position and BX has the invader type/color 
    stosw                                               ; Store the invaders screen position (from AX) into the sprite table. DI now 
                                                        ;   becomes 0xFC98
    add ax, 0x0B * 2                                    ; Calculate the screen position for the next invader (11 big pixels to the right, plus 11 more for a space in between) 
    xchg ax, bx                                         ; Swap AX (next position) with BX (current type/color). AX now holds type/color
    stosw                                               ; Stores the start color and invader state at 0xFC98; DI now becomes 0xFC0B.
    inc ah                                              ; Go to next color for the next invader
    xchg ax, bx                                         ; Swab back. AX now holds the next position. BX now holds next type/color. 
    loop set_invader_positions
    add ax, 0x09 * ROW_STRIDE - (0x0B * 0x0B * 2)       ; After a row is complete, move to the start of the next row. To do this, we
                                                        ;   go down 9 big rows and move left by 11 invader widths (plus the 11 big pixel space)
    dec dh                                              ; This line was not in his original code. We're simply decrementing the row counter
    jnz reset_invader_rows                              ; A bit different from the original `jne` instruction. We use "jump if not zero" since
                                                        ;   it's convention to use jnz after a dec or inc instruction

  ; Draws the barriers that protect the ship.
  mov di, 0x55 * ROW_STRIDE + 0x10 *0x 2                  ; Annoyingly, the author used 0x55*280 instead of 0x55 * ROW_STRIDE (or OFFSET_X as he called it).
                                                        ;   Regardless, what this does is sets the DI to the memory address corresponding: 
                                                        ;   0x55 * ROW_STRIDE or 85 decimal * 2 = 170, the Y position. The X pos is calculated as 
                                                        ;   16 decimal * 2, or 32.  
  mov cl, 5                                             ; set a counter of 5 to draw 5 barriers

draw_barriers:
  mov ax, BARRIER_COLOR * 0x0100 + 0x04                 ; Moves the barrier color to AH. the 0x04 part is clever on part of the author so I'm leaving it rather than adding
                                                        ;   another shape to the sprites data. When I'm sure I've properly absorbed the trick, I may add a new shape.
                                                        ;   The draw_sprite routine uses the value in AL as the starting index of the bitmaps table. It loops over the data
                                                        ;   until the index is a multiple of 8. The 0x04 index happens be in the spaceship, and thus draw_sprite will
                                                        ;   draw the last 4 rows of the spaceship, which is what is used for the barrier. 
  call draw_sprite
  add di, 0x1E * 2                                      ; Move DI to the starting position for the next barrier, 60 pixels (30 *2) to the right.
  loop draw_barriers                                    ; Decrements the counter in cl

