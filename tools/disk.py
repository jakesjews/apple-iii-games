#!/usr/bin/env python3
"""Build a raw native Apple III boot disk in ProDOS block and DOS sector order."""
import argparse
import subprocess
from pathlib import Path

DISK_SIZE = 35 * 16 * 256
# Logical sectors indexed by physical sector number.
PRODOS = (0, 8, 1, 9, 2, 10, 3, 11, 4, 12, 5, 13, 6, 14, 7, 15)
DOS = (0, 7, 14, 6, 13, 5, 12, 4, 11, 3, 10, 2, 9, 1, 8, 15)


def dos_order(prodos: bytes) -> bytes:
    if len(prodos) != DISK_SIZE:
        raise ValueError("Expected a 35-track, 140 KiB disk")
    result = bytearray(DISK_SIZE)
    for track in range(35):
        for physical in range(16):
            src = (track * 16 + PRODOS[physical]) * 256
            dst = (track * 16 + DOS[physical]) * 256
            result[dst:dst + 256] = prodos[src:src + 256]
    return bytes(result)


def build(binary: Path, ca65: str, ld65: str) -> None:
    payload = binary.read_bytes()
    if not 0 < len(payload) <= 0x4000:
        raise ValueError("Payload must fit $6000-$9FFF (16 KiB)")
    blocks = (len(payload) + 511) // 512
    out = binary.parent
    subprocess.run([ca65, "-D", f"BLOCK_COUNT={blocks}", "-o", str(out / "boot.o"),
                    "platform/apple3/boot.s"], check=True)
    subprocess.run([ld65, "-C", "platform/apple3/boot.cfg", "-o", str(out / "boot.bin"),
                    str(out / "boot.o")], check=True)
    boot = (out / "boot.bin").read_bytes()
    assert len(boot) == 512
    disk = (boot + payload).ljust(DISK_SIZE, b"\0")
    binary.with_suffix(".po").write_bytes(disk)
    binary.with_suffix(".dsk").write_bytes(dos_order(disk))
    print(f"{binary.stem}: {len(payload):,} bytes, {blocks} blocks; .po and .dsk ready")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=Path)
    parser.add_argument("--ca65", default="ca65")
    parser.add_argument("--ld65", default="ld65")
    args = parser.parse_args()
    build(args.binary, args.ca65, args.ld65)
