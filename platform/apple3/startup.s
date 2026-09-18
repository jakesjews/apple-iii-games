.setcpu "6502"
.export __STARTUP__ : absolute = 1
.import _main, zerobss
.importzp sp
.segment "STARTUP"
start:
    sei
    cld
    ldx #$FF
    txs
    lda #0
    sta $FFD0                 ; unrelocated zero page
    lda #$77
    sta $FFDF                 ; native 2 MHz, video, I/O, primary ROM
    lda #$40
    sta $FFEF                 ; native mode, bank 0
    lda #$7F
    sta $FFDE
    sta $FFEE                 ; poll VBL; no interrupt handlers required
    sta $C0F1                 ; reset serial IRQ source
    lda #<$C000
    sta sp
    lda #>$C000
    sta sp+1
    jsr zerobss
    jsr _main
:
    jmp :-
