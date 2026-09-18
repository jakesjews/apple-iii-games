#!/usr/bin/env python3
"""Run Highway's actual program on a snapshot of a local MiSTer core checkout.

The ROM/disk path is tested separately in MAME. This harness preloads the same
code/assets and uses our own reset stub, without redistributing Apple's ROM.
The caller's checkout is read only, including any uncommitted timing changes.
"""
import argparse
import hashlib
import shutil
import subprocess
from pathlib import Path
from test_joystick_core import SOURCES

ROOT=Path(__file__).resolve().parent.parent

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('core',type=Path)
    parser.add_argument('--reuse-snapshot',action='store_true',help='reuse the recorded, immutable test snapshot')
    args=parser.parse_args(); source=args.core.resolve()
    out=ROOT/'build/highway/core'; core=out/'source'; core.mkdir(parents=True,exist_ok=True)
    if not args.reuse_snapshot:
        shutil.rmtree(core)
        core.mkdir(parents=True)
        files=subprocess.check_output(['git','-C',str(source),'ls-files','--cached','--others','--exclude-standard','-z']).split(b'\0')
        digest=hashlib.sha256()
        for raw in sorted(set(files)):
            if not raw: continue
            name=raw.decode(); path=source/name
            if not path.is_file(): continue
            data=path.read_bytes(); digest.update(raw+b'\0'+data)
            destination=core/name; destination.parent.mkdir(parents=True,exist_ok=True); destination.write_bytes(data)
        head=subprocess.check_output(['git','-C',str(source),'rev-parse','HEAD'],text=True).strip()
        (out/'source.txt').write_text(f'Base: {head}\nWorking tree SHA256: {digest.hexdigest()}\n')
        print((out/'source.txt').read_text(),flush=True)
        with (out/'netlists.log').open('w') as log:
            subprocess.run(['zsh','sim/gen_vhdl.sh'],cwd=core,stdout=log,stderr=subprocess.STDOUT,check=True)
    elif not (out/'source.txt').is_file():
        parser.error('No recorded snapshot exists')
    subprocess.run(['ca65','-o',str(out/'reset.o'),str(ROOT/'tests/highway_core.s')],check=True)
    subprocess.run(['ld65','-C',str(ROOT/'tests/joystick_core.cfg'),'-o',str(out/'reset.rom'),str(out/'reset.o')],check=True)
    (out/'reset.hex').write_text(''.join(f'{b:02x}\n' for b in (out/'reset.rom').read_bytes()))
    memory=bytearray(262144)
    code=(ROOT/'build/highway/code.bin').read_bytes()
    banks=(ROOT/'build/highway/banks.bin').read_bytes()
    memory[0x3A200:0x3C000]=code[:7680]; memory[0x3D000:0x3F000]=code[7680:]
    memory[0x8000:0x8000+len(banks)]=banks
    paired=[0]*131072
    for physical,b in enumerate(memory):
        word=((physical>>12)<<11)|((((physical>>10)^(physical>>11))&1)<<10)|(physical&1023)
        paired[word]|=b<<(((physical>>11)&1)*8)
    (out/'memory.hex').write_text(''.join(f'{v:04x}\n' for v in paired))
    tb=(core/'sim/coretest/core_tb.sv').read_text()
    tb=tb.replace('output logic        write_mode1','output wire [15:0]  test_audio,\n\toutput logic        write_mode1')
    tb=tb.replace('endmodule',f'assign test_audio = audio;\ninitial $readmemh("{out / "memory.hex"}", dut.ram.mem);\nendmodule')
    (out/'core_tb.sv').write_text(tb)
    symbols={}
    for line in (ROOT/'build/highway/highway.lbl').read_text().splitlines():
        tokens=line.split()
        if len(tokens)==3: symbols[tokens[2].lstrip('.')]=int(tokens[1],16)
    needed=['state','speed','player','frame_counter','simulation_ticks','time_left','irq_ticks','page','redraw_scene','joy','joy_x','joy_y','countdown','throttle','brake']
    (out/'symbols.h').write_text(''.join(f'constexpr unsigned a_{n}=0x{symbols["_"+n]:04x};\n' for n in needed))
    commands=['verilator','--cc','--exe','--build','-j','4','-O2','--top-module','core_tb',f'-GROM_FILE="{out / "reset.hex"}"',
              '-CFLAGS',f'-O3 -std=c++17 -I{out}','-Wno-fatal','--Mdir',str(out/'obj'),str(out/'core_tb.sv'),*SOURCES[1:],*[str(p) for p in sorted((core/'rtl/cards').glob('*.sv'))],
              str(ROOT/'tests/highway_core.cpp'),'-o','highway-test']
    print(f'Building simulation; log: {out / "build.log"}',flush=True)
    with (out/'build.log').open('w') as log:
        subprocess.run(commands,cwd=core,stdout=log,stderr=subprocess.STDOUT,check=True)
    subprocess.run([str(out/'obj/highway-test')],cwd=core,check=True,timeout=300)

if __name__=='__main__': main()
