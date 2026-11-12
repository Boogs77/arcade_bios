.segment "PROGRAM"
.define BIOS_VER "12.11.26 ARCADE"

; =============================================================================
; ARCADE FRONT-END: the game menu of the cabinet, driven by the joysticks.
;
; RESET (and JT_SHOW_MENU, and the two START buttons held during a game) come here.
; 1. The list: a scrolling list of the games on the SD card (either joystick: UP/DOWN one
;    game, LEFT/RIGHT one page, BUTTON 1 or START opens the game).
; 2. The game page: a preview (title screen of the game, 128x96 pixels), who made the game
;    that inspired it, the players and the description (UP/DOWN scroll it).
;    START or BUTTON 1 load and run the game, BUTTON 2 goes back to the list.
; The TEST switch opens the input test. On the serial port: W WozMon, B BASIC,
; I system information, T input test (help is sent at every start).
;
; The list comes from the ARCADE CATALOG on the SD (written by tools/make_arcade_sd.mjs):
;   sector CAT_LBA (24576, byte $00C00000), after the documents and the stories of the full SD:
;     +0 "ARCD"  +4 version 1  +5 number of entries N (1..255)  +16 cabinet title (31 chars + $00)
;   sectors CAT_LBA+1...: the index, 32 bytes per entry (16 per sector):
;     +0 SD slot of the program   +1 kind (1 game, 2 music: the MiniVIC Jukebox)
;     +2 flags (bit 0: preview, bit 1: text)   +3..+7 reserved   +8 name (23 chars + $00)
;   sectors CAT_LBA + 64 + i*8 ... +6: the page of entry i
;     sector 0: 16 text lines of 32 bytes (31 chars + $00): line 0 inspired by, line 1 players,
;               lines 2-15 description (pre-wrapped at 30 columns, an empty line ends it)
;     sectors 1-3: preview patterns, 192 tiles (16 x 12, by rows) of 8 bytes
;     sectors 4-6: preview colours, 192 x 8 bytes (foreground << 4 | background)
; Without the catalog (an SD made only with make_sd.py) the list is made from the SD directory:
; the GAME programs (not the keyboard versions) and the JUKEBOX, without previews and texts.
;
; Screen: Graphics II. Patterns 0-127 = BIOS font in white on dark blue, 128-255 = the same
; font in black on yellow (selection bar), in all three thirds. The preview uses patterns
; 128-223 of the first two thirds while the game page is shown.
; =============================================================================

; VDP (Graphics II) - VDATA / VREG are defined in crt_text_drv.s
G2_NAMES      = $3800       ; name table (R2 = $0E)
G2_COLORS     = $2000       ; colour table (R3 = $FF)
G2_SAT        = $3B00       ; sprite attributes (R5 = $76)
COL_NORMAL    = $F4         ; white on dark blue
COL_HILITE    = $1B         ; black on light yellow

; zero page of the front-end (used only while it runs)
G_ROW   = $50
G_COL   = $51
G_ATTR  = $52               ; 0 normal font, $80 selection bar font
G_PTR   = $53               ; 2 bytes
G_LEFT  = $55               ; column a $0A in a string goes back to
G_T1    = $56
G_T2    = $57
E_PTR   = $58               ; 2 bytes: current catalog entry
V_SRC   = $5A               ; 2 bytes
V_CNT   = $5C               ; 2 bytes

; RAM of the front-end (free again once a program is loaded)
FE_COUNT   = $1200          ; entries in the list
FE_SEL     = $1201          ; selected entry
FE_TOP     = $1202          ; first entry shown
FE_PREV    = $1203          ; joystick bits of the last frame (1 = pressed)
FE_SYSPREV = $1204          ; system bits of the last frame
FE_REPT    = $1205          ; auto-repeat countdown
FE_HASCAT  = $1206          ; 1 = the catalog is on the SD
FE_LBA     = $1207          ; 2 bytes: sector for fe_read (the high 16 bits are 0)
FE_TXTOFS  = $1209          ; first description line shown
FE_TXTN    = $120A          ; description lines
FE_HOLD    = $120B          ; hold counter of the input test
FE_NEW     = $120C          ; new presses (with auto-repeat) of this frame
FE_SYSNEW  = $120D          ; new system presses of this frame
FE_CUR     = $120E          ; joystick bits now
FE_SCAN    = $120F          ; directory page (list without catalog)
FE_DPAGES  = $1210          ; directory pages
FE_IDX     = $1211          ; entry in the directory page
FE_TITLE   = $1220          ; 32 bytes: cabinet title
FE_TEXT    = $1000          ; text sector of the game page (also the directory buffer)
FE_INDEX   = $2000          ; catalog index: 255 * 32 bytes, up to $3FDF
FE_PREVIEW = $4000          ; 6 sectors: patterns $4000-$45FF, colours $4600-$4BFF

CAT_LBA       = 24576       ; $6000: first sector of the catalog
CAT_PAGE_OFS  = 64          ; pages of the entries from CAT_LBA + 64
LIST_ROW      = 4           ; first row of the list
LIST_ROWS     = 16          ; rows of the list
DESC_ROW      = 18          ; first row of the description window
DESC_ROWS     = 5
HOLD_FRAMES   = 120         ; both START held 2 s: back to the front-end (games: NMI handler)

KIND_GAME     = 1
KIND_MUSIC    = 2
FLAG_PREVIEW  = 1
FLAG_TEXT     = 2

