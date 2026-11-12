.segment "PROGRAM"

; =============================================================================
; TITLE SCREEN (power-on): "ARCADE 6502" in big letters, "DEVELOPED BY BOOGS"
; =============================================================================
; The big letters are the BIOS font with every pixel 4 wide and 8 high: patterns 28-31
; (unused debug glyphs of the font) become blank / left half / right half / full tile,
; with colour stripes from yellow to red.
BIG_PAT       = 28

fe_splash:
    jsr g2_cls
    ldx #0
@third:                                     ; the 4 patterns and their colours in the 3 thirds
    phx
    txa
    asl
    asl
    asl                                     ; third * 8 = high byte of the third
    pha
    ora #>(BIG_PAT*8)
    tax
    lda #<(BIG_PAT*8)
    jsr vdp_wr_addr
    ldy #0
@pat:
    lda big_patterns,y
    sta VDATA
    iny
    cpy #32
    bne @pat
    pla
    ora #>(G2_COLORS+BIG_PAT*8)
    tax
    lda #<(G2_COLORS+BIG_PAT*8)
    jsr vdp_wr_addr
    ldx #4
@colp:
    ldy #0
@col:
    lda big_colors,y
    sta VDATA
    iny
    cpy #8
    bne @col
    dex
    bne @colp
    plx
    inx
    cpx #3
    bne @third
    lda #2
    sta G_ROW
    lda #7
    sta G_COL
    lda #<txt_big1
    ldx #>txt_big1
    jsr big_puts                            ; ARCADE: rows 2-8
    lda #11
    sta G_ROW
    lda #10
    sta G_COL
    lda #<txt_big2
    ldx #>txt_big2
    jsr big_puts                            ; 6502: rows 11-17
    lda #20
    sta G_ROW
    lda #$80
    jsr g2_clear_row
    lda #<txt_developed
    ldx #>txt_developed
    jsr g2_puts_center
    stz G_ATTR
    PUTS_AT 23, 1, txt_version
    rts

; big_puts: string (A lo, X hi) in big letters from G_ROW / G_COL (3 columns, 7 rows each)
big_puts:
    sta G_PTR
    stx G_PTR+1
@char:
    lda (G_PTR)
    beq @end
    stz ZP_PTR2+1                           ; ZP_PTR2 = VDP_PATTERNS + char * 8
    asl
    rol ZP_PTR2+1
    asl
    rol ZP_PTR2+1
    asl
    rol ZP_PTR2+1
    clc
    adc #<VDP_PATTERNS
    sta ZP_PTR2
    lda ZP_PTR2+1
    adc #>VDP_PATTERNS
    sta ZP_PTR2+1
    lda G_ROW
    pha
    ldy #0
@row:
    phy
    jsr g2_pos
    ply
    lda (ZP_PTR2),y
    ldx #3
@tile:
    stz G_T1
    asl                                     ; left pixel
    rol G_T1                                ; -> bit 0
    asl                                     ; right pixel
    bcc @no_right
    pha
    lda G_T1
    ora #2
    sta G_T1
    pla
@no_right:
    pha
    lda G_T1
    clc
    adc #BIG_PAT
    sta VDATA
    pla
    dex
    bne @tile
    inc G_ROW
    iny
    cpy #7
    bne @row
    pla
    sta G_ROW
    lda G_COL
    clc
    adc #3
    sta G_COL
    inc G_PTR
    bne @char
    inc G_PTR+1
    bra @char
@end:
    rts

big_patterns:
    .byte $00,$00,$00,$00,$00,$00,$00,$00   ; 28 blank
    .byte $F0,$F0,$F0,$F0,$F0,$F0,$F0,$F0   ; 29 left half
    .byte $0F,$0F,$0F,$0F,$0F,$0F,$0F,$0F   ; 30 right half
    .byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF   ; 31 full
big_colors:                                 ; foreground per line on dark blue: yellow -> red
    .byte $B4,$B4,$A4,$A4,$94,$94,$84,$84

