-- MAME 0.289 labels the port B switch Button 1 and the pushbutton Button 2.
-- Match MiSTer: host button 1 is the pushbutton, button 2 toggles the switch.
local input = manager.machine.input
local buttons = manager.machine.ioport.ports[':joy_buttons']
buttons:field(2):set_input_seq('standard', emu.input_seq())
buttons:field(1):set_input_seq('standard', emu.input_seq())
-- Parsing host joystick tokens without a connected device produces invalid
-- saved assignments in MAME. Keyboard play and input-port tests still work.
if not next(input.device_classes.joystick.devices) then return end
buttons:field(2):set_input_seq('standard', input:seq_from_tokens('JOYCODE_1_BUTTON1'))
local toggle = input:seq_from_tokens('JOYCODE_1_BUTTON2')
local down, latched = false, false
emu.register_frame_done(function()
    local pressed = input:seq_pressed(toggle)
    if pressed and not down then
        latched = not latched
        buttons:field(1):set_value(latched and 1 or 0)
    end
    down = pressed
end, 'frame')
