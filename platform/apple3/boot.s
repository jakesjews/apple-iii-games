; Original Apple /// ROM loads block zero at $A000. Keep its disk workspace
; intact, select native bank zero, then read the payload using ROM BLOCKIO.
.setcpu "6502"
.segment "CODE"
start:
    sei
    cld
    lda #$77
    sta $FFDF
    lda #$40
    sta $FFEF
    lda #$00
    sta $85
    lda #$60
    sta $86
    lda #$01
    sta $87
    sta block
load:
    lda block
    ldx #0
    jsr $F479
    bcs error
    inc $86
    inc $86
    inc block
    lda block
    cmp #BLOCK_COUNT+1
    bne load
    bit $C0E8                  ; stop the internal disk motor
    jmp $6000
error:
    ldx #0
:
    lda message,x
    beq retry
    ora #$80
    sta $0500,x
    inx
    bne :-
retry:
    lda $C000
    bpl retry
    bit $C010
    jmp start
block: .byte 1
message: .byte "DISK READ ERROR - PRESS A KEY TO RETRY",0
.assert * - start <= 512, error, "Boot block exceeds 512 bytes"
