.segment "BIOS"

; =============================================================================
; CREDITS (coins) of the cabinet
;
; The credits are counted by the BIOS, not by the games: a coin inserted in the front-end or
; during a game is never lost, and the credits stay when a game is left. They are lost at
; power-on / RESET, as on the arcade cabinets. 1 coin = 1 credit, at most 9 (a coin beyond 9
; is lost). Every COIN input counts once per pulse (the coin mechanism gives one pulse).
;
; CRED ($D587) is the T1 latch high of the joystick VIA, used as a byte of storage (like
; JOY_HOLD): writing it does not start the timer (only T1C-H does), reading it gives the latch
; back, and no game uses the timers of this VIA.
;   bits 0-3  credits (0-9)
;   bit 4     the program running now is in FREE PLAY (written by the front-end at the launch)
;   bit 5     COIN 1 was pressed at the last sample (edge detection)
;   bit 6     COIN 2 was pressed at the last sample
;
; Who counts:
;   - the NMI handler (every frame of a game) and the front-end (every frame): arc_coin_poll,
;     press and release of both coins;
;   - JT_ARC_CREDITS and the SD sector reads (a picture or a game takes ~1 s to read): cred_tap,
;     only the press (TSB on the edge bit), so that they never count a coin the NMI counted too.
; The game takes the credits with JT_ARC_USE_CREDIT (one DEC per credit: a single
; read-modify-write instruction, an NMI never falls in the middle of it).
; =============================================================================

CRED        = $D587
CR_COUNT    = %00001111
CR_FREE     = %00010000
CR_C1PREV   = %00100000
CR_C2PREV   = %01000000
CR_MAX      = 9

; arc_coin_poll: one sample of both coins (press and release). Changes A only.
arc_coin_poll:
    lda SYS_PORT
    bit #$40                    ; COIN 1 (active low)
    bne @c1_up
    lda #CR_C1PREV
    tsb CRED                    ; Z = 1: it was not pressed before -> a new coin
    bne @c2
    jsr cred_add
    bra @c2
@c1_up:
    lda #CR_C1PREV
    trb CRED
@c2:
    lda SYS_PORT
    bmi @c2_up                  ; COIN 2 (bit 7, active low)
    lda #CR_C2PREV
    tsb CRED
    bne @end
    jmp cred_add
@c2_up:
    lda #CR_C2PREV
    trb CRED
@end:
    rts

; cred_tap: the press of the coins only (see above). Changes A only.
cred_tap:
    lda SYS_PORT
    bit #$40
    bne @c2
    lda #CR_C1PREV
    tsb CRED
    bne @c2
    jsr cred_add
@c2:
    lda SYS_PORT
    bmi @end
    lda #CR_C2PREV
    tsb CRED
    beq cred_add
@end:
    rts

; cred_add: one credit more, if there are less than 9. Changes A only.
cred_add:
    lda CRED
    and #CR_COUNT
    cmp #CR_MAX
    bcs @full
    inc CRED
@full:
    rts

; ---------------------------------------------------------------
; ARC_CREDITS (jump table $FD86, JT_ARC_CREDITS): A = credits (0-9), C = 1 if the program
; running now is in FREE PLAY. Preserves X and Y.
; ---------------------------------------------------------------
ARC_CREDITS:
    jsr cred_tap                ; a coin while the VDP interrupt is off is not lost
    lda CRED
    and #CR_FREE
    cmp #CR_FREE                ; C = free play
    lda CRED
    and #CR_COUNT               ; (AND does not touch the Carry)
    rts

; ---------------------------------------------------------------
; ARC_USE_CREDIT (jump table $FD89, JT_ARC_USE_CREDIT): A = credits to take (1 or 2).
; C = 0 taken (in FREE PLAY nothing is taken), C = 1 not enough credits (nothing taken).
; Preserves X and Y.
; ---------------------------------------------------------------
ARC_USE_CREDIT:
    phx
    pha                         ; credits to take, on the stack
    lda #CR_FREE
    bit CRED
    bne @ok                     ; free play
    tsx
    lda CRED
    and #CR_COUNT
    cmp $0101,x                 ; credits >= wanted?
    bcc @short
    pla
    tax
    beq @none
@take:
    dec CRED                    ; one RMW instruction: the NMI can only add meanwhile
    dex
    bne @take
@none:
    plx
    clc
    rts
@ok:
    pla
    plx
    clc
    rts
@short:
    pla
    plx
    sec
    rts

.segment "PROGRAM"

