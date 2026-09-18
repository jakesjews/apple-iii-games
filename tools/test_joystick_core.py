#!/usr/bin/env python3
"""Run our production joystick reader on a local Apple-III-MiSTer RTL checkout."""
import argparse
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent.parent
SOURCES = """
sim/coretest/core_tb.sv sim/gen/t65.v sim/gen/via6522.v
rtl/disk/apple3_woz_drive.sv rtl/disk/woz/flux_drive.v
rtl/disk/woz/woz_cell525.sv rtl/disk/woz/woz_bram.sv
rtl/disk/woz/woz_floppy_controller.sv rtl/disk/apple3_p6.sv
rtl/disk/apple3_disk_sequencer.sv rtl/apple3_mmu.sv rtl/apple3_timing.sv
rtl/apple3_ram.sv rtl/apple3_rom.sv rtl/apple3_extaddr.sv rtl/apple3_keyboard.sv
rtl/apple3_io.sv rtl/apple3_rtc.sv rtl/acia/gen_uart.v rtl/apple3_acia.sv
rtl/apple3_disk.sv rtl/apple3_video.sv rtl/apple3_slots.sv
rtl/apple3_slot_rom.sv rtl/apple3_core.sv
""".split()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("core", type=Path)
    core = parser.parse_args().core.resolve()
    for source in SOURCES:
        if not (core / source).is_file():
            parser.error(f"Missing {core / source}; run the core's sim/gen_vhdl.sh first if netlists are missing.")
    out = ROOT / "build/joystick-core"
    out.mkdir(parents=True, exist_ok=True)
    for name, source in (("reader", "platform/apple3/joystick.s"), ("test", "tests/joystick_core.s")):
        subprocess.run([os.getenv("CA65", "ca65"), "-o", str(out / (name + ".o")), str(ROOT / source)], check=True)
    rom = out / "test.rom"
    subprocess.run([os.getenv("LD65", "ld65"), "-C", str(ROOT / "tests/joystick_core.cfg"),
                    "-o", str(rom), str(out / "test.o"), str(out / "reader.o")], check=True)
    rom_hex = out / "test.hex"
    rom_hex.write_text("".join(f"{byte:02x}\n" for byte in rom.read_bytes()))
    args = ["verilator", "--cc", "--exe", "--build", "-j", "4", "-O2", "--top-module", "core_tb",
            f'-GROM_FILE="{rom_hex}"', "-CFLAGS", "-O3 -std=c++17", "-Wno-fatal",
            "--Mdir", str(out / "obj"), *SOURCES, str(ROOT / "tests/joystick_core.cpp"), "-o", "joystick-test"]
    print(f"Building core simulation; log: {out / 'build.log'}", flush=True)
    with (out / "build.log").open("w") as log:
        subprocess.run(args, cwd=core, stdout=log, stderr=subprocess.STDOUT, check=True)
    subprocess.run([str(out / "obj/joystick-test")], cwd=core, check=True, timeout=180)


if __name__ == "__main__":
    main()
