# Native Apple III platform

The game logic is C compiled for the NMOS 6502 using cc65's `none` target. The
platform is deliberately small: a boot block, startup, bitmap renderer, VBL wait
and speaker effects. It does not depend on another checkout, a host-side game
engine, SOS or an Apple II runtime.

## Layout

```text
games/<game>/main.c          game rules, state and screen composition
games/<game>/sprites.json    original, editable pixel art
games/<game>/controls.lua    optional MAME keyboard mapping
platform/apple3/             shared native hardware code and font
platform/apple3/ui.h         small C helpers for text, numbers, titles and keys
tools/assets.py             sprite shifts and font tables
tools/disk.py               boot block and disk image construction
tools/mame.py               emulator launch and test result checking
tests/                      disk tests and emulator scenarios
build/<game>/               generated binaries, labels, disks and screenshots
```

The linker emits a map, VICE labels and a cc65 debug file. MAME tests resolve C
variables from the labels rather than baking addresses into scenarios.

## Memory map

| CPU address | Purpose |
| --- | --- |
| `$0040–$007F` | cc65 and renderer zero-page workspace |
| `$0100–$01FF` | hardware stack in the system bank |
| `$2000–$3FFF` | native graphics pixels, physical bank 0 `$0000–$1FFF` |
| `$4000–$5FFF` | native graphics color attributes, physical bank 0 `$2000–$3FFF` |
| `$6000–$9FFF` | up to 16 KB of code, assets and initialized data in bank 0 |
| `$A000–$A1FF` | system-bank boot block |
| `$A200–$B7FF` | system-bank BSS |
| `$B800–$BFFF` | reserved downward-growing cc65 software stack |
| `$C000–$CFFF` | hardware I/O |
| `$F000–$FFFF` | original boot ROM, with VIA registers at `$FFD0–$FFEF` |

Startup selects native mode and bank zero (`$FFEF = $40`), unrelocated zero page,
the primary stack, 2 MHz operation, I/O and video (`$FFDF = $77`). Interrupts are
disabled. Game frames poll the E VIA's CB2 vertical-blank flag; game speed is
bounded by the real emulated CPU, not a host clock. Expensive fleet redraws can
span more than one display frame.

## Boot and disk ordering

The original Apple III ROM reads block zero into `$A000` and jumps there. The
512-byte loader calls the ROM's `BLOCKIO` routine at `$F479` to read successive
512-byte blocks into `$6000`. It retains the ROM's disk workspace until loading
finishes, stops the disk motor and jumps to the runtime. A read failure displays
a message and offers a keypress retry.

`tools/disk.py` assembles that loader using the actual payload block count,
rejects payloads larger than 16 KB and pads the image to 35 tracks × 16 sectors ×
256 bytes. It writes both `.po` and `.dsk` order. The disk-order test independently
uses the boot ROM's physical sector-pair table to check all 280 blocks.

These images contain only our boot block and game payload. They carry no
filesystem directory, third-party boot code or Apple ROM bytes.

## Graphics and input

`apple3.h` exposes the platform API. Set `gfx_x`, `gfx_y` and `gfx_color` before
drawing. Color is the foreground palette nibble in bits 7–4, with black in the
background nibble. `gfx_y` is always a pixel scanline.

- `video_init()` selects native 280×192 color mode and clears the screen.
- `video_clear()` clears both 8 KB graphics planes.
- `video_sprite(id)` XORs a 14×8 sprite. Drawing twice erases it. Valid positions
  are `x = 0..255`, `y = 0..184`; the renderer does not clip.
- `video_text(string)` writes the original 5×7 font in 7×8 cells. Here `gfx_x` is
  a text column, `0..39`. Strings stop at the right edge. Use uppercase ASCII.
- `video_tile(pattern)` overwrites a 7×8 cell from eight row bytes, bit 0 at the
  left. Like text, `gfx_x` is a column (`0..39`); `gfx_y` must be `0..184`.
  This primitive does not clip. Blockfall aligns its board with these color cells.