; SD directory (make_sd.py, see sdcard_drv.s)
SD_DIR_BUF    = $1000
SD_DIR_COUNT  = SD_DIR_BUF+5
SD_DIR_TOTAL  = SD_DIR_BUF+15
SD_DIR_PARAMS = SD_DIR_BUF+16
SD_DIR_NAMES  = SD_DIR_BUF+96

.macro PUTS_AT row, col, str
    lda #row
    sta G_ROW
    lda #col
    sta G_COL
    sta G_LEFT
    lda #<str
    ldx #>str
    jsr g2_puts
.endmacro

; =============================================================================
; RESET / JT_SHOW_MENU
; =============================================================================
SHOW_MENU:
    sei
    cld
    ldx #$FF
    txs
    jsr INIT_SERIAL                         ; (CLI: no interrupt source is enabled)
    jsr arc_io_init                         ; VIAs, sound off
    stz sd_type                             ; SD to be initialized again
    stz FE_COUNT
    stz FE_SEL
    stz FE_TOP
    stz FE_SYSPREV                          ; TEST held at power-on opens the input test
    jsr arc_read_joy
    sta FE_PREV
    jsr g2_init
    lda #<ser_help
    ldx #>ser_help
    jsr ser_puts                            ; help for a terminal on the serial port

fe_load:
    jsr g2_cls
    jsr fe_draw_title
    PUTS_AT 11, 7, txt_reading
    jsr fe_load_catalog
    lda FE_COUNT
    bne fe_list
    ; no games: no card, no directory, or nothing to show
    jsr g2_cls
    jsr fe_draw_title
    PUTS_AT 9, 4, txt_nogames
@wait:
    jsr fe_input
    lda FE_NEW
    and #(J_START | J_B1)
    bne fe_load                             ; try again (the card may have been inserted)
    bra @wait

; =============================================================================
; THE LIST
; =============================================================================
fe_list:
    jsr g2_cls
    jsr fe_draw_title
    PUTS_AT 2, 1, txt_select
    PUTS_AT 21, 1, txt_list_help1
    PUTS_AT 22, 1, txt_list_help2
    PUTS_AT 23, 1, txt_version
    jsr fe_draw_rows

fe_list_loop:
    jsr fe_input
    lda FE_NEW
    bit #(J_START | J_B1)
    beq @not_open
    jmp fe_page
@not_open:
    bit #J_UP
    beq @not_up
    lda FE_SEL
    bne @up1
    lda FE_COUNT                            ; from the first to the last
@up1:
    dec
    bra @moved
@not_up:
    bit #J_DOWN
    beq @not_down
    lda FE_SEL
    inc
    cmp FE_COUNT
    bcc @moved
    lda #0                                  ; from the last to the first
    bra @moved
@not_down:
    bit #J_LEFT
    beq @not_left
    lda FE_SEL
    sec
    sbc #LIST_ROWS
    bcs @moved
    lda #0
    bra @moved
@not_left:
    bit #J_RIGHT
    beq fe_list_loop
    lda FE_SEL
    clc
    adc #LIST_ROWS
    bcs @last
    cmp FE_COUNT
    bcc @moved
@last:
    lda FE_COUNT
    dec
@moved:
    sta FE_SEL
    ; keep the selection in the window
    cmp FE_TOP
    bcs @below_top
    sta FE_TOP
    bra @draw
@below_top:
    sec
    sbc FE_TOP
    cmp #LIST_ROWS
    bcc @draw
    lda FE_SEL
    sec
    sbc #LIST_ROWS-1
    sta FE_TOP
@draw:
    jsr fe_draw_rows
    jmp fe_list_loop

; title bar (row 0, selection colours) with the cabinet title in the middle
fe_draw_title:
    lda #0
    sta G_ROW
    lda #$80
    jsr g2_clear_row
    lda #<FE_TITLE
    ldx #>FE_TITLE
    jsr g2_puts_center
    stz G_ATTR
    rts

; the rows of the list and the "n/N" counter
fe_draw_rows:
    lda #LIST_ROW
    sta G_ROW
    lda FE_TOP
    sta G_T2                                ; G_T2 = entry of the row
@row:
    lda G_T2
    cmp FE_COUNT
    bcs @empty
    ldx #0
    cmp FE_SEL
    bne @attr
    ldx #$80
@attr:
    txa
    jsr g2_clear_row
    lda #2
    sta G_COL
    lda G_T2
    jsr fe_entry_ptr
    jsr fe_puts_name
    bra @next
@empty:
    lda #0
    jsr g2_clear_row
@next:
    stz G_ATTR
    inc G_T2
    inc G_ROW
    lda G_ROW
    cmp #LIST_ROW+LIST_ROWS
    bne @row
    ; counter at the right of row 2: "  n/N" (right-aligned in 8 columns)
    lda #2
    sta G_ROW
    lda #24
    sta G_COL
    jsr g2_pos
    ldx #8
    lda #' '
@sp:
    sta VDATA
    dex
    bne @sp
    lda #24
    sta G_COL
    jsr g2_pos
    lda FE_SEL
    inc
    jsr g2_put_dec
    lda #'/'
    jsr g2_putc
    lda FE_COUNT
    jmp g2_put_dec

; fe_puts_name: prints the name of entry E_PTR at G_ROW/G_COL (address set by g2_pos)
fe_puts_name:
    jsr g2_pos
    ldy #8
@l:
    lda (E_PTR),y
    beq @e
    jsr g2_putc
    iny
    cpy #31
    bne @l
@e:
    rts

