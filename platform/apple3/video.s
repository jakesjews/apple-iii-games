.setcpu "6502"
.export _video_init, _video_clear, _wait_frame, _video_sprite, _video_text
.export _video_pixel, _video_read_pixel, _gfx_x, _gfx_y, _gfx_color
.export _gfx_band_y, _gfx_band_color
.import sprite_lo, sprite_hi, font_lo, font_hi
.segment "ZEROPAGE"
dst: .res 2
src: .res 2
str: .res 2
column: .res 1
line: .res 1
rows: .res 1
bits: .res 1
mode: .res 1
.segment "BSS"
_gfx_x: .res 1
_gfx_y: .res 1
_gfx_color: .res 1
_gfx_band_y: .res 1
_gfx_band_color: .res 1
.segment "CODE"
_video_init:
    lda #192
    sta _gfx_band_y
    bit $C0D8                 ; no smooth scrolling or character downloads
    bit $C0DA
    bit $C051                 ; VM0=1: color
    bit $C052                 ; VM1=0: 280 pixels
    bit $C054                 ; VM2=0: first graphics page
    bit $C057                 ; VM3=1: graphics
    lda $FFEC
    and #$1F
    ora #$60                  ; E VIA CB2 independent positive VBL edge
    sta $FFEC
    lda #$F0
    sta _gfx_color
    jmp _video_clear

_wait_frame:
    lda #8
    sta $FFED
:
    lda $FFED
    and #8
    beq :-
    rts

_video_clear:
    lda #0
    sta dst
    lda #$20
    sta dst+1
    ldy #0
    lda #0
@page:
    sta (dst),y
    iny
    bne @page
    inc dst+1
    ldx dst+1
    cpx #$60
    bne @page
    rts

; Find a scanline in the native bank. CPU $2000 maps to physical bank 0 $0000.
address:
    ldx line
    lda row_lo,x
    clc
    adc column
    sta dst
    lda row_hi,x
    adc #0
    sta dst+1
    rts

_video_sprite:
    tax
    lda sprite_lo,x
    sta src
    lda sprite_hi,x
    sta src+1
    ldx _gfx_x
    lda shift_offset,x
    clc
    adc src
    sta src
    bcc :+
    inc src+1
:
    lda x_column,x
    sta column
    lda _gfx_y
    sta line
    lda #8
    sta rows
@row:
    jsr address
    ldy #2
@byte:
    lda (src),y
    eor (dst),y
    sta (dst),y
    dey
    bpl @byte
    lda dst+1
    clc
    adc #$20
    sta dst+1
    lda line
    cmp _gfx_band_y
    bcc @object_color
    lda _gfx_band_color
    jmp @color
@object_color:
    lda _gfx_color
@color:
    ldy #2
    sta (dst),y
    dey
    sta (dst),y
    dey
    sta (dst),y
    lda src
    clc
    adc #3
    sta src
    bcc :+
    inc src+1
:
    inc line
    dec rows
    bne @row
    rts

_video_text:
    sta str
    stx str+1
    lda _gfx_x
    sta column
@char:
    ldy #0
    lda (str),y
    beq @done
    and #$3F                  ; font pointer table uses ASCII mod 64
    tax
    lda font_lo,x
    sta src
    lda font_hi,x
    sta src+1
    lda _gfx_y
    sta line
    lda #0
    sta rows
@row:
    jsr address
    ldy rows
    lda (src),y
    ldy #0
    sta (dst),y
    lda dst+1
    clc
    adc #$20
    sta dst+1
    lda _gfx_color
    sta (dst),y
    inc line
    inc rows
    lda rows
    cmp #8
    bne @row
    inc str
    bne :+
    inc str+1
:
    inc column
    lda column
    cmp #40
    bcc @char
@done:
    rts

pixel_address:
    ldx _gfx_x
    lda x_mask,x
    sta bits
    lda x_column,x
    sta column
    lda _gfx_y
    sta line
    jsr address
    ldy #0
    rts
_video_read_pixel:
    jsr pixel_address
    lda (dst),y
    and bits
    ldx #0
    rts
_video_pixel:
    sta mode
    jsr pixel_address
    lda mode
    beq @clear
    lda (dst),y
    ora bits
    bne @write
@clear:
    lda bits
    eor #$7F
    and (dst),y
@write:
    sta (dst),y
    lda dst+1
    clc
    adc #$20
    sta dst+1
    lda _gfx_color
    sta (dst),y
    rts

.segment "RODATA"
row_lo:
.repeat 192, I
    .byte <($2000 + (I .mod 8)*$400 + ((I/8) .mod 8)*$80 + (I/64)*40)
.endrepeat
row_hi:
.repeat 192, I
    .byte >($2000 + (I .mod 8)*$400 + ((I/8) .mod 8)*$80 + (I/64)*40)
.endrepeat
x_column:
.repeat 256, I
    .byte I/7
.endrepeat
shift_offset:
.repeat 256, I
    .byte (I .mod 7)*24
.endrepeat
x_mask:
.repeat 256, I
    .byte 1 << (I .mod 7)
.endrepeat
