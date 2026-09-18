; Original loader. The ROM supplies BLOCKIO, but no ROM bytes are distributed.
.setcpu "6502"
.segment "CODE"
start:
    sei
    cld
    lda #$77
    sta $FFDF
    lda #0
    sta $85
    sta block+1
    sta stage
    lda #1
    sta $87
    sta block
    ; Five independent windows cannot exist on a 128 KB board. Probe a byte
    ; outside this loader and the ROM workspace before loading banked assets.
    ldx #4
@save:
    txa
    ora #$40
    sta $FFEF
    lda $9FFF
    sta saved,x
    dex
    bpl @save
    ldx #4
@mark:
    txa
    ora #$40
    sta $FFEF
    txa
    sta $9FFF
    dex
    bpl @mark
    ldx #4
@check:
    txa
    ora #$40
    sta $FFEF
    txa
    cmp $9FFF
    bne ram_error
    dex
    bpl @check
    ldx #4
@restore:
    txa
    ora #$40
    sta $FFEF
    lda saved,x
    sta $9FFF
    dex
    bpl @restore
    ldx #0
@message:
    lda loading,x
    beq next_stage
    ora #$80
    sta $0400,x
    inx
    bne @message
next_stage:
    ldx stage
    lda banks,x
    sta $FFEF
    lda addresses,x
    sta $86
    lda counts,x
    sta remaining
load:
    lda block
    ldx block+1
    jsr $F479
    bcs disk_error
    inc $86
    inc $86
    inc block
    bne :+
    inc block+1
:
    dec remaining
    bne load
    ldx stage
    lda #$AA
    sta $0480,x
    inc stage
    lda stage
    cmp #6
    bne next_stage
    bit $C0E8
    lda #$40
    sta $FFEF
    jmp $A200
ram_error:
    ldx #0
@ram:
    lda ram_message,x
    beq stopped
    ora #$80
    sta $0400,x
    inx
    bne @ram
disk_error:
    ldx #0
@disk:
    lda disk_message,x
    beq stopped
    ora #$80
    sta $0400,x
    inx
    bne @disk
stopped:
    bit $C0E8
    bit $C050
    bit $C052
    bit $C054
    bit $C056
    jmp stopped
banks: .byte $40,$40,$41,$42,$43,$44
addresses: .byte $A2,$D0,$20,$20,$20,$20
counts: .byte 15,16,64,64,64,48
stage: .byte 0
block: .word 1
remaining: .byte 0
saved: .res 5
loading: .byte "HIGHWAY /// - LOADING 256K EDITION",0
ram_message: .byte "HIGHWAY /// REQUIRES 256K RAM    ",0
disk_message: .byte "DISK READ ERROR - RESET TO RETRY ",0
.assert * - start <= 512, error, "Loader exceeds one block"