; fe_entry_ptr: A = entry -> E_PTR = FE_INDEX + A * 32
fe_entry_ptr:
    pha
    lsr
    lsr
    lsr
    clc
    adc #>FE_INDEX
    sta E_PTR+1
    pla
    asl
    asl
    asl
    asl
    asl
    sta E_PTR
    rts

; =============================================================================
; THE GAME PAGE
; =============================================================================
fe_page:
    lda FE_SEL
    jsr fe_entry_ptr
    jsr g2_cls
    lda #0
    sta G_ROW
    lda E_PTR
    clc
    adc #8
    pha
    lda E_PTR+1
    adc #0
    tax
    pla
    jsr g2_puts_center                      ; name on row 0, normal font: the patterns of the
                                            ; selection bar in this third are taken by the preview
    lda #1
    sta G_ROW
    stz G_COL
    jsr g2_pos
    ldx #32
@line:
    stz VDATA                               ; pattern 0 of the BIOS font: horizontal line
    nop
    dex
    bne @line
    PUTS_AT 23, 1, txt_page_help
    stz FE_TXTOFS
    stz FE_TXTN

    lda FE_HASCAT
    beq @no_text
    ldy #2
    lda (E_PTR),y
    sta G_T2                                ; flags
    and #FLAG_TEXT
    beq @no_text
    jsr fe_page_lba                         ; FE_LBA = sector 0 of the page
    ldx #<FE_TEXT
    ldy #>FE_TEXT
    jsr fe_read
    bcs @no_text
    jsr fe_count_lines
    lda #15
    ldx #0
    jsr fe_text_line                        ; inspired by
    lda #16
    ldx #1
    jsr fe_text_line                        ; players
    jsr fe_draw_desc
    bra @preview
@no_text:
    PUTS_AT 15, 1, txt_no_text
@preview:
    lda FE_HASCAT
    beq @no_preview
    lda G_T2
    and #FLAG_PREVIEW
    beq @no_preview
    jsr fe_load_preview
    bcc fe_page_loop
@no_preview:
    PUTS_AT 7, 11, txt_no_preview

fe_page_loop:
    jsr fe_input
    lda FE_NEW
    bit #(J_START | J_B1)
    beq @not_play
    jmp fe_launch
@not_play:
    bit #J_B2
    beq @not_back
    ldx #0
    jsr g2_font_hilite                      ; patterns 128-255 of thirds 0 and 1: the font again
    ldx #1
    jsr g2_font_hilite
    jmp fe_list
@not_back:
    bit #J_UP
    beq @not_up
    lda FE_TXTOFS
    beq fe_page_loop
    dec FE_TXTOFS
    jsr fe_draw_desc
    bra fe_page_loop
@not_up:
    bit #J_DOWN
    beq fe_page_loop
    lda FE_TXTOFS
    clc
    adc #DESC_ROWS
    cmp FE_TXTN
    bcs fe_page_loop                        ; the last line is already shown
    inc FE_TXTOFS
    jsr fe_draw_desc
    bra fe_page_loop

; fe_page_lba: FE_LBA = CAT_LBA + CAT_PAGE_OFS + FE_SEL * 8
fe_page_lba:
    stz FE_LBA+1
    lda FE_SEL
    asl
    rol FE_LBA+1
    asl
    rol FE_LBA+1
    asl
    rol FE_LBA+1
    clc
    adc #<(CAT_LBA + CAT_PAGE_OFS)
    sta FE_LBA
    lda FE_LBA+1
    adc #>(CAT_LBA + CAT_PAGE_OFS)
    sta FE_LBA+1
    rts

; fe_count_lines: FE_TXTN = description lines (lines 2-15 up to the first empty one)
fe_count_lines:
    ldx #2
@l:
    txa
    jsr fe_line_ptr
    lda (ZP_PTR)
    beq @e
    inx
    cpx #16
    bne @l
@e:
    dex
    dex
    stx FE_TXTN
    rts

; fe_line_ptr: A = text line (0..15) -> ZP_PTR = FE_TEXT + A * 32. Preserves X.
fe_line_ptr:
    pha
    lsr
    lsr
    lsr
    clc
    adc #>FE_TEXT
    sta ZP_PTR+1
    pla
    asl
    asl
    asl
    asl
    asl
    sta ZP_PTR
    rts

; fe_text_line: A = screen row, X = text line: clears the row and prints the line from column 1
fe_text_line:
    sta G_ROW
    phx
    lda #0
    jsr g2_clear_row
    pla
    jsr fe_line_ptr
    lda #1
    sta G_COL
    sta G_LEFT
    lda ZP_PTR
    ldx ZP_PTR+1
    jmp g2_puts

; fe_draw_desc: description lines FE_TXTOFS... in rows DESC_ROW..., with ^ v when there is more
fe_draw_desc:
    stz G_T1
@row:
    lda G_T1
    clc
    adc FE_TXTOFS
    cmp FE_TXTN
    bcs @blank
    adc #2                                  ; (C = 0) text line
    tax
    lda G_T1
    adc #DESC_ROW
    jsr fe_text_line
    bra @next
@blank:
    lda G_T1
    clc
    adc #DESC_ROW
    sta G_ROW
    lda #0
    jsr g2_clear_row
@next:
    inc G_T1
    lda G_T1
    cmp #DESC_ROWS
    bne @row
    ; markers in column 31
    lda #DESC_ROW
    sta G_ROW
    lda #31
    sta G_COL
    jsr g2_pos
    lda FE_TXTOFS
    beq @no_up
    lda #'^'
    jsr g2_putc
