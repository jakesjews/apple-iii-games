.setcpu "6502"
.export __STARTUP__ : absolute = 1
.export _engine_init,_scene_init,_road_load,_road_draw,_object_draw,_object_erase
.export _digit_draw
.export _road_prepare,_road_damage,_object_damaged,_object_damage,_object_slot,_object_full
.export _present,_wait_frame,_clock_read,_say_ready,_text
.export _page,_scene,_road_phase,_road_pose,_engine_pitch,_engine_on,_muted
.export _object_id,_object_x,_object_y,_object_w,_object_h,_geom
.export _gfx_x,_gfx_y,_gfx_color,_irq_ticks,_pcm_remaining
.import _main,zerobss,_hill
.importzp sp
.import hill_lo,hill_hi
.import road_lo,road_hi,asset_bank,asset_lo,asset_hi,asset_w,asset_h
.import asset_size_lo,asset_size_hi,row_lo,row_hi,stripe_depth,waveform
.import font_lo,font_hi,voice_address,expand_lo,expand_hi,column_left,column_right,mark_lo,mark_hi
.segment "ZEROPAGE"
src: .res 2
dst: .res 2
attr: .res 2
str: .res 2
count: .res 2
row: .res 1
col: .res 1
height: .res 1
tmp: .res 1
band: .res 1
ground: .res 1
curb: .res 1
old: .res 2
left: .res 1
right: .res 1
pcm: .res 2
oldleft: .res 1
oldright: .res 1
fill: .res 1
dst2: .res 2
attr2: .res 2
pointer_cache: .res 2
.segment "BSS"
_page: .res 1
_scene: .res 1
_road_phase: .res 1
_road_pose: .res 1
_engine_pitch: .res 1
_engine_on: .res 1
_muted: .res 1
_object_id: .res 1
_object_x: .res 1
_object_y: .res 1
_object_w: .res 1
_object_h: .res 1
_gfx_x: .res 1
_gfx_y: .res 1
_gfx_color: .res 1
_irq_ticks: .res 2
_pcm_remaining: .res 2
phase: .res 1
initial: .res 2
old_revision: .res 2
dirty: .res 1
revision: .res 1
geometry_dirty: .res 1
; 0 clean, 1 stripes only, 2 changed geometry, 3 initial fill, 4 erased pixels.
_road_damage: .res 56
_object_slot: .res 1
_object_full: .res 1
damage_columns: .res 56
object_mask: .res 1
object_any: .res 1
flags_full: .res 1
expand_bank: .res 1
_geom: .res 392
previous: .res 784
pointer_x: .res 18
pointer_y: .res 18
pointer_h: .res 18
pointer_page: .res 1
road_marks: .res 56
previous_marks: .res 112
blit_vector: .res 2
.segment "SCRATCH"
; Speech/skyline scratch becomes the eight extended-address sister pages.
cache: .res 2048
.assert cache = $1000, lderror, "Sister pages must cover $1000..$17FF"
.segment "STARTUP"
start:
    sei
    cld
    ldx #$FF
    txs
    lda #0
    sta $FFD0
    lda #$40
    sta $FFEF
    lda #$7F
    sta $FFDE
    sta $FFEE
    sta $C0F1
    ; The boot block is disposable after loading: reuse its 512 bytes for
    ; the C software stack, leaving all eight private zero pages resident.
    lda #<$A200
    sta sp
    lda #>$A200
    sta sp+1
    jsr zerobss
    ; RAM vectors are written beneath the ROM, then the ROM is disabled.
    lda #<irq
    sta $FFFE
    lda #>irq
    sta $FFFF
    lda #<nmi
    sta $FFFA
    lda #>nmi
    sta $FFFB
    lda #$76
    sta $FFDF
    jsr _main
    jmp start
.segment "RENDER"
_engine_init:
    jsr expand_cars
    jsr sprite_reset
    bit $C0D8
    bit $C0DA
    bit $C051
    bit $C052
    bit $C054
    bit $C057
    lda $FFEC
    and #$1F
    ora #$60
    sta $FFEC
    lda #$3F
    sta $FFE2                 ; six DAC outputs; blanking and NMI remain inputs
    lda #32
    sta $FFE0
    lda $FFEB
    and #$3F
    ora #$40                  ; E VIA timer 1 free runs at nominal 2 kHz
    sta $FFEB
    lda #<499
    sta $FFE4
    lda #>499
    sta $FFE5
    lda #$C0
    sta $FFEE
    cli
    rts
