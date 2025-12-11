; Draws an 8x8 sprite to the screen at a specific location. It takes:
; AL = Sprite number. Since each sprite is 8 bytes, it multiples AL by 8 to get the full bytes ??? (is this correctly said)
; DI = Target screen memory address where we will draw the sprite


draw_sprite:
  ; The original code had a conditional to check for `pure80088`, which couldn't use the `pusha`
  ; instruction. Given we're using DOSBox, which does support pusha, I've removed that check.
  pusha

  draw_sprite_row_loop:
    push ax
    mov bx,bitmap
    cs xlat                 ; Extract one byte from bitmap
    xchg ax,bx              ; bl contains byte, bh contains color
    mov cx,10               ; Two extra zero pixels at left and right
    clc                     ; Left pixel as zero (clean)

  draw_sprite_pixel_loop:    
    mov al,bh               ; Duplicate color in AX
    mov ah,bh
    call bit                ; Draw pixel
    shl bl,1
    loop in0
    add di,OFFSET_X-20      ; Go to next video line
    pop ax
    inc ax                  ; Next bitmap byte
    test al,7               ; Sprite complete?
    jne in3                 ; No, jump
    popa                    ; Removed another `pure8088` conditional
  
  ret

