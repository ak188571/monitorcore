#!/usr/bin/env python3
"""Patch known display anchors, preserve local USB files, and create separate projects."""
import argparse
import json
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[2]
BEGIN = '// UI16 integration BEGIN'


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply',action='store_true',help='write patch and new project files')
    args=parser.parse_args()
    try:
        iosys=ROOT/'src/iosys/iosys_bl616.v'
        project=ROOT/'monitor_console138k.gprj'
        board=ROOT/'src/boards/console138k.v'
        source=iosys.read_text(encoding='utf-8')
        gprj=project.read_text(encoding='utf-8')
        board_source=board.read_text(encoding='utf-8')
        options=json.loads((ROOT/'impl/monitor_console138k_process_config.json').read_text(encoding='utf-8'))
        block=(ROOT/'tools/ui16/integration_block.v.txt').read_text(encoding='utf-8').rstrip()
        if BEGIN in source:
            if block not in source:raise ValueError('different UI16 integration already present')
            patched=source
        else:
            start=source.find('// text display\n`ifndef SIM')
            end=source.find('\nendmodule',start)
            if start<0 or end<0:raise ValueError('expected v0.9 text-display anchors not found')
            old=source[start:end]
            if 'textdisp #(.COLOR_LOGO(COLOR_LOGO)) disp' not in old:
                raise ValueError('display block differs; inspect before applying')
            for marker in ['wire [7:0] rx_data;', 'wire rx_valid;', 'reg [6:0] recv_state', 'localparam BAUD_RATE = 2_000_000;']:
                if marker not in source:raise ValueError('UART structure differs: '+marker)
            patched=source[:start]+block+'\n'+source[end:]
            anchor='endcase\n        \n    end\nend\n\nlocalparam SEND_IDLE'
            replacement='''endcase
`ifdef UI16_ENABLE
`ifndef SIM
        if (ui16_abort) recv_state <= RECV_IDLE;
`endif
`endif
        
    end
end

localparam SEND_IDLE'''
            if patched.count(anchor)!=1:raise ValueError('UART receive-end anchor differs')
            patched=patched.replace(anchor,replacement,1)
        if gprj.count('src/boards/console138k.v')!=1 or gprj.count('</FileList>')!=1:
            raise ValueError('project structure differs')
        pending=[(iosys,patched)]
        for mode in ['test','uart']:
            board_name=f'src/boards/console138k_ui_{mode}.v'
            macros='\n`define UI16_ENABLE\n'+('`define UI16_SELFTEST\n' if mode=='test' else '')
            pending.append((ROOT/board_name,board_source+macros))
            extra=''.join(f'        <File path="src/iosys/ui16/{name}" type="file.verilog" enable="1"/>\n'
                          for name in ['ui_frame_decoder.sv','ui16_transport.sv','ui_textdisp.sv'])
            p=gprj.replace('src/boards/console138k.v',board_name).replace('    </FileList>',extra+'    </FileList>')
            pending.append((ROOT/f'monitor_console138k_ui_{mode}.gprj',p))
            mode_options=dict(options)
            mode_options.update(OUTPUT_BASE_NAME=f'monitor_console138k_ui_{mode}', TopModule='monitor_top', Verilog_Standard='Vlg_Std_Sysv2017')
            pending.append((ROOT/f'impl/monitor_console138k_ui_{mode}_process_config.json',json.dumps(mode_options,indent=1)+'\n'))
        for path,content in pending:
            if path!=iosys and path.exists() and path.read_text(encoding='utf-8')!=content:
                raise ValueError('would overwrite a modified generated file: '+str(path.relative_to(ROOT)))
        print('Base project/device and USB source references are preserved.')
        for path,_ in pending:print(('write: ' if args.apply else 'planned: ')+str(path.relative_to(ROOT)))
        if not args.apply:
            print('Dry run succeeded. Run again with --apply to write.')
            return 0
        if source!=patched:
            backup=iosys.with_name('iosys_bl616.v.ui16_backup')
            if backup.exists():raise ValueError('backup already exists; inspect before applying')
            shutil.copy2(iosys,backup)
        for path,content in pending:
            path.parent.mkdir(parents=True,exist_ok=True)
            path.write_text(content,encoding='utf-8',newline='\n')
        print('Applied. Original monitor_console138k.gprj remains unchanged.')
        return 0
    except (OSError,ValueError) as e:
        print('UI16 apply error: '+str(e),file=sys.stderr);return 1


if __name__=='__main__':sys.exit(main())