; Expand color-specialized car code into spare banks five/six once at boot.
; The source remains read-only in bank two. Only startup pays for switching
; banks for literal bytes; rendering runs straight-line immediate stores.
expand_cars:
    lda #$56
    sta $FFDF
    lda #$45
    sta expand_bank
@bank:
    sec
    sbc #$45
    tax
    lda expand_lo,x
    sta src
    lda expand_hi,x
    sta src+1
    lda #0
    sta dst
    lda #$20
    sta dst+1
@token:
    jsr expand_read
    beq @done
    bmi @match
    sta count
@literal:
    jsr expand_read
    jsr expand_write
    dec count
    bne @literal
    beq @token
@match:
    and #127
    clc
    adc #3
    sta count
    jsr expand_read
    sta tmp
    jsr expand_read
    sta height
    sec
    lda dst
    sbc tmp
    sta str
    lda dst+1
    sbc height
    sta str+1
    lda expand_bank
    sta $FFEF
@copy:
    ldy #0
    lda (str),y
    jsr expand_write
    inc str
    bne :+
    inc str+1
:
    dec count
    bne @copy
    jmp @token
@done:
    inc expand_bank
    lda expand_bank
    cmp #$47
    bne @bank
    lda #$40
    sta $FFEF
    lda #$76
    sta $FFDF
    rts
expand_read:
    lda #$42
    sta $FFEF
    ldy #0
    lda (src),y
    inc src
    bne :+
    inc src+1
:
    cmp #0
    rts
expand_write:
    ldx expand_bank
    stx $FFEF
    ldy #0
    sta (dst),y
    inc dst
    bne :+
    inc dst+1
:
    rts
irq:
    pha
    txa
    pha
    lda $FFE4                 ; acknowledge timer 1, never the joystick timer
    inc _irq_ticks
    bne :+
    inc _irq_ticks+1
:
    lda _pcm_remaining
    ora _pcm_remaining+1
    beq @engine
    ; PCM reads only the system-bank cache; asset banking cannot interrupt it.
    tya
    pha
    ldy #0
    lda (pcm),y
    tax
    inc pcm
    bne :+
    inc pcm+1
:
    lda _pcm_remaining
    bne :+
    dec _pcm_remaining+1
:
    dec _pcm_remaining
    pla
    tay
    txa
    jmp @output
@engine:
    lda _engine_on
    beq @quiet
    lda phase
    clc
    adc _engine_pitch
    sta phase
    lsr a
    lsr a
    lsr a
    lsr a
    tax
    lda waveform,x
    jmp @output
@quiet:
    lda #32
@output:
    ldx _muted
    beq :+
    lda #32
:
    sta $FFE0
    pla
    tax
    pla
nmi:
    rti
_clock_read:
    sei
    lda _irq_ticks
    ldx _irq_ticks+1
    cli
    rts
_wait_frame:
    lda #8
    sta $FFED
:
    lda $FFED
    and #8
    beq :-
    rts
_present:
    jsr _wait_frame
    lda _page
    beq @first
    bit $C055
    lda #0
    sta _page
    rts
@first:
    bit $C054
    lda #$40
    sta _page
    rts
; row is a scanline, dst/attr point to the hidden graphics page.
address:
    ldx row
    lda row_lo,x
    sta dst
    sta attr
    lda row_hi,x
    clc
    adc _page
    sta dst+1
    clc
    adc #$20
    sta attr+1
    rts
copy:
    ldy #0
    ldx count+1
    beq @tail
@page:
    lda (src),y
    sta (dst),y
    iny
    bne @page
    inc src+1
    inc dst+1
    dex
    bne @page
@tail:
    cpy count
    beq @done
@byte:
    lda (src),y
    sta (dst),y
    iny
    cpy count
    bne @byte
@done:
    tya
    clc
    adc src
    sta src
    bcc :+
    inc src+1