@no_up:
    lda #DESC_ROW+DESC_ROWS-1
    sta G_ROW
    lda #31
    sta G_COL
    jsr g2_pos
    lda FE_TXTOFS
    clc
    adc #DESC_ROWS
    cmp FE_TXTN
    bcs @no_down
    lda #'v'
    jsr g2_putc
@no_down:
    rts

; fe_load_preview: reads sectors 1-6 of the page and shows the 16x12 preview in rows 2-13,
; columns 8-23. C=1 if the read failed.
fe_load_preview:
    jsr fe_page_lba
    lda #<FE_PREVIEW
    sta V_SRC
    lda #>FE_PREVIEW
    sta V_SRC+1
    ldx #6
@sec:
    phx
    inc FE_LBA
    bne @nc
    inc FE_LBA+1
@nc:
    ldx V_SRC
    ldy V_SRC+1
    jsr fe_read
    plx
    bcs @err
    inc V_SRC+1
    inc V_SRC+1                             ; +512
    dex
    bne @sec
    ; patterns: tiles 0-95 -> third 0, patterns 128-223 ($0400); 96-191 -> third 1 ($0C00)
    lda #<$0400
    ldx #>$0400
    jsr vdp_wr_addr
    lda #<FE_PREVIEW
    ldx #>FE_PREVIEW
    jsr vdp_copy768
    lda #<$0C00
    ldx #>$0C00
    jsr vdp_wr_addr
    lda #<(FE_PREVIEW+768)
    ldx #>(FE_PREVIEW+768)
    jsr vdp_copy768
    lda #<(G2_COLORS+$0400)
    ldx #>(G2_COLORS+$0400)
    jsr vdp_wr_addr
    lda #<(FE_PREVIEW+1536)
    ldx #>(FE_PREVIEW+1536)
    jsr vdp_copy768
    lda #<(G2_COLORS+$0C00)
    ldx #>(G2_COLORS+$0C00)
    jsr vdp_wr_addr
    lda #<(FE_PREVIEW+2304)
    ldx #>(FE_PREVIEW+2304)
    jsr vdp_copy768
    ; names: rows 2-13, columns 8-23; tile k -> 128 + (k mod 96)
    lda #2
    sta G_ROW
    lda #128
    sta G_T1                                ; next pattern
@nrow:
    lda #8
    sta G_COL
    jsr g2_pos
    ldx #16
@ncol:
    lda G_T1
    sta VDATA
    inc G_T1
    dex
    bne @ncol
    lda G_T1
    cmp #128+96
    bne @same_third
    lda #128                                ; row 8: second third, patterns from 128 again
    sta G_T1
@same_third:
    inc G_ROW
    lda G_ROW
    cmp #14
    bne @nrow
    clc
    rts
@err:
    sec
    rts

; =============================================================================
; LAUNCH: the program starts like from the SD menu of the miniVIC BIOS:
; text mode with the BIOS font, "[TYPE] Name" on the serial port, JMP to its entry point
; =============================================================================
fe_launch:
    lda FE_SEL
    jsr fe_entry_ptr
    lda (E_PTR)                             ; SD slot
    pha
    jsr INIT_CRT
    lda #<txt_loading
    ldx #>txt_loading
    jsr crt_puts
    lda E_PTR
    clc
    adc #8
    pha
    lda E_PTR+1
    adc #0
    tax
    pla
    jsr crt_puts
    pla
    jsr INIT_SDCARD                         ; load (the directory gives load, length, entry)
    bcs @err
    jsr SD_ANNOUNCE
    ldx #$FF
    txs
    jmp (sd_entry)
@err:
    jsr INIT_CRT
    lda #<txt_load_err
    ldx #>txt_load_err
    jsr crt_puts
    jsr FLUSH_KEYBOARD_HARD
@wait:
    jsr CHRIN_NO_ECHO
    bcc @wait
    jmp SHOW_MENU

; crt_puts: string (A lo, X hi) on the CRT only (text mode, not on the serial port)
crt_puts:
    sta ZP_PTR
    stx ZP_PTR+1
    ldy #0
@l:
    lda (ZP_PTR),y
    beq @e
    jsr print_crt_ch
    iny
    bne @l
@e:
    rts

; =============================================================================
; INPUT TEST (TEST switch, or T on the serial port)
; =============================================================================
fe_test:
    jsr g2_cls
    lda #0
    sta G_ROW
    lda #$80
    jsr g2_clear_row
    lda #<txt_test_title
    ldx #>txt_test_title
    jsr g2_puts_center
    stz G_ATTR
    PUTS_AT 2, 1, txt_test_head
    PUTS_AT 4, 1, txt_test_rows
    PUTS_AT 21, 1, txt_test_help1
    PUTS_AT 22, 1, txt_test_help2
    stz FE_HOLD
@loop:
    jsr fe_input_nocmd
    ; player columns: P1 at 13, P2 at 20; rows 4-11 = bits 0-7
    lda JOY_P1
    eor #$FF
    ldx #13
    jsr fe_test_col
    lda JOY_P2
    eor #$FF
    ldx #20
    jsr fe_test_col
    jsr arc_read_sys
    sta G_T2
    lda #12
    sta G_ROW                               ; COIN
    lda #13
    ldx #SYS_COIN1
    jsr fe_test_mark
    lda #20
    ldx #SYS_COIN2
    jsr fe_test_mark
    lda #14
    sta G_ROW
    lda #13
    ldx #SYS_TEST
    jsr fe_test_mark
    lda #15
    sta G_ROW
    lda #13
    ldx #SYS_SERVICE
    jsr fe_test_mark
    ; exits: TEST again, a byte on the serial port, both START held 2 s
    lda FE_SYSNEW
    and #SYS_TEST
    bne @exit
    lda ACIA_STATUS
    and #$08
    beq @no_ser
    lda ACIA_DATA
    bra @exit
