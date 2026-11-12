.segment "PROGRAM"

ZP_PTR  = $40               ; string pointers of the BIOS screens
ZP_PTR2 = $42

; =============================================================================
; ARCADE INPUTS (schematic Arcade6502, sheets JOY and SDC, JAMMA connector)
;
; Joystick board, W65C22 at $D580 (all lines active low, pull-ups on the board):
;   port A ($D581) = player 1, port B ($D580) = player 2
;   bit 0 UP, 1 DOWN, 2 LEFT, 3 RIGHT, 4 BUTTON 1, 5 BUTTON 2, 6 BUTTON 3, 7 START
;   (bits 0-5 are the same as on the miniVIC joystick board: the miniVIC games work unchanged)
; SD board, W65C22 at $DD80, the port A lines not used by the SD card ($DD81, active low):
;   bit 0 TEST switch, bit 5 SERVICE switch, bit 6 P1 COIN, bit 7 P2 COIN
;   (bits 1-4 are the SD card: MISO, MOSI, SCK, CS)
;
; ARC_READ_INPUTS (jump table $FD80) gives all of them with 1 = pressed:
;   A = player 1, X = player 2 (bits as above), Y = system inputs:
;   bit 0 P1 COIN, bit 1 P2 COIN, bit 2 TEST, bit 3 SERVICE
; =============================================================================

JOY_P2      = $D580         ; port B: player 2
JOY_P1      = $D581         ; port A: player 1
JOY_DDRB    = $D582
JOY_DDRA    = $D583
JOY_HOLD    = $D586         ; T1 latch low of the joystick VIA, used as a byte of storage by the
                            ; NMI handler (hold counter of the two START buttons): the latch keeps
                            ; the value written and gives it back when read, and no game uses the
                            ; timers of this VIA (the timer is never started by the BIOS)
JOY_IER     = $D58E
SYS_PORT    = $DD81         ; port A of the SD board: TEST, SERVICE, COIN 1, COIN 2
SD_IER      = $DD8E

J_UP        = %00000001
J_DOWN      = %00000010
J_LEFT      = %00000100
J_RIGHT     = %00001000
J_B1        = %00010000
J_B2        = %00100000
J_B3        = %01000000
J_START     = %10000000
J_DIRS      = J_UP | J_DOWN | J_LEFT | J_RIGHT

SYS_COIN1   = %00000001     ; bits of the system byte returned by ARC_READ_INPUTS
SYS_COIN2   = %00000010
SYS_TEST    = %00000100
SYS_SERVICE = %00001000

; RAM (the old keyboard variables of the miniVIC BIOS, $0306-$0309)
vk_prev     = $0306         ; joystick bits (P1 or P2, 1 = pressed) seen by the last CHRIN_NO_ECHO

; audio board: 2 x AY-3-8910, A2 = 0 right, 1 left; A0 = 0 latch, 1 data
AY_R_LATCH  = $D380
AY_R_DATA   = $D381
AY_L_LATCH  = $D384
AY_L_DATA   = $D385

; ---------------------------------------------------------------
; ARC_READ_INPUTS: A = P1, X = P2, Y = system (1 = pressed). Flags changed.
; ---------------------------------------------------------------
ARC_READ_INPUTS:
    jsr arc_read_sys
    tay
    lda JOY_P2
    eor #$FF
    tax
    lda JOY_P1
    eor #$FF
    rts

; arc_read_sys: A = system inputs (SYS_xxx bits, 1 = pressed). Preserves X and Y.
arc_read_sys:
    phy
    ldy #0
    lda SYS_PORT
    eor #$FF                    ; 1 = pressed: bit 0 TEST, 5 SERVICE, 6 COIN 1, 7 COIN 2
    asl                         ; C = COIN 2
    bcc @c2
    iny
    iny                         ; SYS_COIN2
@c2:
    asl                         ; C = COIN 1
    bcc @c1
    iny                         ; SYS_COIN1
@c1:
    asl                         ; C = SERVICE
    bcc @sv
    pha
    tya
    ora #SYS_SERVICE
    tay
    pla
@sv:
    and #%00001000              ; TEST (bit 0, shifted 3 times)
    beq @ts
    tya
    ora #SYS_TEST
    tay
@ts:
    tya
    ply
    rts

