; Space Invaders
; jbnunn Dec 2025
;
; Inspiration https://github.com/nanochess/Invaders and the book "Programming Boot Sector Games",
; by Oscar Toledo G.
;
; I have modified the code to make it more readable, but it also means this doesn't fit in a boot
; sector anymore, and must be run as a .com file. Many sections have been moved to include files
; to make it easier to learn and debug
;
; To compile as a .com file (for DOSBox):
; nasm -f bin invaders.asm -o invaders.com
;
; To run in DOSBox:
; dosbox invaders.com
;

; Unfortunately the book is poorly edited, so many parts can be confusing because they don't fully
; explain how things are working. I heavily commented this code so that it's more explainable and
; readable than the original book
;
; Note: see "???" for things I don't understand
;

base:           equ 0xFC80                  ; Memory base (same segment as video)

shots:          equ base + 0x00             ; Space to contain 4 shots (2 bytes each one)
                                            ; Plus space for a ignored shot (full table)
                                            ; Notice (sprites + SPRITE_SIZE) - (shots + 2)
                                            ; must be divisible by SPRITE_SIZE.
old_time:       equ base + 0x0C             ; Old time
level:          equ base + 0x10             ; Current level number
lives:          equ base + 0x11             ; Current lives
sprites:        equ base + 0x12             ; Space to contain sprite table

X_WIDTH:        equ 0x140                   ; X-width of video (320 pixels)
ROW_STRIDE:     equ X_WIDTH * 2             ; The original author used the variable "OFFSET_X" which was maddeningly confusing.
                                            ; For one thing, it's not an X direction, but a Y direction we're offsetting. The meant
                                            ; it to represent how many X "columns" we needed to wrap to print the next pixel.    
                                            ; The sprites are drawn using 2x2 pixel blocks, so one row is actually two pixels tall.
                                            ; Thus, if the width of our screen is 320px, then each row is really 640px, thus
                                            ; this ROW_STRIDE value.   
SPRITE_SIZE:    equ 4                       ; Size of each sprite in bytes
SHIP_ROW:       equ 0x5C * ROW_STRIDE       ; Row of spaceship

; Set the colors for different objects
SPACESHIP_COLOR:            equ 0x1C        ; Must be below 0x20
BARRIER_COLOR:              equ 0x0B
SHIP_EXPLOSION_COLOR:       equ 0x0A
INVADER_EXPLOSION_COLOR:    equ 0x0E
BULLET_COLOR:               equ 0x0C
START_COLOR:                equ ((sprites+SPRITE_SIZE-(shots+2))/SPRITE_SIZE+0x20)        

org 0x0100                      ; Start position for COM files

