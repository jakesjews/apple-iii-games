-- The two Apple keys provide independent movement. Control is held soft drop;
-- Shift is an edge-triggered hard drop. Letter keys still reach the keyboard.
dofile('tools/controls.lua')
local port = manager.machine.ioport.ports[':keyb_special']
port:field(0x08):set_input_seq('standard', manager.machine.input:seq_from_tokens('KEYCODE_DOWN OR KEYCODE_S OR KEYCODE_LCONTROL'))