; =============================================================================
; SYSTEM TEST (SERVICE switch, or T on the serial port): everything but the joysticks.
; CPU, ROM checksum, RAM $0200-$7FFF, VRAM 16 KB, VDP frame, SD card, games on the SD,
; a tone on each AY-3-8910 and a line on the serial port.
; RAM and VRAM are tested by writing and reading back two address-dependent patterns,
; so the test reads the list from the SD again afterwards.
; =============================================================================
T_PTR   = $60               ; 2 bytes
T_SEED  = $62
T_SUM   = $63               ; 2 bytes
T_FAIL  = $65               ; 2 bytes: failing RAM address
T_VFAIL = $67               ; 2 bytes: failing VRAM address
T_VOK   = $69               ; 0 = VRAM ok
RES_COL = 21                ; column of the results

.macro RESULT row, str, attr
    lda #row
    jsr fe_res_at
    lda #attr
    sta G_ATTR
    lda #<str
    ldx #>str
    jsr g2_puts
    stz G_ATTR
.endmacro

fe_systest:
    lda #$80
    ldx #1
    jsr vdp_set_reg                         ; display off during the VRAM test
    jsr vram_test
    lda #0
    rol                                     ; C -> A
    sta T_VOK
    jsr g2_init                             ; the screen again
    lda #<txt_systest
    ldx #>txt_systest
    jsr fe_test_title
    PUTS_AT 2, 1, txt_sys_rows
    PUTS_AT 21, 1, txt_sys_help1
    PUTS_AT 22, 1, txt_sys_help2
    ; CPU: INC A exists only on the 65C02 (a NOP on the NMOS 6502)
    lda #0
    .byte $1A                               ; INC A
    cmp #1
    bne @cpu_bad
    RESULT 2, txt_ok, 0
    bra @rom
@cpu_bad:
    RESULT 2, txt_fail, $80
@rom:
    jsr rom_sum
    lda T_SUM
    cmp ROM_SUM
    bne @rom_bad
    lda T_SUM+1
    cmp ROM_SUM+1
    bne @rom_bad
    RESULT 3, txt_ok, 0
    bra @ram
@rom_bad:
    RESULT 3, txt_fail, $80
@ram:
    RESULT 4, txt_testing, 0
    jsr ram_test
    php
    stz sd_type                             ; the RAM test overwrote the BIOS variables
    jsr arc_read_joy
    sta FE_PREV
    sta vk_prev
    jsr arc_read_sys
    sta FE_SYSPREV
    plp
    bcs @ram_bad
    RESULT 4, txt_ok, 0
    bra @vram
@ram_bad:
    RESULT 4, txt_fail_at, $80
    lda T_FAIL+1
    jsr g2_put_hex
    lda T_FAIL
    jsr g2_put_hex
@vram:
    lda T_VOK
    bne @vram_bad
    RESULT 5, txt_ok, 0
    bra @vdp
@vram_bad:
    RESULT 5, txt_fail_at, $80
    lda T_VFAIL+1
    jsr g2_put_hex
    lda T_VFAIL
    jsr g2_put_hex
@vdp:
    lda VREG                                ; F cleared...
    ldx #0
    ldy #0
@vdp_wait:
    lda VREG                                ; ...and set again within a frame
    bmi @vdp_ok
    dex
    bne @vdp_wait
    dey
    bne @vdp_wait
    RESULT 6, txt_fail, $80
    bra @sd
@vdp_ok:
    RESULT 6, txt_ok, 0
@sd:
    RESULT 7, txt_testing, 0
    jsr fe_load_catalog
    lda #7
    jsr fe_res_at
    ldx sd_type
    bne @card
    lda #$80
    sta G_ATTR
@card:
    lda sd_type_lo,x
    pha
    lda sd_type_hi,x
    tax
    pla
    jsr g2_puts
    stz G_ATTR
    lda #8
    jsr fe_res_at
    lda FE_COUNT
    bne @games
    lda #$80
    sta G_ATTR
    lda #<txt_none
    ldx #>txt_none
    jsr g2_puts
    stz G_ATTR
    bra @audio
@games:
    jsr g2_put_dec
    lda FE_HASCAT
    beq @dir
    lda #<txt_catalog
    ldx #>txt_catalog
    bra @src
@dir:
    lda #<txt_directory
    ldx #>txt_directory
@src:
    jsr g2_puts_here
