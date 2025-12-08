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
OFFSET_X:           equ X_WIDTH * 2         ; ??? I don't understand original comment, "X-offset between screen rows"
SHIP_ROW:           equ 0x5C * OFFSET_X     ; 0x5c = 92 decimal. Row we place the space ship on
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