@no_ser:
    lda JOY_P1
    ora JOY_P2
    bmi @release                            ; bit 7 = 1: a START is not pressed
    inc FE_HOLD
    lda FE_HOLD
    cmp #HOLD_FRAMES
    bcc @loop
    bra @exit
@release:
    stz FE_HOLD
    bra @loop
@exit:
    lda FE_COUNT
    bne @to_list
    jmp fe_load
@to_list:
    jmp fe_list

; fe_test_col: A = bits (1 = pressed), X = column: rows 4-11 "ON" / "--"
fe_test_col:
    sta G_T2
    lda #4
    sta G_ROW
@l:
    txa
    phx
    ldx #1
    jsr fe_test_mark
    plx
    lsr G_T2
    inc G_ROW
    lda G_ROW
    cmp #12
    bne @l
    rts

; fe_test_mark: A = column, X = mask in G_T2: "ON" (selection colours) or "--" at G_ROW
fe_test_mark:
    sta G_COL
    txa
    and G_T2
    php
    jsr g2_pos
    plp
    beq @off
    lda #$80
    sta G_ATTR
    lda #'O'
    jsr g2_putc
    lda #'N'
    jsr g2_putc
    stz G_ATTR
    rts
@off:
    lda #'-'
    jsr g2_putc
    lda #'-'
    jmp g2_putc

; =============================================================================
; INPUT: one frame
; =============================================================================
; fe_input: waits for the next frame, reads the joysticks (FE_NEW: new presses, with
; auto-repeat of the directions) and the system inputs (FE_SYSNEW), and answers the serial
; port (W B I T) and the TEST switch: those never come back here.
fe_input:
    jsr fe_input_nocmd
    lda FE_SYSNEW
    and #SYS_TEST
    beq @no_test
    jmp fe_test
@no_test:
    lda ACIA_STATUS
    and #$08
    beq @rts
    lda ACIA_DATA
    and #$DF                                ; lower case -> upper case
    cmp #'W'
    beq fe_go_woz
    cmp #'B'
    beq fe_go_basic
    cmp #'I'
    beq fe_go_info
    cmp #'T'
    bne @help
    jmp fe_test
@help:
    lda #<ser_help
    ldx #>ser_help
    jsr ser_puts
@rts:
    rts

fe_input_nocmd:
    jsr fe_wait_frame
    jsr arc_read_joy
    sta FE_CUR
    lda FE_PREV
    eor #$FF
    and FE_CUR
    sta FE_NEW
    lda FE_CUR
    sta FE_PREV
    and #J_DIRS
    beq @sys                                ; no direction held
    lda FE_NEW
    and #J_DIRS
    beq @held
    lda #20                                 ; first repeat after 1/3 s...
    sta FE_REPT
    bra @sys
@held:
    dec FE_REPT
    bne @sys
    lda #5                                  ; ...then 12 per second
    sta FE_REPT
    lda FE_CUR
    and #J_DIRS
    ora FE_NEW
    sta FE_NEW
@sys:
    jsr arc_read_sys
    tax
    lda FE_SYSPREV
    eor #$FF
    stx FE_SYSPREV
    and FE_SYSPREV
    sta FE_SYSNEW
    rts

; fe_wait_frame: waits for the end of the active area (F flag of the VDP status, the VDP
; interrupt is off in the front-end)
fe_wait_frame:
    lda VREG
    bpl fe_wait_frame
    rts

fe_go_woz:
    jsr fe_text_mode
    jmp RESET

fe_go_basic:
    jsr fe_text_mode
    jmp $8000

fe_text_mode:
    jsr RESET_SERIAL_TERM                   ; also clears the CRT (ESC)
    jmp INIT_CRT

; --- System Information Page (serial port I) ---
fe_go_info:
    jsr fe_text_mode
    lda #<sys_info_text
    sta ZP_PTR
    lda #>sys_info_text
    sta ZP_PTR+1
    jsr print_debug_string
    jsr FLUSH_KEYBOARD_HARD
@wait:
    jsr CHRIN_NO_ECHO
    bcc @wait
    jmp SHOW_MENU

; =============================================================================
; THE LIST FROM THE SD
; =============================================================================
; fe_load_catalog: FE_COUNT, FE_TITLE and the index at FE_INDEX, from the arcade catalog
; or, without it, from the SD directory. FE_COUNT = 0 if there is nothing.
fe_load_catalog:
    stz FE_COUNT
    stz FE_HASCAT
    stz FE_SEL
    stz FE_TOP
    ldx #31
@deft:
    lda txt_def_title,x
    sta FE_TITLE,x
    dex
    bpl @deft
    jsr SD_INIT
    bcc @card
    rts                                     ; no card
@card:
    lda #<CAT_LBA
    sta FE_LBA
    lda #>CAT_LBA
    sta FE_LBA+1
    ldx #<FE_TEXT
    ldy #>FE_TEXT
    jsr fe_read
    bcs @from_dir
    ldx #3
@magic:
    lda FE_TEXT,x
    cmp cat_magic,x
    bne @from_dir
    dex
    bpl @magic
    lda FE_TEXT+4
    cmp #1
    bne @from_dir                           ; unknown version
    lda FE_TEXT+5
    beq @from_dir
    sta FE_COUNT
    lda FE_TEXT+16
    beq @no_title
    ldx #30