@audio:
    RESULT 9, txt_tone, 0
    ldx #0
    jsr ay_beep                             ; right chip
    RESULT 10, txt_tone, 0
    ldx #4
    jsr ay_beep                             ; left chip
    lda #<txt_ser_test
    ldx #>txt_ser_test
    jsr ser_puts
    RESULT 11, txt_sent, 0
@loop:
    jsr fe_input_nocmd
    lda FE_SYSNEW
    and #SYS_SERVICE
    bne @exit
    lda FE_NEW
    and #J_START
    bne @exit
    lda ACIA_STATUS
    and #$08
    beq @loop
    lda ACIA_DATA
@exit:
    jmp fe_test_exit

; fe_res_at: A = row: clears the result field and puts the cursor there
fe_res_at:
    sta G_ROW
    lda #RES_COL
    sta G_COL
    jsr g2_pos
    ldx #32-RES_COL
    lda #' '
@c:
    sta VDATA
    nop
    dex
    bne @c
    lda #RES_COL
    sta G_COL
    sta G_LEFT
    jmp g2_pos

; g2_puts_here: string (A lo, X hi) from the current G_ROW / G_COL
g2_puts_here:
    pha
    phx
    jsr g2_pos
    plx
    pla
    jmp g2_puts

; g2_put_hex: A as two hex digits at the current position
g2_put_hex:
    pha
    lsr
    lsr
    lsr
    lsr
    jsr @nib
    pla
@nib:
    and #$0F
    cmp #10
    bcc @dig
    adc #6                                  ; C = 1: + 7
@dig:
    adc #'0'
    jmp g2_putc

; ay_beep: X = 0 right chip, 4 left chip: 440 Hz on channel A for half a second
ay_beep:
    lda #0
    ldy #142                                ; 1 MHz / (16 * 440)
    jsr ay_reg
    lda #1
    ldy #0
    jsr ay_reg
    lda #8
    ldy #$0F
    jsr ay_reg                              ; volume A
    lda #7
    ldy #$3E
    jsr ay_reg                              ; tone A on
    ldy #30
@w:
    jsr fe_wait_frame
    dey
    bne @w
    lda #8
    ldy #0
    jsr ay_reg
    lda #7
    ldy #$3F
    ; falls through
; ay_reg: register A = Y on the chip of X (0 right, 4 left)
ay_reg:
    sta AY_R_LATCH,x
    tya
    sta AY_R_DATA,x
    rts

; vram_test: 16 KB, two passes. C=0 ok, C=1 failed at T_VFAIL
vram_test:
    stz T_SEED
    jsr @pass
    bcs @r
    lda #$FF
    sta T_SEED
@pass:
    lda #0
    tax
    jsr vdp_wr_addr
    stz T_PTR+1
@wp:
    ldy #0
@wb:
    tya
    eor T_PTR+1
    eor T_SEED
    sta VDATA
    iny
    bne @wb
    inc T_PTR+1
    lda T_PTR+1
    cmp #$40
    bne @wp
    lda #0
    sta VREG
    sta VREG                                ; read address 0
    stz T_PTR+1
@rp:
    ldy #0
@rb:
    tya
    eor T_PTR+1
    eor T_SEED
    cmp VDATA
    bne @bad
    iny
    bne @rb
    inc T_PTR+1
    lda T_PTR+1
    cmp #$40
    bne @rp
    clc
@r:
    rts
@bad:
    sty T_VFAIL
    lda T_PTR+1
    sta T_VFAIL+1
    sec
    rts

; ram_test: $0200-$7FFF, two passes. C=0 ok, C=1 failed at T_FAIL
ram_test:
    stz T_SEED
    jsr @pass
    bcs @r
    lda #$FF
    sta T_SEED
@pass:
    stz T_PTR
    lda #$02
    sta T_PTR+1
@wp:
    ldy #0
@wb:
    tya
    eor T_PTR+1
    eor T_SEED
    sta (T_PTR),y
    iny
    bne @wb
    inc T_PTR+1
    bpl @wp                                 ; up to $7FFF
    lda #$02
    sta T_PTR+1
@rp:
    ldy #0
@rb:
    tya
    eor T_PTR+1
    eor T_SEED
    cmp (T_PTR),y
    bne @bad
    iny
    bne @rb
    inc T_PTR+1
    bpl @rp
    clc
@r:
    rts
