local t = dofile('tests/mame.lua')('2048')
local space, enter, undo, new = t.key('SPACE'), t.key('ENTER'), t.key('U'), t.key('N')
local arrows = {t.key('LEFT'),t.key('RIGHT'),t.key('UP'),t.key('DOWN')}
local function board(values)
    t.settle()
    for i = 0, 15 do t.array('board',i,values[i+1] or 0) end
    t.write('state',1); t.write('won',0); t.write('undo_valid',0)
    t.writelong('score',0); t.writeword('moves',0); t.write('spawned',0)
end
local function count()
    local n=0; for i=0,15 do if t.array('board',i)>0 then n=n+1 end end; return n
end
local function bytes(name) return t.mem:read_range(t.addr(name),t.addr(name)+15,8) end
t.run(function()
    t.tap(space)
    t.check(t.read('state') == 1 and count() == 2 and t.word('moves') == 0, 'new board has exactly two starting tiles')
    for _, key in ipairs(arrows) do t.tap(key) end
    t.check(t.word('moves') > 0 and count() >= 2, 'all four cursor keys play the board')
    if t.smoke then return end
    for i=1,32 do t.tap(arrows[(i*7)%4+1]) end
    t.check(t.long('score') > 0 and t.long('best') == t.long('score'), 'input-only play merges tiles and updates best')
    for y=34,167 do
        local row=0x2000+(y%8)*1024+(math.floor(y/8)%8)*128+math.floor(y/64)*40
        for _,col in ipairs({0,1,2,3,11,19,27,35,36,37,38,39}) do
            assert(t.mem:read_u8(row+col) == 0, 'tile digits escaped into a gutter')
        end
    end
    t.check(true, 'tile numbers stay inside their cells and preserve all gutters')
    t.snapshot('gameplay')
    local pixels, saved = t.pixels(), bytes('board')
    t.tap(t.key('P')); t.check(t.read('state') == 4, 'P pauses')
    pixels = t.pixels()
    t.tap(arrows[1]); t.ticks(20)
    t.check(bytes('board') == saved and t.pixels() == pixels, 'pause freezes the board and ignores moves')
    t.tap(t.key('P')); t.check(t.read('state') == 1, 'P resumes')

    board({1,1,1,1}); t.tap(arrows[1])
    t.check(t.array('board',0) == 2 and t.array('board',1) == 2 and t.long('score') == 8 and count() == 3, '2 2 2 2 becomes 4 4 plus exactly one new tile')
    t.check(t.read('spawned') == 1 and (t.read('last_value') == 1 or t.read('last_value') == 2), 'valid move spawns a 2 or 4 in an empty cell')
    board({1,1,2,0}); t.tap(arrows[1])
    t.check(t.array('board',0) == 2 and t.array('board',1) == 2 and t.long('score') == 4, 'a newly merged tile cannot merge again in the same move')
    board({1,0,1,1}); t.tap(arrows[1])
    t.check(t.array('board',0) == 2 and t.array('board',1) == 1 and t.long('score') == 4, 'gaps compact before a single directional merge')
    board({1,1,1,0}); t.tap(arrows[2])
    t.check(t.array('board',3) == 2 and t.array('board',2) == 1, 'right merges from the right edge')
    board({1,0,0,0,1,0,0,0,1,0,0,0,1}); t.tap(arrows[3])
    t.check(t.array('board',0) == 2 and t.array('board',4) == 2 and t.long('score') == 8, 'up merges columns toward the top')
    board({1,0,0,0,1,0,0,0,1}); t.tap(arrows[4])
    t.check(t.array('board',12) == 2 and t.array('board',8) == 1, 'down merges columns toward the bottom')
    board({1,2,3,4}); saved = bytes('board')
    local random = t.word('random_state')
    t.tap(arrows[1])
    t.check(bytes('board') == saved and t.read('spawned') == 0 and t.word('moves') == 0 and t.word('random_state') == random, 'no-op move does not spawn, score or consume randomness')
    board({1,1}); saved = bytes('board'); random = t.word('random_state')
    t.tap(arrows[1]); local moved = bytes('board')
    t.tap(undo)
    t.check(bytes('board') == saved and t.long('score') == 0 and t.word('moves') == 0 and t.word('random_state') == random, 'undo restores board, score, move count and random sequence')
    t.tap(arrows[1]); t.check(bytes('board') == moved, 'repeating an undone move produces the same new tile')
    t.tap(undo); t.tap(undo)
    t.check(bytes('board') == saved and t.read('undo_valid') == 0, 'undo cannot step back more than one move')
    board({1,1,0,0}); t.tap(arrows[1]); saved=bytes('board')
    -- Arrange a no-op without disturbing the saved undo slot.
    for i=0,15 do t.array('board',i,0) end
    for i=0,3 do t.array('board',i,i+1) end
    local previous = bytes('undo_board'); t.tap(arrows[1]); t.tap(undo)
    t.check(bytes('board') == previous, 'a no-op preserves the previous undo opportunity')
    board({10,10}); t.tap(arrows[1])
    t.check(t.array('board',0) == 11 and t.read('state') == 2 and t.long('score') == 2048, '1024 pair creates 2048 and the win screen')
    t.snapshot('won'); t.tap(enter)
    t.check(t.read('state') == 1 and t.read('won') == 1, 'Enter continues after reaching 2048')
    t.tap(undo); t.check(t.read('won') == 0 and t.array('board',0) == 10, 'undo can reverse the winning move')
    board({14,14}); t.write('won',1); t.tap(arrows[1])
    t.check(t.array('board',0) == 15 and t.long('score') == 32768, 'large tiles and scores do not overflow sixteen-bit arithmetic')
    board({15,15}); t.write('won',1); t.tap(arrows[1])
    t.check(t.array('board',0) == 15 and t.array('board',1) == 15 and t.read('spawned') == 0, '32768 tiles stay separate at the documented limit')
    board({1,2,1,2,2,1,2,1,1,2,1,2,2,1,2,1}); t.tap(arrows[1])
    t.check(t.read('state') == 3 and count() == 16, 'full board without adjacent matches ends the game')
    local best=t.long('best'); t.tap(new)
    t.check(t.read('state') == 1 and count() == 2 and t.long('score') == 0 and t.long('best') == best, 'new game resets the board and retains best')
    t.ticks(15); t.tap(t.key('M')); t.check(t.read('muted') == 1, 'M mutes sound')
    local edges=t.edges; board({1,1}); t.tap(arrows[1])
    t.check(t.edges == edges, 'muted merges produce no speaker toggles')
    t.ticks(15); t.tap(t.key('M')); t.check(t.read('muted') == 0, 'M restores sound')
    t.tap(t.key('ESC')); t.check(t.read('state') == 0, 'Escape returns to title')
    t.integrity()
end)
