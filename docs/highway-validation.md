# Highway /// validation — 2026-09-18

The game is built for a native 256 KB Apple III with the original boot ROM.
The released disk and ZIP are under `releases/`. No Apple ROM is distributed.

## Results

- **6 Python checks** pass for disk geometry, payload placement and word data.
- **465 MAME checks** pass across all six games. Highway contributes 111: 44
  gameplay/rendering checks on the ProDOS-order disk, 12 on the DOS-order disk,
  five for each complete controller-driven tour, 22 rendering checks per disk
  format, and the 128 KB rejection check.
- Highway's suite verifies the timer, DAC output and mute, keyboard and joystick
  inputs, pause, off-road slowdown, collisions, overtaking, tunnel transitions,
  both checkpoints, the finish, timeout, retry, best-score retention, sharp-turn
  background restoration, and every byte of the loaded asset banks,
  runtime-expanded banks and program.
- The complete tour driver only changes joystick input ports. Both disk formats
  finish all three stages. The recorded run takes approximately **94 seconds**,
  survives ten collisions and finishes with time remaining.
- **10 RTL checks** pass using the local Apple-III-MiSTer CPU, video, RAM, VIAs,
  DAC and ADC. They cover startup, timer activity, acceleration, pause/resume,
  audio, both display pages, banked sprite execution, and **zero writes to the
  displayed graphics page during racing**.
- The ZIP-extracted Highway disk boots and passes the 12-check smoke suite.
  Release checksums match, and a clean build reproduces the disk bytes.

The other five game disks remain byte-for-byte unchanged.

The rendering suite compares both graphics pages against a full reconstruction
across twelve camera/hill/stripe combinations, overlapping traffic, and finish
banner appearance/removal. It also verifies zero framebuffer writes on unchanged
paused frames, one-digit speed updates, timer warning colors, and digit carries.
The added checks observe partial sprite execution and compare its result against
full reconstruction. A separate comparison with `d0925da` covers 48 frozen scenes
across all three stages and 16 sprite scales: all **860,160 pixel/attribute bytes**
match exactly on both pages.

## Timing

These are measured rendered frame rates, rather than a claim based on the
nominal CPU frequency:

| Workload | MAME 0.289 | Current core RTL |
| --- | --- | --- |
| Attract scene | About 23.4 fps, 5-second sample | About 25.3 fps, 3-second sample |
| Complete controller-driven race | About 11.1 fps, 94-second run | Not measured over a complete tour |
| Steering and traffic sample | Included in the complete run above | About 13.3 fps, 4-second sample |

The preceding build (`d0925da`) averaged **10.64 fps** over a complete MAME
tour; this build averages **11.07 fps**, about **4% faster**. Attract mode improves
from 18.2 to 23.4 fps (about 29%). A render-focused fixture, with 48 frozen scenes
and four stripe changes per scene, improves from 47.10 to 36.42 ms/frame.
The fixture includes vertical-blank waits and omits active racing physics.

The controller is closed-loop, so traffic, collisions and tour duration differ
as frame pacing changes. These are complete-play benchmarks, not identical
instruction traces. The core's short driving sample changes from 13.75 to 13.25
fps; it does **not** establish a racing improvement on the FPGA. The core sample
is shorter and should not be presented as a full-race average.

This pass adds:

- Eight horizontal damage regions per two-line band, with precomputed road
  footprints. Erasure on plain ground/asphalt does not invalidate road markings.
- Generated blitters that skip untouched row pairs. Partial redraws propagate
  damage only through the pairs actually drawn, preserving painter order.
- Color-specialized car routines expanded once at boot from compressed disk
  data into banks five and six. Palette lookups are removed from car drawing.
- Resident car address tables in zero pages `$18..$1F`. Scenery borrows `$18`
  and invalidates its resident car; speech and skyline loads restore all sister
  bytes. The completed boot loader's memory becomes the C software stack.

The previous four optimizations remain:

- Per-page geometry/stripe history skips unchanged two-scanline road bands.
  Erased sprites invalidate affected bands, and clipped lane/edge aliases remain
  correct when only stripe colors change.
- Sprites retain per-page address tables and skip unchanged, undamaged objects.
  Erasure uses straight-line span stores; scene preparation and speech invalidate
  the affected caches before drawing resumes.
- Highway uses `-Oirs -Cl --codesize 500`. Its C routines are nonrecursive and
  never run from interrupts, so static locals are safe. Projection uses bounded
  8-bit coordinates and generated dimensions; tables replace repeated arithmetic.
- Each HUD digit is cached per page and drawn through a specialized assembly
  routine. Color changes invalidate the time digits even if their value is equal.

The original **30 fps target was not achieved**, nor a sustained 15 fps race.
Drawing cost varies with steering, traffic sizes, hills and the checkpoint banner. Driving physics uses
a 50 Hz fixed step derived from the VIA clock, with bounded catch-up. Scene
preparation and the spoken countdown do not consume race time.

## Core provenance and scope

The test uses a fresh snapshot of the user's sibling checkout, including its
uncommitted core-test changes, based on:

- Commit: `f723fda16431cdbb1e5b47b29c11b3fdbf412288`
  (`Implement the virtual block-storage card`).
- Working-tree snapshot SHA-256:
  `a5f73b272ce2a94c7af2f3fe148b3bb73238c93b017ee5ef93819169c016d268`.

The harness preloads the actual linked program and asset banks and starts them
with an original diagnostic reset stub. It does not replace the CPU, memory
controller or peripheral timing. The stock-ROM disk-loading path is tested in
MAME; the RTL test is not a second disk-boot test. The caller's core checkout is
never modified by the harness.

Physical MiSTer testing remains outstanding. These tests validate this game's
observed paths, not every behavior of the Apple III core.

## Reproduce

```sh
make test-all
python3 tools/test_highway_core.py ../Apple-III-MiSTer
make release
```

Tests, logs, source snapshots and generated emulator files stay under ignored
`build/`. Use `--reuse-snapshot` on the RTL command to repeat against its recorded
snapshot rather than copying a newly changed checkout.
