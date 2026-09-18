-- Boot and play the actual 6502 disk. Input-only checks come first; later
-- fixtures arrange rare board positions, then the game resolves them itself.
dofile('games/tetris/controls.lua')
local machine = manager.machine
local cpu = machine.devices[':maincpu']
local mem = cpu.spaces.program
local screen = machine.screens[':screen']
local output = assert(os.getenv('A3_TEST_OUTPUT'))
local symbols = {}
for line in io.lines('build/tetris/tetris.lbl') do
    local address, name = line:match('al (%x+) %.(%S+)')
    if name then symbols[name] = tonumber(address, 16) end
end
local function addr(name) return assert(symbols['_' .. name], name) end
local function read(name) return mem:read_u8(addr(name)) end
local function signed(name) local n = read(name); return n < 128 and n or n - 256 end
local function word(name) return mem:read_u16(addr(name)) end
local function long(name) return mem:read_u32(addr(name)) end
local function write(name, n) mem:write_u8(addr(name), n & 255) end
local function writeword(name, n) mem:write_u16(addr(name), n) end
local function writelong(name, n) mem:write_u32(addr(name), n) end
local function board(x, y, n)
    if n then mem:write_u8(addr('board') + y * 10 + x, n) end
    return mem:read_u8(addr('board') + y * 10 + x)
end
local function field(port, mask) return machine.ioport.ports[':' .. port]:field(mask) end
local left, right = field('keyb_special', 0x10), field('keyb_special', 0x20)
local hard, soft = field('keyb_special', 2), field('keyb_special', 8)
local space, pause = field('X7', 8), field('X5', 0x100)
local clockwise, reverse, hold = field('X3', 2), field('X3', 1), field('X3', 4)
local mute, escape = field('X3', 0x40), field('X0', 1)
local inputs = {left, right, hard, soft, space, pause, clockwise, reverse, hold, mute, escape}
local checks, frames, speaker_edges = 0, 0, 0
local speaker_tap
local function check(condition, message)
    assert(condition, message)
    checks = checks + 1
    print('PASS ' .. message)
end
local function wait(n) for _ = 1, n do coroutine.yield() end end
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
local function settle() until_true(idle, 'CPU waiting for vertical blank') end
local function ticks(n)
    local start = word('frame_counter')
    until_true(function() return ((word('frame_counter') - start) & 65535) >= n end, 'game ticks', n * 15 + 120)
    settle()
end
local function tap(key)
    key:set_value(1); wait(5); key:set_value(0); wait(5); settle()
end
local function drop()
    space:set_value(1); hard:set_value(1); ticks(2)
    space:set_value(0); hard:set_value(0); ticks(2)
end
local function snapshot(name)
    assert(not screen:snapshot(output .. '/' .. name .. '.png'), 'snapshot ' .. name)
end
local function occupied()
    local total = 0
    for y = 0, 21 do for x = 0, 9 do if board(x, y) ~= 0 then total = total + 1 end end end
    return total
end
local function fresh_game()
    for _, input in ipairs(inputs) do input:set_value(0) end
    tap(escape)
    until_true(function() return read('state') == 0 and idle() end, 'title')
    tap(space)
    until_true(function() return read('state') == 1 and idle() end, 'new game')
    ticks(15)
end
local function fixture(kind, turn, x, y)
    settle()
    for by = 0, 21 do for bx = 0, 9 do board(bx, by, 0) end end
    write('state', 1); write('piece', kind); write('rotation', turn)
    write('piece_x', x); write('piece_y', y); write('ghost_dirty', 1)
    write('falling_drawn', 0); write('fall_timer', 0); write('lock_timer', 0)
    write('lock_resets', 0); write('move_direction', 0); write('move_timer', 0)
    write('action_timer', 0); write('soft_hold', 0); write('level', 1)
    writeword('lines', 0); writeword('pieces_locked', 0); writelong('score', 0)
end

