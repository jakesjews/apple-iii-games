-- Map modern controls to independently readable Apple III modifier keys.
-- These are ordinary emulated key presses, not writes into game memory.
local port = manager.machine.ioport.ports[":keyb_special"]
local input = manager.machine.input
port:field(0x10):set_input_seq("standard", input:seq_from_tokens("KEYCODE_LEFT OR KEYCODE_A OR KEYCODE_LALT"))
port:field(0x20):set_input_seq("standard", input:seq_from_tokens("KEYCODE_RIGHT OR KEYCODE_D OR KEYCODE_RALT"))
port:field(0x02):set_input_seq("standard", input:seq_from_tokens("KEYCODE_SPACE OR KEYCODE_LSHIFT"))
