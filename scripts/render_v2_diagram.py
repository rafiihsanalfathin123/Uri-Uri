"""Static, vector proposal diagrams generated directly from the implemented design."""
from pathlib import Path
from html import escape

root=Path(__file__).resolve().parents[1]
items=['<svg xmlns="http://www.w3.org/2000/svg" width="1400" height="780" viewBox="0 0 1400 780">',
 '<rect width="1400" height="780" fill="white"/>',
 '<style>text{font-family:Arial,sans-serif;fill:#17324d}.title{font-size:27px;font-weight:bold}.label{font-size:18px}.small{font-size:16px}</style>',
 '<defs><marker id="arrow" markerWidth="10" markerHeight="8" refX="9" refY="4" orient="auto"><path d="M0,0 L10,4 L0,8" fill="#315f85"/></marker></defs>',
 '<text x="35" y="43" class="title">ML-DSA-44 ExpandA: compact SHAKE128 and tightly packed output</text>',
 '<text x="35" y="75" class="label">Implemented Verilog-2001 producer · 16 polynomials · 256 unsigned 23-bit coefficients per polynomial</text>']
def text(x,y,t,cls='label'):
    items.append(f'<text x="{x}" y="{y}" class="{cls}">{escape(t)}</text>')
def box(x,y,w,h,lines,color='#e8f1fa',dash=False):
    items.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="10" fill="{color}" stroke="#315f85" stroke-width="2"'+(' stroke-dasharray="7 5"' if dash else '')+'/>')
    for i,line in enumerate(lines): text(x+15,y+28+26*i,line,'label' if i==0 else 'small')
def line(x1,y1,x2,y2,dash=False):
    items.append(f'<path d="M{x1},{y1} L{x2},{y2}" fill="none" stroke="#315f85" stroke-width="2" marker-end="url(#arrow)"'+(' stroke-dasharray="6 4"' if dash else '')+'/>')
box(35,120,1330,112,['ExpandA controller and index generator','row/col, init, absorb, finalize, squeeze, flush, done','Waits for accepted final output; propagates errors'], '#dcece6')
for x in [145,420,690,945,1235]:
    line(x,232,x,320)
text(35,278,'clk / synchronous rst to all blocks','small')
box(35,320,220,145,['Seed capture / absorb','rho: 2 × 128-bit words','256-bit seed held','SHAKE input: 16+16+2 B','rho || col || row'])
box(295,320,250,145,['SHAKE128 engine','state 1600 + scratch 320','carry 64 + I/O 128 bits','5-lane theta/chi schedule','1105 cycles / permutation'])
box(585,320,220,145,['XOF byte buffer','144-bit reservoir','Preserves byte ordering','128-bit input words','24-bit candidates'])
box(845,320,220,145,['RejNTTPoly sampler','t = candidate[22:0]','Accept if t < 8380417','Exactly 256 coefficients','23-bit data + 8-bit index'])
box(1105,320,260,145,['128-bit output packer','150-bit reservoir','Continuous 23-bit packing','46 words per polynomial','No coefficient padding'])
for x in [255,545,805,1065]: line(x,393,x+40,393)
line(1235,465,1235,542)
box(1070,542,300,102,['Streaming consumer interface','data[127:0], valid / ready','poly_idx[3:0], word_idx[5:0], last'], '#dcece6')
line(1120,465,925,542,True)
box(740,542,295,102,['Optional A memory wrapper','One row: 184 × 128 = 2944 B','Full matrix: 736 × 128 = 11776 B'], '#fff2d7',True)
line(1035,590,1070,590,True)
text(35,535,'Ready/valid backpressure preserves data and tags across stalls.')
text(35,567,'Main producer: 2806 declared storage bits; no A RAM.')
text(35,599,'Row/full wrappers share the same producer and packed layout.')
text(35,631,'Matrix-vector arithmetic is a future downstream integration.')
text(35,708,'Word 0: five full coefficients + low 13 bits of coefficient 5; word 1 continues coefficient 5.')
text(35,740,'256 × 23 = 46 × 128 bits: every polynomial ends on a complete word; last is asserted on word 45.')
items.append('</svg>')
(root/'docs/assets/expanda_system.svg').write_text('\n'.join(items),encoding='utf-8')
print('Rendered current vector block diagram.')
