.setcpu "65C02"
.debuginfo
.segment "BIOS"

; =============================================================================
; Arcade BIOS: machine I/O of the Arcade6502 (no keyboard).
; CHRIN reads only the serial port (BASIC and WozMon are used from a terminal);
; CHROUT writes to the CRT (text mode) and to the serial port, as on the miniVIC.
; =============================================================================

ACIA_DATA	= $c000
ACIA_STATUS	= $c001
ACIA_CMD	= $c002
ACIA_CTRL	= $c003


LOAD:
                rts

SAVE:
                rts


; Input a character from the serial port, with echo.
; Out: C=1 and A = character, C=0 no character. Preserves X and Y.
MONRDKEY:
CHRIN:
                lda     ACIA_STATUS
                and     #$08
                beq     @none
                lda     ACIA_DATA
                jsr     CHROUT          ; echo (as the miniVIC BIOS does for the serial port)
                sec
                rts
@none:
                clc
                rts


; Output a character (from the A register) to the CRT and to the serial interface.
;
; Modifies: flags
MONCOUT:
CHROUT:
                pha
                jsr     print_crt_ch
                sta     ACIA_DATA
                lda     #$FF
@txdelay:       dec
                bne     @txdelay
                pla
                rts

IRQ_HANDLER:
  PHA
  PHX
  PHY
  JSR $0FA0         ; CALL DISPATCH (IN RAM)
  PLY
  PLX
  PLA
  RTI


;; LOADING DRIVER
.include "serial_drv.s"
.include "arcade_io.s"
.include "frontend.s"
.include "crt_text_drv.s"
.include "crt_g2_drv.s"



; LOADING SOFTWARE
.include "sdcard_drv.s"
.include "wozmon.s"
.include "jumptable.s" ; SD vector



.segment "RESETVEC"
                .word   NMI_HANDLER ; NMI vector (VDP interrupt)
                .word   SHOW_MENU   ; RESET vector: the game front-end
                .word   IRQ_HANDLER ; IRQ vector