@bad:
    sty T_FAIL
    lda T_PTR+1
    sta T_FAIL+1
    sec
    rts

; rom_sum: T_SUM = 16-bit sum of the ROM ($8000-$AFFF, $E000-$FFFF) without the two bytes of
; ROM_SUM, where make.sh writes the same sum
rom_sum:
    stz T_SUM
    stz T_SUM+1
    stz T_PTR
    lda #$80
    sta T_PTR+1
@p:
    ldy #0
@b:
    lda (T_PTR),y
    clc
    adc T_SUM
    sta T_SUM
    bcc @nc
    inc T_SUM+1
@nc:
    iny
    bne @b
    inc T_PTR+1
    lda T_PTR+1
    cmp #$B0
    bne @next
    lda #$E0                                ; skip the I/O pages
    sta T_PTR+1
@next:
    lda T_PTR+1
    bne @p                                  ; up to $FFFF
    ldx #1
@sub:                                       ; minus the two bytes of ROM_SUM
    lda T_SUM
    sec
    sbc ROM_SUM,x
    sta T_SUM
    bcs @ns
    dec T_SUM+1
@ns:
    dex
    bpl @sub
    rts

; fe_test_title: clear screen, title bar with the string A / X
fe_test_title:
    pha
    phx
    jsr g2_cls
    lda #0
    sta G_ROW
    lda #$80
    jsr g2_clear_row
    plx
    pla
    jsr g2_puts_center
    stz G_ATTR
    rts

; back from a test: the list if there are games, otherwise the "no games" screen
fe_test_exit:
    lda FE_COUNT
    bne @list
    jmp fe_no_games
@list:
    jmp fe_list

sd_type_lo:     .byte <txt_none, <txt_sdsc1, <txt_sdsc2, <txt_sdhc
sd_type_hi:     .byte >txt_none, >txt_sdsc1, >txt_sdsc2, >txt_sdhc

; =============================================================================
; JOYSTICK TEST (TEST switch, or J on the serial port)
; Every input of the two control panels (4 directions, buttons 1-3, START, COIN):
; "--" not pressed yet, "ON" pressed now, "OK" pressed at least once. All 18 tested: ALL OK.
; =============================================================================
fe_joytest:
    lda #<txt_joytest
    ldx #>txt_joytest
    jsr fe_test_title
    PUTS_AT 2, 1, txt_test_head
    PUTS_AT 4, 1, txt_test_rows
    PUTS_AT 21, 1, txt_joy_help1
    PUTS_AT 22, 1, txt_joy_help2
    stz FE_TESTED
    stz FE_TESTED+1
    stz FE_TESTED+2
    lda #$FF
    sta FE_TESTED+3                         ; count shown: none yet
@loop:
    jsr fe_input_nocmd
    lda JOY_P1
    eor #$FF
    tay
    ora FE_TESTED
    sta FE_TESTED
    tya
    ldx #13
    ldy FE_TESTED
    jsr fe_joy_col
    lda JOY_P2
    eor #$FF
    tay
    ora FE_TESTED+1
    sta FE_TESTED+1
    tya
    ldx #20
    ldy FE_TESTED+1
    jsr fe_joy_col
    jsr arc_read_sys
    and #(SYS_COIN1 | SYS_COIN2)
    tay
    ora FE_TESTED+2
    sta FE_TESTED+2
    lda #12
    sta G_ROW
    tya
    pha
    sta G_T1
    lda FE_TESTED+2
    sta G_T2
    lda #13
    jsr fe_joy_cell                         ; COIN 1: bit 0
    pla
    lsr
    sta G_T1
    lda FE_TESTED+2
    lsr
    sta G_T2
    lda #20
    jsr fe_joy_cell                         ; COIN 2: bit 1
    jsr fe_joy_count
    lda FE_SYSNEW
    and #SYS_TEST
    bne @exit
    lda ACIA_STATUS
    and #$08
    beq @loop
    lda ACIA_DATA
@exit:
    jmp fe_test_exit

; fe_joy_col: A = pressed, Y = tested, X = column: rows 4-11, bits 0-7
fe_joy_col:
    sta G_T1
    sty G_T2
    lda #4
    sta G_ROW
