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
# Compile sprites into straight-line 6502 stores. Each row uses two native
# extended-address pointers, allowing code in an asset bank to draw bank zero.
# Four car colors share the same code through an indexed attribute palette.
banks[1].extend(bytes((((([1,12,7,13][v] if a>>4==9 else a>>4)<<4) |
                       ([1,12,7,13][v] if a&15==9 else a&15)))
                      for a in range(256) for v in range(4)))
def compiled(img, car=False):
    data=pack(img); w=len(img[0])//7; code=bytearray()
    for row in range(len(img)):
        code.extend((0xA0,0))  # LDY #0; horizontal position is in the row pointers
        for col in range(w):
            mask,pixel,attr=(data[row*w*3+col+k*w] for k in range(3))
            zp=row*4
            if mask:
                if mask==127:
                    code.extend((0xA9,pixel,0x91,zp))
                else:
                    code.extend((0xB1,zp,0x29,127^mask,0x09,pixel,0x91,zp))
                if car:
                    # Palette contains the complete opaque attribute and, in a
                    # second table, the foreground nibble for boundary cells.
                    address=0x2000+(1024 if mask!=127 else 0)+attr*4
                    code.extend((0xBD,address&255,address>>8))
                    if mask!=127:
                        code.extend((0x85,0xF1,0xB1,zp+2,0x29,15,0x05,0xF1))
                elif mask==127:
                    code.extend((0xA9,attr))
                else:
                    code.extend((0xB1,zp+2,0x29,15,0x09,attr&240))
                code.extend((0x91,zp+2))
            if col+1<w: code.append(0xC8) # INY
    code.append(0x60)
    return code
banks[1].extend(bytes(v&240 for v in banks[1][:1024]))
car_meta=[]
for scale in range(16):
    cols=1+scale//3; height=4+scale*2
    data=compiled(raster('car',cols*7,height),True)
    car_meta.append((2,0x2000+len(banks[1]),cols,height,len(data)))
    banks[1].extend(data)
for variant in range(4): meta.extend(car_meta)
for kind in ['palm','cactus','tower','sign']:
    for scale in range(16):
        cols=1+scale//4; height=5+scale*3 if kind=='palm' else 4+scale*2
        data=compiled(raster(kind,cols*7,height))
        bank=next(i for i,capacity in ((1,32768),(2,32768),(3,24576)) if len(banks[i])+len(data)<=capacity)
        meta.append((bank+1,0x2000+len(banks[bank]),cols,height,len(data)))
        banks[bank].extend(data)
for scale,(cols,height) in enumerate(((8,6),(14,8),(22,10),(30,12))):
    img=[[15 if ((x//7)+(y//2))%2 else 0 for x in range(cols*7)] for y in range(height)]
    data=compiled(img)
    meta.append((4,0x2000+len(banks[3]),cols,height,len(data)))
    banks[3].extend(data)
print('Asset bytes by bank:',*[len(b) for b in banks])
for i,size in enumerate((32768,32768,32768,24576)):
    assert len(banks[i])<=size
    banks[i]=banks[i].ljust(size,b'\0')
(OUT/'banks.bin').write_bytes(b''.join(banks))
s='.segment "RODATA"\n'
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
