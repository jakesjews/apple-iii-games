"""Disk geometry is part of the boot contract, not just packaging."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from disk import DISK_SIZE, dos_order


class DiskTests(unittest.TestCase):
    def test_every_rom_block_reads_the_correct_two_sectors(self):
        # Independent of the converter's ProDOS permutation: this is the
        # BLOCKIO $F4A0 sector table from the original Apple III boot ROM.
        rom_sector = (0, 4, 8, 12, 1, 5, 9, 13)
        dos_physical = (0, 7, 14, 6, 13, 5, 12, 4, 11, 3, 10, 2, 9, 1, 8, 15)
        source = b"".join(block.to_bytes(2, "little") * 256 for block in range(280))
        result = dos_order(source)
        self.assertEqual(len(result), DISK_SIZE)
        for block in range(280):
            track, index = divmod(block, 8)
            for physical in (rom_sector[index], rom_sector[index] + 2):
                offset = (track * 16 + dos_physical[physical]) * 256
                self.assertEqual(result[offset:offset + 256], block.to_bytes(2, "little") * 128)

    def test_rejects_wrong_disk_size(self):
        for size in (0, DISK_SIZE - 1, DISK_SIZE + 1):
            with self.assertRaises(ValueError):
                dos_order(bytes(size))

    def test_build_contains_exact_boot_and_payload(self):
        for folder in Path("games").iterdir():
            if not folder.is_dir():
                continue
            out = Path("build") / folder.name
            disk = (out / (folder.name + ".po")).read_bytes()
            boot = (out / "boot.bin").read_bytes()
            payload = (out / (folder.name + ".bin")).read_bytes()
            self.assertEqual(disk[:512], boot)
            self.assertEqual(disk[512:512 + len(payload)], payload)
            self.assertEqual(set(disk[512 + len(payload):]), {0})
            self.assertEqual(disk[0], 0x78)  # SEI at the ROM's $A000 entry


if __name__ == "__main__":
    unittest.main()
