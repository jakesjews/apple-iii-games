-- Executes the real disk on the real MAME 6502. The first section uses only
-- keyboard I/O. Later fixtures arrange rare states in RAM; all transitions,
-- collision detection, rendering and scoring still execute in the game.
dofile('tools/controls.lua')
local machine = manager.machine
local cpu = machine.devices[':maincpu']
local mem = cpu.spaces.program
local screen = machine.screens[':screen']
local output = assert(os.getenv('A3_TEST_OUTPUT'))
local symbols = {}
for line in io.lines('build/invaders/invaders.lbl') do
    local address, name = line:match('al (%x+) %.(%S+)')
    if name then symbols[name] = tonumber(address, 16) end
end
local function addr(name) return assert(symbols['_' .. name], name) end
local function read(name) return mem:read_u8(addr(name)) end
local function word(name) return mem:read_u16(addr(name)) end
local function write(name, value) mem:write_u8(addr(name), value) end
local function writeword(name, value) mem:write_u16(addr(name), value) end
local function array(name, index, value) mem:write_u8(addr(name) + index, value) end
local function field(port, mask) return machine.ioport.ports[':' .. port]:field(mask) end
local left = field('keyb_special', 0x10)
local right = field('keyb_special', 0x20)
local fire = field('keyb_special', 2)
local space = field('X7', 8)
local pause = field('X5', 0x100)
local mute = field('X3', 0x40)
local escape = field('X0', 1)
local checks, frames, speaker_edges = 0, 0, 0
local speaker_tap

local function check(condition, message)
    assert(condition, message)
    checks = checks + 1
    print('PASS ' .. message)
end
local function wait(n)
    for _ = 1, n do coroutine.yield() end
end
local function until_true(predicate, description, limit)
    for _ = 1, limit or 1200 do
        if predicate() then return end
        coroutine.yield()
    end
    error('Timeout: ' .. description)
end
local function idle()
    local pc = cpu.state['PC'].value
    return pc >= addr('wait_frame') + 5 and pc < addr('wait_frame') + 12
end
local function settle()
    until_true(idle, 'CPU waiting for vertical blank')
end
local function ticks(n)
    local start = word('frame_counter')
    until_true(function() return ((word('frame_counter') - start) & 65535) >= n end, 'game ticks', n * 12 + 120)
    settle()
end
local function tap(key)
    key:set_value(1); wait(5); key:set_value(0); wait(5)
    settle()
end
local function snapshot(name)
    assert(not screen:snapshot(output .. '/' .. name .. '.png'), 'snapshot ' .. name)
end
local function shield_pixels()
    local total = 0
    for y = 146, 161 do
        local row = 0x2000 + (y % 8) * 1024 + (math.floor(y / 8) % 8) * 128 + math.floor(y / 64) * 40
        for x = 0, 39 do
            local value = mem:read_u8(row + x)
            for bit = 0, 6 do total = total + ((value >> bit) & 1) end
        end
    end
    return total
end
local function fresh_game()
    left:set_value(0); right:set_value(0); fire:set_value(0)
    tap(escape)
    until_true(function() return read('state') == 0 and idle() end, 'title')
    tap(space)
    until_true(function() return read('state') == 1 and idle() end, 'new game')
end
local function place_bomb()
    settle()
    write('invulnerable', 0)
    write('bomb_timer', 250)
    array('bomb_x', 0, read('player_x') + 5)
    array('bomb_y', 0, 164)
    array('bomb_y', 1, 255)
    array('bomb_y', 2, 255)
end

