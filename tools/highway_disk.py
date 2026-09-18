#!/usr/bin/env python3
"""Fixed system-bank code plus four asset segments, loaded by our boot block."""
import argparse
import subprocess
from pathlib import Path
from disk import DISK_SIZE,dos_order
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--ca65',default='ca65')
parser.add_argument('--ld65',default='ld65')
args=parser.parse_args()
out=Path('build/highway')
code=(out/'code.bin').read_bytes()
banks=(out/'banks.bin').read_bytes()
assert len(code)==15872 and len(banks)==122880
payload=code+banks
(out/'highway.bin').write_bytes(payload)
subprocess.run([args.ca65,'-o',str(out/'boot.o'),'games/highway/boot.s'],check=True)
subprocess.run([args.ld65,'-C','platform/apple3/boot.cfg','-o',str(out/'boot.bin'),str(out/'boot.o')],check=True)
disk=((out/'boot.bin').read_bytes()+payload).ljust(DISK_SIZE,b'\0')
assert len(disk)==DISK_SIZE
(out/'highway.po').write_bytes(disk)
(out/'highway.dsk').write_bytes(dos_order(disk))
print(f'Highway: {len(payload):,} bytes; native 256K boot disks ready')