@title:
    lda FE_TEXT+16,x
    sta FE_TITLE,x
    dex
    bpl @title
    stz FE_TITLE+31
@no_title:
    ; index: (N + 15) / 16 sectors from CAT_LBA + 1 to FE_INDEX
    lda FE_COUNT
    clc
    adc #15
    ror                                     ; (9 bits: N + 15 can be 270)
    lsr
    lsr
    lsr
    sta G_T1                                ; sectors
    lda #>FE_INDEX
    sta G_T2
@idx:
    inc FE_LBA
    ldx #0
    ldy G_T2
    jsr fe_read
    bcs @fail
    inc G_T2
    inc G_T2
    dec G_T1
    bne @idx
    lda #1
    sta FE_HASCAT
    rts
@fail:
    stz FE_COUNT
@from_dir:
    jmp fe_list_from_dir

; fe_list_from_dir: the GAME programs (not "... KEYBOARD") and the JUKEBOX of the directory
fe_list_from_dir:
    stz FE_COUNT
    stz FE_SCAN
    lda #1
    sta FE_DPAGES                           ; set from page 0
@page:
    lda FE_SCAN
    jsr SD_READ_DIR
    jsr fe_dir_valid
    jcs @done
    lda FE_SCAN
    bne @not0
    lda SD_DIR_TOTAL                        ; page 0: number of pages
    bne @tot
    lda SD_DIR_COUNT
@tot:
    jsr fe_div9_up
    stx FE_DPAGES
@not0:
    stz FE_IDX
@entry:
    lda FE_IDX
    asl
    asl
    asl
    tay                                     ; parameters of the entry
    lda SD_DIR_PARAMS+6,y                   ; type
    ldx #KIND_GAME
    cmp #1
    beq @game
    jsr fe_is_jukebox
    bcc @next
    ldx #KIND_MUSIC
    bra @add
@game:
    jsr fe_is_keyboard
    bcs @next                               ; keyboard version: no keyboard here
@add:
    lda FE_COUNT
    cmp #255
    beq @done
    jsr fe_entry_ptr
    txa
    ldy #1
    sta (E_PTR),y                           ; kind
    lda #0
    iny
    sta (E_PTR),y                           ; flags: no preview, no text
    lda FE_SCAN
    asl
    asl
    asl
    adc FE_SCAN                             ; (C = 0) page * 9
    adc FE_IDX
    sta (E_PTR)                             ; slot
    ; name: up to the length of byte +7 (0 = all), max 23 characters
    lda FE_IDX
    asl
    asl
    asl
    tay
    lda SD_DIR_PARAMS+7,y
    beq @all
    cmp #24
    bcc @len
@all:
    lda #23
@len:
    sta G_T1
    jsr fe_dir_name_ptr                     ; ZP_PTR = name in the directory
    ldy #0
@copy:
    lda (ZP_PTR),y
    beq @end_name
    cpy G_T1
    beq @end_name
    phy
    pha
    tya
    clc
    adc #8
    tay
    pla
    sta (E_PTR),y
    ply
    iny
    bra @copy
@end_name:
    tya
    clc
    adc #8
    tay
    lda #0
    sta (E_PTR),y
    inc FE_COUNT
@next:
    inc FE_IDX
    lda FE_IDX
    cmp SD_DIR_COUNT
    jne @entry
    inc FE_SCAN
    lda FE_SCAN
    cmp FE_DPAGES
    jne @page
@done:
    rts

; fe_dir_name_ptr: ZP_PTR = name of directory entry FE_IDX (SD_DIR_NAMES + FE_IDX * 32)
fe_dir_name_ptr:
    lda FE_IDX
    lsr
    lsr
    lsr
    clc
    adc #>SD_DIR_NAMES
    sta ZP_PTR+1
    lda FE_IDX
    asl
    asl
    asl
    asl
    asl
    clc
    adc #<SD_DIR_NAMES
    sta ZP_PTR
    bcc @r
    inc ZP_PTR+1
@r:
    rts

; fe_is_jukebox: C=1 if the name of entry FE_IDX starts with "JUKEBOX". Preserves X.
fe_is_jukebox:
    phx
    jsr fe_dir_name_ptr
    ldy #0
@l:
    lda (ZP_PTR),y
    cmp str_jukebox,y
    bne @no
    iny
    cpy #7
    bne @l
    plx
    sec
    rts
@no:
    plx
    clc
    rts

; fe_is_keyboard: C=1 if the name of entry FE_IDX contains "KEYBOARD". Preserves X.
fe_is_keyboard:
    phx
    jsr fe_dir_name_ptr
    ldy #0
@start:
    ldx #0
    phy
@cmp:
    lda (ZP_PTR),y
    beq @no_pull
    cmp str_keyboard,x
    bne @next
    iny
    inx
    cpx #8
    bne @cmp
    ply
    plx
    sec
    rts
@next:
    ply
    iny
    cpy #31
    bne @start
    plx
    clc
    rts
@no_pull:
    ply
    plx
    clc
    rts

; fe_dir_valid: C=0 if $1000 holds a valid directory page
fe_dir_valid:
    ldx #3
@m:
    lda SD_DIR_BUF,x
    cmp sd_magic,x
    bne @bad
    dex
    bpl @m
    lda SD_DIR_BUF+4
    cmp #2
    bcc @bad
    cmp #4
    bcs @bad
    lda SD_DIR_COUNT
    beq @bad
    cmp #10
    bcs @bad
    clc
    rts
@bad:
    sec
    rts

