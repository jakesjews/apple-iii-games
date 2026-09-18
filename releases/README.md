# Apple III Games for MiSTer

Six ready-to-play boot disks for an already installed
[Apple-III-MiSTer core](https://github.com/jakesjews/Apple-III-MiSTer).

## Copy and play

1. Extract `Apple-III-Games.zip` and merge its `games` folder into the root of
   your MiSTer's SD card (`/media/fat/`). You can also upload the unpacked
   `games/Apple-III/Apple-III-Games/` folder directly to
   `/media/fat/games/Apple-III/Apple-III-Games/` over the network.
2. Launch the Apple III core. Open its menu with **Windows + F12** (Command on
   a Mac keyboard) or the **OSD button**. Choose **Mount Drive 1**, open
   **Apple-III-Games**, and select a game's `.dsk` file.
3. Close the menu and press **Ctrl + F12** for a hardware reset. The game boots
   directly. Press **Space** or **Return** at its title to start. The four
   arcade games also start with **joystick button 1**.

To switch games, mount another disk in **Drive 1** and press **Ctrl + F12**.
The core's [setup and controls](https://github.com/jakesjews/Apple-III-MiSTer#controls)
describe these menu and reset shortcuts.

After copying, the disks are here:

```text
/media/fat/games/Apple-III/Apple-III-Games/
    Star Siege.dsk
    Blockfall.dsk
    Brick Bash.dsk
    Merge 2048.dsk
    Word Five.dsk
    Highway III.dsk
    README.md
    WORDLIST-LICENSE.txt
```

| Disk | Game |
| --- | --- |
| Star Siege.dsk | Space Invaders-style shooter with shields, waves and a mystery ship |
| Blockfall.dsk | Tetris-style falling blocks with hold, preview and a ghost piece |
| Brick Bash.dsk | Breakout-style paddle game with sixty bricks and advancing stages |
| Merge 2048.dsk | Sliding-number puzzle with undo and play beyond 2048 |
| Word Five.dsk | Five-letter word puzzle with 405 numbered answers and six guesses |
| Highway III.dsk | Three-stage road racer with traffic, hills and a tunnel; **256 KB required** |

## Joystick controls on MiSTer

Use **controller 1** with the core's **Joystick 1 on** option set to **Port B**
(the default). The D-pad or left analog stick controls movement. The stick has
a center dead zone, and keyboard controls remain available.

| Game | Stick / D-pad | Button 1 | Button 2 |
| --- | --- | --- | --- |
| Star Siege | Left/right moves | Hold to fire; press to start/retry | Pause/resume |
| Blockfall | Left/right moves; down soft drops; up hard drops | Rotate clockwise; press to start/retry | Pause/resume |
| Brick Bash | Left/right moves | Serve; press to start/retry | Pause/resume |
| Highway III | Left/right steers; down brakes | Hold to accelerate; press to start/retry | Pause/resume |

Blockfall requires a new up press for each hard drop and a new button press for
each rotation. Its keyboard **Z** and **C** still rotate counterclockwise and
hold a piece. Brick Bash waits for a separate button press to serve after start.

The core turns button 2 into the Apple III joystick's latching switch. Each
press toggles pause; there is no need to hold it or reset the switch before play.

## Keyboard controls on MiSTer

For the four arcade games, hold **Windows/Command** to move left and **Alt** to
move right. These are the core's Open Apple and Solid Apple keys. Use these
modifier keys for continuous movement; a held arrow key also activates Solid
Apple in this core.

| Game | Controls |
| --- | --- |
| Star Siege | Windows/Command and Alt move; hold Shift to fire. Space also fires. |
| Blockfall | Windows/Command and Alt move; X/Z rotate; hold Ctrl to soft drop; Shift or Space hard drops; C holds/swaps. |
| Brick Bash | Windows/Command and Alt move; Space, Return or Shift serves the ball. |
| Highway III | Windows/Command and Alt steer; hold Shift to accelerate; hold Ctrl to brake. |
| Merge 2048 | Arrows or WASD slide; U undoes; N starts a new board; Return continues after reaching 2048. |
| Word Five | Type letters; Return submits; Left Arrow deletes; Tab toggles sound. |

**Space/Return** starts or retries. **Escape** returns to the title. In Star
Siege, Blockfall, Brick Bash, Highway III and Merge 2048, **P** pauses and **M** toggles sound.
In Word Five, type a puzzle number **1–405** at the title and press **Return**;
**Space** chooses a random puzzle. After a round, **Return** starts the next
puzzle. Letter keys always enter letters while guessing.

Scores and statistics last until the core resets. These games do not write to
their disks.

## Build details

Each `.dsk` is a 140 KiB native Apple III boot disk in **DOS sector order**. Keep
the `.dsk` extension. Each game runs directly from Drive 1 without an SOS disk.
Highway III requires 256 KiB RAM; the other five require 128 KiB. All use the
original Apple III boot ROM supplied by the installed core's normal configuration.

The first five disks have been booted and exercised in MAME with 128 KiB RAM.
Highway III is tested with 256 KiB, including a complete controller-driven tour,
and shows a clear requirement message on a 128 KiB machine.
The joystick reader was also tested on the core's CPU, VIA and ADC simulation
at all 256 positions, with video on/off and both CPU speeds.
Physical MiSTer validation remains to be done.

Run `make release` from the source repository to rebuild the unpacked disks,
ZIP and `SHA256SUMS`. Checksums use paths relative to `releases/`; verify with
`sha256sum -c SHA256SUMS` on Linux or `shasum -a 256 -c SHA256SUMS` on macOS.
Keep `WORDLIST-LICENSE.txt` with Word Five when redistributing it.
