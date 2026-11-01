#!/usr/bin/env python3
"""Validate the installed font and generate initialized 28-row cells."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / 'src/iosys/ui16'
table = (ASSETS / 'font16_table.h').read_text(encoding='utf-8')
glyphs = {int(cp,16): int(gid) for cp,gid in re.findall(r'\{\s*0x([0-9A-Fa-f]+)\s*,\s*(\d+)\s*\}',table)}
words = (ASSETS / 'font16_full.hex').read_text(encoding='utf-8').split()
if len(words)!=16384 or any(not re.fullmatch('[0-9A-Fa-f]{1,4}',w) for w in words):
    raise ValueError('invalid font data')
if max(glyphs.values())>=1024 or len(words)<(max(glyphs.values())+1)*16:
    raise ValueError('invalid glyph IDs or insufficient font rows')
config=(ASSETS/'ui_config.svh').read_text(encoding='utf-8')
for name,value in {'SCREEN_WIDTH':256,'SCREEN_HEIGHT':224,'GLYPH_BITMAP_WIDTH':16,'GLYPH_BITMAP_HEIGHT':16,'GLYPH_COUNT':1024,'TEXT_UNIT_WIDTH':8,'VERTICAL_UNIT_HEIGHT':8,'MENU_ROWS':28,'CELL_ADDR_BITS':10}.items():
    if not re.search(r'`define UI_'+name+r' '+str(value)+r'\b',config):raise ValueError('unsupported hardware profile: '+name)
cells = [0]*1024
for y,text,selected in [(6,'ファミリーコンピュータ',True),(8,'ABC 日本 DEF 日本',False),(10,'EMPTY',False)]:
    x = 0
    for c in text:
        width=1 if ord(c)<128 else 2
        if x+width>32: raise ValueError('selftest line too long')
        if c!=' ':
            gid=glyphs[ord(c)]
            base=gid | (int(selected)<<12)
            cells[(2*y)*32+x]=base
            cells[(2*y+1)*32+x]=base | (1<<14)
            if width==2:
                cells[(2*y)*32+x+1]=base | (1<<13)
                cells[(2*y+1)*32+x+1]=base | (1<<13) | (1<<14)
        x+=width
(ASSETS/'cells_selftest.hex').write_text(''.join(f'{v:04x}\n' for v in cells),encoding='utf-8',newline='\n')
(ASSETS/'cells_zero.hex').write_text('000\n'*1024,encoding='utf-8',newline='\n')
print('validated: 16384 font rows; generated: 1024 selftest words, 1024 zero words (896 visible cells)')