; fe_div9_up: A = programs (1..255) -> X = pages of 9, rounded up
fe_div9_up:
    ldx #0
@pg:
    inx
    sec
    sbc #9
    beq @e
    bcs @pg
@e:
    rts

; fe_read: sector FE_LBA (16 bits) -> buffer X/Y. C=1 error
fe_read:
    lda FE_LBA
    sta SD_LBA
    lda FE_LBA+1
    sta SD_LBA+1
    stz SD_LBA+2
    stz SD_LBA+3
    jmp SD_READ_SECTOR

; =============================================================================
; GRAPHICS II SCREEN
; =============================================================================
g2_init:
    ldx #0
@reg:
    lda g2_regs,x
    jsr vdp_set_reg
    inx
    cpx #8
    bne @reg
    ldx #0
@third:
    phx
    jsr g2_font_normal
    plx
    phx
    jsr g2_font_hilite
    plx
    inx
    cpx #3
    bne @third
    lda #<G2_SAT
    ldx #>G2_SAT
    jsr vdp_wr_addr
    lda #$D0                                ; no sprites
    sta VDATA
    jsr g2_cls
    ldx #1
    lda #$C0                                ; display on, VDP interrupt off
    jmp vdp_set_reg

g2_regs:
    .byte $02                               ; R0: Graphics II
    .byte $80                               ; R1: 16K, display off while loading
    .byte $0E                               ; R2: names at $3800
    .byte $FF                               ; R3: colours at $2000
    .byte $03                               ; R4: patterns at $0000
    .byte $76                               ; R5: sprite attributes at $3B00
    .byte $03                               ; R6: sprite patterns at $1800
    .byte $04                               ; R7: dark blue border

; g2_font_normal / g2_font_hilite: X = third (0..2): font in patterns 0-127 / 128-255
g2_font_normal:
    lda #COL_NORMAL
    ldy #0
    bra g2_font
g2_font_hilite:
    lda #COL_HILITE
    ldy #4
g2_font:
    sta G_T1                                ; colour
    sty G_T2
    txa
    asl
    asl
    asl                                     ; third * 8
    ora G_T2                                ; + half * 4
    sta G_T2                                ; high byte of the pattern address
    tax
    lda #0
    jsr vdp_wr_addr
    lda #<VDP_PATTERNS
    sta V_SRC
    lda #>VDP_PATTERNS
    sta V_SRC+1
    stz V_CNT
    lda #4
    sta V_CNT+1
    jsr vdp_copy
    lda G_T2
    ora #>G2_COLORS
    tax
    lda #0
    jsr vdp_wr_addr
    ldy #4
    ldx #0
    lda G_T1
@c:
    sta VDATA
    nop
    inx
    bne @c
    dey
    bne @c
    rts

; g2_cls: all names = space (normal font)
g2_cls:
    lda #<G2_NAMES
    ldx #>G2_NAMES
    jsr vdp_wr_addr
    ldy #3
    ldx #0
    lda #' '
@l:
    sta VDATA
    nop
    inx
    bne @l
    dey
    bne @l
    stz G_ATTR
    rts

; g2_clear_row: A = attribute (0 / $80): row G_ROW = 32 spaces; G_ATTR = A, G_COL = 0
g2_clear_row:
    sta G_ATTR
    stz G_COL
    jsr g2_pos
    ldx #32
    lda #' '
    ora G_ATTR
@l:
    sta VDATA
    nop
    dex
    bne @l
    rts

; g2_pos: VRAM write address = name of G_ROW, G_COL. Changes A and X.
g2_pos:
    lda G_ROW
    lsr
    lsr
    lsr
    clc
    adc #>G2_NAMES
    tax
    lda G_ROW
    asl
    asl
    asl
    asl
    asl
    ora G_COL
    ; falls through

; vdp_wr_addr: VRAM write address = X (hi) / A (lo)
vdp_wr_addr:
    sta VREG
    txa
    ora #$40
    sta VREG
    rts

; vdp_set_reg: register X = A
vdp_set_reg:
    sta VREG
    txa
    ora #$80
    sta VREG
    rts

; g2_putc: A -> screen (font of G_ATTR), next column. Preserves X and Y.
g2_putc:
    ora G_ATTR
    sta VDATA
    inc G_COL
    rts

; g2_puts: string (A lo, X hi) at G_ROW/G_COL; $0A = next row, from column G_LEFT
g2_puts:
    sta G_PTR
    stx G_PTR+1
    jsr g2_pos
    ldy #0
@l:
    lda (G_PTR),y
    beq @e
    cmp #$0A
    bne @c
    inc G_ROW
    lda G_LEFT
    sta G_COL
    jsr g2_pos
    bra @n
@c:
    jsr g2_putc
@n:
    iny
    bne @l
@e:
    rts

; g2_puts_center: string (A lo, X hi, one line, max 32 characters) in the middle of row G_ROW
g2_puts_center:
    sta G_PTR
    stx G_PTR+1
    ldy #0
@len:
    lda (G_PTR),y
    beq @got
    iny
    cpy #32
    bne @len
@got:
    tya
    eor #$FF
    sec
    adc #32                                 ; 32 - length
    lsr
    sta G_COL
    sta G_LEFT
    lda G_PTR
    ldx G_PTR+1
    jmp g2_puts

; g2_put_dec: A (0..255) in decimal at the current position, no leading zeros
g2_put_dec:
    ldx #0
@h:
    cmp #100
    bcc @h_done
    sbc #100
    inx
    bra @h
@h_done:
    pha
    txa
    beq @no_h
    ora #'0'
    jsr g2_putc
