; Run the production joystick reader on the MiSTer core's CPU/VIA/ADC.
; The host changes port B only after each complete pair of samples.
.setcpu "6502"
.import _joystick_init, _joystick_poll, _joy, _joy_x, _joy_y
.import _joy_pressed, _joy_switch_changed
.segment "CODE"
reset:
    sei
    cld
    ldx #$FF
    txs
    lda #$73
    sta $FFDF
    lda #0
    sta $FFD0
    sta $FFE0
    sta $FFEF
    sta $0410
    lda #$FF
    sta $FFD2
    sta $FFD3
    lda #$0F
    sta $FFE3
    lda #$7F
    sta $FFDE
    sta $FFEE
    jsr _joystick_init
loop:
    lda $0410
    and #3
    tax
    lda environments,x
    sta $FFDF
    jsr _joystick_poll
    lda _joy_x
    sta $0400
    lda _joy_y
    sta $0401
    lda _joy
    sta $0402
    lda _joy_pressed
    sta $0403
    lda _joy_switch_changed
    sta $0404
    inc $0410
    jmp loop
environments:
    .byte $73, $53, $D3, $F3 ; 2 MHz on/off, 1 MHz off/on
.segment "VECTORS"
    .word reset, reset, reset
