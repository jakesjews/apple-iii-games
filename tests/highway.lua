-- Stock-ROM boot, real inputs, fixed-clock physics and banked memory checks.
local t = dofile('tests/mame.lua')('highway','games/highway/controls.lua')
local function signed(name) local v=t.word(name); return v>=32768 and v-65536 or v end
local function fixture()
    t.settle()
    t.write('state',2); t.write('stage',0); t.write('scene',0); t.write('tunnel',0)
    t.write('speed',120); t.write('crash_timer',0); t.write('checkpoint',0)
    t.writeword('player',0); t.writeword('stage_distance',0); t.writeword('time_left',1750)
    t.write('redraw_scene',1); t.write('action_timer',0)
    for i=0,2 do t.mem:write_u16(t.addr('traffic_depth')+2*i,0); t.array('car_hit',i,0); t.array('traffic_lane',i,0) end
    t.ticks(3)
end
local function keypress(key,condition,message)
    key:set_value(1)
    t.until_true(condition,message,600)
    key:set_value(0); t.ticks(2)
end
local function integrity()
    local f=assert(io.open('build/highway/banks.bin','rb')); local bytes=f:read('a'); f:close()
    local offset=1
    for bank=1,4 do
        t.mem:write_u8(0xFFEF,0x40+bank)
        local size=bank==4 and 24576 or 32768
        for i=0,size-1 do assert(t.mem:read_u8(0x2000+i)==bytes:byte(offset+i),string.format('asset corruption bank %d offset %04x',bank,i)) end
        offset=offset+size
    end
    t.mem:write_u8(0xFFEF,0x40)
    t.check(true,'all four loaded asset banks remain byte-for-byte intact')
    f=assert(io.open('build/highway/code.bin','rb')); bytes=f:read('a'); f:close()
    local symbols={}
    for line in io.lines('build/highway/highway.lbl') do local a,n=line:match('al (%x+) %.(%S+)'); if n then symbols[n]=tonumber(a,16) end end
    for i=1,#bytes do
        local address=i<=7680 and 0xA200+i-1 or 0xD000+i-7681
        local mutable=(address>=symbols.hill_read+1 and address<=symbols.hill_read+2) or (address>=symbols.road_store+1 and address<=symbols.road_store+2)
        if not mutable then assert(t.mem:read_u8(address)==bytes:byte(i),string.format('code corruption %04x',address)) end
    end
    t.check(true,'system-bank program and tables remain intact')
end