local function suite()
    until_true(function() return word('frame_counter') > 2 and idle() end, 'cold boot', 1800)
    check(read('state') == 0, 'stock ROM boots the disk to the title')
    check((mem:read_u8(0xFFEF) & 0x47) == 0x40, 'native Apple III mode and graphics bank zero')
    -- Reset/boot can rebuild MAME's handlers, so install after the cold boot.
    speaker_tap = mem:install_read_tap(0xC030, 0xC030, 'test-speaker', function()
        speaker_edges = speaker_edges + 1
    end)
    snapshot('title')
    tap(space)
    until_true(function() return read('state') == 1 and idle() end, 'space starts game')
    check(read('remaining') == 32 and read('lives') == 3 and read('wave') == 1, 'space starts a complete first wave')
    local original_shields = shield_pixels()
    check(original_shields > 1400, 'four solid bunkers rendered')
    local start_x = read('player_x')
    left:set_value(1); ticks(18); left:set_value(0)
    check(read('player_x') < start_x - 25, 'held left control moves continuously')
    right:set_value(1); ticks(18); right:set_value(0)
    check(math.abs(read('player_x') - start_x) <= 4, 'held right control reverses movement')
    if os.getenv('A3_SMOKE_ONLY') == '1' then return end

    left:set_value(1); ticks(130); left:set_value(0)
    check(read('player_x') >= 8 and read('player_x') <= 10, 'left edge clamps without wrapping')
    right:set_value(1); ticks(140); right:set_value(0)
    check(read('player_x') >= 246 and read('player_x') <= 248, 'right edge clamps without wrapping')
    left:set_value(1); ticks(61); left:set_value(0)
    local edges = speaker_edges
    local previous_score = word('score')
    local previous_remaining = read('remaining')
    fire:set_value(1)
    until_true(function() return word('score') > previous_score end, 'player shot destroys invader', 1200)
    ticks(2)
    check(read('remaining') < previous_remaining and word('score') >= previous_score + 10, 'real shots kill invaders and award points')
    check(word('best') == word('score'), 'high score tracks earned points')
    check(speaker_edges > edges, 'sound effects toggle the emulated speaker')
    fire:set_value(0)
    ticks(30)
    snapshot('gameplay')

    tap(pause)
    check(read('state') == 2, 'P pauses')
    local pixels = mem:read_range(0x2000, 0x5FFF, 8)
    local paused_x = read('player_x')
    right:set_value(1); fire:set_value(1); ticks(60)
    check(read('player_x') == paused_x and pixels == mem:read_range(0x2000, 0x5FFF, 8), 'pause freezes motion, shots and framebuffer')
    right:set_value(0); fire:set_value(0)
    tap(pause)
    check(read('state') == 1, 'P resumes')
    ticks(25)
    tap(mute)
    check(read('muted') == 1, 'M mutes')
    edges = speaker_edges
    fire:set_value(1); ticks(75); fire:set_value(0)
    check(speaker_edges == edges, 'muted gameplay generates no speaker toggles')
    tap(mute)
    check(read('muted') == 0, 'M restores sound')

    -- Controlled fixtures exercise boundary cases without waiting for chance.
    fresh_game()
    local before = shield_pixels()
    write('shot_x', 40); write('shot_y', 163)
    ticks(3)
    check(read('shot_y') == 255 and shield_pixels() < before, 'player shot cuts a crater in a bunker')
    local green = true
    for y = 146, 161 do
        local offset = (y % 8) * 1024 + (math.floor(y / 8) % 8) * 128 + math.floor(y / 64) * 40
        green = green and mem:read_u8(0x4000 + offset + 5) == 0xC0
    end
    check(green, 'shield color survives impact')

    fresh_game()
    write('ufo_active', 1); write('ufo_x', 100)
    write('shot_x', 106); write('shot_y', 35)
    ticks(2)
    check(read('ufo_active') == 0 and word('score') == 100, 'mystery ship collision awards 100 points')

    fresh_game()
    writeword('score', 1490)
    write('fleet_timer', 250)
    write('shot_x', 38); write('shot_y', 106)
    ticks(2)
    check(word('score') == 1500 and read('lives') == 4, '1500 points grants one extra life')

    fresh_game()
    place_bomb()
    ticks(3)
    check(read('lives') == 2 and read('invulnerable') > 100, 'enemy bomb costs a life and grants respawn protection')
    array('bomb_x', 0, read('player_x') + 5); array('bomb_y', 0, 164)
    ticks(3)
    check(read('lives') == 2, 'respawn protection prevents a second immediate hit')
    write('lives', 1)
    place_bomb()
    ticks(3)
    check(read('state') == 3 and read('lives') == 0, 'last life enters game over')
    snapshot('game-over')
    local saved_best = word('best')
    ticks(95)
    tap(space)
    until_true(function() return read('state') == 1 and idle() end, 'restart')
    check(read('lives') == 3 and read('wave') == 1 and word('score') == 0 and word('best') == saved_best, 'restart resets the run and preserves high score')

    -- One remaining invader, actually killed by the game's projectile code.
    for i = 0, 31 do array('aliens', i, 0) end
    array('aliens', 0, 1); write('remaining', 1)
    write('fleet_timer', 250)
    write('shot_x', 38); write('shot_y', read('fleet_y') + 8)
    ticks(3)
    check(read('state') == 4 and read('remaining') == 0, 'last invader completes the wave')
    until_true(function() return read('wave') == 2 and read('state') == 1 and idle() end, 'next wave', 1200)
    check(read('remaining') == 32 and shield_pixels() == original_shields, 'next wave replenishes invaders and repairs shields')
    snapshot('wave-two')

    write('fleet_y', 90); write('fleet_timer', 0)
    ticks(2)
    check(read('state') == 3, 'invaders reaching the shield line end the run')
    tap(escape)
    until_true(function() return read('state') == 0 and idle() end, 'escape to title')
    check(read('state') == 0, 'Escape returns to the title')

    -- Catch accidental writes from video addressing into executable bank 0.
    local file = assert(io.open('build/invaders/invaders.bin', 'rb'))
    local binary = file:read('a'); file:close()
    for i = 1, #binary do
        if 0x6000 + i - 1 ~= addr('random_state') then
            assert(mem:read_u8(0x6000 + i - 1) == binary:byte(i), string.format('program corrupted at %04X', 0x6000 + i - 1))
        end
    end
    check(true, 'gameplay and rendering preserve the loaded program')
end

local function finish(ok, message)
    for _, key in ipairs({left, right, fire, space, pause, mute, escape}) do key:clear_value() end
    if speaker_tap then speaker_tap:remove() end
    local result = assert(io.open(output .. '/result.txt', 'w'))
    result:write(ok and ('PASS ' .. checks .. ' checks\n') or ('FAIL ' .. tostring(message) .. '\n'))
    result:close()
    if not ok then print('FAIL ' .. tostring(message)); snapshot('failure') end
    machine:exit()
end
local thread = coroutine.create(suite)
emu.register_frame_done(function()
    frames = frames + 1
    if frames > 16000 then finish(false, 'suite watchdog'); return end
    local ok, message = coroutine.resume(thread)
    if not ok then finish(false, message)
    elseif coroutine.status(thread) == 'dead' then finish(true) end
end, 'frame')
