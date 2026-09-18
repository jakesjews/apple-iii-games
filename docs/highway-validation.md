# Highway /// validation — 2026-09-18

The game is built for a native 256 KB Apple III with the original boot ROM.
The released disk and ZIP are under `releases/`. No Apple ROM is distributed.

## Results

- **6 Python checks** pass for disk geometry, payload placement and word data.
- **459 MAME checks** pass across all six games. Highway contributes 105: 43
  gameplay/rendering checks on the ProDOS-order disk, 11 on the DOS-order disk,
  five for each complete controller-driven tour, 20 rendering checks per disk
  format, and the 128 KB rejection check.
- Highway's suite verifies the timer, DAC output and mute, keyboard and joystick
  inputs, pause, off-road slowdown, collisions, overtaking, tunnel transitions,
  both checkpoints, the finish, timeout, retry, best-score retention, sharp-turn
  background restoration, and every byte of the loaded asset banks and program.
- The complete tour driver only changes joystick input ports. Both disk formats
  finish all three stages. The recorded run takes approximately **85 seconds**,
  survives seven collisions and finishes with time remaining.
- **10 RTL checks** pass using the local Apple-III-MiSTer CPU, video, RAM, VIAs,
  DAC and ADC. They cover startup, timer activity, acceleration, pause/resume,
  audio, both display pages, banked sprite execution, and **zero writes to the
  displayed graphics page during racing**.
- The ZIP-extracted Highway disk boots and passes the 11-check smoke suite.
  Release checksums match, and a clean build reproduces the disk bytes.

The other five game disks remain byte-for-byte unchanged.

The rendering suite compares both graphics pages against a full reconstruction
across twelve camera/hill/stripe combinations, overlapping traffic, and finish
banner appearance/removal. It also verifies zero framebuffer writes on unchanged
paused frames, one-digit speed updates, timer warning colors, and digit carries.

## Timing

These are measured rendered frame rates, rather than a claim based on the
nominal CPU frequency:

| Workload | MAME 0.289 | Current core RTL |
| --- | --- | --- |
| Attract scene | About 18.2 fps, 5-second sample | About 19.0 fps, 3-second sample |
| Complete controller-driven race | About 10.6 fps, 85-second run | Not measured over a complete tour |
| Steering and traffic sample | Included in the complete run above | About 13.8 fps, 4-second sample |

With the same controller-driver policy, the previous build (`65ba105`) averaged
**9.04 fps** over a complete MAME tour; this build averages **10.64 fps**, about
**18% faster**. The attract scene improved from 14.2 to 18.2 fps. The driver is
closed-loop, so traffic, collisions and tour duration differ as frame pacing
changes; these are complete-play benchmarks, not identical instruction traces.
The core sample is shorter and should not be presented as a full-race average.

All four optimization areas are implemented:

- Per-page geometry/stripe history skips unchanged two-scanline road bands.
  Erased sprites invalidate affected bands, and clipped lane/edge aliases remain
  correct when only stripe colors change.
- Sprites retain per-page address tables and skip unchanged, undamaged objects.
  Damage propagates in painter order; erasure uses straight-line span stores.
  Address caches are invalidated after scene preparation and spoken audio.
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

The test uses a fresh snapshot of the user's sibling checkout (clean at the
time of this run), based on:

- Commit: `f723fda16431cdbb1e5b47b29c11b3fdbf412288`
  (`Implement the virtual block-storage card`).
- Working-tree snapshot SHA-256:
  `43713b24bd3a1bedfb43b74460879ace549c4881746eae42bcb04a1d592e0616`.

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