:
    tya
    clc
    adc dst
    sta dst
    bcc :+
    inc dst+1
:
    rts
_scene_init:
    lda #$40
    sta $FFEF
    lda #0
    sta dst
    lda #$20
    clc
    adc _page
    sta dst+1
    ldx #$40
    ldy #0
    lda #0
@clear:
    sta (dst),y
    iny
    bne @clear
    inc dst+1
    dex
    bne @clear
    ; The road renderer subsequently changes only displaced edges and stripes.
    ldx _scene
    lda grounds,x
    sta ground
    lda #64
    sta row
@ground:
    jsr address
    lda ground
    ldy #39
@groundbyte:
    sta (attr),y
    dey
    bpl @groundbyte
    inc row
    lda row
    cmp #176
    bne @ground
    lda #1
    sta initial
    sta initial+1
    ; One skyline is 40 rows of pixels and attributes in bank four.
    lda #$44
    sta $FFEF
    ldx _scene
    lda sky_lo,x
    sta src
    lda sky_hi,x
    sta src+1
    lda #24
    sta row
@sky:
    lda #<cache
    sta dst
    lda #>cache
    sta dst+1
    lda #80
    sta count
    lda #0
    sta count+1
    jsr copy
    lda #$40
    sta $FFEF
    jsr address
    ldy #39
@skybyte:
    lda cache,y
    sta (dst),y
    lda cache+40,y
    sta (attr),y
    dey
    bpl @skybyte
    inc row
    lda #$44
    sta $FFEF
    lda row
    cmp #64
    bne @sky
    lda #$40
    sta $FFEF
    ; Clear previous edge positions to valid columns for both page histories.
    lda #0
    ldx #0
@previous:
    sta previous,x
    sta previous+256,x
    sta previous+512,x
    sta previous+528,x
    inx
    bne @previous
    jmp sprite_reset
_road_load:
    inc revision
    ldx _hill
    lda hill_lo,x
    sta str
    sta hill_read+1
    lda hill_hi,x
    sta str+1
    sta hill_read+2
    ldx _road_pose
    lda road_lo,x
    sta src
    lda road_hi,x
    sta src+1
    lda #<_geom
    sta road_store+1
    lda #>_geom
    sta road_store+2
    lda #7
    sta height
    lda #$41
    sta $FFEF
road_field:
    ldx #55
road_row:
hill_read:
    ldy $FFFF,x
    lda (src),y
road_store:
    sta $FFFF,x
    dex
    bpl road_row
    clc
    lda src
    adc #56
    sta src
    bcc :+
    inc src+1
:
    clc
    lda road_store+1
    adc #56
    sta road_store+1
    bcc :+
    inc road_store+2
:
    dec height
    bne road_field
    ; The same hill mapping selects precomputed horizontal footprints.
    ldx _road_pose
    lda mark_lo,x
    sta src
    lda mark_hi,x
    sta src+1
    lda #$45
    sta $FFEF
    ldx #55
@marks:
    txa
    tay
    lda (str),y
    tay
    lda (src),y
    sta road_marks,x
    dex
    bpl @marks
    lda #$40
    sta $FFEF
    rts
_road_prepare:
    lda #<previous_marks
    sta count
    lda #>previous_marks
    sta count+1
    lda #<previous
    sta old
    lda #>previous
    sta old+1
    lda _page
    beq :+
    clc
    lda old
    adc #<392
    sta old
    lda old+1
    adc #>392
    sta old+1
    clc
    lda count
    adc #56
    sta count
    bcc :+
    inc count+1
:
    ldx #0
    lda _page
    beq :+
    inx
:
    lda #0
    sta dirty
    lda revision
    cmp old_revision,x
    beq :+
    inc dirty
:
    lda initial,x
    beq :+
    lda #2
    sta dirty
:
    lda revision
    sta old_revision,x
    lda #0
    sta initial,x
    lda dirty
    sta geometry_dirty
    ldx _scene
    lda grounds,x
    sta ground
    ; The seventh history field stores stripe phase; object projection uses
    ; only the current geometry's seventh field (its road center).
    clc
    lda old
    adc #<336
    sta str
    lda old+1
    adc #>336
    sta str+1
    ldx #0