@l:
    txa
    phx
    jsr fe_joy_cell
    plx
    lsr G_T1
    lsr G_T2
    inc G_ROW
    lda G_ROW
    cmp #12
    bne @l
    rts

; fe_joy_cell: A = column; bit 0 of G_T1 = pressed, of G_T2 = tested: "ON", "OK" or "--"
fe_joy_cell:
    sta G_COL
    jsr g2_pos
    lda G_T1
    lsr
    bcc @not_on
    lda #$80
    sta G_ATTR
    lda #'O'
    jsr g2_putc
    lda #'N'
    jsr g2_putc
    stz G_ATTR
    rts
@not_on:
    lda G_T2
    lsr
    bcc @untested
    lda #'O'
    jsr g2_putc
    lda #'K'
    jmp g2_putc
@untested:
    lda #'-'
    jsr g2_putc
    lda #'-'
    jmp g2_putc

; fe_joy_count: "TESTED n/18" on row 14, or "ALL 18 INPUTS OK"
fe_joy_count:
    ldy #0                                  ; count of the tested bits
    ldx #2
@byte:
    lda FE_TESTED,x
@bit:
    asl
    bcc @no
    iny
@no:
    cmp #0
    bne @bit
    dex
    bpl @byte
    cpy FE_TESTED+3
    bne @changed
    rts                                     ; same count: nothing to redraw
@changed:
    sty FE_TESTED+3
    lda #14
    sta G_ROW
    cpy #18
    bne @some
    lda #$80
    jsr g2_clear_row
    lda #<txt_joy_all
    ldx #>txt_joy_all
    jsr g2_puts_center
    stz G_ATTR
    rts
@some:
    phy
    lda #0
    jsr g2_clear_row
    lda #1
    sta G_COL
    sta G_LEFT
    lda #<txt_joy_tested
    ldx #>txt_joy_tested
    jsr g2_puts
    pla
    jsr g2_put_dec
    lda #<txt_joy_of
    ldx #>txt_joy_of
    jmp g2_puts_here

txt_test_head:  .byte "             P1     P2", 0
txt_test_rows:  .byte "UP", $0A, "DOWN", $0A, "LEFT", $0A, "RIGHT", $0A
                .byte "BUTTON 1", $0A, "BUTTON 2", $0A, "BUTTON 3", $0A, "START", $0A
                .byte "COIN", 0
txt_joytest:    .byte "JOYSTICK TEST", 0
txt_joy_help1:  .byte "PRESS EVERY BUTTON ONCE", 0
txt_joy_help2:  .byte "TEST AGAIN: EXIT", 0
txt_joy_all:    .byte "ALL 18 INPUTS OK", 0
txt_joy_tested: .byte "TESTED ", 0
txt_joy_of:     .byte "/18", 0
txt_systest:    .byte "SYSTEM TEST", 0
txt_sys_rows:   .byte "CPU 65C02", $0A, "ROM CHECKSUM", $0A, "RAM $0200-$7FFF", $0A
                .byte "VRAM 16 KB", $0A, "VDP FRAME", $0A, "SD CARD", $0A, "GAMES ON SD", $0A
                .byte "AUDIO RIGHT", $0A, "AUDIO LEFT", $0A, "SERIAL 6551", 0
txt_sys_help1:  .byte "LISTEN: A TONE RIGHT, THEN LEFT", 0
txt_sys_help2:  .byte "SERVICE AGAIN OR START: EXIT", 0
txt_ok:         .byte "OK", 0
txt_fail:       .byte "FAIL", 0
txt_fail_at:    .byte "FAIL $", 0
txt_testing:    .byte "TESTING", 0
txt_none:       .byte "NONE", 0
txt_sdsc1:      .byte "SDSC V1", 0
txt_sdsc2:      .byte "SDSC V2", 0
txt_sdhc:       .byte "SDHC", 0
txt_catalog:    .byte " CATALOG", 0
txt_directory:  .byte " DIR", 0
txt_tone:       .byte "TONE", 0
txt_sent:       .byte "LINE SENT", 0
txt_ser_test:   .byte "ARCADE6502 SYSTEM TEST: SERIAL OK", $0D, $0A, 0
txt_big1:       .byte "ARCADE", 0
txt_big2:       .byte "6502", 0
txt_developed:  .byte "DEVELOPED BY BOOGS", 0