- `video_pixel(set)` and `video_read_pixel()` address one pixel, with `x <= 255`
  and `y <= 191`. The read returns zero or the set bit's mask.
- `gfx_band_y` / `gfx_band_color` optionally keep sprites below a given scanline
  in a fixed color. Star Siege uses a green shield/player band so crossing shots
  cannot permanently recolor the bunkers. `gfx_band_y = 192` disables it.
- `wait_frame()` waits for the next vertical-blank edge.
- `sound(effect)` plays one of the five short speaker effects in `apple3.h`;
  `muted` suppresses them. Effects run briefly on the CPU rather than in an IRQ.

Video switches are `$C051`, `$C052`, `$C054`, `$C057`: VM0 color, VM1 280 pixels,
VM2 page zero, VM3 graphics. `$C0D8` and `$C0DA` disable scrolling and character
downloads. A scanline has the standard interleaved offset:

```text
(y % 8) * 1024 + ((y / 8) % 8) * 128 + (y / 64) * 40
```

There are seven pixels per byte and a foreground/background attribute byte for
each group. This is native Apple III color, with the associated attribute-sharing
constraints.

Sprites are JSON objects mapping names to eight strings of at most 14 characters;
`#` is a pixel and `.` is transparent. The generator pads rows and produces all
seven horizontal shifts as three 7-bit bytes per scanline. It also generates C
IDs in `assets.h`. The font source lives in `platform/apple3/font.json`.
Games using tiles rather than sprites can supply an empty JSON object; the font
is still generated. Text and tiles share the same scanline writer.

Read keys from `$C000` and **write to `$C010` to acknowledge** them. The installed
cc65 optimizer removed a discarded `(void)` volatile read, which caused repeated
keys; the write is required and the pause test protects this behavior. Modifier
bits in `$C008` let the two Apple keys and Shift work simultaneously. The MAME
launcher maps host A/Left, D/Right and Space onto these modifier inputs through
MAME's standard input API. It does not synthesize game state.
Blockfall adds Control for held soft drop. Its Shift edge detects hard drop and
ignores a duplicate Space character on the release tick. A per-game
`controls.lua` overrides the default mapping in `tools/mame.py`.

### Native joystick

The arcade games link `platform/apple3/joystick.s`. Call `joystick_init()` once,
then `joystick_poll()` every game tick, including while paused. `joy` contains
held `JOY_LEFT`, `JOY_RIGHT`, `JOY_UP`, `JOY_DOWN`, `JOY_BUTTON` and `JOY_SWITCH`
bits. `joy_pressed` contains rising edges; `joy_switch_changed` reports either
edge of the latching switch. `joy_x`/`joy_y` expose the sampled axes, with Y
increasing upward. Values 96–160 are neutral.

Port B is the default first controller on MiSTer. Its X/Y channels are 1/2,
pushbutton is `$C062` bit 7, and switch is `$C060` bit 7. The 9708 ADC charges
for 500 D VIA ticks, then its discharge is timed using **D VIA timer 2**, which
this API reserves. This avoids dependence on CPU speed or video bus contention.
The approximately 350-tick offset and eight ticks per position follow the core's
SOS joystick range. Counter reads retry across a low-byte rollover; out-of-range
or timed-out conversions return center. Every discharge is bounded to about
4 ms. These routines use native hardware directly without SOS or copied ROM code.

`tools/joystick.lua` accounts for MAME 0.289's reversed button labels on port B
and turns the host's second button into a toggle. MAME already reverses its Y
axis in the ADC model. Games must consume input edges during pause so a held up
direction or button does not become an extra action on resume.

## Verification and references

`tests/invaders.lua` first boots and plays using keyboard input alone. It then
places controlled fixtures while the CPU is waiting for VBL, including projectiles
about to hit, the final invader, and a fleet about to breach the shield line.
These exercise the actual compiled collision and transition code. Fixture
screenshots are diagnostic, not evidence of a complete unassisted playthrough.
The documentation's gameplay screenshot comes from the input-only section.