; arc_read_joy: A = P1 or P2 (1 = pressed): the menus answer to both players. Preserves X and Y.
arc_read_joy:
    lda JOY_P1
    and JOY_P2
    eor #$FF
    rts

; ---------------------------------------------------------------
; arc_io_init: inputs on both VIAs, their interrupts off, sound off
; ---------------------------------------------------------------
arc_io_init:
    stz JOY_DDRA                ; joysticks: all inputs
    stz JOY_DDRB
    lda #$7F
    sta JOY_IER                 ; no interrupt from the joystick VIA...
    sta SD_IER                  ; ...nor from the SD VIA (a program may have left one on)
    stz JOY_HOLD                ; START hold counter of the NMI handler
    jsr arc_read_joy
    sta vk_prev                 ; a button already held is not a new press
    ; falls through

; AY_SILENCE: both AY-3-8910 silent (mixer off, volumes 0). Preserves X and Y.
AY_SILENCE:
    phx
    ldx #7
    lda #$3F                    ; register 7: tone and noise off, I/O ports as inputs
    jsr ay_both
    lda #0
    ldx #8
    jsr ay_both                 ; volume A
    inx
    jsr ay_both                 ; volume B
    inx
    jsr ay_both                 ; volume C
    plx
    rts

; ay_both: register X = A on both chips
ay_both:
    stx AY_R_LATCH
    sta AY_R_DATA
    stx AY_L_LATCH
    sta AY_L_DATA
    rts

; ---------------------------------------------------------------
; CHRIN_NO_ECHO (jump table $FD03): C=1 and A = key, C=0 no key. Preserves X and Y.
; The serial port first; without a keyboard, the joysticks (either player) give keys
; too, one for every new press (no auto-repeat):
;   START, BUTTON 1 = $0D (ENTER)   BUTTON 2 = $1B (ESC)   BUTTON 3 = ' '
;   UP $80, DOWN $81, LEFT $82, RIGHT $83 (the arrow codes of the KEYB/SD BIOS)
; So the BIOS screens and the programs that wait for "a key" also work on the cabinet.
; ---------------------------------------------------------------
CHRIN_NO_ECHO:
    lda ACIA_STATUS
    and #$08
    beq @joy
    lda ACIA_DATA
    sec
    rts
@joy:
    phx
    jsr arc_read_joy
    tax                         ; X = pressed now
    lda vk_prev
    eor #$FF
    stx vk_prev
    and vk_prev                 ; A = new presses
    beq @none
    ldx #7                      ; highest priority last in the tables
@find:
    bit vk_mask,x
    bne @hit
    dex
    bpl @find
@none:
    plx
    clc
    rts
@hit:
    lda vk_code,x
    plx
    sec
    rts

vk_mask:    .byte J_RIGHT, J_LEFT, J_DOWN, J_UP, J_B3, J_B2, J_B1, J_START
vk_code:    .byte $83,     $82,    $81,    $80,  ' ',  $1B,  $0D,  $0D

; ---------------------------------------------------------------
; FLUSH_INPUT (jump table $FD15, JT_FLUSH_KB): waits ~0.5 s, drops the bytes received on
; the serial port and takes the buttons held now as already seen. Preserves A, X, Y.
; ---------------------------------------------------------------
FLUSH_KEYBOARD_HARD:
    pha
    phx
    phy
    ldx #$FF
@delay1:
    ldy #$FF
@delay2:
    dey
    bne @delay2
    dex
    bne @delay1
@drain:
    lda ACIA_STATUS
    and #$08
    beq @drained
    lda ACIA_DATA
    bra @drain
@drained:
    jsr arc_read_joy
    sta vk_prev
    ply
    plx
    pla
    rts

; KB_SET_MODE (jump table $FD21): there is no keyboard; kept so that the programs made for the
; KEYB/SD BIOS can call it. Does nothing.
KB_SET_MODE:
    rts

; ser_putc: A -> serial port only (fixed delay like CHROUT: never waits for the ACIA).
; Preserves A, X, Y.
ser_putc:
    pha
    sta ACIA_DATA
    lda #$FF
@d:
    dec
    bne @d
    pla
    rts

; ser_puts: string (A lo, X hi, $00 at the end, max 255 characters) -> serial port only
ser_puts:
    sta ZP_PTR
    stx ZP_PTR+1
    ldy #0
@l:
    lda (ZP_PTR),y
    beq @e
    jsr ser_putc
    iny
    bne @l
@e:
    rts