@band:
    lda dirty
    cmp #2
    beq @full
    lda #0
    sta tmp
    lda dirty
    beq @stripe
    ; Compare six geometry fields, leaving the previous page intact until
    ; erased sprite rectangles and displaced road edges have been restored.
    txa
    tay
    lda _geom+0,x
    cmp (old),y
    bne @geometry
    tya
    clc
    adc #56
    tay
    lda _geom+56,x
    cmp (old),y
    bne @geometry
    tya
    clc
    adc #56
    tay
    lda _geom+112,x
    cmp (old),y
    bne @geometry
    tya
    clc
    adc #56
    tay
    lda _geom+168,x
    cmp (old),y
    bne @geometry
    clc
    lda old
    adc #<224
    sta src
    lda old+1
    adc #>224
    sta src+1
    txa
    tay
    lda _geom+224,x
    cmp (src),y
    bne @geometry
    tya
    clc
    adc #56
    tay
    lda _geom+280,x
    cmp (src),y
    beq @stripe
@geometry:
    lda #2
    sta tmp
    bne @stripe
@full:
    lda #3
    sta tmp
@stripe:
    txa
    tay
    lda stripe_depth,x
    clc
    adc _road_phase
    and #8
    cmp (str),y
    beq :+
    ldy tmp
    bne :+
    inc tmp
:
    txa
    tay
    lda stripe_depth,x
    clc
    adc _road_phase
    and #8
    sta (str),y
    lda tmp
    sta _road_damage,x
    beq @mask_ready
    cmp #3
    beq @all_columns
    lda road_marks,x
    ldy tmp
    cpy #2
    bne @mask_ready
    txa
    tay
    lda (count),y
    ora road_marks,x
    sta fill
    lda (old),y
    tay
    lda column_left,y
    ldy _geom,x
    eor column_left,y
    ora fill
    sta fill
    txa
    clc
    adc #56
    tay
    lda (old),y
    tay
    lda column_left,y
    ldy _geom+56,x
    eor column_left,y
    ora fill
    jmp @mask_ready
@all_columns:
    lda #255
@mask_ready:
    sta damage_columns,x
    txa
    tay
    lda road_marks,x
    sta (count),y
    inx
    cpx #56
    beq :+
    jmp @band
:
    rts
_road_draw:
    lda #64
    sta row
    lda #0
    sta band
@row:
    ldx band
    lda _road_damage,x
    bne :+
    jmp @next
:
    sec
    sbc #1
    sta dirty
    jsr address
    lda dst
    sta dst2
    sta attr2
    lda dst+1
    clc
    adc #4
    sta dst2+1
    lda attr+1
    clc
    adc #4
    sta attr2+1
    ldx band
    lda _geom,x
    sta left
    lda _geom+56,x
    sta right
    lda dirty
    beq @same_geometry
    cmp #3
    bne :+
@same_geometry:
    jmp @edges
:
    ldy band
    lda (old),y
    sta oldleft
    tya
    clc
    adc #56
    tay
    lda (old),y
    sta oldright
    lda dirty
    cmp #2
    bne @changes
    ldy #39
    lda ground
@grass:
    sta (attr),y
    sta (attr2),y
    dey
    bpl @grass
    ldy right
    lda #$55
@asphalt:
    sta (attr),y
    sta (attr2),y
    cpy left
    beq @clear_edges
    dey
    bpl @asphalt
@changes:
    ; Fill only the strips exposed or covered by a changing road boundary.
    ldy oldleft
    cpy left
    beq @rightchange
    bcc @leftgrass
    ldy left
    lda #$55
    sta fill
    lda oldleft
    sta tmp
    jsr span
    jmp @rightchange
@leftgrass:
    lda ground
    sta fill
    lda left
    sta tmp
    jsr span
@rightchange:
    ldy oldright
    cpy right
    beq @clear_edges
    bcc @rightroad
    ldy right
    lda ground
    sta fill
    lda oldright
    sta tmp
    jsr span
    jmp @clear_edges
@rightroad:
    ; A sharp camera move can put the entire new road beyond the old one.
    ; Do not paint the gap between the two roads as asphalt.
    cpy left
    bcs :+
    ldy left
