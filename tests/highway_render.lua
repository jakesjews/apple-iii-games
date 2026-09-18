-- Compare incremental updates against a complete reconstruction of the same
-- frozen scene. Both physical pages must agree, including overlapping sprites.
local t=dofile('tests/mame.lua')('highway','games/highway/controls.lua')
local function address(page,x,y,attributes)
    return 0x2000+page*0x4000+(y%8)*1024+(math.floor(y/8)%8)*128+math.floor(y/64)*40+x+(attributes and 0x2000 or 0)
end
local function picture(first,last)
    local bytes={}
    for page=0,1 do for y=first,last do for x=0,39 do
        bytes[#bytes+1]=string.char(t.mem:read_u8(address(page,x,y,false)),t.mem:read_u8(address(page,x,y,true)))
    end end end
    return table.concat(bytes)
end
local function rebuild_matches(first,last,message)
    local incremental=picture(first,last)
    t.write('redraw_scene',1); t.ticks(3)
    local full=picture(first,last)
    if full~=incremental then
        for i=1,#full do if full:byte(i)~=incremental:byte(i) then
            local cell=math.floor((i-1)/2)
            error(string.format('%s: page %d cell %d,%d %s was %02x, expected %02x',message,
                math.floor(cell/(40*(last-first+1))),cell%40,first+math.floor(cell/40)%(last-first+1),
                i%2==0 and 'attribute' or 'pixels',incremental:byte(i),full:byte(i)))
        end end
    end
    t.check(true,message)
end
t.run(function()
    t.settle(); t.write('state',3); t.write('stage',0); t.write('scene',0)
    t.write('tunnel',0); t.write('speed',199); t.writeword('time_left',500)
    t.writeword('score',1999); t.write('redraw_scene',1)
    for car=0,2 do t.array('traffic_color',car,car+1) end
    t.ticks(3)
    for n=0,11 do
        t.write('curve',(n*5)%9); t.write('hill',(n*7)%9)
        t.writeword('player',(({0,-64,64,0})[n%4+1])&65535)
        t.write('road_phase',({0,7,8,15,16,255})[n%6+1])
        t.writeword('stage_distance',n*1513)
        t.write('crash_timer',n%3==0 and 1 or 0); t.write('tick_divider',n%2*4)
        for car=0,2 do
            t.mem:write_u16(t.addr('traffic_depth')+car*2,11000+((car+n)%3)*1400)
            t.array('traffic_lane',car,n%2==0 and 1 or car)
        end
        t.ticks(3)
        rebuild_matches(64,175,'incremental road/sprites match a full redraw on both pages, pose '..n)
    end
    t.write('state',5); t.ticks(3)
    rebuild_matches(64,175,'overlapping finish banner matches a full redraw')
    t.write('state',3); t.ticks(3)
    rebuild_matches(64,175,'removing the finish banner restores obscured objects')

    local writes=0
    local tap=t.mem:install_write_tap(0x2000,0x9fff,'stationary-frame',function() writes=writes+1 end)
    t.ticks(5); tap:remove()
    t.check(writes==0,'unchanged paused frames perform zero framebuffer writes')

    local allowed={}
    for page=0,1 do for y=0,7 do for _,attrs in ipairs({false,true}) do allowed[address(page,8,y,attrs)]=true end end end
    local touched={}
    tap=t.mem:install_write_tap(0x2000,0x9fff,'hud-digit',function(offset)
        assert(allowed[offset],string.format('unnecessary framebuffer write at %04x',offset))
        touched[offset]=true
    end)
    t.write('speed',198); t.ticks(3); tap:remove()
    local count=0; for _ in pairs(touched) do count=count+1 end
    t.check(count==32,'speed change writes only the changed digit on both pages')
    t.writeword('time_left',499); t.ticks(3)
    for page=0,1 do for y=0,7 do for x=16,17 do
        assert(t.mem:read_u8(address(page,x,y,true))==0x90,'stale timer warning color')
    end end end
    t.check(true,'timer warning recolors unchanged digits on both pages')
    t.writeword('score',2000); t.ticks(3)
    rebuild_matches(0,7,'digit carries and timer warning match complete HUD reconstruction')
end)
