.setcpu "6502"
.export __STARTUP__ : absolute = 1
.export _engine_init,_scene_init,_road_load,_road_draw,_object_draw,_object_erase
.export _digit_draw
.export _road_prepare,_road_damage,_object_damaged,_object_damage,_object_slot
.export _present,_wait_frame,_clock_read,_say_ready,_text
.export _page,_scene,_road_phase,_road_pose,_engine_pitch,_engine_on,_muted
.export _object_id,_object_x,_object_y,_object_w,_object_h,_geom
.export _gfx_x,_gfx_y,_gfx_color,_irq_ticks,_pcm_remaining
.import _main,zerobss,_hill
.importzp sp
.import hill_lo,hill_hi
.import road_lo,road_hi,asset_bank,asset_lo,asset_hi,asset_w,asset_h
.import asset_size_lo,asset_size_hi,row_lo,row_hi,stripe_depth,waveform
.import font_lo,font_hi,voice_address
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
_geom: .res 392
previous: .res 784
pointer_x: .res 18
pointer_y: .res 18
pointer_h: .res 18
pointer_slot: .res 1
pointer_rows: .res 1
cache: .res 2048
blit_vector: .res 2
.assert cache <= $1400 && cache+2048 >= $1500, lderror, "Sister bytes must stay inside disposable PCM scratch"
.assert cache+1264 <= $1400, lderror, "Sprite pointers must not overlap sister bytes"
.segment "SPRITECACHE"
cache_first: .res 1264
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
    lda #<$2000
    sta sp
    lda #>$2000
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
    jsr sprite_reset
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
    rts
_road_load:
    inc revision
    ldx _hill
    lda hill_lo,x
    sta hill_read+1
    lda hill_hi,x
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
    lda #$40
    sta $FFEF
    rts
_road_prepare:
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
; Carrying damage forward in painter order also redraws unchanged foreground
; objects touched by an earlier object. Row granularity is conservative in X.
object_bands:
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
    jsr object_bands
@band:
    lda _road_damage,y
    bne @yes
    sty tmp
    cpx tmp
    beq @no
    dey
    bpl @band
@no:
    lda #0
    tax
    rts
@yes:
    lda #1
    ldx #0
    rts
_object_damage:
    jsr object_bands
@band:
    lda _road_damage,y
    cmp #2
    bcs :+
    lda #4                  ; erased pixels need edges as well as stripes
    sta _road_damage,y
:
    sty tmp
    cpx tmp
    beq @done
    dey
    bpl @band
@done:
    rts
_object_erase:
    jsr _object_damage
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
    ; Set up row pointers in the private extended-address zero page. Generated
    ; sprite code consists of immediate pixel values and unrolled stores.
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
    lda pointer_lo,x
    sta pointer_cache
    lda pointer_hi,x
    sta pointer_cache+1
    lda _object_x
    cmp pointer_x,x
    bne @build
    lda _object_y
    cmp pointer_y,x
    bne @build
    lda pointer_h,x
    cmp height
    bcc @build
    cpx pointer_slot
    bne @copy_cache
    lda pointer_rows
    cmp height
    bcs @draw
    ; A cached table already contains this page's exact native addresses.
    ; Four bytes per row: pixel pointer, attribute pointer.
@copy_cache:
    ldy #0
@cached:
    .repeat 4
    lda (pointer_cache),y
    sta $1800,y
    iny
    .endrepeat
    dec height
    bne @cached
    beq @ready
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
    ; Row starts plus a valid column never cross a 256-byte boundary.
    lda row_lo,x
    adc _object_x
    sta $1800,y
    sta (pointer_cache),y
    iny
    lda row_hi,x
    ora _page
    sta $1800,y
    sta (pointer_cache),y
    iny
    lda row_lo,x
    adc _object_x
    sta $1800,y
    sta (pointer_cache),y
    iny
    lda row_hi,x
    ora _page
    adc #$20
    sta $1800,y
    sta (pointer_cache),y
    iny
    inc row
    dec height
    bne @pointers
@ready:
    lda _object_slot
    sta pointer_slot
    lda _object_h
    sta pointer_rows
@draw:
    ldx _object_id
    lda asset_bank,x
    ora #$40
    sta $FFEF
    lda #$18
    sta $FFD0
    txa
    lsr a
    lsr a
    lsr a
    lsr a
    and #3
    tax
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
    ; PCM shares disposable scratch with page-two address tables.
    jmp sprite_reset
sprite_reset:
    lda #255
    sta pointer_slot
    ldx #17
