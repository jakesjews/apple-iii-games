-- Shared harness for new games: real ROM boot, input ports, VBL-safe fixtures,
-- snapshots, speaker observation, fail-closed result files and process cleanup.
return function(game, controls)
    if controls then dofile(controls) end
    local t = {checks = 0, edges = 0}
    local machine = manager.machine
    t.cpu = machine.devices[':maincpu']; t.mem = t.cpu.spaces.program
    local screen = machine.screens[':screen']
    local output = assert(os.getenv('A3_TEST_OUTPUT'))
    local symbols, fields = {}, {}
    for line in io.lines('build/' .. game .. '/' .. game .. '.lbl') do
        local address, name = line:match('al (%x+) %.(%S+)')
        if name then symbols[name] = tonumber(address, 16) end
    end
    function t.addr(name) return assert(symbols['_' .. name], name) end
    function t.read(name) return t.mem:read_u8(t.addr(name)) end
    function t.word(name) return t.mem:read_u16(t.addr(name)) end
    function t.long(name) return t.mem:read_u32(t.addr(name)) end
    function t.write(name, value) t.mem:write_u8(t.addr(name), value & 255) end
    function t.writeword(name, value) t.mem:write_u16(t.addr(name), value) end
    function t.writelong(name, value) t.mem:write_u32(t.addr(name), value) end
    function t.array(name, index, value)
        if value ~= nil then t.mem:write_u8(t.addr(name) + index, value) end
        return t.mem:read_u8(t.addr(name) + index)
    end
    function t.field(port, mask)
        local f = machine.ioport.ports[':' .. port]:field(mask)
        fields[#fields + 1] = f
        return f
    end
    local map = {
        A={'X2',1}, B={'X3',16}, C={'X3',4}, D={'X2',4}, E={'X1',8}, F={'X2',8},
        G={'X2',32}, H={'X2',16}, I={'X1',256}, J={'X2',64}, K={'X2',128}, L={'X2',512},
        M={'X3',64}, N={'X3',32}, O={'X1',512}, P={'X5',256}, Q={'X1',2}, R={'X1',16},
        S={'X2',2}, T={'X1',32}, U={'X1',128}, V={'X3',8}, W={'X1',4}, X={'X3',2},
        Y={'X1',64}, Z={'X3',1}, SPACE={'X7',8}, ENTER={'X6',64}, ESC={'X0',1},
        BACK={'X6',256}, LEFT={'X7',256}, RIGHT={'X7',64}, UP={'X6',128}, DOWN={'X7',128}
    }
    function t.key(name)
        local entry = assert(map[name], name)
        return t.field(entry[1], entry[2])
    end
    function t.check(condition, message)
        assert(condition, message); t.checks = t.checks + 1; print('PASS ' .. message)
    end
    function t.wait(n) for _ = 1, n do coroutine.yield() end end
    function t.until_true(predicate, message, limit)
        for _ = 1, limit or 1800 do if predicate() then return end; coroutine.yield() end
        error('Timeout: ' .. message)
    end
    function t.idle()
        local pc = t.cpu.state['PC'].value
        return pc >= t.addr('wait_frame') + 5 and pc < t.addr('wait_frame') + 12
    end
    function t.settle() t.until_true(t.idle, 'vertical blank wait') end
    function t.ticks(n)
        local start = t.word('frame_counter')
        t.until_true(function() return ((t.word('frame_counter') - start) & 65535) >= n end, 'game ticks', n*15+120)
        t.settle()
    end
    function t.tap(key)
        key:set_value(1); t.wait(5); key:set_value(0); t.wait(5); t.settle()
    end
    function t.type(s) for letter in s:gmatch('.') do t.tap(t.key(letter)) end end
    function t.snapshot(name) assert(not screen:snapshot(output .. '/' .. name .. '.png')) end
    function t.pixels() return t.mem:read_range(0x2000, 0x5FFF, 8) end
    function t.integrity()
        local f = assert(io.open('build/' .. game .. '/' .. game .. '.bin', 'rb'))
        local data = f:read('a'); f:close()
        for i = 1, #data do
            assert(t.mem:read_u8(0x6000+i-1) == data:byte(i), string.format('program corrupted at %04X', 0x6000+i-1))
        end
        t.check(true, 'gameplay preserves the entire loaded program')
    end
    t.smoke = os.getenv('A3_SMOKE_ONLY') == '1'
    function t.run(suite)
        local finished, frames, speaker = false, 0, nil
        local thread = coroutine.create(function()
            t.until_true(function() return t.word('frame_counter') > 2 and t.idle() end, 'cold boot')
            t.check(t.read('state') == 0, 'stock ROM cold-boots to the title')
            t.check((t.mem:read_u8(0xFFEF) & 0x47) == 0x40, 'native Apple III mode and bank zero')
            speaker = t.mem:install_read_tap(0xC030,0xC030,'test-speaker',function() t.edges = t.edges+1 end)
            t.snapshot('title'); suite()
        end)
        local function finish(ok, message)
            finished = true
            for _, f in ipairs(fields) do f:clear_value() end
            if speaker then speaker:remove() end
            local f = assert(io.open(output .. '/result.txt', 'w'))
            f:write(ok and ('PASS ' .. t.checks .. ' checks\n') or ('FAIL ' .. tostring(message) .. '\n')); f:close()
            if not ok then print('FAIL ' .. tostring(message)); t.snapshot('failure') end
            machine:exit()
        end
        emu.register_frame_done(function()
            if finished then return end
            frames = frames+1
            if frames > 16000 then finish(false, 'watchdog'); return end
            local ok, message = coroutine.resume(thread)
            if not ok then finish(false,message)
            elseif coroutine.status(thread) == 'dead' then finish(true) end
        end,'frame')
    end
    return t
end
