#!/usr/bin/env python3
"""Compile original ASCII sprite art into seven pixel shifts for the 6502."""
import json
import sys
from pathlib import Path


def compile_assets(sprites_path: Path, output: Path) -> None:
    sprites = json.loads(sprites_path.read_text())
    font = json.loads(Path("platform/apple3/font.json").read_text())
    assembly = ['.segment "RODATA"', '.export sprite_lo, sprite_hi, font_lo, font_hi, _font_bitmap']
    header = ["/* Generated from sprites.json; do not edit. */"]
    names = list(sprites)
    for index, (name, art) in enumerate(sprites.items()):
        if len(art) != 8 or any(len(row) > 14 or set(row) - set(".#") for row in art):
            raise ValueError(f"{name}: expected eight rows of at most 14 pixels")
        header.append(f"#define {name} {index}")
        assembly.append(f"sprite_{name}:")
        for shift in range(7):
            values = []
            for row in art:
                bits = sum((pixel == "#") << (x + shift) for x, pixel in enumerate(row))
                values.extend((bits >> (7 * byte)) & 0x7F for byte in range(3))
            assembly.append(".byte " + ",".join(f"${value:02X}" for value in values))
    for name, operator in (("sprite_lo", "<"), ("sprite_hi", ">")):
        assembly += [name + ":", ".word 0"] if not names else [
            name + ":", ".byte " + ",".join(operator + "sprite_" + key for key in names)
        ]
    assembly.append("_font_bitmap:")
    for index in range(64):
        character = chr(index if index >= 32 else index + 64)
        rows = font.get(character, font[" "])
        values = [sum((pixel == "1") << (x + 1) for x, pixel in enumerate(row)) for row in rows] + [0]
        assembly += [f"glyph_{index}:", ".byte " + ",".join(map(str, values))]
    for name, operator in (("font_lo", "<"), ("font_hi", ">")):
        assembly += [name + ":", ".byte " + ",".join(f"{operator}glyph_{i}" for i in range(64))]
    output.mkdir(parents=True, exist_ok=True)
    (output / "assets.s").write_text("\n".join(assembly) + "\n")
    (output / "assets.h").write_text("\n".join(header) + "\n")


if __name__ == "__main__":
    compile_assets(Path(sys.argv[1]), Path(sys.argv[2]))