; =============================================================================
; FREE PLAY / COIN of every game: the GAME SETTINGS page (BUTTON 1 in the system test)
;
; Kept on the SD in the save area, zone 0, sector 1 (sector 32769, ../SD_SALVATAGGI.md):
;   +0 "ARCS"  +4 version 1  +16 + z: setting of the game of zone z (0 = as the catalog,
;   1 = FREE PLAY, 2 = COIN)  +510 16-bit sum of the bytes 0-509 (little endian)
; By zone, so it stays right when the order of the SD changes. Without a valid sector the
; catalog defaults count (index byte +3 bit 0: 1 = COIN). Entries without a zone (catalog
; version 1, the list from the directory, the Jukebox) are always in FREE PLAY.
; At the launch the front-end writes bit 4 of CRED; in COIN mode a game that does not handle the
; credits itself (index byte +3 bit 1 = 0) needs a credit, taken by the front-end.
; =============================================================================

FE_SLIST   = $1300          ; entries shown in the settings page
FE_SETS    = $1400          ; 256 bytes: setting of every zone (0 catalog, 1 FREE PLAY, 2 COIN)
FE_CSHOWN  = $1218          ; credit field shown on row 23 ($80 = draw again)
FE_ALLFREE = $1219          ; 1 = every entry of the list is in FREE PLAY
FE_SDIRTY  = $121A          ; 1 = a setting was changed in the page
FE_SKEEP   = $121B          ; 3 bytes: FE_COUNT, FE_SEL, FE_TOP of the list while the page is open

SET_LBA    = 32769          ; zone 0, sector 1 of the save area
IDX_FLAGS2 = 3              ; index byte: bit 0 COIN by default, 1 the game handles the credits,
CF_COIN    = %00000001      ;   2 uses START, 3 uses button 3
CF_GAME    = %00000010
IDX_ZONE   = 4              ; index byte: save zone (0 = none)
SET_ITEMS0 = 2              ; rows "ALL GAMES" before the games
SET_MAXG   = 253
CRED_COL   = 21             ; credit field: row 23, columns 21-31

; fe_load_sets: FE_SETS from the SD (all 0 without a valid sector)
fe_load_sets:
    ldx #0
@z:
    stz FE_SETS,x
    inx
    bne @z
    lda sd_type
    beq @end                                ; no card
    lda #<SET_LBA
    sta FE_LBA
    lda #>SET_LBA
    sta FE_LBA+1
    ldx #<FE_TEXT
    ldy #>FE_TEXT
    jsr fe_read
    bcs @end
    ldx #3
@magic:
    lda FE_TEXT,x
    cmp set_magic,x
    bne @end
    dex
    bpl @magic
    lda FE_TEXT+4
    cmp #1
    bne @end
    jsr fe_sum510
    lda V_CNT
    cmp FE_TEXT+510
    bne @end
    lda V_CNT+1
    cmp FE_TEXT+511
    bne @end
    ldx #0
@copy:
    lda FE_TEXT+16,x
    cmp #3
    bcc @val
    lda #0                                  ; unknown value: as the catalog
@val:
    sta FE_SETS,x
    inx
    bne @copy
@end:
    rts

; fe_save_sets: FE_SETS -> SD. C=1 write error
fe_save_sets:
    ldx #0
@z:
    stz FE_TEXT,x
    stz FE_TEXT+256,x
    inx
    bne @z
    ldx #3
@magic:
    lda set_magic,x
    sta FE_TEXT,x
    dex
    bpl @magic
    lda #1
    sta FE_TEXT+4
@copy:                                      ; (X = $FF -> 0 first)
    inx
    lda FE_SETS,x
    sta FE_TEXT+16,x
    cpx #$FF
    bne @copy
    jsr fe_sum510
    lda V_CNT
    sta FE_TEXT+510
    lda V_CNT+1
    sta FE_TEXT+511
    lda #<SET_LBA
    sta SD_LBA
    lda #>SET_LBA
    sta SD_LBA+1
    stz SD_LBA+2
    stz SD_LBA+3
    ldx #<FE_TEXT
    ldy #>FE_TEXT
    jmp SD_WRITE_SECTOR

; fe_sum510: V_CNT = 16-bit sum of FE_TEXT bytes 0-509
fe_sum510:
    stz V_CNT
    stz V_CNT+1
    ldx #0
@a:
    lda FE_TEXT,x
    jsr @add
    inx
    bne @a
@b:
    lda FE_TEXT+256,x
    jsr @add
    inx
    cpx #254
    bne @b
    rts
@add:
    clc
    adc V_CNT
    sta V_CNT
    bcc @nc
    inc V_CNT+1
@nc:
    rts

; fe_entry_mode: entry E_PTR -> C = 1 FREE PLAY, C = 0 COIN. Changes A and Y.
fe_entry_mode:
    ldy #IDX_ZONE
    lda (E_PTR),y
    beq @free                               ; no zone: always free play
    tay
    lda FE_SETS,y
    beq @default
    lsr                                     ; 1 -> C = 1 FREE PLAY, 2 -> C = 0 COIN
    rts
