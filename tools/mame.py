#!/usr/bin/env python3
"""Run the actual boot disk in MAME, with all emulator output under build/."""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def command(game: str, headless: bool = False, script: Path | None = None, disk: Path | None = None) -> list[str]:
    mame = os.environ.get("MAME", "mame")
    if not shutil.which(mame):
        raise SystemExit("MAME is missing. Install it, or set MAME to its executable path.")
    out = ROOT / "build" / game / ("test" if headless else "mame")
    out.mkdir(parents=True, exist_ok=True)
    roms = os.environ.get("MAME_ROMPATH", str(ROOT / "build/local-roms"))
    args = [mame, "apple3", "-bios", "original", "-rompath", roms,
            "-flop1", str(disk or ROOT / "build" / game / (game + ".po")),
            "-skip_gameinfo", "-window", "-nomouse", "-noautosave", "-adstick_device", "joystick",
            "-noreadconfig", "-autoboot_delay", "0",
            "-snapsize", "1120x768", "-nosnapbilinear"]
    for option, subdir in (("cfg_directory", "cfg"), ("nvram_directory", "nvram"),
                           ("snapshot_directory", "snap"), ("diff_directory", "diff")):
        (out / subdir).mkdir(exist_ok=True)
        args += ["-" + option, str(out / subdir)]
    if headless:
        args += ["-video", "none", "-sound", "none", "-nothrottle", "-seconds_to_run", "300"]
    else:
        args += ["-resolution", "1120x768", "-nounevenstretch", "-nofilter"]
    if script:
        args += ["-autoboot_script", str(script)]
    return args


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("run", "test"))
    parser.add_argument("game", default="invaders", nargs="?")
    parser.add_argument("--script", type=Path)
    parser.add_argument("--windowed", action="store_true", help="run test suites visibly at normal speed")
    args = parser.parse_args()
    if not (ROOT / "games" / args.game / "main.c").is_file():
        parser.error(f"Unknown game: {args.game}")
    testing = args.action == "test"
    headless = testing and not args.windowed
    controls = ROOT / "games" / args.game / "controls.lua"
    if not controls.exists():
        controls = ROOT / "tools/controls.lua"
    script = args.script or (ROOT / "tests" / (args.game + ".lua") if testing else controls)
    env = os.environ.copy()
    if headless:
        env["SDL_VIDEODRIVER"] = "dummy"
        env["SDL_AUDIODRIVER"] = "dummy"
    if not testing or args.script:
        subprocess.run(command(args.game, headless, script), cwd=ROOT, env=env,
                       check=True, timeout=180 if testing else None)
        return
    suites = [(script, "")]
    if args.game in ("invaders", "tetris", "breakout"):
        suites.append((ROOT / "tests/joystick.lua", "joystick-"))
    if args.game == "highway":
        suites.append((ROOT / "tests/highway_race.lua", "race-"))
    env["A3_TEST_GAME"] = args.game
    for suite, prefix in suites:
        for extension, ram, smoke in (("po", "256K", False), ("dsk", "256K" if args.game == "highway" else "128K", True)):
            out = ROOT / "build" / args.game / "test" / (prefix + extension + "-" + ram)
            out.mkdir(parents=True, exist_ok=True)
            result = out / "result.txt"
            result.unlink(missing_ok=True)
            env["A3_TEST_OUTPUT"] = str(out)
            env["A3_SMOKE_ONLY"] = "1" if smoke else "0"
            disk = ROOT / "build" / args.game / (args.game + "." + extension)
            print(f"Testing {disk.name}, {ram} RAM ({suite.stem})", flush=True)
            subprocess.run(command(args.game, headless, suite, disk) + ["-ramsize", ram],
                           cwd=ROOT, env=env, check=True, timeout=180)
            if not result.exists() or not result.read_text().startswith("PASS "):
                raise SystemExit(result.read_text() if result.exists() else "MAME exited without a passing test result")
            print(result.read_text().strip())
    if args.game == "highway":
        out = ROOT / "build/highway/test/128K"
        out.mkdir(parents=True, exist_ok=True)
        result = out / "result.txt"
        result.unlink(missing_ok=True)
        env["A3_TEST_OUTPUT"] = str(out)
        subprocess.run(command(args.game, headless, ROOT / "tests/highway_128.lua") + ["-ramsize", "128K"],
                       cwd=ROOT, env=env, check=True, timeout=180)
        if not result.exists() or not result.read_text().startswith("PASS "):
            raise SystemExit(result.read_text() if result.exists() else "Missing 128K rejection result")
        print(result.read_text().strip())


if __name__ == "__main__":
    main()
