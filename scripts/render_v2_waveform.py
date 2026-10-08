"""Extract actual Questa VCD transitions into a proposal-ready SVG."""
from pathlib import Path
from html import escape
root=Path(__file__).resolve().parents[1]
names={'start':1,'busy':1,'output_valid':1,'output_ready':1,'poly_idx':4,'word_idx':6,'output_last':1,'output_data':128}
values={n:'x'*w for n,w in names.items()}
changes={n:[] for n in names}
signals={}
stack=[]
time=0
dirty=set()
def flush():
    for n in dirty:
        changes[n].append((time/1000,values[n]))
    dirty.clear()
with (root/'results/v2_fast/expanda.vcd').open() as f:
    for raw in f:
        line=raw.strip(); parts=line.split()
        if line.startswith('$scope'):stack.append(parts[2])
        elif line.startswith('$upscope'):stack.pop()
        elif line.startswith('$var') and stack==['tb_expanda_v2']:
            name=parts[4]
            if name in names:
                bit=None
                if int(parts[2])==1 and names[name]>1:
                    bit=int(parts[5].strip('[]'))
                signals[parts[3]]=(name,bit)
        elif line.startswith('#'):
            flush();time=int(line[1:])
        elif line and line[0] in '01xz' and line[1:] in signals:
            name,bit=signals[line[1:]];v=line[0]
            if bit is None: values[name]=v
            else:
                pos=names[name]-1-bit
                values[name]=values[name][:pos]+v+values[name][pos+1:]
            dirty.add(name)
        elif line.startswith('b') and len(parts)==2 and parts[1] in signals:
            name,bit=signals[parts[1]]
            values[name]=parts[0][1:].zfill(names[name]);dirty.add(name)
flush()
starts=[t for t,v in changes['start'] if v=='1']
# Main stress job is the fourth complete job, after two reset/abort exercises.
stress_start=max(t for t in starts if any(t < tv < t+15000 and v=='1' for tv,v in changes['output_valid']))
valid_time=next(t for t,v in changes['output_valid'] if t>stress_start and v=='1')
begin=valid_time-80;end=valid_time+1620
left=190;right=1490;top=110;rowh=58;height=top+rowh*len(names)+80
svg=[f'<svg xmlns="http://www.w3.org/2000/svg" width="1530" height="{height}" viewBox="0 0 1530 {height}">',
 '<rect width="100%" height="100%" fill="white"/>',
 '<style>text{font-family:Arial,sans-serif;fill:#17324d}.label{font-family:monospace;font-size:15px}</style>',
 '<text x="25" y="35" font-size="25" font-weight="bold">Actual Questa simulation: packed output remains stable during backpressure</text>',
 '<text x="25" y="66" font-size="17">Stress job, first word: output_valid=1 and output_ready=0 hold data and both indices.</text>',
 '<text x="25" y="91" font-size="15">Source: results/v2_fast/expanda.vcd · Questa Intel FPGA Starter 2023.3 · 10 ns clock</text>']
def x(t):return left+(t-begin)/(end-begin)*(right-left)
for i in range(9):
    t=begin+(end-begin)*i/8
    svg.extend([f'<path d="M{x(t):.2f},100 V{height-45}" stroke="#e2e9ef"/>',
                f'<text x="{x(t):.2f}" y="{height-20}" text-anchor="middle" font-size="14">{t/1000:.3f} us</text>'])
for idx,(name,width) in enumerate(names.items()):
    y=top+idx*rowh
    svg.append(f'<text x="20" y="{y+24}" class="label">{name}</text>')
    state='x'*width;events=[]
    for t,v in changes[name]:
        if t<=begin:state=v
        elif t<end:events.append((t,v))
    events=[(begin,state)]+events+[(end,state)]
    if width==1:
        path=''
        for j,(t,v) in enumerate(events[:-1]):
            yy=y+(7 if v=='1' else 34 if v=='0' else 20)
            path+=(f'M{x(t):.2f},{yy}' if j==0 else f'V{yy}')+f'H{x(events[j+1][0]):.2f}'
        svg.append(f'<path d="{path}" fill="none" stroke="#087b72" stroke-width="2.5"/>')
    else:
        for j,(t,v) in enumerate(events[:-1]):
            a,b=x(t),x(events[j+1][0])
            svg.append(f'<path d="M{a:.2f},{y+7} H{b:.2f} M{a:.2f},{y+34} H{b:.2f} M{a:.2f},{y+7} V{y+34}" stroke="#315caa" fill="none"/>')
            if b-a>(320 if width==128 else 30):
                label='X' if any(c in v for c in 'xz') else (f'{int(v,2):032x}' if width==128 else str(int(v,2)))
                svg.append(f'<text x="{(a+b)/2:.2f}" y="{y+26}" text-anchor="middle" class="label">{escape(label)}</text>')
svg.append('</svg>')
(root/'results/v2_packed_stall_waveform.svg').write_text('\n'.join(svg),encoding='utf-8')
print(f'Rendered actual stress waveform: {begin/1000:.3f}..{end/1000:.3f} us.')