@default:
    ldy #IDX_FLAGS2
    lda (E_PTR),y
    eor #CF_COIN
    lsr                                     ; C = 1 if not COIN by default
    rts
@free:
    sec
    rts

; fe_calc_allfree: FE_ALLFREE = 1 if every entry of the list is in FREE PLAY
fe_calc_allfree:
    lda #1
    sta FE_ALLFREE
    ldx FE_COUNT
@l:
    beq @end
    dex
    txa
    jsr fe_entry_ptr
    jsr fe_entry_mode
    bcs @next
    stz FE_ALLFREE
    rts
@next:
    cpx #0
    bra @l
@end:
    rts

; fe_try_launch: before loading entry FE_SEL. Writes the FREE PLAY bit of CRED; in COIN mode a
; game that does not handle the credits takes one here. C = 1: no credit, do not launch.
fe_try_launch:
    lda FE_SEL
    jsr fe_entry_ptr
    jsr fe_entry_mode
    bcc @coin
    lda #CR_FREE
    tsb CRED
    clc
    rts
@coin:
    lda #CR_FREE
    trb CRED
    ldy #IDX_FLAGS2
    lda (E_PTR),y
    and #CF_GAME
    bne @ok                                 ; the game takes its credits itself
    lda #1
    jmp ARC_USE_CREDIT
@ok:
    clc
    rts

; fe_cred_list / fe_cred_game: the credit field (row 23, columns 21-31) of the list (FREE PLAY when
; every game is in free play, otherwise CREDITS n) or of the selected game (FREE PLAY, CREDITS n,
; INSERT COIN when the front-end needs a credit for it). Drawn again only when it changes.
; Changes A, X, Y and E_PTR.
fe_cred_list:
    lda #$FF
    ldx FE_ALLFREE
    bne fe_cred_show
    lda CRED
    and #CR_COUNT
    bra fe_cred_show
fe_cred_game:
    lda FE_SEL
    jsr fe_entry_ptr
    jsr fe_entry_mode
    lda #$FF
    bcs fe_cred_show
    lda CRED
    and #CR_COUNT
    bne fe_cred_show
    ldy #IDX_FLAGS2
    lda (E_PTR),y
    and #CF_GAME
    bne @zero
    lda #$FE                                ; INSERT COIN
    bra fe_cred_show
@zero:
    lda #0
fe_cred_show:                               ; A = $FF free play, $FE insert coin, else credits
    cmp FE_CSHOWN
    beq @same
    sta FE_CSHOWN
    stz G_ATTR
    ldx #23
    stx G_ROW
    ldx #CRED_COL
    stx G_COL
    cmp #$FE
    bcc @count
    beq @insert
    lda #<txt_cr_free
    ldx #>txt_cr_free
    jmp g2_puts
@insert:
    lda #<txt_cr_insert
    ldx #>txt_cr_insert
    jmp g2_puts
@count:
    cmp #10
    bcc @digit
    lda #9
@digit:
    pha
    lda #<txt_cr_count
    ldx #>txt_cr_count
    jsr g2_puts
    pla
    ora #'0'
    jmp g2_putc
@same:
    rts

.segment "BIOS"                             ; (no room left in PROGRAM)

; =============================================================================
; GAME SETTINGS page (BUTTON 1 in the system test): FREE PLAY or COIN for every game with a
; save zone, or for all of them. UP/DOWN choose (LEFT/RIGHT one page), BUTTON 1 changes,
; BUTTON 2 or SERVICE save (one sector, only if something changed) and go back to the list.
; While the page is open FE_COUNT / FE_SEL / FE_TOP are its rows (kept in FE_SKEEP).
; =============================================================================
fe_settings:
    lda FE_COUNT
    sta FE_SKEEP
    lda FE_SEL
    sta FE_SKEEP+1
    lda FE_TOP
    sta FE_SKEEP+2
    stz FE_SDIRTY
    ; the entries with a save zone
    ldx #0                                  ; entries listed
    stz G_T2                                ; entry
@scan:
    lda G_T2
    cmp FE_SKEEP
    bcs @scanned
    jsr fe_entry_ptr
    ldy #1
    lda (E_PTR),y
    cmp #KIND_GAME
    bne @skip
    ldy #IDX_ZONE
    lda (E_PTR),y
    beq @skip
    lda G_T2
    sta FE_SLIST,x
    inx
    cpx #SET_MAXG
    beq @scanned
@skip:
    inc G_T2
    bra @scan
@scanned:
    txa
    clc
    adc #SET_ITEMS0
    sta FE_COUNT
    stz FE_SEL
    stz FE_TOP
    lda #<txt_settings
    ldx #>txt_settings
    jsr fe_test_title
    PUTS_AT 2, 1, txt_set_head
    PUTS_AT 21, 1, txt_set_help1
    PUTS_AT 22, 1, txt_set_help2
    jsr fe_set_rows
