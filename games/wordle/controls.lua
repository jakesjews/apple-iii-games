-- Full alphabet input: no arcade modifier-key mappings in this word game.
-- MAME's Apple III Delete matrix entry has no encoder translation. Route host
-- Backspace to the real left-arrow key, which emits ASCII backspace ($08).
manager.machine.ioport.ports[':X7']:field(0x100):set_input_seq('standard',
    manager.machine.input:seq_from_tokens('KEYCODE_LEFT OR KEYCODE_BACKSPACE'))
