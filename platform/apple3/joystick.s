.setcpu "6502"
.export _joystick_init, _joystick_poll
.export _joy, _joy_pressed, _joy_switch_changed, _joy_x, _joy_y

; Native 9708 converter, port B: channels 1/2, pushbutton $C062,
; latching switch $C060. Use the D VIA's 1 MHz timer, so video and CPU
; wait states cannot change the measurement. No ROM/SOS routines are copied.
.segment "BSS"
_joy:                .res 1
_joy_pressed:        .res 1
_joy_switch_changed: .res 1
_joy_x:              .res 1
_joy_y:              .res 1
previous:            .res 1
elapsed:             .res 2

.segment "CODE"
_joystick_init:
    lda $FFDB
    and #$DF                 ; timer 2 counts clocks, not PB6 pulses
    sta $FFDB
    bit $C05D                ; discharge before the first sample
    jsr buttons              ; a switch left on at reset is not a new press
    lda #0
    sta _joy_pressed
    sta _joy_switch_changed
    rts

_joystick_poll:
    lda _joy
    sta previous
    jsr buttons
    lda #1
    jsr axis
    sta _joy_x
    cmp #96
    bcc left
    cmp #161
    bcc sample_y
    lda #2
    bne direction_x
left:
    lda #1
direction_x:
    ora _joy
    sta _joy
sample_y:
    lda #2
    jsr axis
    sta _joy_y
    cmp #96
    bcc down
    cmp #161
    bcc edges
    lda #4                   ; high voltage is UP on an Apple III
    bne direction_y
down:
    lda #8
direction_y:
    ora _joy
    sta _joy
edges:
    lda previous
    eor #$FF
    and _joy
    sta _joy_pressed
    lda previous
    eor _joy
    and #32
    sta _joy_switch_changed
    rts

buttons:
    lda $C060
    and #$80
    lsr a
    lsr a
    sta _joy
    lda $C062
    and #$80
    lsr a
    lsr a
    lsr a
    ora _joy
    sta _joy
    rts

; A = channel 1 (X) or 2 (Y). About 500 us acquisition, then up to
; 4 ms discharge. SOS's joystick range is roughly 350 + position*8
; timer ticks. A broad center dead zone also tolerates MAME's ADC model.
axis:
    bit $C05A                ; channel bit 2 = 0
    cmp #1
    bne select_y
    bit $C059
    bit $C05E
    jmp acquire
select_y:
    bit $C058
    bit $C05F
acquire:
    bit $C05C
    lda #<500
    sta $FFD8
    lda #>500
    sta $FFD9
    lda #$20
charge:
    bit $FFDD
    beq charge
    bit $C05D
    lda #$FF
    sta $FFD8
    lda #$0F
    sta $FFD9
    lda #$20
discharge:
    bit $C066
    bpl measured
    bit $FFDD
    beq discharge
neutral:
    lda #128                 ; disconnected/saturated ADC cannot stall play
    rts
measured:
    ldx $FFD9                ; retry if the low byte rolled over while reading
    lda $FFD8
    cpx $FFD9
    bne measured
    eor #$FF
    sta elapsed
    txa
    eor #$0F
    cmp #10                  ; floating input is above the joystick range
    bcs neutral
    sta elapsed+1
    sec
    lda elapsed
    sbc #<350
    sta elapsed
    lda elapsed+1
    sbc #>350
    bcc minimum
    sta elapsed+1
    lsr elapsed+1
    ror elapsed
    lsr elapsed+1
    ror elapsed
    lsr elapsed+1
    ror elapsed
    lda elapsed+1
    bne maximum
    lda elapsed
    rts
minimum:
    lda #0
    rts
maximum:
    lda #255
    rts
