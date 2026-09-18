# Highway /// validation — 2026-09-18

The game is built for a native 256 KB Apple III with the original boot ROM.
The released disk and ZIP are under `releases/`. No Apple ROM is distributed.

## Results

- **6 Python checks** pass for disk geometry, payload placement and word data.
- **419 MAME checks** pass across all six games. Highway contributes 65: 43
  gameplay/rendering checks on the ProDOS-order disk, 11 on the DOS-order disk,
  five for each complete controller-driven tour, and the 128 KB rejection check.
- Highway's suite verifies the timer, DAC output and mute, keyboard and joystick
  inputs, pause, off-road slowdown, collisions, overtaking, tunnel transitions,
  both checkpoints, the finish, timeout, retry, best-score retention, sharp-turn
  background restoration, and every byte of the loaded asset banks and program.
- The complete tour driver only changes joystick input ports. Both disk formats
  finish all three stages. The recorded run takes approximately **91 seconds**,
  survives nine collisions and finishes with time remaining.
- **10 RTL checks** pass using the local Apple-III-MiSTer CPU, video, RAM, VIAs,
  DAC and ADC. They cover startup, timer activity, acceleration, pause/resume,
  audio, both display pages, banked sprite execution, and **zero writes to the
  displayed graphics page during racing**.
- The ZIP-extracted Highway disk boots and passes the 11-check smoke suite.
  Release checksums match, and a clean build reproduces the disk bytes.

The other five game disks remain byte-for-byte unchanged.

After removing the checkpoint HUD, Highway's 65 MAME checks and the ZIP smoke
suite were rerun. The core results are from the initial release.

## Timing

These are measured rendered frame rates, rather than a claim based on the
nominal CPU frequency:

| Workload | MAME 0.289 | Core RTL (initial release) |
| --- | --- | --- |
| Attract scene | About 14.2 fps, 5-second sample | About 14.7 fps, 3-second sample |
| Complete controller-driven race | About 9.0 fps, 91-second run | Not measured over a complete tour |
| Steering and traffic sample | Included in the complete run above | About 10.5 fps, 4-second sample |

The original **30 fps target was not achieved**. Drawing cost varies with
steering, traffic sizes, hills and the checkpoint banner. Driving physics uses
a 50 Hz fixed step derived from the VIA clock, with bounded catch-up. Scene
preparation and the spoken countdown do not consume race time.

## Core provenance and scope

The test uses a snapshot of the user's sibling checkout, including then-current
uncommitted changes, based on:

- Commit: `7a54cba792cc545a009ae1833ad05df2e9f11620`
  (`Implement peripheral wait states and boundary timing`).
- Working-tree snapshot SHA-256:
  `38b68c2a78def35df0dfdf24b8bba6a810473f95cc8422f790aa22f46e3330d7`.

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
