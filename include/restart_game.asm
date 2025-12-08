; restart_game.asm

restart_game:             ; ??? This is a confusing label. It implies a full reset, but it is also used
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
                          ;   ??? if we notice weird errors we should move back to stosw and `level/2`


  ; This block initializes the invaders' first move. The game uses the DX register as a "steering wheel"
  ; for the invader swarm, where DL holds the current movement and DH holds the next movement.
  ; The author's movement codes are: 0 = move left, 1 = move right, 2 = move down.
  ; The goal here is to calculate a descent value based on the current level and load it into both DL and DH.
  ; The formula used is: Descent Value = Current Level + 2.
  ;
  ; --- TASK 1: Calculate and Save New Level ---
  mov ax, [level]         ; Load the OFFICIAL `level` (into AL) and `lives` (into AH) from their permanent
                          ;   storage location in memory into the AX temporary scratchpad. Your use of [level]
                          ;   is correct to achieve the book's intent.
  inc ax                  ; Add 1 to the level value in AL. On level 0, AX becomes 0x0401.
  inc ax                  ; Add 1 again. On level 0, AX becomes 0x0402. AL now holds the descent value (2).
  stosw                   ; "Save". Store the updated values from the AX scratchpad back to the OFFICIAL
                          ;   storage location for `level` and `lives` in memory (at address ES:DI, which
                          ;   should be pointing to `level`). Task 1 is now complete.
  ;
  ; --- TASK 2: Prepare and Deliver the Movement Command to DX ---
  mov ah, al              ; Prepare the command. We copy the descent value from AL (2) into AH. The AX
                          ;   scratchpad now holds 0x0202. At this moment, AH no longer represents "lives";
                          ;   it's just part of the command we are building.
  xchg ax, dx             ; Deliver the command. Swap the move command we built in our AX scratchpad with the
                          ;   DX register. DX now holds 0x0202, telling the game loop to move down.

  ;
  ; Setup the spaceship
  ;
  mov ax,SPACESHIP_COLOR*0x0100+0x00
  stosw
  mov ax,SHIP_ROW+0x4c*2
  stosw
  ;
  ; Setup the invaders
  ;
  mov ax,0x08*OFFSET_X+0x28
  mov bx,START_COLOR*0x0100+0x10