@loop:
    jsr fe_input_nocmd
    lda FE_SYSNEW
    and #SYS_SERVICE
    bne @exit
    lda FE_NEW
    bit #J_B2
    bne @exit
    bit #J_B1
    bne @change
    jsr fe_nav
    bcc @loop
    jsr fe_set_rows
    bra @loop
@change:
    jsr fe_set_change
    jsr fe_set_rows
    bra @loop
@exit:
    lda FE_SDIRTY
    beq @restore
    PUTS_AT 2, 1, txt_set_saving
    jsr fe_save_sets
    bcc @restore
    PUTS_AT 2, 1, txt_set_error
    ldx #120                                ; 2 s
@wait:
    jsr fe_wait_frame
    dex
    bne @wait
@restore:
    lda FE_SKEEP
    sta FE_COUNT
    lda FE_SKEEP+1
    sta FE_SEL
    lda FE_SKEEP+2
    sta FE_TOP
    jsr fe_calc_allfree
    jsr arc_read_joy
    sta FE_PREV                             ; B2 still held is not a press in the list
    jmp fe_test_exit

; fe_set_change: BUTTON 1 on row FE_SEL
fe_set_change:
    lda #1
    sta FE_SDIRTY
    lda FE_SEL
    cmp #SET_ITEMS0
    bcs @one
    inc                                     ; row 0: all FREE PLAY (1), row 1: all COIN (2)
    sta G_T1
    ldx FE_COUNT
@all:
    dex
    cpx #SET_ITEMS0-1
    beq @end
    phx
    jsr fe_set_entry                        ; E_PTR and Y = zone of row X
    lda G_T1
    sta FE_SETS,y
    plx
    bra @all
@one:
    tax
    jsr fe_set_entry
    phy
    jsr fe_entry_mode
    ply
    lda #1                                  ; COIN -> FREE PLAY
    bcc @put
    lda #2                                  ; FREE PLAY -> COIN
@put:
    sta FE_SETS,y
@end:
    rts

; fe_set_entry: X = row of a game (>= SET_ITEMS0) -> E_PTR = its entry, Y = its zone
fe_set_entry:
    lda FE_SLIST-SET_ITEMS0,x
    jsr fe_entry_ptr
    ldy #IDX_ZONE
    lda (E_PTR),y
    tay
    rts

; fe_set_rows: the rows of the page (window FE_TOP, selection FE_SEL)
fe_set_rows:
    lda #LIST_ROW
    sta G_ROW
    lda FE_TOP
    sta G_T2
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
    lda #1
    sta G_COL
    sta G_LEFT
    lda G_T2
    cmp #SET_ITEMS0
    bcs @game
    tay
    ldx set_all_hi,y
    lda set_all_lo,y
    jsr g2_puts
    bra @next
@game:
    tax
    jsr fe_set_entry
    jsr g2_pos
    ldy #8                                  ; name, at most 19 characters
@name:
    lda (E_PTR),y
    beq @dots
    jsr g2_putc
    iny
    cpy #8+19
    bne @name
@dots:
    lda #' '
    jsr g2_putc
@dot:
    lda G_COL
    cmp #21
    bcs @value
    lda #'.'
    jsr g2_putc
    bra @dot
@value:
    lda #' '
    jsr g2_putc
    jsr fe_entry_mode
    lda #<txt_set_coin
    ldx #>txt_set_coin
    bcc @put
    lda #<txt_set_free
    ldx #>txt_set_free
@put:
    jsr g2_puts
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
    rts

set_all_lo:     .byte <txt_set_allf, <txt_set_allc
set_all_hi:     .byte >txt_set_allf, >txt_set_allc
set_magic:      .byte "ARCS"
txt_settings:   .byte "GAME SETTINGS", 0
txt_set_head:   .byte "1 COIN = 1 CREDIT, MAX 9  ", 0
txt_set_saving: .byte "SAVING ON THE SD CARD...  ", 0
txt_set_error:  .byte "SD WRITE ERROR: NOT SAVED ", 0
txt_set_help1:  .byte "STICK: CHOOSE   B1: CHANGE", 0
txt_set_help2:  .byte "B2 OR SERVICE: SAVE AND EXIT", 0
txt_set_allf:   .byte "ALL GAMES  >  FREE PLAY", 0
txt_set_allc:   .byte "ALL GAMES  >  COIN", 0
txt_set_free:   .byte "FREE PLAY", 0
txt_set_coin:   .byte "COIN", 0
txt_cr_free:    .byte "  FREE PLAY", 0
txt_cr_insert:  .byte "INSERT COIN", 0
txt_cr_count:   .byte "  CREDITS ", 0