:
    lda #$55
    sta fill
    lda right
    sta tmp
    jsr span
@clear_edges:
    ldy oldleft
    cpy left
    beq @oldright
    jsr erase_road_pixel
    iny
    cpy #40
    bcs :+
    jsr erase_road_pixel
:
@oldright:
    ldy oldright
    cpy right
    beq @oldlanes
    jsr erase_road_pixel
    dey
    bmi :+
    jsr erase_road_pixel
:
@oldlanes:
    lda old
    clc
    adc #224
    sta str
    lda old+1
    adc #0
    sta str+1
    ldx band
    ldy band
    lda (str),y
    cmp _geom+224,x
    beq :+
    tay
    jsr erase_road_pixel
:
    ldy band
    tya
    clc
    adc #56
    tay
    lda (str),y
    cmp _geom+280,x
    beq :+
    tay
    jsr erase_road_pixel
:
    ldx band
@edges:
    ldy _geom+224,x
    lda #0
    sta (dst),y
    sta (dst2),y
    lda #$55
    sta (attr),y
    sta (attr2),y
    ldy _geom+280,x
    lda #0
    sta (dst),y
    sta (dst2),y
    lda #$55
    sta (attr),y
    sta (attr2),y
    lda dirty
    bne @edge_pixels
    ; Clipped lane markers can share an edge cell. Clearing a lane then
    ; skipping its edge mask would leave a hole even on a stripe-only update.
    lda _geom+224,x
    cmp left
    beq @edge_pixels
    cmp right
    beq @edge_pixels
    lda _geom+280,x
    cmp left
    beq @edge_pixels
    cmp right
    bne @stripes
@edge_pixels:
    lda ground
    and #15
    ora #$50
    ldy left
    sta (attr),y
    sta (attr2),y
    lda _geom+112,x
    sta (dst),y
    sta (dst2),y
    ldy right
    lda ground
    and #15
    ora #$50
    sta (attr),y
    sta (attr2),y
    lda _geom+168,x
    sta (dst),y
    sta (dst2),y
@stripes:
    lda stripe_depth,x
    clc
    adc _road_phase
    and #8
    beq @white
    lda #$95
    bne @curb
@white:
    lda #$F5
@curb:
    sta curb
    ldy left
    iny
    cpy right
    bcs @next
    sta (attr),y
    sta (attr2),y
    lda #3
    sta (dst),y
    sta (dst2),y
    ldy right
    dey
    lda curb
    sta (attr),y
    sta (attr2),y
    lda #$60
    sta (dst),y
    sta (dst2),y
    lda curb
    cmp #$F5
    bne @next
    ldy _geom+224,x
    lda #8
    sta (dst),y
    sta (dst2),y
    lda #$F5
    sta (attr),y
    sta (attr2),y
    ldy _geom+280,x
    lda #8
    sta (dst),y
    sta (dst2),y
    lda #$F5
    sta (attr),y
    sta (attr2),y
@next:
    inc row
    inc row
    inc band
    lda band
    cmp #56
    beq @done
@row_jump:
    jmp @row
@done:
    lda geometry_dirty
    bne :+
    rts
:
    lda #<_geom
    sta src
    lda #>_geom
    sta src+1
    lda old
    sta dst
    lda old+1
    sta dst+1
    lda #<336
    sta count
    lda #>336
    sta count+1
    jmp copy
; Span is inclusive; final edge drawing supplies exact seven-pixel masks.
span:
    lda fill
:
    sta (attr),y
    sta (attr2),y
    cpy tmp
    beq :+
    iny
    bne :-
:
    rts
erase_road_pixel:
    lda #0
    sta (dst),y
    sta (dst2),y
    lda ground
    cpy left
    bcc :+
    cpy right
    bcs :+
    lda #$55
:
    sta (attr),y
    sta (attr2),y
    rts
erase_pixel:
    lda #0
    sta (dst),y
    lda ground
    cpy left
    bcc :+
    cpy right
    bcs :+
    lda #$55
:
    sta (attr),y
    rts
