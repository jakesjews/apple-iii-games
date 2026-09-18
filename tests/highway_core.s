; Original diagnostic reset stub. The testbench preloads the released game's
; code/assets, then this establishes the VIA state normally supplied by ROM.
.setcpu "6502"
.segment "CODE"
reset:
    sei
    cld
    ldx #$FF
    txs
    lda #0
    sta $FFD0
    lda #$77
    sta $FFDF
    lda #$FF
    sta $FFD2
    sta $FFD3
    lda #$0F
    sta $FFE3
    lda #$40
    sta $FFEF
    lda #$7F
    sta $FFDE
    sta $FFEE
    jmp $A200
.segment "VECTORS"
    .word reset,reset,reset
