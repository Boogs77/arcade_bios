.segment "CODE"
; NMI handler: the VDP interrupt (end of frame) of the program in RAM, then the arcade
; exit: P1 START and P2 START held together for 2 seconds (120 frames) go back to the
; front-end from any game. The hold counter is kept in the T1 latch of the joystick VIA
; (JOY_HOLD, see arcade_io.s), so no RAM byte of the game is touched.
NMI_HANDLER:
  PHA
  PHX
  PHY
  JSR $0FD0         ; CALL DISPATCH (IN RAM)
  LDA VREG          ; acknowledge VDP
  LDA JOY_P1
  ORA JOY_P2
  BMI @released     ; bit 7 = 1: one of the START buttons is not pressed
  INC JOY_HOLD
  LDA JOY_HOLD
  CMP #HOLD_FRAMES
  BCC @done
  LDX #$FF
  TXS
  JMP SHOW_MENU     ; the game is left: the front-end starts again
@released:
  STZ JOY_HOLD
@done:
  PLY
  PLX
  PLA
  RTI
