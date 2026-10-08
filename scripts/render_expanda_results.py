"""Render actual VCD transitions and measured benchmark CSV to standalone SVG."""
import csv
from html import escape
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'results'

def read_vcd(path, scope_name, names):
    stack, signals, changes, widths = [], {}, {}, {}
    time = 0
    with path.open() as f:
        for raw in f:
            line = raw.strip()
            parts = line.split()
            if line.startswith('$scope'):
                stack.append(parts[2])
            elif line.startswith('$upscope'):
                stack.pop()
            elif line.startswith('$var') and '.'.join(stack) == scope_name:
                name = parts[4]
                if name in names:
                    signals[parts[3]] = name
                    widths[name] = int(parts[2])
                    changes[name] = []
            elif line.startswith('#'):
                time = int(line[1:]) / 1000  # simulator files declare 1 ps
            elif line and line[0] in 'bB' and len(parts) == 2:
                if parts[1] in signals:
                    changes[signals[parts[1]]].append((time, parts[0][1:]))
            elif line and line[0] in '01xz' and line[1:] in signals:
                changes[signals[line[1:]]].append((time, line[0]))
    assert set(names) <= changes.keys(), set(names) - changes.keys()
    return changes, widths

def waveform(filename, scope, names, start, end, output, title):
    changes, widths = read_vcd(OUT / filename, scope, names)
    left, right, top, rowh = 180, 1200, 88, 50
    height = top + rowh * len(names) + 60
    svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="{height}" viewBox="0 0 1280 {height}">',
           '<rect width="100%" height="100%" fill="white"/>',
           '<style>text{font-family:Arial,sans-serif;fill:#243447} .label{font-family:monospace;font-size:14px}</style>',
           f'<text x="24" y="30" font-size="20" font-weight="bold">{escape(title)}</text>',
           f'<text x="24" y="54" font-size="13">Actual Icarus VCD transitions · source: {escape(filename)} · testbench clock: 10 ns</text>']
    def xpos(t): return left + (t-start)/(end-start)*(right-left)
    for i in range(9):
        t=start+(end-start)*i/8
        x=xpos(t)
        svg += [f'<path d="M{x:.2f} 78V{height-42}" stroke="#e4eaf0"/>',
                f'<text x="{x:.2f}" y="{height-22}" text-anchor="middle" font-size="12">{t/1000:.2f} µs</text>']
    for index,name in enumerate(names):
        y=top+index*rowh
        svg.append(f'<text x="18" y="{y+20}" class="label">{escape(name)}</text>')
        state='x'
        entries=[]
        for t,v in changes[name]:
            if t<=start: state=v
            elif t<end: entries.append((t,v))
        entries=[(start,state)]+entries+[(end,state)]
        if widths[name]==1:
            path=''
            for j,(t,v) in enumerate(entries[:-1]):
                yy=y+(7 if v=='1' else 29 if v=='0' else 18)
                x1,x2=xpos(t),xpos(entries[j+1][0])
                path += (f'M{x1:.2f},{yy}' if j==0 else f'V{yy}') + f'H{x2:.2f}'
            svg.append(f'<path d="{path}" fill="none" stroke="#087b72" stroke-width="2"/>')
        else:
            for j,(t,v) in enumerate(entries[:-1]):
                x1,x2=xpos(t),xpos(entries[j+1][0])
                svg.append(f'<path d="M{x1:.2f},{y+7}H{x2:.2f}M{x1:.2f},{y+29}H{x2:.2f}M{x1:.2f},{y+7}V{y+29}" stroke="#315caa" fill="none"/>')
                if x2-x1>42:
                    value='X' if any(c in v for c in 'xz') else f'{int(v,2):0{(widths[name]+3)//4}X}'
                    svg.append(f'<text x="{(x1+x2)/2:.2f}" y="{y+23}" text-anchor="middle" class="label">{value}</text>')
    svg.append('</svg>')
    (OUT/output).write_text('\n'.join(svg),encoding='utf-8')

waveform('expanda_sampler.vcd','tb_expanda_sampler',
         ['clk','byte_valid','byte_ready','byte_data','coeff_valid','coeff_ready','coeff','busy'],
         70,450,'sampler_waveform.svg','Rejection sampler: stable coefficient while output is stalled')
waveform('expanda_shake64_msb.vcd','tb_expanda_stream',
         ['request_valid','req_row','req_col','cancel','row_valid','row_index','release_row','done'],
         0,200000,'row_buffer_waveform.svg','ExpandA: polynomial contexts and bounded row-buffer lifetime')
with (OUT/'expanda_benchmark.csv').open() as f:
    rows=list(csv.DictReader(f))
old=sum(int(r['baseline_cycles']) for r in rows)
new=sum(int(r['new_cycles']) for r in rows)
svg=['<svg xmlns="http://www.w3.org/2000/svg" width="1100" height="330" viewBox="0 0 1100 330">',
     '<rect width="100%" height="100%" fill="white"/>',
     '<g font-family="Arial,sans-serif" fill="#243447">',
     '<text x="24" y="32" font-size="21" font-weight="bold">Measured post-SHAKE sampler cycles</text>',
     '<text x="24" y="60" font-size="14">16 sequential ML-DSA-44 polynomials · one channel · precomputed XOF · no output stalls</text>']
for y,label,value,color in [(100,'OSH rejection_a',old,'#315caa'),(180,'New sampler + 64-bit serializer',new,'#087b72')]:
    width=650*value/new
    svg += [f'<text x="24" y="{y+23}" font-size="15">{label}</text>',
            f'<rect x="310" y="{y}" width="{width:.2f}" height="36" fill="{color}"/>',
            f'<text x="{320+width:.2f}" y="{y+24}" font-size="15">{value:,}</text>']
svg += [f'<text x="24" y="270" font-size="15">New / OSH cycle ratio: {new/old:.2f}×. Both matched all 4,096 expected coefficients.</text>',
        '<text x="24" y="300" font-size="13">Excludes SHAKE, full-system control, RAM consumer, HPS transfer, and FPGA timing/resource measurements.</text>',
        '</g></svg>']
(OUT/'sampler_benchmark.svg').write_text('\n'.join(svg),encoding='utf-8')
print(f'Rendered two waveform SVGs and benchmark SVG; measured cycle ratio {new/old:.4f}.')

if (OUT / 'expanda_integrated.vcd').exists():
    waveform('expanda_integrated.vcd', 'tb_expanda_integrated.dut',
             ['ctrl_state','input_word','shake_init','shake_in_valid','shake_in_ready',
              'shake_in_nbytes','shake_finalize','shake_phase_done','shake_squeeze_en'],
             1000,1800,'integrated_absorb_waveform.svg',
             'Live SHAKE integration: seed and indices absorbed as 16 + 16 + 2 bytes')
    waveform('expanda_integrated.vcd', 'tb_expanda_integrated.dut',
             ['ctrl_state','shake_out_valid','shake_out_ready','shake_out_data'],
             26000,28500,'integrated_xof_waveform.svg',
             'Live SHAKE output: 128-bit least-significant-byte-first transfers')
    waveform('expanda_integrated.vcd', 'tb_expanda_integrated',
             ['job_valid','busy','row_valid','row_index','read_enable','release_row','done','error'],
             1000,2240000,'integrated_rows_waveform.svg',
             'Complete ExpandA: actual SHAKE128, four row lifetimes, one matrix')
    print('Rendered three live-SHAKE integration waveform SVGs.')