; Eight five-column regions keep horizontal damage cheap on a 6502. Road
; stripes touch just their regions; sprites propagate damage in painter order.
object_bounds:
    ldy _object_x
    lda column_left,y
    sta object_mask
    tya
    clc
    adc _object_w
    tay
    dey
    lda column_right,y
    and object_mask
    sta object_mask
    lda _object_y
    sec
    sbc #64
    lsr a
    tax
    lda _object_y
    clc
    adc _object_h
    sec
    sbc #65
    lsr a
    tay
    rts
_object_damaged:
    lda _object_full
    beq @partial
    lda flags_full
    bne @full_ready
    lda #1
    sta flags_full
    ldx #24
@full_flags:
    sta $0700,x
    dex
    bpl @full_flags
@full_ready:
    lda #1
    ldx #0
    rts
@partial:
    lda #0
    sta flags_full
    jsr object_bounds
    stx band
    lda _object_y
    and #1
    sta row
    lda _object_h
    sta height
    lda #0
    sta object_any
    ldx #0
@pair:
    ldy band
    lda damage_columns,y
    sta tmp
    lda row
    beq @test
    lda height
    cmp #2
    bcc @test
    lda damage_columns+1,y
    ora tmp
    sta tmp
@test:
    lda tmp
    and object_mask
    beq @flag
@hit:
    lda #1
    sta object_any
@flag:
    sta $0700,x
    inx
    inc band
    dec height
    beq @done
    dec height
    bne @pair
@done:
    lda object_any
    ldx #0
    rts
_object_damage:
    lda _object_full
    bne damage_whole
    jsr object_bounds
    stx band
    lda _object_y
    and #1
    sta row
    lda _object_h
    sta height
    ldx #0
@pair:
    lda $0700,x
    beq @next
    ldy band
    lda damage_columns,y
    ora object_mask
    sta damage_columns,y
    lda row
    beq @next
    lda height
    cmp #2
    bcc @next
    lda damage_columns+1,y
    ora object_mask
    sta damage_columns+1,y
@next:
    inx
    inc band
    dec height
    beq @done
    dec height
    bne @pair
@done:
    rts
damage_whole:
    jsr object_bounds
@band:
    lda damage_columns,y
    ora object_mask
    sta damage_columns,y
    sty tmp
    cpx tmp
    beq @done
    dey
    bpl @band
@done:
    rts
erase_damage:
    jsr damage_whole
    jsr object_bounds
@band:
    lda _road_damage,y
    cmp #2
    bcs :+
    lda road_marks,y
    and object_mask
    beq :+
    lda #4                  ; only erasure touching decorations needs repair
    sta _road_damage,y
    lda damage_columns,y
    ora road_marks,y
    sta damage_columns,y
:
    sty tmp
    cpx tmp
    beq @done
    dey
    bpl @band
@done:
    rts
_object_erase:
    jsr erase_damage
    ldx _object_w
    lda erase_attr_lo,x
    sta src
    lda erase_attr_hi,x
    sta src+1
    lda erase_pixel_lo,x
    sta str
    lda erase_pixel_hi,x
    sta str+1
    lda _object_y
    sta row
    lda _object_h
    sta height
@row:
    jsr address
    lda row
    sec
    sbc #64
    lsr a
    tax
    lda _geom,x
    sta left
    lda _geom+56,x
    sta right
    lda _object_x
    clc
    adc _object_w
    sec
    sbc #1
    cmp left
    bcc @grass
    lda _object_x
    cmp right
    bcs @grass
    cmp left
    bcc @mixed
    clc
    adc _object_w
    cmp right
    bcs @mixed
    lda #$55
    bne @flat
@grass:
    lda ground
@flat:
    ldy _object_x
    jsr erase_flat
    jmp @next
@mixed:
    ldy _object_x
    ldx _object_w
@byte:
    jsr erase_pixel
    iny
    dex
    bne @byte
@next:
    inc row
    dec height
    bne @row
    rts
; Width selects a suffix of these straight-line stores. Color and pixel
; bytes each load A once for the whole span, with no per-byte branch.
erase_flat:
    jmp (src)
.repeat 30, n
.ident(.sprintf("erase_attr_%d", 30-n)):
    sta (attr),y
    iny
