; Brief speaker chirps. Bounded to a few milliseconds so input stays responsive.
.setcpu "6502"
.export _sound, _muted
.segment "BSS"
_muted: .res 1
pitch: .res 1
pulses: .res 1
.segment "CODE"
_sound:
    ldx _muted
    bne @done
    tax
    lda pitches,x
    sta pitch
    lda durations,x
    sta pulses
@pulse:
    bit $C030
    ldy pitch
@delay:
    dey
    bne @delay
    dec pitch
    dec pulses
    bne @pulse
@done:
    rts
.segment "RODATA"
pitches: .byte 34,90,160,75,120
durations: .byte 12,18,24,8,20
