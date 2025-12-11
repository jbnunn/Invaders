; Draws a sprite to the screen

draw_sprite:
    %if pure8088
        push cx
        push di
        pushf
    %else
        pusha
    %endif

draw_sprite_row_loop:
  push ax
  mov bx,bitmaps
  cs xlat                 ; Extract one byte from bitmap
  xchg ax,bx              ; bl contains byte, bh contains color
  mov cx,10               ; Two extra zero pixels at left and right
  clc                     ; Left pixel as zero (clean)

draw_sprite_pixel_loop:

  mov al,bh               ; Duplicate color in AX
  call bit                ; Draw pixel
  shl bl,1
  loop in0
  add di,OFFSET_X-20      ; to next video line
  pop ax
        inc ax                  ; Next bitmap byte
        te7               ; Sprite complete?
        jne in3                 ; No, jump
    %if pure808popf
        pop di
        pop cx
    %else
        popa
endif
      t
