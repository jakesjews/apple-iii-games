-- End-to-end tour: the driver only touches real emulated joystick inputs.
local t=dofile('tests/mame.lua')('highway','games/highway/controls.lua')
t.run(function()
    local button=t.field('joy_buttons',2)
    local x=t.field('joy_1_x',255)
    local y=t.field('joy_1_y',255)
    x:set_value(128); y:set_value(128); button:set_value(1)
    t.until_true(function() return t.read('state')==2 end,'start with button',900)
    local frames,start=t.word('frame_counter'),t.word('irq_ticks')
    local ticks=0; local stages={}; local pictures={}; local crashes=0; local old_crash=0
    for host=1,9000 do
        local state=t.read('state')
        if state==5 or state==4 then break end
        local player=t.word('player'); if player>=32768 then player=player-65536 end
        local best,target=1e9,0
        for lane=0,2 do
            local cost=math.abs(player-(lane-1)*36)
            for car=0,2 do
                local depth=t.mem:read_u16(t.addr('traffic_depth')+car*2)
                if t.array('traffic_lane',car)==lane and depth>6500 then cost=cost+200+depth/100 end
            end
            if cost<best then best=cost; target=(lane-1)*36 end
        end
        x:set_value(player<target-4 and 255 or player>target+4 and 0 or 128)
        local crash=t.read('crash_timer'); if crash>old_crash then crashes=crashes+1 end; old_crash=crash
        local stage=t.read('stage')
        if not stages[stage] then stages[stage]=true; print('Driver reached stage '..(stage+1)) end
        if t.word('stage_distance')>7000 and not pictures[stage] and t.idle() then
            pictures[stage]=true; t.snapshot(({'coast-drive','canyon-drive','midnight-drive'})[stage+1])
        end
        t.wait(1); ticks=ticks+1
    end
    button:set_value(0); x:set_value(128); t.settle()
    print('tour ended state '..t.read('state')..' stage '..t.read('stage')..' distance '..t.word('stage_distance')..' speed '..t.read('speed')..' player '..t.word('player')..' crashes '..crashes..' time '..t.word('time_left'))
    t.snapshot('tour-end')
    t.check(t.read('state')==5,'controller-only driver completes all three stages before time expires')
    t.check(stages[0] and stages[1] and stages[2],'controller-only run visits every stage')
    t.check(t.word('score')>=3000,'complete tour earns checkpoint and finish points')
    print(string.format('RACE %.2f fps over %.1f emulated seconds; %d collisions; score %d',((t.word('frame_counter')-frames)&65535)/(ticks/60),ticks/60,crashes,t.word('score')))
    t.ticks(2); t.snapshot('full-tour-finish')
end)
