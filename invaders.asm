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

org 0x0100                                  ; Start position for COM files

%include "include/init_game.asm"
%include "include/restart_game.asm"


