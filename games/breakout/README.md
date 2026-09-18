# Brick Bash ///

A Breakout-style game for the native Apple III. Run `make run GAME=breakout`.

![Brick Bash](../../docs/images/brick-bash.png)

Hold Left/Right or A/D to move in MAME. On an Apple III, hold the Open/Solid Apple
keys; A/D and cursor keys also move with keyboard repeat. Space or Return starts
the game and serves the ball; Shift also serves. P pauses, M toggles sound, and
Escape returns to the title. A missed ball waits for another serve.

There are sixty bricks and three lives. Paddle edges send the ball sharply left
or right; the middle produces a steeper rebound. Bricks score 10–60 points from
the bottom row to the top. From stage two, the outlined top bricks require two
hits and score only when destroyed. The ball speeds up every two stages, capped
at stage seven. Every movement is resolved in single-pixel substeps so the ball
cannot skip a thin brick at higher speeds.

Clear the wall to advance. Best score persists across retries, but resets with
the machine. Score caps at 999,999 and the displayed stage caps at 99.

`make test GAME=breakout` boots both disk formats in MAME and checks controls,
collision angles, armor, scoring, lives, stages and program integrity. The
screenshot is from keyboard-input play. Disk images are
`build/breakout/breakout.po` and `build/breakout/breakout.dsk`; mount either in the
internal floppy drive. See the [root guide](../../README.md) for ROM setup.