local function suite()
    until_true(function() return word('frame_counter') > 2 and idle() end, 'cold boot', 1800)
    check(read('state') == 0, 'stock ROM boots Blockfall to its title')
    check((mem:read_u8(0xFFEF) & 0x47) == 0x40, 'native Apple III mode and graphics bank zero')
    speaker_tap = mem:install_read_tap(0xC030, 0xC030, 'test-speaker', function()
        speaker_edges = speaker_edges + 1
    end)
    snapshot('title')
    tap(space)
    until_true(function() return read('state') == 1 and idle() end, 'space starts game')
    check(occupied() == 0 and read('level') == 1 and long('score') == 0, 'start creates an empty ten by twenty well')
    check(read('piece') < 7 and read('next_piece') < 7 and read('piece') ~= read('next_piece'), 'current and next pieces come from the seven-piece bag')
    check(signed('ghost_y') >= 18 and signed('ghost_y') <= 20, 'ghost finds the bottom of the empty well')
    local start_x = signed('piece_x')
    left:set_value(1); ticks(20); left:set_value(0)
    check(signed('piece_x') < start_x, 'held left moves with autorepeat')
    right:set_value(1); ticks(20); right:set_value(0)
    check(signed('piece_x') >= start_x, 'held right reverses movement')
    if os.getenv('A3_SMOKE_ONLY') == '1' then return end

    left:set_value(1); ticks(60); left:set_value(0)
    local edge = signed('piece_x')
    ticks(1); left:set_value(1); ticks(20); left:set_value(0)
    check(signed('piece_x') == edge and edge >= -2 and edge <= 0, 'left wall blocks movement without wrapping')
    right:set_value(1); ticks(75); right:set_value(0)
    edge = signed('piece_x')
    ticks(1); right:set_value(1); ticks(20); right:set_value(0)
    check(signed('piece_x') == edge and edge >= 6 and edge <= 8, 'right wall blocks movement without wrapping')
    left:set_value(1); ticks(25); left:set_value(0); ticks(15)
    tap(pause)
    check(read('state') == 2, 'P pauses')
    local pixels = mem:read_range(0x2000, 0x5FFF, 8)
    local old_y, old_x = signed('piece_y'), signed('piece_x')
    left:set_value(1); hard:set_value(1); soft:set_value(1); ticks(40)
    check(signed('piece_y') == old_y and signed('piece_x') == old_x and word('pieces_locked') == 0
          and pixels == mem:read_range(0x2000, 0x5FFF, 8), 'pause freezes the board, drop and framebuffer')
    left:set_value(0); hard:set_value(0); soft:set_value(0); ticks(2)
    tap(pause)
    check(read('state') == 1, 'P resumes')
    ticks(15)
    old_y = signed('piece_y')
    local old_score = long('score')
    soft:set_value(1); ticks(10); soft:set_value(0)
    check(signed('piece_y') >= old_y + 4 and long('score') >= old_score + 4, 'held soft drop moves faster and earns points')
    local old_piece, old_next = read('piece'), read('next_piece')
    tap(hold)
    check(read('held_piece') == old_piece and read('piece') == old_next and read('hold_used') == 1, 'C holds a piece and spawns the preview')
    ticks(10); tap(hold)
    check(read('held_piece') == old_piece and read('piece') == old_next, 'hold is limited to once per placed piece')
    ticks(10)
    if read('piece') ~= 1 then
        tap(clockwise)
        check(read('rotation') == 1, 'X rotates clockwise through keyboard I/O')
        ticks(10); tap(reverse)
        check(read('rotation') == 0, 'Z rotates counterclockwise through keyboard I/O')
    end
    local edges = speaker_edges
    local landing = signed('ghost_y')
    old_y = signed('piece_y'); old_score = long('score')
    -- MAME maps host Space to both the character key and Shift modifier.
    space:set_value(1); hard:set_value(1); ticks(18)
    check(word('pieces_locked') == 1 and occupied() == 4, 'hard drop places four cells; holding the key does not repeat')
    check(long('score') == old_score + (landing - old_y) * 2 and long('best') == long('score'), 'hard drop awards two points per cell and updates best')
    check(speaker_edges > edges, 'placement generates real speaker accesses')
    space:set_value(0); hard:set_value(0); ticks(3)
    check(word('pieces_locked') == 1, 'releasing mapped Space does not drop a second piece')
    check(read('hold_used') == 0, 'placing a piece enables hold again')
    ticks(12); tap(mute)
    check(read('muted') == 1, 'M mutes sound')
    edges = speaker_edges
    drop()
    check(speaker_edges == edges, 'muted placement does not toggle the speaker')
    ticks(15); tap(mute)
    check(read('muted') == 0, 'M restores sound')

    -- A varied input-only board for the documentation screenshot.
    fresh_game()
    for i = 1, 8 do
        local direction = i % 2 == 1 and left or right
        direction:set_value(1); ticks(i % 3 == 0 and 20 or 30); direction:set_value(0)
        if i % 3 == 0 then tap(clockwise); ticks(8) end
        if i == 4 then tap(hold); ticks(8) end
        drop()
    end
    ticks(50)
    snapshot('gameplay')
    check(read('state') == 1 and word('pieces_locked') == 8, 'eight pieces can be played using inputs alone')

    -- Fixtures below only change game data while the CPU is waiting for VBL.
    fixture(0, 1, -2, 8)
    tap(clockwise)
    check(read('rotation') == 2 and signed('piece_x') == 0, 'I piece kicks two cells away from the left wall')
    fixture(2, 0, 3, 20)
    tap(clockwise)
    check(read('rotation') == 1 and signed('piece_y') == 19, 'rotation can kick upward off the floor')
    fixture(2, 0, 3, 8)
    for y = 0, 21 do for x = 0, 9 do board(x, y, 1) end end
    for _, xy in ipairs({{4,8},{3,9},{4,9},{5,9}}) do board(xy[1],xy[2],0) end
    tap(clockwise)
    check(read('rotation') == 0 and signed('piece_x') == 3 and signed('piece_y') == 8, 'rotation rejects occupied cells after all kicks fail')
    fixture(1, 0, 3, 20)
    ticks(15)
    check(word('pieces_locked') == 0 and read('lock_timer') >= 15, 'grounded pieces retain a lock delay')
    left:set_value(1); ticks(1); left:set_value(0)
    check(read('lock_resets') == 1 and read('lock_timer') < 5, 'a successful grounded move resets lock delay')
    write('lock_resets', 8); write('lock_timer', 28); write('move_direction', 0)
    right:set_value(1); ticks(2); right:set_value(0)
    check(word('pieces_locked') == 1, 'lock-reset limit prevents endless floor movement')

    for kind = 0, 6 do
        for turn = 0, 3 do
            fixture(kind, turn, 3, 5)
            drop()
            assert(occupied() == 4 and word('pieces_locked') == 1, 'invalid placement for piece/rotation ' .. kind .. '/' .. turn)
        end
    end
    check(true, 'all seven pieces in all four rotations lock exactly four cells')
    for count = 1, 4 do
        fixture(0, 1, 2, 18)
        for y = 22 - count, 21 do for x = 0, 9 do if x ~= 4 then board(x, y, 3) end end end
        board(0, 17, 5)
        drop()
        check(read('state') == 4 and read('clear_count') == count, count .. '-line clear enters its animation')
        until_true(function() return read('state') == 1 and idle() end, 'line clear completes')
        local points = ({100,300,500,800})[count]
        check(word('lines') == count and long('score') == points and board(0, 17 + count) == 5
              and occupied() == 5 - count, count .. '-line clear scores and compacts the board')
    end
    fixture(0, 1, 2, 18)
    for x = 0, 9 do if x ~= 4 then board(x, 21, 3) end end
    writeword('lines', 9)
    drop()
    until_true(function() return read('state') == 1 and idle() end, 'level transition')
    check(word('lines') == 10 and read('level') == 2 and long('score') == 100, 'ten lines increases level after scoring at the previous level')
    fixture(1, 0, 3, 1)
    write('level', 20); ticks(10)
    check(signed('piece_y') >= 6, 'maximum level falls at one cell per two ticks')

    fresh_game()
    local seen = {}
    for i = 1, 7 do
        local kind = read('piece')
        assert(not seen[kind], 'piece repeated inside a bag')
        seen[kind] = true
        fixture(kind, 0, 3, 5)
        drop()
    end
    check(true, 'a complete bag supplies each of the seven pieces once')
    fixture(1, 0, 3, 20)
    write('next_piece', 2); board(4, 2, 3)
    drop()
    check(read('state') == 3, 'blocked spawn ends the game')
    snapshot('game-over')
    local saved_best = long('best')
    ticks(50); tap(space)
    until_true(function() return read('state') == 1 and idle() end, 'restart')
    check(occupied() == 0 and long('score') == 0 and word('lines') == 0 and long('best') == saved_best, 'restart clears the board and preserves best score')
    fixture(0, 0, 3, 0)
    for x = 3, 6 do board(x, 2, 3) end
    drop()
    check(read('state') == 3, 'locking a piece in hidden rows ends the game')
    tap(escape)
    until_true(function() return read('state') == 0 and idle() end, 'Escape to title')
    check(read('state') == 0, 'Escape returns to the title')
    local file = assert(io.open('build/tetris/tetris.bin', 'rb'))
    local binary = file:read('a'); file:close()
    for i = 1, #binary do
        assert(mem:read_u8(0x6000 + i - 1) == binary:byte(i), string.format('program corrupted at %04X', 0x6000 + i - 1))
    end
    check(true, 'gameplay and tile rendering preserve the entire loaded program')
end

local finished = false
local function finish(ok, message)
    finished = true
    for _, input in ipairs(inputs) do input:clear_value() end
    if speaker_tap then speaker_tap:remove() end
    local result = assert(io.open(output .. '/result.txt', 'w'))
    result:write(ok and ('PASS ' .. checks .. ' checks\n') or ('FAIL ' .. tostring(message) .. '\n'))
    result:close()
    if not ok then print('FAIL ' .. tostring(message)); snapshot('failure') end
    machine:exit()
end
local thread = coroutine.create(suite)
emu.register_frame_done(function()
    if finished then return end
    frames = frames + 1
    if frames > 16000 then finish(false, 'suite watchdog'); return end
    local ok, message = coroutine.resume(thread)
    if not ok then finish(false, message)
    elseif coroutine.status(thread) == 'dead' then finish(true) end
end, 'frame')