`tests/tetris.lua` likewise starts with keyboard-only play, including simultaneous
Space/Shift press and release, movement, hold, rotation, pause and sound. Its board
fixtures cover every piece and rotation, kicks and blocked rotation, grounded
lock delay, all four line-clear counts and row compaction, bag order, level
progression and both spawn/hidden-row top-out. Tests verify that gameplay has not
overwritten the loaded program. `make test-all` runs every game and the shared
disk checks; each game boots with both disk orders and with 128 KB and 256 KB RAM.

New game suites use `tests/mame.lua` for symbol lookup, keyboard input, snapshots,
VBL-safe fixtures, speaker observation and fail-closed result reporting. Brick
Bash checks real rallies before arranging precise paddle, wall and brick
contacts. Its ball advances in single-pixel collision substeps at every speed.
Merge 2048 checks include single-merge rules, deterministic undo, large tile
values and clear gutters around rendered numbers. Word Five tests operate through
keyboard input throughout and select known answers using numbered puzzles.

Word Five stores its compressed dictionary and answer references in the program's
read-only segment. `tools/wordlist.py` builds the header from vendored text inputs;
host tests independently round-trip the complete lexicon and check every puzzle
ID. The game remains within the same 16 KB payload limit as the arcade games.

MAME validation is distinct from physical or FPGA validation. The generated disks
are ready for a hardware smoke test, but no hardware result is claimed here.

Hardware and emulator references used during implementation:

- [MiSTer joystick ADC model](https://github.com/jakesjews/Apple-III-MiSTer/blob/7f30d4dc1830a86d935ac08b318965714f9b2d6d/rtl/apple3_io.sv)
  and [joystick timing verification](https://github.com/jakesjews/Apple-III-MiSTer/blob/7f30d4dc1830a86d935ac08b318965714f9b2d6d/sim/joystick/adc.s):
  channel/switch wiring, Y polarity and acquisition/discharge timing. On
  2026-09-18, `tools/test_joystick_core.py` passed 5,120 checks against a snapshot
  of the sibling core checkout, including its then-uncommitted peripheral-wait,
  VIA-select and horizontal-boundary timing changes based on this revision.
  Netlists were freshly generated from that snapshot; the source checkout was
  untouched. All 1,024 paired samples passed across every position and four
  CPU/video settings, with a maximum axis error of 3/255. The production joystick
  assembly is linked into an original test ROM; no Apple ROM is needed here.
- [MAME 0.289 native ADC implementation](https://github.com/mamedev/mame/blob/mame0289/src/mame/apple/apple3_m.cpp):
  analog input fields, Y reversal and port B's button/switch ordering.

- [Apple III Boot ROM Listing, David T. Craig collection](https://www.apple3.org/Documents/SourceCode/DTCA3DOC-085_apple_3_boot_rom_listing.pdf):
  block-zero handoff, `$F479`, parameter block and sector pairing.
- [Apple III Bits, John Jeppson](https://mirrors.apple2.org.za/Apple%20II%20Documentation%20Project/Computers/Apple%20III/Apple%20III/Documentation/AppleIIIBits.html):
  native memory and graphics programming.
- [MAME Apple III machine implementation](https://github.com/mamedev/mame/blob/mame0289/src/mame/apple/apple3_m.cpp)
  and [video implementation](https://github.com/mamedev/mame/blob/mame0289/src/mame/apple/apple3_v.cpp):
  cross-checks for banking, keyboard, speaker and color planes.
- [MAME Lua documentation](https://docs.mamedev.org/luascript/index.html):
  input injection, CPU memory inspection, speaker access observation and snapshots.
- [cc65 documentation](https://cc65.github.io/doc/): compiler, linker and calling
  convention.

The artwork, font, boot block, game and platform sources in this repository were
created for this collection. The hardware references informed the implementation;
their ROMs and source files are not bundled. Word Five includes a derived ESDB
word list with its [source attribution and license](../games/wordle/README.md).
