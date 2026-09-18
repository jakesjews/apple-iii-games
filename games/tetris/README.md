# Blockfall ///

A native Apple III falling-block game inspired by Tetris. The game, graphics,
sound and boot disk are built from the sources in this repository.

```sh
make
make run GAME=tetris
```

![Blockfall](../../docs/images/blockfall.png)

## Controls

| Action | MAME launcher | Native keyboard |
| --- | --- | --- |
| Start / retry | Space or Return | Space or Return |
| Move left / right | Hold arrows or A/D | Hold Open/Solid Apple |
| Rotate clockwise | Up or X | Up or X |
| Rotate counterclockwise | Z | Z |
| Soft drop | Hold Down or S | Hold Control |
| Hard drop | Space or Shift | Shift or Space |
| Hold / swap | C | C |
| Pause / resume | P | P |
| Mute / unmute | M | M |
| Return to title | Escape | Escape |

On native hardware, A/D and the arrow keys also work through keyboard repeat;
Down/S briefly accelerate the piece. The Apple keys, Shift and Control can be
read independently, allowing movement while dropping. The MAME launcher maps
familiar controls to these real modifier inputs. Mapped Space and Shift trigger
one hard drop per press; a native unmodified Space follows keyboard repeat.

## Rules

- The well is ten columns by twenty visible rows, with two hidden rows above it.
  Pieces spawn fully visible. The seven shapes appear once each per shuffled bag.
- A preview shows the next piece. C stores the current piece or swaps with hold.
  You can hold once per piece, re-enabled after that piece locks.
- The gray outline shows where a hard drop will land. Soft drop earns one point
  per cell descended; hard drop earns two.
- Clearing one, two, three or four rows awards 100, 300, 500 or 800 points,
  multiplied by the level before the clear. Rows flash, then the board compacts.
- Every ten total lines raises the level, capped at 20. Gravity ranges from one
  cell per 48 game ticks to one per two ticks. Timing follows the emulated CPU
  and vertical blank; rendering and speaker effects can span display frames.
- A piece has 30 game ticks to lock once grounded. Successful moves and rotations
  can reset that delay at most eight times. Hard drop locks immediately.
- Rotations try the original position, one/two cells left or right, then one/two
  cells up. These are simple wall/floor kicks, not the official SRS rotation rules.
- A blocked spawn or a piece locking into either hidden row ends the run. Space
  restarts after a short delay. Best score survives retries, but not a reset.

Score caps at 999,999; line and placement counters cap at 9,999. There are no
T-spin, combo or back-to-back bonuses, and no saved scores on disk.

## Build and verification

`build/tetris/tetris.po` is in ProDOS sector order and `tetris.dsk` is in DOS
sector order. Both boot from the internal floppy drive without SOS. See the
[repository instructions](../../README.md) for ROM setup and hardware use.

```sh
make test GAME=tetris
```

The suite boots both disk formats in MAME, plays through actual keyboard inputs,
then checks controlled board positions using the compiled game. It covers every
shape and rotation, one-to-four-line clears, scoring, lock delay, hold, top-out,
restart, sound and program integrity. The screenshot above is from input-only
play. MAME validation does not substitute for testing on a physical Apple III or
the FPGA core.