.start:
    ; Initialize the video mode and game state
    mov ax, 0x0013      ; Set mode to 0x13 (320x200x256 VGA)
    int 0x10            ; BIOS interrupt that sets the video mode (https://en.wikipedia.org/wiki/INT_10H)
    cld                 ; Makes sure the direction flag is cleared (for STOSW etc.)

    mov ax, 0xA000      ; this is the segement address where VGA Mode video memory begins
    mov ds, ax          ; Copies video memory segment address into the data segment (ds) register
    mov es, ax          ; Do the same for extra segment (es) register. Now we can access the screen and
                        ; game variables at the same address

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


    ; Draws the barriers that protect the ship.
    mov di, 0x55 * ROW_STRIDE + 0x10 * 0x2          ; Annoyingly, the author used 0x55*280 instead of 0x55 * ROW_STRIDE (or OFFSET_X as he called it).
                                                    ; Regardless, what this does is sets the DI to the memory address corresponding: 
                                                    ; 0x55 * ROW_STRIDE or 85 decimal * 2 = 170, the Y position. The X pos is calculated as 
                                                    ; 16 decimal * 2, or 32.  

    ; Draw the barriers
    ; -----------------
    ; Barriers are drawn directly to screen (using draw_sprite), not stored in sprite table.
    
    mov di, 0x55 * 0x280 + 0x10 * 2                 ; Initial screen position for barrier
    mov cl, 5                                       ; 5 barriers

.draw_barriers:
    mov ax, BARRIER_COLOR * 0x0100 + 0x04           ; Barrier Color and Sprite Index (0x04 is part of spaceship sprite used as barrier)
    call draw_sprite                                ; Call the draw_sprite routine to render a single segment of the barrier, using the 
                                                    ; color (in ah) and sprite pattern index (in al) previously loaded into ax." 
    add di, 0x1E * 2                                ; Advance to the right 2x the width of the barrier 
    loop .draw_barriers                             ; We've set cl to 5 above, so this will draw 5 barriers

game_loop_start:                                    
    mov si,sprites+SPRITE_SIZE                      ; We've already setup the spaceship below (which was at the start of the `sprites`)
                                                    ; memory space. So, we advance 4 bytes past that (SPRITE_SIZE) to start the invaders
    ;
    ; Game loop
    ;
    ; Globals:
    ; SI = Next invader to animate
    ; DL = state (0=left, 1=right, >=2 down)
    ; DH = nstate (next state)
    ; CH = dead invaders
    ; BP = frame counter
    ;

check_invader_state:                               
    ; Check the invader state
    ; --- INVADER STATE CODES (stored at [SI+2]) ---
    ; 0x10:  Invader active, animation frame 1 (initial state)
    ; 0x18:  Invader active, animation frame 2 (toggled with 0x10 for animation)
    ; 0x20:  Invader hit, currently in explosion animation
    ; 0x28:  Invader destroyed ("cosmic debris"), no longer active or drawn
    ; -------------------------------------------------

    cmp byte [si+2],0x20                            ; We know from when we setup the invaders above that si and si+1 hold the screen position, and
                                                    ; si+2 and s+3 hold the invader's state and color. Invader state (see table above) of 0x20 means 
                                                    ; the invader is currently exploding. 
    jc in2                                          ; if the invader state at si+2 is less than 0x20, the carry flag gets set, and we jump to in2
    inc ch                                          ; Increment ch, which will track dead invaders
    cmp ch, 55                                      ; Are all invaders defeated?
    je restart_game                                 ; If yes, restart game, if not, contineu.

process_invader:
    lodsw                                           ; Load the word at [DS:SI] into AX, which gives us current invader's position, and advances SI by 2
    xchg ax, di                                     ; Swap the value of AX and DI. Now DI has the screen position (which will be needed for draw_sprite later)
                                                    ; AX just holds whatever was in DI, but it doesn't matter, we don't need it
    lodsw                                           ; Load the word at [DS:SI] into AX, which gives us the invader's state and color, and advances SI by 2 
    cmp al, 0x28                                    ; Check to see if invader is in the destroyed state
    je in27                                         ; If yes, jump to in27
    cmp al, 0x20                                    ; Check to see if invader is in explosion animation state
    jne in29                                        ; If no, jump to in29
    mov byte [si-2], 0x28                           ; Ok, so if we're here, the invader was just in an explosion state, and now we need to destroy it.
                                                    ; To set the destroy state, we need to go back a word, so we use [si-2], and write the 0x28 destroyed state.
in29:   
    call draw_sprite                                ; Draw the invader using the type/color in AX and position in DI 

in27:   cmp si,sprites+56*SPRITE_SIZE     ; Whole board revised?
        jne check_invader_state                ; No, jump
        mov al,dh
        sub al,2                ; Going down?
        jc game_loop_start                 ; No, preserve left/right direction
        xor al,1                ; Switch direction
        mov dl,al
        mov dh,al
        jmp game_loop_start

in2:
        xor byte [si+2],8       ; Invader animation (before possible explosion)
        ;
        ; Synchronize game to 18.20648 hz. of BIOS
        ;
        inc bp
        and bp,7                ; Each 8 invaders
        pusha                   ; Save registers (simpler than pure8088 checks)
        jne in12
in22:
        mov ah,0x00           
        int 0x1a                ; BIOS clock read
        cmp dx,[old_time]       ; Wait for change
        je in22
        mov [old_time],dx       ; Save new current time
in12:
        ;
        ; Handle player bullet
        ;
        mov si,shots                    ; Point to shots list
        mov cx,4                        ; 4 shots at most
        lodsw                           ; Read position (player)
        cmp ax,X_WIDTH                  ; Is it at top of screen?
        xchg ax,di
        jc in31                         ; Erase bullet
                                        ; Doesn't mind doing it all time
        call zero                       ; Remove bullet 
        sub di,X_WIDTH+2
        mov al,[di]                     ; Read pixel
        sub al,0x20                     ; Hits invader?
        jc in30                         ; No, jump
        pusha
        mov ah,SPRITE_SIZE              ; The pixel indicates the...
        mul ah                          ; ...invader hit.
        add si,ax
        lodsw
        xchg ax,di
        mov byte [si],0x20              ; Erase next time
        mov ax,INVADER_EXPLOSION_COLOR*0x0100+0x08      ; But explosion now
        call draw_sprite                ; Draw sprite
        popa
        jmp in31

        ;
        ; Handle invader bullets
        ;
in24:
        lodsw                           ; Read current coordinate
        or ax,ax                        ; Is it falling?
        je in23                         ; No, jump
        cmp ax,0x60*ROW_STRIDE            ; Pixel lower than spaceship?
        xchg ax,di
        jnc in31                        ; Yes, remove bullet
        call zero                       ; Remove bullet 
        add di,X_WIDTH-2                ; Bullet falls down

        ; Draw bullet
in30:
        mov ax,BULLET_COLOR*0x0100+BULLET_COLOR
        mov [si-2],di                   ; Update position of bullet
        cmp byte [di+X_WIDTH],BARRIER_COLOR     ; Barrier in path?
        jne in7                         ; Yes, erase bullet and barrier pixel

        ; Remove bullet
in31:   xor ax,ax                       ; AX contains zero (DI unaffected)
        mov [si-2],ax                   ; Delete bullet from table

in7:    cmp byte [di],SPACESHIP_COLOR   ; Check collision with player
        jne in41                        ; No, jump
        mov word [sprites],SHIP_EXPLOSION_COLOR*0x0100+0x38 ; Player explosion
in41:
        call big_pixel                  ; Draw/erase bullet
in23:   loop in24

        ;
        ; Spaceship handling
        ;
        mov si,sprites                  ; Point to spaceship
        lodsw                           ; Load sprite frame / color
        or al,al                        ; Explosion?
        je in42                         ; No, jump
        add al,0x08                     ; Keep explosion
        jne in42                        ; Finished? No, jump
        mov ah,SPACESHIP_COLOR          ; Restore color (sprite already)
        dec byte [lives]                ; Remove one life
        js in10                         ; Exit if all used
in42:   mov [si-2],ax                   ; Save new frame / color
        mov di,[si]                     ; Load position
        call draw_sprite                ; Draw sprite (spaceship)
        jne in43                        ; Jump if still explosion

        mov ah,0x02                     ; BIOS Get Keyboard Flags 
        int 0x16

        test al,0x10                    ; Test for Scroll Lock and exit
        jnz in10

        test al,0x04                    ; Ctrl key?
        jz in17                         ; No, jump
        dec di                          ; Move 2 pixels to left
        dec di

in17:   test al,0x08                    ; Alt key?
        jz in18                         ; No, jump
        inc di                          ; Move 2 pixels to right
        inc di
in18:
        test al,0x03                    ; Shift keys?
        jz in35                         ; No, jump
        cmp word [shots],0              ; Bullet available?
        jne in35                        ; No, jump
        lea ax,[di+(0x04*2)]            ; Offset from spaceship
        mov [shots],ax                  ; Start bullet
in35:
        xchg ax,di
        cmp ax,SHIP_ROW-2               ; Update if not touching border
        je in43
        cmp ax,SHIP_ROW+0x0132
        je in43
in19:   mov [si],ax                     ; Update position
in43:
        popa

        mov ax,[si]             ; Get position of current invader
        cmp dl,1                ; Going down (state 2)?
        jbe in9                 ; No, jump
        add ax,0x0280           ; Go down by 2 pixels
        cmp ax,0x55*0x280       ; Reaches Earth?
        jc in8                  ; No, jump
in10:
        mov ax,0x0003           ; Restore text mode
        int 0x10
        int 0x20                ; Exit to DOS

in9:    dec ax                  ; Moving to left
        dec ax
        jc in20
        add ax,4                ; Moving to right
in20:   push ax
        shr ax,1                ; Divide position by 2...
        mov cl,0xa0             ; ...means we can get column dividing by 0xa0
        div cl                  ; ...instead of 0x0140 (longer code)
        dec ah                  ; Convert 0x00 to 0xff
        cmp ah,0x94             ; Border touched? (>= 0x94)
        pop ax
        jb in8                  ; No, jump
        or dh,22                ; Goes down by 11 pixels (11 * 2) must be odd
in8:    mov [si],ax
        add ax,0x06*0x280+0x03*2        ; Offset for bullet
        xchg ax,bx

        mov cx,3        ; ch = 0 - invader alive
        in al,(0x40)    ; Read timer
        cmp al,0xfc     ; Random event happening?
        jc in4          ; No, jump
        ;
        ; Doesn't work in my computer:
        ;
        ; mov di,shots+2
        ; xor ax,ax
        ; repne scasw
        ; mov [di-2],bx
        ;
        mov di,shots+2
in45:   cmp word [di],0 ; Search for free slot
        je in44         ; It's free, jump!
        scasw           ; Advance DI
        loop in45       ; Until 3 slots searched
in44:
        mov [di],bx     ; Start invader shot (or put in ignored slot)
in4:
        jmp process_invader

        ;
        ; Bitmaps for sprites
        ;
bitmaps:
        db 0x18,0x18,0x3c,0x24,0x3c,0x7e,0xFf,0x24      ; Spaceship
        db 0x00,0x80,0x42,0x18,0x10,0x48,0x82,0x01      ; Explosion
        db 0x00,0xbd,0xdb,0x7e,0x24,0x3c,0x66,0xc3      ; Alien (frame 1)
        db 0x00,0x3c,0x5a,0xff,0xa5,0x3c,0x66,0x66      ; Alien (frame 2)
        db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00      ; Erase

        ;
        ; Draw pixel per Carry (use AX if Carry=1 or zero if Carry=0)
        ;
bit:    jc big_pixel
zero:   xor ax,ax
        ; Draw a big pixel (2x2 pixels)
big_pixel:
        mov [di+X_WIDTH],ax
        stosw
        ret

dj; Inputs:
; AH = Color of the sprite
; AL = Sprite index
; DI = Screen position
;

draw_sprite:
    pusha                   ; Save all registers (AX, CX, DX, BX, SP, BP, SI, DI)
                            ; This ensures we don't clobber the game loop state (especially SI!)

    ; Setup
    mov si, ax              ; Copy index/color to SI
    mov dl, ah              ; Save Color to DL (AH)
    and si, 0xFF            ; SI = Index (AL)

.draw_row:
    push di                 ; Save start of row
    
    ; Load pixels from Code Segment (CS override needed for .COM/Boot)
    mov bl, [cs:bitmaps + si]  
    
    inc si                  ; Next row byte
    
    ; 1. Draw Left Padding (Black)
    mov ah, 0
    call .draw_single_pixel
    
    ; 2. Draw 8 Sprite Pixels
    mov cx, 8
.pixel_loop:
    shl bl, 1
    jc .set_color
    mov ah, 0               ; Black
    jmp .draw_it
.set_color:
    mov ah, dl              ; Color
.draw_it:
    call .draw_single_pixel
    loop .pixel_loop
    
    ; 3. Draw Right Padding (Black)
    mov ah, 0
    call .draw_single_pixel
    
    pop di                  ; Restore start of row
    add di, 0x280           ; Next row (ROW_STRIDE)
    
    ; Check if sprite is complete
    ; Original logic: Continue until SI is a multiple of 8
    test si, 7
    jnz .draw_row

    popa                    ; Restore all registers
    ret

; Helper to draw one 2x2 pixel block and advance DI
; Inputs: AH = Color, DI = Screen Address
.draw_single_pixel:
    mov [di], ah            ; Top-Left
    mov [di+1], ah          ; Top-Right
    mov [di+0x140], ah      ; Bottom-Left
    mov [di+0x140+1], ah    ; Bottom-Right
    add di, 2
    ret
