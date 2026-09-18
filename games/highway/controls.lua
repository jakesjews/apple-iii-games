dofile('tools/controls.lua')
local input = manager.machine.input
manager.machine.ioport.ports[':keyb_special']:field(0x08):set_input_seq('standard', input:seq_from_tokens('KEYCODE_DOWN OR KEYCODE_S OR KEYCODE_LCONTROL'))