.endrepeat
erase_attr_0:
    ldy _object_x
    lda #0
    jmp (str)
.repeat 30, n
.ident(.sprintf("erase_pixel_%d", 30-n)):
    sta (dst),y
    iny
.endrepeat
erase_pixel_0:
    rts
_object_draw:
    ; Car tables stay in their own private zero pages. Scenery borrows $18.
    ; Generated code uses immediate colors and skips untouched pairs of rows.
    ldx _object_id
    lda asset_w,x
    sta _object_w
    lda asset_h,x
    sta _object_h
    sta height
    lda asset_lo,x
    sta blit_vector
    lda asset_hi,x
    sta blit_vector+1
    lda _object_y
    sta row
    ldx _object_slot
    lda pointer_pages,x
    sta pointer_page
    sta pointer_cache+1
    lda #0
    sta pointer_cache
    lda _object_id
    cmp #64
    bcc @car_cache
    ; Scenery and gates borrow page $18; invalidate its resident traffic car.
    lda #255
    sta pointer_x
    jmp @build
@car_cache:
    lda _object_x
    cmp pointer_x,x
    bne @build
    lda _object_y
    cmp pointer_y,x
    bne @build
    lda pointer_h,x
    cmp height
    bcs @draw
@build:
    lda _object_x
    sta pointer_x,x
    lda _object_y
    sta pointer_y,x
    lda height
    sta pointer_h,x
    ldy #0
    clc
@pointers:
    ldx row
    ; Native row starts plus a valid column never cross a 256-byte boundary.
    lda row_lo,x
    adc _object_x
    sta (pointer_cache),y
    iny
    lda row_hi,x
    ora _page
    sta (pointer_cache),y
    iny
    lda row_lo,x
    adc _object_x
    sta (pointer_cache),y
    iny
    lda row_hi,x
    ora _page
    adc #$20
    sta (pointer_cache),y
    iny
    inc row
    dec height
    bne @pointers
@draw:
    ldx _object_id
    lda asset_bank,x
    ora #$40
    sta $FFEF
    lda pointer_page
    sta $FFD0
    jsr blit_jump
    lda #0
    sta $FFD0
    lda #$40
    sta $FFEF
    rts
blit_jump:
    jmp (blit_vector)
; HUD digits always occupy scanlines 0..7. Native row addresses can be
; baked into stores; the general text routine still handles other labels.
_digit_draw:
    ora #$30
    tax
    lda font_lo,x
    sta src
    lda font_hi,x
    sta src+1
    ldx _gfx_x
    lda _page
    beq @first
    .repeat 8, scanline
    ldy #scanline
    lda (src),y
    sta $6000+scanline*$400,x
    lda _gfx_color
    sta $8000+scanline*$400,x
    .endrepeat
    rts
@first:
    .repeat 8, scanline
    ldy #scanline
    lda (src),y
    sta $2000+scanline*$400,x
    lda _gfx_color
    sta $4000+scanline*$400,x
    .endrepeat
    rts
_text:
    sta str
    stx str+1
    lda _gfx_x
    sta col
@char:
    ldy #0
    lda (str),y
    beq @done
    and #63
    tax
    lda font_lo,x
    sta src
    lda font_hi,x
    sta src+1
    lda _gfx_y
    sta row
    lda #0
    sta height
@row:
    jsr address
    ldy height
    lda (src),y
    ldy col
    sta (dst),y
    lda _gfx_color
    sta (attr),y
    inc row
    inc height
    lda height
    cmp #8
    bne @row
    inc str
    bne :+
    inc str+1
:
    inc col
    lda col
    cmp #40
    bcc @char
@done:
    rts
_say_ready:
    lda #$44
    sta $FFEF
    lda #<voice_address
    sta src
    lda #>voice_address
    sta src+1
    lda #<cache
    sta dst
    lda #>cache
    sta dst+1
    lda #0
    sta count
    lda #8
    sta count+1
    jsr copy
    lda #$40
    sta $FFEF
    sei
    lda #<cache
    sta pcm
    lda #>cache
    sta pcm+1
    lda #0
    sta _pcm_remaining
    lda #8
    sta _pcm_remaining+1
    cli
