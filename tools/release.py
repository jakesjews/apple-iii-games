#!/usr/bin/env python3
"""Package native game disks in the installed Apple-III-MiSTer core's layout."""
import hashlib
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

from disk import dos_order

ROOT = Path(__file__).resolve().parent.parent
DESTINATION = Path("games/Apple-III/Apple-III-Games")
ARCHIVE = "Apple-III-Games.zip"
GAMES = {
    "invaders": "Star Siege.dsk",
    "tetris": "Blockfall.dsk",
    "breakout": "Brick Bash.dsk",
    "2048": "Merge 2048.dsk",
    "wordle": "Word Five.dsk",
    "highway": "Highway III.dsk",
}


def build() -> None:
    sources = {path.name for path in (ROOT / "games").iterdir() if path.is_dir()}
    if sources != set(GAMES):
        raise SystemExit("Update GAMES in tools/release.py to match the games/ directories.")

    release = ROOT / "releases"
    files = {}
    for game, filename in GAMES.items():
        # .po is Make's tracked output; regenerate DOS order so a missing or
        # stale .dsk side product cannot enter a release.
        disk = (ROOT / "build" / game / (game + ".po")).read_bytes()
        files[DESTINATION / filename] = dos_order(disk)
    files[DESTINATION / "README.md"] = (release / "README.md").read_bytes()
    files[DESTINATION / "WORDLIST-LICENSE.txt"] = (
        ROOT / "games/wordle/WORDLIST-LICENSE.txt"
    ).read_bytes()

    for path, data in files.items():
        output = release / path
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(data)

    # Fixed timestamps and permissions avoid ZIP changes on identical builds.
    with ZipFile(release / ARCHIVE, "w", compression=ZIP_DEFLATED) as archive:
        for path, data in sorted(files.items()):
            entry = ZipInfo(path.as_posix(), date_time=(1980, 1, 1, 0, 0, 0))
            entry.create_system = 3
            entry.external_attr = 0o100644 << 16
            archive.writestr(entry, data, compress_type=ZIP_DEFLATED, compresslevel=9)

    files[Path(ARCHIVE)] = (release / ARCHIVE).read_bytes()
    checksums = "".join(
        f"{hashlib.sha256(data).hexdigest()}  {path.as_posix()}\n"
        for path, data in sorted(files.items())
    )
    (release / "SHA256SUMS").write_text(checksums, encoding="utf-8")
    print(f"Prepared {len(GAMES)} boot disks in releases/{DESTINATION.as_posix()}")
    print(f"Created releases/{ARCHIVE} ({len(files[Path(ARCHIVE)]):,} bytes)")


if __name__ == "__main__":
    build()
