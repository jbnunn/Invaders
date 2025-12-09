; restart_game.asm

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
  ; This block sets up the first 4 bytes of the sprites memory area to hold the complete initial state and
  ; position of the player's spaceship.
  mov di, sprites                             ; Explicitly set DI to the start of the sprites memory area. Note this was
                                              ; not in the original code but I feel safer setting the index manually
                                              
  mov ax, SPACESHIP_COLOR * 0x0100            ; Calculates a value and loads it into the AX register. The value is the
                                              ;   spaceship color (0x1c) * 0x0100, which means AH is 0x1c and AL is 0x00.
                                              ;   Later in the code, we'll see that 0 is a status code for the ship, meaning
                                              ;   it is not in an exploded state.   
  stosw                                       ; Stores the value of AX at ES:DI
  mov ax, SHIP_ROW + 0x4c * 2                 ; Stores the ships vertical position (row) and horizontal position
  stosw                                       ; Writes the spaceships initial position to the memory location immediately following
                                              ;   its color/status position.
