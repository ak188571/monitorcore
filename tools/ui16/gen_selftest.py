#!/usr/bin/env python3
"""Generate full font and initialized cells; no third-party Python packages."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / 'src/iosys/ui16'
table = (ASSETS / 'font16_table.h').read_text(encoding='utf-8')
glyphs = {int(cp,16): int(gid) for cp,gid in re.findall(r'\{\s*0x([0-9A-Fa-f]+)\s*,\s*(\d+)\s*\}',table)}
words = (ASSETS / 'font16_source.hex').read_text(encoding='utf-8').split()
if len(words)>4096 or any(not re.fullmatch('[0-9A-Fa-f]{1,4}',w) for w in words):
    raise ValueError('invalid font data')
if max(glyphs.values())>=256 or len(words)<(max(glyphs.values())+1)*16:
    raise ValueError('invalid glyph IDs or insufficient font rows')
words += ['0000']*(4096-len(words))
(ASSETS / 'font16_full.hex').write_text('\n'.join(words)+'\n',encoding='utf-8')
config=(ASSETS/'ui_config.svh').read_text(encoding='utf-8')
for name,value in {'SCREEN_WIDTH':256,'SCREEN_HEIGHT':224,'GLYPH_BITMAP_WIDTH':16,'GLYPH_BITMAP_HEIGHT':16,'GLYPH_COUNT':256,'TEXT_UNIT_WIDTH':8,'CELL_ADDR_BITS':9}.items():
    if not re.search(r'`define UI_'+name+r' '+str(value)+r'\b',config):raise ValueError('unsupported hardware profile: '+name)
cells = [0]*512
for y,text,selected in [(6,'ファミリーコンピュータ',True),(8,'ABC 日本 DEF 日本',False),(10,'EMPTY',False)]:
    x = 0
    for c in text:
        width=1 if ord(c)<128 else 2
        if x+width>32: raise ValueError('selftest line too long')
        if c!=' ':
            gid=glyphs[ord(c)]
            cells[y*32+x]=gid | (int(selected)<<8)
            if width==2:cells[y*32+x+1]=gid | (int(selected)<<8) | (1<<9)
        x+=width
(ASSETS/'cells_selftest.hex').write_text(''.join(f'{v:03x}\n' for v in cells),encoding='utf-8')
(ASSETS/'cells_zero.hex').write_text('000\n'*512,encoding='utf-8')
print('generated: 4096 font rows, 512 selftest words, 512 zero words (448 visible cells)')