local function road_clean()
    local ground=({[0]=0x44,0x88,0x00,0x22})[t.read('scene')]
    local base=0x2000+t.read('page')*256
    local rectangles={}
    for i=0,8 do
        if t.array('new_visible',i)~=0 then rectangles[#rectangles+1]={t.array('new_x',i),t.array('new_y',i),t.array('new_w',i),t.array('new_h',i)} end
    end
    for y=64,175 do
        local row=math.floor((y-64)/2)
        local left,right=t.array('geom',row),t.array('geom',56+row)
        local lane1,lane2=t.array('geom',224+row),t.array('geom',280+row)
        for x=0,39 do
            local free=true
            for _,r in ipairs(rectangles) do if x>=r[1] and x<r[1]+r[3] and y>=r[2] and y<r[2]+r[4] then free=false;break end end
            if free and x~=left and x~=right and x~=left+1 and x~=right-1 and x~=lane1 and x~=lane2 then
                local address=base+(y%8)*1024+(math.floor(y/8)%8)*128+math.floor(y/64)*40+x
                local expected=(x>left and x<right) and 0x55 or ground
                assert(t.mem:read_u8(address)==0 and t.mem:read_u8(address+0x2000)==expected,string.format('road trail at %d,%d: bits %02x attr %02x expected %02x',x,y,t.mem:read_u8(address),t.mem:read_u8(address+0x2000),expected))
            end
        end
    end
    t.check(true,'road changes leave clean background outside current sprites')
end

t.run(function()
    t.check((t.mem:read_u8(0xFFDF)&1)==0,'game uses RAM interrupt vectors')
    t.check((t.mem:read_u8(0xFFE2)&63)==63,'native six-bit DAC configured')
    local start=t.word('irq_ticks'); t.wait(120)
    local delta=(t.word('irq_ticks')-start)&65535
    t.check(delta>3900 and delta<4100,'VIA clock advances at 2000 ticks per second')
    local frames=t.word('frame_counter'); t.wait(300)
    print(string.format('ATTRACT %.2f rendered frames/sec in MAME',((t.word('frame_counter')-frames)&65535)/5))
    t.settle(); t.snapshot('title')
    local dac_samples,dac_values=0,{}
    local dac=t.mem:install_write_tap(0xFFE0,0xFFE0,'highway-dac',function(_,data) dac_samples=dac_samples+1; dac_values[data&63]=true end)
    local enter=t.key('ENTER'); t.tap(enter)
    t.until_true(function() return t.read('state')==2 end,'spoken countdown and start',600); t.settle()
    local levels=0; for _ in pairs(dac_values) do levels=levels+1 end
    t.check(dac_samples>2000 and levels>12,'spoken countdown drives multiple DAC amplitude levels')
    t.check(t.read('speed')==0,'standing start waits for accelerator')
    local gas=t.field('keyb_special',2)
    gas:set_value(1); t.wait(180); t.settle()
    t.check(t.read('speed')>90,'held Shift accelerates')
    t.check(t.word('stage_distance')>1000,'accelerating advances the race')
    t.ticks(1); t.snapshot('coast'); gas:set_value(0)
    if t.smoke then integrity(); dac:remove(); return end

    fixture(); t.write('state',3)
    for _,pose in ipairs({{0,-64,0},{8,64,8},{0,64,4},{8,-64,4},{4,0,4}}) do
        t.write('curve',pose[1]); t.writeword('player',pose[2]&65535); t.write('hill',pose[3]); t.ticks(3); road_clean()
    end
    fixture(); t.write('speed',180)
    local brake=t.field('keyb_special',8)
    brake:set_value(1); t.wait(60); t.settle(); brake:set_value(0)
    t.check(t.read('speed')<30,'held Control brakes to a stop')
    fixture()
    local left=t.field('keyb_special',16); local right=t.field('keyb_special',32)
    left:set_value(1); t.wait(30); t.settle(); left:set_value(0)
    t.check(signed('player')<-15,'held Open Apple steers left')
    right:set_value(1); t.wait(60); t.settle(); right:set_value(0)
    t.check(signed('player')>15,'held Solid Apple steers right')
    fixture(); t.writeword('player',75); t.write('speed',180); t.ticks(6)
    t.check(t.read('speed')<100,'off-road grass slows the car')

    fixture()
    local pause=t.key('P'); keypress(pause,function() return t.read('state')==3 end,'pause')
    local distance,time=t.word('stage_distance'),t.word('time_left')
    t.wait(120); t.settle()
    t.check(t.word('stage_distance')==distance and t.word('time_left')==time,'pause freezes motion and the race clock')
    t.check(t.read('engine_on')==0,'pause silences the engine')
    keypress(pause,function() return t.read('state')==2 end,'resume')
    t.check(t.word('time_left')<time,'resuming restarts the clock')
    keypress(t.key('M'),function() return t.read('muted')==1 end,'mute')
    dac_values={}; t.wait(60)
    levels=0; for v in pairs(dac_values) do assert(v==32,'non-silent DAC while muted'); levels=levels+1 end
    t.check(levels==1,'mute holds the DAC at its midpoint')
    t.write('action_timer',0); keypress(t.key('M'),function() return t.read('muted')==0 end,'unmute')

    fixture()
    local x=t.field('joy_1_x',255); local y=t.field('joy_1_y',255)
    local button=t.field('joy_buttons',2); local switch=t.field('joy_buttons',1)
    x:set_value(0); t.wait(30); t.settle()
    t.check(signed('player')<-15,'Port B joystick steers left')
    x:set_value(255); t.wait(60); t.settle(); x:set_value(128)
    t.check(signed('player')>15,'Port B joystick steers right')
    fixture(); t.write('speed',0)
    button:set_value(1); t.wait(120); t.settle(); button:set_value(0)
    t.check(t.read('speed')>60,'joystick button accelerates')
    y:set_value(255); t.wait(60); t.settle(); y:set_value(128)
    t.check(t.read('speed')<30,'joystick down brakes')
    switch:set_value(1); t.until_true(function() return t.read('state')==3 end,'switch pauses'); t.ticks(3)
    t.check(t.read('state')==3,'latched switch pauses exactly once')
    switch:set_value(0); t.until_true(function() return t.read('state')==2 end,'switch resumes'); t.settle()
    t.check(t.read('state')==2,'opposite switch edge resumes')

    fixture(); t.write('speed',180); t.writeword('player',0)
    t.array('traffic_lane',0,1); t.mem:write_u16(t.addr('traffic_depth'),13990)
    t.ticks(2)
    t.check(t.read('crash_timer')>0 and t.read('speed')<=25,'traffic contact reduces speed and starts recovery')
    t.check(t.word('time_left')<1640,'collision also costs two seconds')
    t.ticks(1); t.snapshot('collision')
    fixture(); t.write('speed',180); t.array('traffic_lane',0,0)
    t.mem:write_u16(t.addr('traffic_depth'),16300)
    local score=t.word('score'); t.ticks(3)
    t.check(t.word('score')>=score+100,'clean overtake awards points')

    fixture(); t.writeword('stage_distance',13990); t.write('speed',120); t.ticks(4)
    t.check(t.read('scene')==3 and t.read('tunnel')==1,'coast enters the lighthouse tunnel')
    t.ticks(1); t.snapshot('tunnel')
    t.writeword('stage_distance',19000); t.ticks(4)
    t.check(t.read('scene')==0 and t.read('tunnel')==0,'tunnel exits back into sunset')
    t.writeword('stage_distance',24990); t.writeword('time_left',500); t.write('speed',120); t.ticks(4)
    t.check(t.read('stage')==1 and t.read('scene')==1,'first checkpoint opens the canyon')
    t.check(t.word('time_left')>2000,'checkpoint adds 35 seconds')
    t.ticks(1); t.snapshot('canyon')
    t.writeword('stage_distance',24990); t.ticks(4)
    t.check(t.read('stage')==2 and t.read('scene')==2,'second checkpoint opens midnight city')
    t.ticks(1); t.snapshot('midnight')
    t.writeword('stage_distance',24990); t.ticks(4)
    t.check(t.read('state')==5,'third checkpoint finishes the tour')
    t.check(t.word('best')==t.word('score'),'completed score becomes the session best')
    distance=t.word('stage_distance'); t.ticks(5)
    t.check(t.word('stage_distance')==distance,'finished race stops progressing')
    t.ticks(1); t.snapshot('finish')
    local best=t.word('best')
    keypress(enter,function() return t.read('state')==1 end,'restart finished tour')
    t.check(t.read('stage')==0 and t.word('score')==0 and t.word('best')==best,'restart resets the race and retains the best')
    fixture(); t.writeword('time_left',1); t.ticks(3)
    t.check(t.read('state')==4,'time expiration ends the race')
    t.ticks(1); t.snapshot('time-up')
    keypress(t.key('ESC'),function() return t.read('state')==0 end,'return to title')
    integrity(); dac:remove()
end)