@no_h:
    pla
    ldy #0
@t:
    cmp #10
    bcc @t_done
    sbc #10
    iny
    bra @t
@t_done:
    pha
    tya
    bne @put_t
    cpx #0
    beq @no_t                               ; no hundreds and no tens
@put_t:
    ora #'0'
    jsr g2_putc
@no_t:
    pla
    ora #'0'
    jmp g2_putc

; vdp_copy: V_CNT bytes from (V_SRC) to VRAM (address already set). V_CNT > 0
vdp_copy:
    ldy #0
@l:
    lda (V_SRC),y
    sta VDATA
    iny
    bne @n
    inc V_SRC+1
@n:
    lda V_CNT
    bne @d
    dec V_CNT+1
@d:
    dec V_CNT
    lda V_CNT
    ora V_CNT+1
    bne @l
    rts

; vdp_copy768: 768 bytes from A (lo) / X (hi) to VRAM (address already set)
vdp_copy768:
    sta V_SRC
    stx V_SRC+1
    stz V_CNT
    lda #3
    sta V_CNT+1
    jmp vdp_copy

; =============================================================================
; SERIAL TERMINAL (kept from the miniVIC BIOS: jump table $FD06)
; =============================================================================
RESET_SERIAL_TERM:
    pha
    lda #$1B        ; ESC character
    jsr CHROUT
    lda #'['
    jsr CHROUT
    lda #'2'
    jsr CHROUT
    lda #'J'        ; Clear Screen command
    jsr CHROUT
    lda #$1B
    jsr CHROUT
    lda #'['
    jsr CHROUT
    lda #'H'        ; Move Cursor to Home (1,1)
    jsr CHROUT
    pla
    rts

; Quick helper routine to print strings (ZP_PTR) with CHROUT
print_debug_string:
    ldy #0
@db_loop:
    lda (ZP_PTR), y
    beq @db_exit
    jsr CHROUT
    iny
    bne @db_loop
    inc ZP_PTR+1
    jmp @db_loop
@db_exit:
    rts

; =============================================================================
; DATA
; =============================================================================
cat_magic:      .byte "ARCD"
str_jukebox:    .byte "JUKEBOX"
str_keyboard:   .byte "KEYBOARD"

txt_def_title:  .byte "MINIVIC ARCADE", 0
                .res 17, 0
txt_reading:    .byte "READING THE SD CARD...", 0
txt_nogames:    .byte "NO GAMES FOUND ON THE SD", $0A, $0A
                .byte "INSERT THE SD CARD AND", $0A
                .byte "PRESS START TO TRY AGAIN", 0
txt_select:     .byte "SELECT A GAME", 0
txt_list_help1: .byte "STICK: CHOOSE, LEFT/RIGHT: PAGE", 0
txt_list_help2: .byte "START OR BUTTON 1: GAME PAGE", 0
txt_version:    .byte "ARCADE BIOS ", BIOS_VER, 0
txt_page_help:  .byte "START: PLAY    BUTTON 2: BACK", 0
txt_no_text:    .byte "NO DESCRIPTION ON THIS SD CARD", 0
txt_no_preview: .byte "NO PREVIEW", 0
txt_loading:    .byte "LOADING FROM SD, PLEASE WAIT...", $0A, $0A, 0
txt_load_err:   .byte "SD LOAD ERROR", $0A
                .byte "(CARD, DIRECTORY OR PROGRAM PARAMS)", $0A, $0A
                .byte "PRESS A BUTTON...", 0
txt_test_title: .byte "INPUT TEST", 0
txt_test_head:  .byte "             P1     P2", 0
txt_test_rows:  .byte "UP", $0A, "DOWN", $0A, "LEFT", $0A, "RIGHT", $0A
                .byte "BUTTON 1", $0A, "BUTTON 2", $0A, "BUTTON 3", $0A, "START", $0A
                .byte "COIN", $0A, $0A, "TEST", $0A, "SERVICE", 0
txt_test_help1: .byte "EXIT: TEST AGAIN, OR HOLD", 0
txt_test_help2: .byte "BOTH START FOR 2 SECONDS", 0

ser_help:
    .byte $0D, $0A, "MINIVIC ARCADE BIOS ", BIOS_VER, $0D, $0A
    .byte "W = WOZMON  B = BASIC  I = INFO  T = INPUT TEST", $0D, $0A, 0

sys_info_text:
    .byte " ",$0D, $0A
    .byte "  --- MINIVIC ARCADE INFORMATION ---", $0D, $0A
    .byte " ",$0D, $0A
    .byte "CPU : W65C02S 8 bit Microprocessor", $0D, $0A
    .byte "CLOCK Frequency:    1MHz", $0D, $0A
    .byte "RAM:                32KB $0000-7FFF", $0D, $0A
    .byte "ROM:                32KB $8000-FFFF", $0D, $0A
    .byte "VIDEO TMS9918A:     $B000 (NMI)", $0D, $0A
    .byte "SERIAL 6551:        $C000 DB9", $0D, $0A
    .byte "AUDIO 2x AY-3-8910: $D380", $0D, $0A
    .byte "JOYSTICKS 6522:     $D580 JAMMA", $0D, $0A
    .byte "SD CARD 6522:       $DD80", $0D, $0A
    .byte "COIN/TEST/SERVICE:  $DD81", $0D, $0A
    .byte "VERSION:            ", BIOS_VER, $0D, $0A
    .byte " ",$0D, $0A
    .byte "       --------------------------", $0D, $0A
    .byte "        Press a key or button...", 0