@wait:
    lda _pcm_remaining
    ora _pcm_remaining+1
    bne @wait
    ; PCM overwrites the sister-byte tags; restore them before any drawing.
    jmp sprite_reset
sprite_reset:
    lda #255
    ldx #17
:
    sta pointer_x,x
    dex
    bpl :-
    ; Tags select bank-zero graphics from any of the eight private zero
    ; pages. Speech and skyline loading reuse this scratch, then reset it.
    ldx #0
    lda #$8F
:
    .repeat 8, p
    sta $1000+p*$100,x
    .endrepeat
    inx
    bne :-
    rts
.segment "RODATA"
grounds: .byte $44,$88,$00,$22
sky_lo: .byte <$2000,<$2C80,<$3900,<$4580
sky_hi: .byte >$2000,>$2C80,>$3900,>$4580

; Slots 0..2 cars, 3..4 tall scenery, 5..6 signs, 7 player, 8 gate.
pointer_pages: .byte $18,$19,$1A,$18,$18,$18,$18,$1B,$18,$1C,$1D,$1E,$18,$18,$18,$18,$1F,$18
erase_attr_lo: .byte <erase_attr_0,<erase_attr_1,<erase_attr_2,<erase_attr_3,<erase_attr_4,<erase_attr_5,<erase_attr_6,<erase_attr_7,<erase_attr_8,<erase_attr_9,<erase_attr_10,<erase_attr_11,<erase_attr_12,<erase_attr_13,<erase_attr_14,<erase_attr_15,<erase_attr_16,<erase_attr_17,<erase_attr_18,<erase_attr_19,<erase_attr_20,<erase_attr_21,<erase_attr_22,<erase_attr_23,<erase_attr_24,<erase_attr_25,<erase_attr_26,<erase_attr_27,<erase_attr_28,<erase_attr_29,<erase_attr_30
erase_attr_hi: .byte >erase_attr_0,>erase_attr_1,>erase_attr_2,>erase_attr_3,>erase_attr_4,>erase_attr_5,>erase_attr_6,>erase_attr_7,>erase_attr_8,>erase_attr_9,>erase_attr_10,>erase_attr_11,>erase_attr_12,>erase_attr_13,>erase_attr_14,>erase_attr_15,>erase_attr_16,>erase_attr_17,>erase_attr_18,>erase_attr_19,>erase_attr_20,>erase_attr_21,>erase_attr_22,>erase_attr_23,>erase_attr_24,>erase_attr_25,>erase_attr_26,>erase_attr_27,>erase_attr_28,>erase_attr_29,>erase_attr_30
erase_pixel_lo: .byte <erase_pixel_0,<erase_pixel_1,<erase_pixel_2,<erase_pixel_3,<erase_pixel_4,<erase_pixel_5,<erase_pixel_6,<erase_pixel_7,<erase_pixel_8,<erase_pixel_9,<erase_pixel_10,<erase_pixel_11,<erase_pixel_12,<erase_pixel_13,<erase_pixel_14,<erase_pixel_15,<erase_pixel_16,<erase_pixel_17,<erase_pixel_18,<erase_pixel_19,<erase_pixel_20,<erase_pixel_21,<erase_pixel_22,<erase_pixel_23,<erase_pixel_24,<erase_pixel_25,<erase_pixel_26,<erase_pixel_27,<erase_pixel_28,<erase_pixel_29,<erase_pixel_30
erase_pixel_hi: .byte >erase_pixel_0,>erase_pixel_1,>erase_pixel_2,>erase_pixel_3,>erase_pixel_4,>erase_pixel_5,>erase_pixel_6,>erase_pixel_7,>erase_pixel_8,>erase_pixel_9,>erase_pixel_10,>erase_pixel_11,>erase_pixel_12,>erase_pixel_13,>erase_pixel_14,>erase_pixel_15,>erase_pixel_16,>erase_pixel_17,>erase_pixel_18,>erase_pixel_19,>erase_pixel_20,>erase_pixel_21,>erase_pixel_22,>erase_pixel_23,>erase_pixel_24,>erase_pixel_25,>erase_pixel_26,>erase_pixel_27,>erase_pixel_28,>erase_pixel_29,>erase_pixel_30
