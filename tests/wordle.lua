-- Every scenario uses only real keyboard input; puzzle IDs select known answers.
local t = dofile('tests/mame.lua')('wordle','games/wordle/controls.lua')
local enter, back, escape, tab = t.key('ENTER'), t.key('LEFT'), t.key('ESC'), t.key('TAB')
local answers, words = {}, {}
for line in io.lines('games/wordle/answers.txt') do answers[#answers+1] = line end
for line in io.lines('games/wordle/words.txt') do words[#words+1] = line end
local function letters(name) return t.mem:read_range(t.addr(name),t.addr(name)+4,8) end
local function puzzle_id(word)
    for id=1,#answers do if answers[((id-1)*73)%#answers+1] == word then return id end end
    error('Missing answer: ' .. word)
end
local function select_id(id)
    if t.read('state') ~= 0 then t.tap(escape) end
    t.type(tostring(id)); t.tap(enter)
    t.until_true(function() return t.read('state') == 1 and t.idle() end,'start selected puzzle')
end
local function select(word) select_id(puzzle_id(word)) end
local function clear()
    while t.read('length') > 0 do t.tap(back) end
end
local function submit(word)
    t.type(word); t.tap(enter)
    t.until_true(function() return t.read('state') ~= 4 and t.idle() end,'letter reveal finishes')
end
local function grades(row, expected)
    for i=1,5 do if t.array('grades',row*5+i-1) ~= expected[i] then return false end end
    return true
end
t.run(function()
    select('APPLE')
    t.check(letters('answer') == 'APPLE' and t.read('attempt') == 0, 'numbered puzzle loads its repeatable answer')
    t.type('APP'); t.tap(enter)
    t.check(t.read('state') == 1 and t.read('attempt') == 0 and t.read('length') == 3, 'short guesses are rejected without spending an attempt')
    t.type('LEZZ')
    t.check(t.read('length') == 5 and letters('entry') == 'APPLE', 'typing beyond five letters is ignored safely')
    t.tap(back)
    t.check(t.read('length') == 4 and t.array('entry',4) == 0, 'Backspace edits the current word')
    if t.smoke then return end
    clear(); submit('ZZZZZ')
    t.check(t.read('valid_word') == 0 and t.read('attempt') == 0 and t.read('length') == 5, 'nonword guesses are rejected and remain editable')
    clear(); submit('EAGLE')
    t.check(t.read('valid_word') == 1 and t.read('attempt') == 1 and grades(0,{0,1,0,2,2}), 'exact matches reserve duplicate letters before yellow matches')
    submit('LEVEL')
    t.check(grades(1,{1,1,0,0,0}), 'extra copies turn gray after available letters are used')
    t.check(t.array('key_status',4) == 3 and t.array('key_status',11) == 3, 'keyboard green status is never downgraded by later guesses')
    submit('ALLEY')
    t.check(grades(2,{2,1,0,1,0}), 'one answer L produces only one yellow L')
    t.ticks(2)
    t.snapshot('gameplay')
    local edges=t.edges; submit('APPLE')
    t.check(t.read('state') == 2 and t.read('attempt') == 4 and grades(3,{2,2,2,2,2}), 'five correct letters win the round')
    t.check(t.word('played') == 1 and t.word('wins') == 1 and t.word('streak') == 1 and t.edges > edges, 'win updates session statistics and plays sound')
    t.snapshot('won')
    local id=t.word('puzzle'); t.tap(enter)
    t.check(t.read('state') == 1 and t.word('puzzle') == id%#answers+1 and t.read('attempt') == 0 and t.read('length') == 0, 'Return advances to a fresh numbered puzzle')
    for i=0,25 do assert(t.array('key_status',i)==0,'keyboard was not cleared') end
    t.check(true,'new puzzle clears all keyboard feedback')
    select('APPLE'); t.check(letters('answer') == 'APPLE', 'reselecting an ID reproduces the same answer')
    for _,word in ipairs({'CRANE','SOUND','BRICK','GHOST','PLUMB','FJORD'}) do submit(word) end
    t.check(t.read('state') == 3 and t.read('attempt') == 6, 'six wrong valid guesses lose the round and reveal the answer')
    t.check(t.word('played') == 2 and t.word('wins') == 1 and t.word('streak') == 0 and t.word('best_streak') == 1, 'loss records a completed round and resets the streak')
    t.snapshot('lost')
    local history=t.mem:read_range(t.addr('guesses'),t.addr('guesses')+35,8)
    t.type('APPLE')
    t.check(t.read('state') == 3 and history == t.mem:read_range(t.addr('guesses'),t.addr('guesses')+35,8), 'completed rounds ignore further letter entry')
    t.tap(enter); t.check(t.read('state') == 1, 'Return restarts after a loss')
    t.type('MANGO')
    t.check(t.read('state') == 1 and letters('entry') == 'MANGO' and t.read('muted') == 0, 'alphabet keys remain letters instead of arcade shortcuts')
    select('SHEEP'); submit('SPEED')
    t.check(grades(0,{2,1,2,2,0}), 'two repeated exact letters are both green')
    select('APPLE'); submit(words[1]); submit(words[#words])
    t.check(t.read('attempt') == 2 and t.read('valid_word') == 1, 'dictionary accepts its first and last alphabetic entries')
    t.ticks(15); t.tap(tab); t.check(t.read('muted') == 1,'Tab mutes without occupying a letter key')
    edges=t.edges; submit('AMPLE')
    t.check(t.edges == edges,'muted feedback has no speaker accesses')
    t.ticks(15); t.tap(tab); t.check(t.read('muted') == 0,'Tab restores sound')
    t.tap(escape); t.type('999'); t.tap(enter)
    t.check(t.read('state') == 0,'out-of-range puzzle numbers stay on the title')
    t.tap(back); t.tap(back); t.tap(back); t.type('0'); t.tap(enter)
    t.check(t.read('state') == 0,'puzzle zero is rejected')
    t.tap(back); select_id(#answers)
    t.check(letters('answer') == answers[((#answers-1)*73)%#answers+1], 'highest puzzle ID decodes the correct packed answer')
    t.tap(escape); t.tap(t.key('SPACE'))
    t.check(t.read('state') == 1 and t.word('puzzle') >= 1 and t.word('puzzle') <= #answers,'Space starts a random valid puzzle')
    t.tap(escape); t.check(t.read('state') == 0,'Escape returns to title')
    t.integrity()
end)
