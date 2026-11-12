; ============================================================
; SYSTEM VECTOR TABLE ("KERNAL" style, like C64 / Apple //)
; ------------------------------------------------------------
; FIXED, stable addresses: any program loaded from SD calls the
; BIOS services ONLY through these addresses, NEVER through the
; internal labels of the BIOS, which move every time it is rebuilt.
;
; $FD00-$FD21: the same entries as the miniVIC BIOS 03.11.26 KEYB/SD,
; so the miniVIC games and applications find them at the same place.
; Without a keyboard the keyboard entries change meaning (see each line).
; $FD24-$FD7F: left free for the entries the miniVIC BIOS adds later.
; $FD80-: Arcade BIOS entries.
; New entries are added ONLY at the end of their block.
; ============================================================
.segment "JUMPTBL"

JT_CHROUT:          jmp CHROUT              ; $FD00 - A=character to print (CRT text mode and serial)
JT_CHRIN_NOECHO:    jmp CHRIN_NO_ECHO       ; $FD03 - Carry=1+A=key if pressed, Carry=0 if none: serial port, then joystick keys (START/B1 $0D, B2 $1B, B3 ' ', arrows $80-$83)
JT_RESET_TERM:      jmp RESET_SERIAL_TERM   ; $FD06 - ANSI reset of the serial terminal
JT_INIT_CRT:        jmp INIT_CRT            ; $FD09 - reset of the local CRT (text mode)
JT_LOAD_RUN_SLOT:   jmp LOAD_AND_RUN_SLOT   ; $FD0C - A=SD slot, loads the program AND RUNS IT; error -> front-end (never RTS: call with JMP)
JT_SHOW_MENU:       jmp SHOW_MENU           ; $FD0F - back to the front-end (never RTS: call with JMP)
JT_INIT_SDCARD:     jmp INIT_SDCARD         ; $FD12 - A=SD slot, loads the program and RETURNS without running it: C=0 ok, C=1 error
JT_FLUSH_KB:        jmp FLUSH_KEYBOARD_HARD ; $FD15 - ~0.5 s, drops the serial input, held buttons are not new presses (saves A/X/Y)
JT_SD_READ_SECTOR:  jmp SD_READ_SECTOR      ; $FD18 - reads sector SD_LBA ($0316-$0319, little endian) into the buffer X/Y (lo/hi, 512 bytes): C=0 ok, C=1 error; preserves A/X/Y
JT_SD_WRITE_SECTOR: jmp SD_WRITE_SECTOR     ; $FD1B - writes the buffer X/Y (512 bytes) to sector SD_LBA: C=0 ok, C=1 error; preserves A/X/Y
JT_SD_INIT:         jmp SD_INIT             ; $FD1E - (re)initializes the SD: C=0 ok and A=type (1 SDSC v1, 2 SDSC v2, 3 SDHC/SDXC), C=1 no card (A=0)
JT_KB_SET_MODE:     jmp KB_SET_MODE         ; $FD21 - no keyboard: does nothing (kept for the KEYB/SD programs)

.res $80 - (* - JT_CHROUT), 0                          ; $FD24-$FD7F: reserved for the miniVIC BIOS

; --- Arcade BIOS ---
JT_ARC_INPUTS:      jmp ARC_READ_INPUTS     ; $FD80 - A=P1, X=P2 (bit 0 UP,1 DOWN,2 LEFT,3 RIGHT,4 B1,5 B2,6 B3,7 START), Y=bit 0 COIN1,1 COIN2,2 TEST,3 SERVICE; 1 = pressed
JT_ARC_SILENCE:     jmp AY_SILENCE          ; $FD83 - both AY-3-8910 silent; preserves X/Y

.res $FE - (* - JT_CHROUT), 0
ROM_SUM:            .word 0                 ; $FDFE - 16-bit sum of the ROM without these two bytes (written by make.sh, checked by the system test)
