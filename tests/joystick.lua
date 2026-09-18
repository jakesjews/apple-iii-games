-- Exercise the actual ADC, buttons and compiled games through MAME input
-- fields. Button 2 is a latching switch on the Apple III, not a second trigger.
local game = assert(os.getenv('A3_TEST_GAME'))
local controls = game == 'tetris' and 'games/tetris/controls.lua' or 'tools/controls.lua'
local t = dofile('tests/mame.lua')(game, controls)
local x, y = t.field('joy_1_x',255), t.field('joy_1_y',255)
local button, switch = t.field('joy_buttons',2), t.field('joy_buttons',1)
local escape, pause = t.key('ESC'), t.key('P')
local active = 1
local paused = game == 'breakout' and 3 or 2
local position = game == 'invaders' and 'player_x' or game == 'tetris' and 'piece_x' or 'paddle_x'
local function xpos()
    local n = t.read(position)
    return game == 'tetris' and n >= 128 and n-256 or n
end
local function neutral()
    x:set_value(128); y:set_value(128); button:set_value(0); t.ticks(2)
end
x:set_value(128); y:set_value(128); button:set_value(0); switch:set_value(1)

t.run(function()
    t.check((t.read('joy') & 15) == 0, 'centered stick has no direction')
    t.check(t.read('joy_switch_changed') == 0, 'switch left on at boot is not a press')
    button:set_value(1); t.ticks(3)
    t.check(t.read('state') == active, 'joystick pushbutton starts the game')
    t.ticks(15)
    if game == 'breakout' then
        t.check(t.read('state') == 1, 'held start button waits for a separate serve press')
    elseif game == 'tetris' then
        t.check(t.read('rotation') == 0 and t.word('pieces_locked') == 0, 'held start button does not rotate or drop the first piece')
    end
    neutral()
    local start = xpos()
    x:set_value(0); t.ticks(17)
    t.check(xpos() < start and (t.read('joy') & 3) == 1, 'analog left moves continuously')
    local left = xpos()
    x:set_value(255); t.ticks(17)
    t.check(xpos() > left and (t.read('joy') & 3) == 2, 'analog right reverses movement')
    neutral(); start = xpos(); t.ticks(10)
    t.check(xpos() == start, 'centering stops horizontal movement')
    for _, value in ipairs({112,128,144}) do
        x:set_value(value); y:set_value(value); t.ticks(2)
        t.check((t.read('joy') & 15) == 0, 'center dead zone rejects drift at ' .. value)
    end
    neutral()

    if game == 'invaders' then
        local start_x = xpos()
        x:set_value(0); button:set_value(1); t.ticks(5)
        t.until_true(function() return t.read('shot_y') ~= 255 end, 'joystick fire')
        t.check(xpos() < start_x and (t.read('joy') & 17) == 17, 'ship moves and fires simultaneously')
        neutral()
    elseif game == 'breakout' then
        button:set_value(1); t.ticks(3)
        t.check(t.read('state') == 2 and t.read('ball_y') < 164, 'second button press launches the ball')
        active = 2
        neutral()
    else
        button:set_value(1); t.ticks(3)
        t.check(t.read('rotation') == 1, 'pushbutton rotates clockwise')
        t.ticks(15)
        t.check(t.read('rotation') == 1, 'held button rotates only once')
        neutral(); button:set_value(1); t.ticks(3)
        t.check(t.read('rotation') == 2, 'release and repress rotates again')
        neutral()
        local locked = t.word('pieces_locked')
        y:set_value(0); t.ticks(3)
        t.check(t.word('pieces_locked') == locked+1, 'stick up hard drops one piece')
        t.ticks(18)
        t.check(t.word('pieces_locked') == locked+1, 'held up cannot hard drop the next piece')
        neutral()
        local height, score = t.read('piece_y'), t.long('score')
        y:set_value(255); t.ticks(10)
        t.check(t.read('piece_y') >= height+4 and t.long('score') >= score+4, 'stick down soft drops and earns points')
        neutral()
    end

    switch:set_value(0); t.ticks(2)
    t.check(t.read('state') == paused, 'switch transition pauses')
    local pixels, before_x = t.pixels(), xpos()
    local locked = game == 'tetris' and t.word('pieces_locked') or 0
    x:set_value(0); y:set_value(0); button:set_value(1); t.ticks(15)
    t.check(t.read('state') == paused and xpos() == before_x and pixels == t.pixels(), 'joystick and held switch preserve the paused game')
    switch:set_value(1); t.ticks(2)
    t.check(t.read('state') == active, 'opposite switch transition resumes')
    if game == 'tetris' then
        t.check(t.word('pieces_locked') == locked, 'up pressed while paused is not queued as a hard drop')
    end
    neutral(); t.ticks(25); t.tap(pause)
    t.check(t.read('state') == paused, 'keyboard pause still works alongside the joystick')
    t.ticks(25); t.tap(pause)
    t.check(t.read('state') == active, 'keyboard resumes with the switch still on')
    t.snapshot('joystick')

    -- A comparator that never falls must time out, neutralize the stick,
    -- and leave the game responsive. No game variable is changed for this test.
    local stuck = t.mem:install_read_tap(0xC066,0xC066,'stuck-adc',function() return 0x80 end)
    x:set_value(0); y:set_value(0); t.ticks(3)
    t.check(t.read('joy_x') == 128 and t.read('joy_y') == 128 and (t.read('joy') & 15) == 0, 'ADC timeout returns neutral without hanging the game')
    t.tap(escape)
    t.check(t.read('state') == 0, 'keyboard remains responsive with a stuck ADC')
    stuck:remove(); neutral()
    button:set_value(1); t.ticks(3)
    t.check(t.read('state') == 1, 'joystick can start another game')
    neutral()
    -- Arrange only the end state; the normal game loop must handle retry.
    t.write('state', game == 'breakout' and 4 or 3); t.write('transition_timer',0)
    button:set_value(1); t.ticks(3)
    t.check(t.read('state') == 1, 'pushbutton retries after game over')
    neutral()
    -- Star Siege's initialized PRNG byte lives in writable DATA in the payload.
    t.integrity(game == 'invaders' and t.addr('random_state') or nil)
end)
