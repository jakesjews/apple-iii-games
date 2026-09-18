#!/usr/bin/env python3
"""Original raster art and perspective tables; no runtime sprite scaling."""
import json
import math
from pathlib import Path

OUT = Path('build/highway')
OUT.mkdir(parents=True, exist_ok=True)

def emit(name, values):
    return f'.export {name}\n{name}:\n' + '\n'.join('.byte '+','.join(map(str,values[i:i+24])) for i in range(0,len(values),24))+'\n'

def offset(y):
    return (y%8)*1024+(y//8%8)*128+(y//64)*40

# 81 road poses: nine bends by nine lateral camera positions, 56 two-line bands.
road = bytearray()
road_addresses = []
road_marks = bytearray()
for curve in range(-4,5):
    for player in range(-4,5):
        road_addresses.append(0x2000+len(road))
        fields = [[] for _ in range(7)]
        for row in range(56):
            depth = row/55
            center = 140 + curve*11*(1-depth)**2 - player*13*depth
            radius = 4 + 143*depth**1.35
            left = max(0,min(278,round(center-radius)))
            right = max(left+1,min(279,round(center+radius)))
            vals = [left//7,right//7,127 & (127 << (left%7)),(1 << (right%7+1))-1,
                    max(0,min(39,round(center-radius/3)//7)),
                    max(0,min(39,round(center+radius/3)//7)), round(center)//7]
            for arr,val in zip(fields,vals): arr.append(val)
        road.extend(v for arr in fields for v in arr)
        for row in range(56):
            columns=(fields[0][row],fields[0][row]+1,fields[1][row],fields[1][row]-1,fields[4][row],fields[5][row])
            road_marks.append(sum(1<<region for region in {x//5 for x in columns if 0<=x<40}))
assert len(road) == 31752
banks = [road.ljust(32768,b'\0'), bytearray(), bytearray(), bytearray()]
meta = []

def raster(kind, w, h, variant=0):
    # Logical source coordinates make every stored size a fresh rasterization.
    img = [[-1]*w for _ in range(h)]
    def rect(x0,y0,x1,y1,c):
        for y in range(max(0,round(y0*h)),min(h,round(y1*h))):
            for x in range(max(0,round(x0*w)),min(w,round(x1*w))): img[y][x]=c
    if kind == 'car':
        body = [9,12,14,11][variant%4]
        rect(.20,.03,.80,.55,body); rect(.08,.38,.92,.87,body)
        rect(.0,.56,.12,1,0); rect(.88,.56,1,1,0)
        rect(.24,.12,.76,.34,6); rect(.29,.16,.71,.27,7)
        rect(.14,.50,.86,.56,15); rect(.14,.60,.86,.72,body)
        rect(.17,.72,.32,.81,9 if variant else 14)
        rect(.68,.72,.83,.81,9 if variant else 14)
        rect(.14,.86,.86,.96,5); rect(.40,.87,.60,.96,15)
        rect(.39,.40,.61,.65,15 if variant==0 else body)
    elif kind == 'palm':
        for y in range(h):
            yy=y/h
            trunk=.47+.16*(yy-.2)**2
            if yy>.2: rect(trunk,yy,trunk+.09,yy+1/h,8)
        for y in range(round(h*.47)):
            for x in range(w):
                xx=(x/w-.5); yy=y/h
                for sign in (-1,1):
                    arc=.08+abs(xx)*.55
                    if abs(yy-arc)<.075 and xx*sign>=0: img[y][x]=12 if y%3 else 4
                if abs(xx)<.1 and yy<.25: img[y][x]=12
    elif kind == 'cactus':
        rect(.43,.02,.61,1,12); rect(.09,.24,.24,.65,4)
        rect(.16,.55,.50,.69,12); rect(.77,.10,.94,.48,12)
        rect(.57,.40,.86,.53,4); rect(.45,.09,.49,.92,13)
    elif kind == 'tower':
        rect(.15,.1,.85,1,2); rect(.3,0,.7,.1,6)
        for y in (.22,.4,.58,.76):
            for x in (.27,.57): rect(x,y,x+.12,y+.08,11)
    elif kind == 'sign':
        rect(.46,.4,.56,1,5); rect(.05,.03,.95,.54,15)
        rect(.10,.08,.90,.48,9)
        for y in range(h):
            for x in range(w):
                if .13<y/h<.44 and abs(x/w-(.48+(.27-y/h)*1.2))<.14: img[y][x]=15
    return img

def pack(img):
    h,w=len(img),len(img[0]); result=bytearray()
    for row in img:
        masks=[]; pixels=[]; colors=[]
        for x in range(0,w,7):
            cell=row[x:x+7]; freq={c:cell.count(c) for c in set(cell) if c>=0}
            if not freq: masks.append(0); pixels.append(0); colors.append(0); continue
            cs=sorted(freq,key=lambda c:(freq[c],c),reverse=True)
            fg=next((c for c in cs if c!=0),cs[0])
            bg=next((c for c in cs if c!=fg),fg)
            mask=sum(1<<i for i,c in enumerate(cell) if c>=0)
            # Boundary cells retain the destination background; interior cells
            # use two opaque colors. Each group obeys the native seven-pixel limit.
            pix=mask if mask!=127 else sum(1<<i for i,c in enumerate(cell) if c==fg)
            masks.append(mask); pixels.append(pix); colors.append((fg<<4)|bg)
        result.extend(masks+pixels+colors)
    return result

# Bank four stores three richly colored skyline strips and the DAC voice sample.
for scene in range(4):
    for y in range(24,64):
        pixels=[]; colors=[]
        for col in range(40):
            sky = ([6,3,9,8][min(3,(y-24)//10)] if scene==0 else
                   [6,2,8,9][min(3,(y-24)//10)] if scene==1 else [0,0,2,6][min(3,(y-24)//10)])
            bits=0; fg=5 if scene==0 else 8 if scene==1 else 2
            for bit in range(7):
                x=col*7+bit
                mountain=53+int(6*math.sin(x*.035)+4*math.sin(x*.087+scene))
                if scene<3 and y>=mountain: bits |= 1<<bit
                elif scene<2 and (x-213)**2+(y-39)**2<100: bits|=1<<bit; fg=13
                elif scene==2 and (x*37+y*71)%193==0: bits|=1<<bit; fg=15
                if scene==3:
                    sky=0; fg=5
                    # Lit ribs recede toward the tunnel mouth.
                    edge=abs(x-140)
                    if edge>125-(y-24)*2 or y<27: bits|=1<<bit
                    if y in (31,32,45,46) and edge<80: bits|=1<<bit; fg=13
            pixels.append(bits); colors.append((fg<<4)|sky)
        banks[3].extend(pixels+colors)
voice_offset=len(banks[3]); voice=Path('games/highway/ready.pcm').read_bytes()
assert len(voice)==2048 and max(voice)<64
banks[3].extend(voice)
# Each pair of rows can be skipped independently through flags in private
# shared flags $0700..$0718. Car colors are immediate operands, not palette reads.
def compiled(img, base, color=None):
    data=pack(img); w=len(img[0])//7; code=bytearray()
    for pair in range(0,len(img),2):
        chunk=bytearray()
        for row in range(pair,min(pair+2,len(img))):
            chunk.extend((0xA0,0))
            for col in range(w):
                mask,pixel,attr=(data[row*w*3+col+k*w] for k in range(3))
                zp=row*4
                if color is not None:
                    fg,bg=attr>>4,attr&15
                    attr=((color if fg==9 else fg)<<4)|(color if bg==9 else bg)
                if mask:
                    if mask==127: chunk.extend((0xA9,pixel,0x91,zp))
                    else: chunk.extend((0xB1,zp,0x29,127^mask,0x09,pixel,0x91,zp))
                    if mask==127: chunk.extend((0xA9,attr))
                    else: chunk.extend((0xB1,zp+2,0x29,15,0x09,attr&240))
                    chunk.extend((0x91,zp+2))
                if col+1<w: chunk.append(0xC8)
        code.extend((0xAD,pair//2,0x07))
        if len(chunk)<=127: code.extend((0xF0,len(chunk)))
        else:
            target=base+len(code)+5+len(chunk)
            code.extend((0xD0,3,0x4C,target&255,target>>8))
        code.extend(chunk)
    code.append(0x60)
    return code

def compress(data):
    """Literal runs (1..127) or backreferences (length 3..130, 16-bit distance).

    Expanded code lives in spare banks five/six; only compressed bytes occupy
    the floppy. Zero terminates the stream. Matches may overlap their source.
    """
    from collections import defaultdict
    positions=defaultdict(list); output=bytearray(); literals=bytearray(); pos=0
    def flush():
        if literals: output.append(len(literals)); output.extend(literals); literals.clear()
    while pos<len(data):
        best=0; distance=0
        for candidate in reversed(positions[bytes(data[pos:pos+3])][-96:]):
            length=3
            while length<130 and pos+length<len(data) and data[candidate+length]==data[pos+length]: length+=1
            if length>best: best=length; distance=pos-candidate
        count=best if best>=4 else 1
        if best>=4:
            flush(); output.extend((128+best-3,distance&255,distance>>8))
        else:
            literals.append(data[pos])
            if len(literals)==127: flush()
        for i in range(pos,pos+count): positions[bytes(data[i:i+3])].append(i)
        pos+=count
    flush(); output.append(0)
    return output

expanded=[bytearray(),bytearray()]
for variant,color in enumerate((1,12,7,13)):
    bank=variant//2
    for scale in range(16):
        cols=1+scale//3; height=4+scale*2
        base=0x2000+len(expanded[bank])
        data=compiled(raster('car',cols*7,height),base,color)
        meta.append((5+bank,base,cols,height,len(data)))
        expanded[bank].extend(data)
# Precompute road footprints too; their 81x56 bytes fit after bank-five cars.
road_mark_addresses=[0x2000+len(expanded[0])+i*56 for i in range(81)]
expanded[0].extend(road_marks)
expand_addresses=[]
for i,data in enumerate(expanded):
    assert len(data)<=32768
    (OUT/f'cars{i+5}.bin').write_bytes(data)
    expand_addresses.append(0x2000+len(banks[1]))
    packed=compress(data); banks[1].extend(packed)
    print(f'Car bank {i+5}: {len(data)} bytes expanded from {len(packed)} bytes')
for kind in ['palm','cactus','tower','sign']:
    for scale in range(16):
        cols=1+scale//4; height=5+scale*3 if kind=='palm' else 4+scale*2
        img=raster(kind,cols*7,height)
        size=len(compiled(img,0))
        bank=next(i for i,capacity in ((1,32768),(2,32768),(3,24576)) if len(banks[i])+size<=capacity)
        data=compiled(img,0x2000+len(banks[bank]))
        meta.append((bank+1,0x2000+len(banks[bank]),cols,height,len(data)))
        banks[bank].extend(data)
for scale,(cols,height) in enumerate(((8,6),(14,8),(22,10),(30,12))):
    img=[[15 if ((x//7)+(y//2))%2 else 0 for x in range(cols*7)] for y in range(height)]
    size=len(compiled(img,0))
    bank=next(i for i,capacity in ((1,32768),(2,32768),(3,24576)) if len(banks[i])+size<=capacity)
    data=compiled(img,0x2000+len(banks[bank]))
    meta.append((bank+1,0x2000+len(banks[bank]),cols,height,len(data)))
    banks[bank].extend(data)
print('Asset bytes by bank:',*[len(b) for b in banks])
for i,size in enumerate((32768,32768,32768,24576)):
    assert len(banks[i])<=size
    banks[i]=banks[i].ljust(size,b'\0')
(OUT/'banks.bin').write_bytes(b''.join(banks))
s='.segment "RODATA"\n'
s+=emit('mark_lo',[p&255 for p in road_mark_addresses])+emit('mark_hi',[p>>8 for p in road_mark_addresses])
s+=emit('expand_lo',[p&255 for p in expand_addresses])+emit('expand_hi',[p>>8 for p in expand_addresses])
s+=emit('column_left',[(255<<(x//5))&255 for x in range(40)])
s+=emit('column_right',[(1<<(x//5+1))-1 for x in range(40)])
s+=emit('road_lo',[p&255 for p in road_addresses])+emit('road_hi',[p>>8 for p in road_addresses])
for name,col in [('asset_bank',0),('asset_lo',1),('asset_hi',1),('asset_w',2),('asset_h',3),('asset_size_lo',4),('asset_size_hi',4)]:
    vals=[m[col] for m in meta]
    if name.endswith('_lo'): vals=[v&255 for v in vals]
    if name.endswith('_hi'): vals=[v>>8 for v in vals]
    s+=emit(name,vals)
    if name in ('asset_w','asset_h'): s+=f'.export _{name}\n_{name} = {name}\n'
s+=emit('row_lo',[offset(y)&255 for y in range(192)])
s+=emit('row_hi',[(offset(y)>>8)+0x20 for y in range(192)])
s+=emit('stripe_depth',[int(600/(r+5))&255 for r in range(56)])
hill_maps=[]
for hill in range(-4,5):
    hill_maps.append([max(0,min(55,round(r+hill*2*math.sin(math.pi*r/55)))) for r in range(56)])
s+='.export hill_lo,hill_hi\n'
s+='hill_lo: .byte '+','.join('<hill_'+str(i) for i in range(9))+'\n'
s+='hill_hi: .byte '+','.join('>hill_'+str(i) for i in range(9))+'\n'
for i,mapping in enumerate(hill_maps): s+=emit('hill_'+str(i),mapping)
bottoms=[70,70,71,73,77,80,85,91,98,105,113,122,133,143,155,168]
projected=[]
for mapping in hill_maps:
    projected.append([64+2*min(range(56),key=lambda r:abs(mapping[r]-(b-64)/2)) for b in bottoms])
(OUT/'perspective.h').write_text('/* Generated hill projection. */\nstatic const unsigned char hill_bottoms[9][16]={\n'+',\n'.join('{'+','.join(map(str,row))+'}' for row in projected)+'\n};\n')
s+=emit('waveform',[32,33,35,37,38,37,35,33,32,31,29,27,26,27,29,31])
font=json.loads(Path('platform/apple3/font.json').read_text())
s+='.export font_lo,font_hi\n'
for i in range(64):
    ch=chr(i if i>=32 else i+64)
    vals=[sum((p=='1')<<(x+1) for x,p in enumerate(row)) for row in font.get(ch,font[' '])]+[0]
    s+=f'glyph_{i}: .byte '+','.join(map(str,vals))+'\n'
s+='font_lo: .byte '+','.join(f'<glyph_{i}' for i in range(64))+'\n'
s+='font_hi: .byte '+','.join(f'>glyph_{i}' for i in range(64))+'\n'
s+=f'.export voice_address\nvoice_address = ${0x2000+voice_offset:04x}\n'
(OUT/'tables.s').write_text(s)
print('Highway: 81 road poses, 128 sprite variants and four checkpoint banners, four skylines, 6-bit voice')
