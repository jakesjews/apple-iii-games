# Apple III Games

Native Apple /// games, built together in one repository. Each game boots directly
from its own floppy image. Shared 6502 platform code handles graphics, frame
timing, sound and booting; individual games live under `games/`.

## Star Siege ///

A Space Invaders-style arcade game for the Apple III. Defend against 32 animated
invaders, carve holes through four destructible bunkers, dodge enemy fire and
hunt the passing mystery ship. Surviving invaders accelerate. Each cleared wave
repairs the shields and brings a faster fleet. Three lives, an extra life at
1,500 points, and a high score retained until the machine resets.

![Star Siege running in MAME](docs/images/star-siege.png)

Native 280×192 color graphics, original pixel art and font, speaker effects,
pause, mute and restart. Requires at least 128 KB of RAM and the original Apple
III boot ROM. No SOS disk, Apple II emulation, expansion card or downloaded game
assets are needed.

## Build and play

Install [cc65](https://cc65.github.io/), Python 3.9 or later, Make and
[MAME](https://www.mamedev.org/). On macOS:

```sh
brew install cc65 mame
make
make run
```

The emulator needs your Apple III ROM set. Put these files under the ignored
`build/local-roms/` directory, or point `MAME_ROMPATH` at an existing MAME ROM
directory containing the `apple3` and `a3fdc` sets:

```text
build/local-roms/apple3/apple3.rom       4096 bytes, CRC32 1af7ec42
build/local-roms/a3fdc/341-0028-a.rom      256 bytes, CRC32 b72a2c70
```

```sh
MAME_ROMPATH=/path/to/mame/roms make run
```

ROMs are not part of the repository or generated game disks. The launcher selects
the original BIOS explicitly, so the optional SOSHDBOOT ROM is not required.
All emulator settings and snapshots stay under `build/`.

| Action | `make run` in MAME | Native Apple III keyboard |
| --- | --- | --- |
| Start / restart | Space or Return | Space or Return |
| Move | Hold Left/Right or A/D | Hold Open/Solid Apple |
| Fire | Hold Space or Shift | Hold Shift; Space also fires |
| Pause / resume | P | P |
| Mute / unmute | M | M |
| Return to title | Escape | Escape |

Native A/D and cursor keys also move the ship using keyboard repeat. The Apple
keys and Shift provide independent, continuous movement and firing. The MAME
launcher maps modern controls onto those real hardware inputs. Close the MAME
window to quit the emulator.

## Game disks

`make` produces two 140 KB boot images of the same game:

- `build/invaders/invaders.po` — ProDOS sector order; the default MAME image.
- `build/invaders/invaders.dsk` — DOS sector order; convenient for the MiSTer core.

Mount either image in the Apple III's **internal / first floppy drive**, then
reset or power on. Preserve the extension because it identifies the sector order.
These are standalone boot disks, **not SOS or ProDOS filesystems**. The game makes
no disk writes; high scores are held in RAM only.

For the Apple-III-MiSTer core, copy the `.dsk` into its game directory, mount it in
the internal drive and reset. This release was tested in MAME; physical Apple III
and FPGA hardware validation remains to be done.

## Test

```sh
make test
```

The tests cold-boot the actual disk in MAME, run the assembled 6502 game and save
screenshots under `build/invaders/test/`. Failures return a nonzero exit status.

- Three Python checks cover disk geometry, ROM block ordering and boot payloads.
- Thirty emulator checks cover native mode, controls, bounds, real shooting and
  scoring, speaker accesses, pause, mute, shield damage, mystery-ship scoring,
  extra lives, respawn protection, game over, restart and wave progression.
- Six additional boot/control checks run the `.dsk` with 128 KB of RAM. The full
  suite runs the `.po` with 256 KB.

The first gameplay tests use only emulated key presses. Later tests arrange rare
collision and end-of-wave situations in RAM, then let the game's actual code
resolve them. No game code or graphics are injected in place of booting.

Validated with MAME 0.289 and Homebrew cc65 2.19. `MAME`, `CL65`, `CA65`, `LD65`
and `PYTHON` can override tool paths. `make clean` removes generated game and test
directories while preserving `build/local-roms/`.

## Add another game

Create `games/<name>/main.c` and `games/<name>/sprites.json`. The top-level Makefile
discovers the directory and builds it with the common runtime:

```sh
make
make run GAME=<name>
```

Add `tests/<name>.lua` to enable `make test GAME=<name>`. See
[the platform guide](docs/platform.md) for the memory map, graphics API, asset
format, boot contract and source references.