:
    sta pointer_x,x
    dex
    bpl :-
    ; These extended-address tags are invariant across every sprite/page.
    ; Only speech can overwrite them; skylines use the first 80 cache bytes.
    ldx #0
    lda #$8F
:
    sta $1400,x
    inx
    bne :-
    rts
.segment "RODATA"
grounds: .byte $44,$88,$00,$22
sky_lo: .byte <$2000,<$2C80,<$3900,<$4580
sky_hi: .byte >$2000,>$2C80,>$3900,>$4580

; Slots 0..2 cars, 3..4 tall scenery, 5..6 signs, 7 player, 8 gate.
pointer_lo: .byte <(cache_first+0),<(cache_first+136),<(cache_first+272),<(cache_first+408),<(cache_first+608),<(cache_first+808),<(cache_first+944),<(cache_first+1080),<(cache_first+1216),<(cache+0),<(cache+136),<(cache+272),<(cache+408),<(cache+608),<(cache+808),<(cache+944),<(cache+1080),<(cache+1216)
pointer_hi: .byte >(cache_first+0),>(cache_first+136),>(cache_first+272),>(cache_first+408),>(cache_first+608),>(cache_first+808),>(cache_first+944),>(cache_first+1080),>(cache_first+1216),>(cache+0),>(cache+136),>(cache+272),>(cache+408),>(cache+608),>(cache+808),>(cache+944),>(cache+1080),>(cache+1216)
erase_attr_lo: .byte <erase_attr_0,<erase_attr_1,<erase_attr_2,<erase_attr_3,<erase_attr_4,<erase_attr_5,<erase_attr_6,<erase_attr_7,<erase_attr_8,<erase_attr_9,<erase_attr_10,<erase_attr_11,<erase_attr_12,<erase_attr_13,<erase_attr_14,<erase_attr_15,<erase_attr_16,<erase_attr_17,<erase_attr_18,<erase_attr_19,<erase_attr_20,<erase_attr_21,<erase_attr_22,<erase_attr_23,<erase_attr_24,<erase_attr_25,<erase_attr_26,<erase_attr_27,<erase_attr_28,<erase_attr_29,<erase_attr_30
erase_attr_hi: .byte >erase_attr_0,>erase_attr_1,>erase_attr_2,>erase_attr_3,>erase_attr_4,>erase_attr_5,>erase_attr_6,>erase_attr_7,>erase_attr_8,>erase_attr_9,>erase_attr_10,>erase_attr_11,>erase_attr_12,>erase_attr_13,>erase_attr_14,>erase_attr_15,>erase_attr_16,>erase_attr_17,>erase_attr_18,>erase_attr_19,>erase_attr_20,>erase_attr_21,>erase_attr_22,>erase_attr_23,>erase_attr_24,>erase_attr_25,>erase_attr_26,>erase_attr_27,>erase_attr_28,>erase_attr_29,>erase_attr_30
erase_pixel_lo: .byte <erase_pixel_0,<erase_pixel_1,<erase_pixel_2,<erase_pixel_3,<erase_pixel_4,<erase_pixel_5,<erase_pixel_6,<erase_pixel_7,<erase_pixel_8,<erase_pixel_9,<erase_pixel_10,<erase_pixel_11,<erase_pixel_12,<erase_pixel_13,<erase_pixel_14,<erase_pixel_15,<erase_pixel_16,<erase_pixel_17,<erase_pixel_18,<erase_pixel_19,<erase_pixel_20,<erase_pixel_21,<erase_pixel_22,<erase_pixel_23,<erase_pixel_24,<erase_pixel_25,<erase_pixel_26,<erase_pixel_27,<erase_pixel_28,<erase_pixel_29,<erase_pixel_30
erase_pixel_hi: .byte >erase_pixel_0,>erase_pixel_1,>erase_pixel_2,>erase_pixel_3,>erase_pixel_4,>erase_pixel_5,>erase_pixel_6,>erase_pixel_7,>erase_pixel_8,>erase_pixel_9,>erase_pixel_10,>erase_pixel_11,>erase_pixel_12,>erase_pixel_13,>erase_pixel_14,>erase_pixel_15,>erase_pixel_16,>erase_pixel_17,>erase_pixel_18,>erase_pixel_19,>erase_pixel_20,>erase_pixel_21,>erase_pixel_22,>erase_pixel_23,>erase_pixel_24,>erase_pixel_25,>erase_pixel_26,>erase_pixel_27,>erase_pixel_28,>erase_pixel_29,>erase_pixel_30
