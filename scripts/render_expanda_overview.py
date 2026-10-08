"""Create editable SVG overview figures for the README and proposal."""
from html import escape
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'docs/assets'
ASSETS.mkdir(exist_ok=True)
style = '<style>text{font-family:Arial,sans-serif;fill:#203047} .small{font-size:15px} .title{font-size:19px;font-weight:bold}</style>'
svg = ['<svg xmlns="http://www.w3.org/2000/svg" width="1240" height="630" viewBox="0 0 1240 630">',
       '<rect width="1240" height="630" fill="white"/>', style,
       '<defs><marker id="arrow" markerWidth="10" markerHeight="8" refX="9" refY="4" orient="auto"><path d="M0,0 L10,4 L0,8" fill="#465c72"/></marker></defs>',
       '<text x="30" y="36" font-size="25" font-weight="bold">Integrated ExpandA-44 with reusable row storage</text>',
       '<text x="30" y="61" class="small">Implemented generation path; current consumer is a simulation scoreboard. Matrix-vector arithmetic is planned.</text>']

def box(x, y, w, h, title, lines, color='#eaf6f2'):
    svg.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="10" fill="{color}" stroke="#536b80"/>')
    svg.append(f'<text x="{x+14}" y="{y+29}" class="title">{escape(title)}</text>')
    for i, line in enumerate(lines):
        svg.append(f'<text x="{x+14}" y="{y+55+i*21}" class="small">{escape(line)}</text>')

def arrow(path, label=None, x=0, y=0, dashed=False):
    dash=' stroke-dasharray="7 5"' if dashed else ''
    svg.append(f'<path d="{path}" fill="none" stroke="#465c72" stroke-width="2" marker-end="url(#arrow)"{dash}/>')
    if label:
        svg.append(f'<text x="{x}" y="{y}" class="small">{escape(label)}</text>')

box(30,95,250,100,'Job input',['rho: 256 bits, earliest byte LSB','job_valid / job_ready'], '#edf2fb')
box(345,95,370,100,'SHAKE phase controller',['Init; absorb 16 + 16 + 2 bytes','Finalize; squeeze; cancel / flush'])
box(785,95,420,100,'Row scheduler and ownership',['16 contexts: row 0..3, column 0..3','Hold completed row until row_release'])
box(30,270,275,115,'Shared SHAKE128',['1,600-bit state; reusable scratch','128-bit output, earliest byte LSB','2,112 main data bits'])
box(360,270,205,115,'Serializer',['128 bits to 8 bits','Elastic word storage','Flush on cancellation'])
box(620,270,245,115,'Rejection sampler',['Three bytes to 23-bit candidate','Accept candidate < 8,380,417','Stop at 256 accepted values'])
box(920,270,285,115,'Coefficient packing',['Four zero-padded 24-bit slots','96-bit word; 64 words / poly','Single write stream'])
box(920,465,285,110,'Reusable A row RAM',['256 x 96 declared bits = 3 KiB','Four polynomial slots','Synchronous 96-bit read'])
box(30,465,470,110,'Row consumer boundary',['Current: testbench reads and checks all values','Planned: NTT-domain matrix-vector datapath','Release only after all operand uses finish'], '#fff4dd')
arrow('M155 95 V80 H995 V95')
arrow('M345 170 H320 V237 H165 V270', 'phase commands', 35,225)
arrow('M785 145 H715', 'req', 732,130, True)
arrow('M305 328 H360','128',315,315)
arrow('M565 328 H620','8',580,315)
arrow('M865 328 H920','23',880,315)
arrow('M1060 385 V465','96-bit writes',1075,433)
arrow('M920 525 H500','96-bit read response',595,515)
arrow('M500 480 H890 V465','read enable / address',560,470)
arrow('M280 465 V425 H995 V195','row_release: return ownership',345,417,True)
svg.append('<text x="30" y="613" class="small">All RTL uses one clock and synchronous reset. Dashed paths show control/ownership; arrows do not imply clock-domain crossing.</text>')
svg.append('</svg>')
system = '\n'.join(svg)
ET.fromstring(system)
(ASSETS / 'expanda_system.svg').write_text(system, encoding='utf-8')

memory = ['<svg xmlns="http://www.w3.org/2000/svg" width="1100" height="350" viewBox="0 0 1100 350">',
          '<rect width="1100" height="350" fill="white"/>', style,
          '<text x="30" y="38" font-size="25" font-weight="bold">ML-DSA-44 logical A storage: 75% reduction</text>',
          '<text x="30" y="70" class="small">Same format: four 24-bit coefficient slots per 96-bit word. A payload only.</text>']
for y,label,kib,color in [(110,'Full A: 16 polynomials',12,'#315caa'),(200,'One row: 4 polynomials',3,'#087b72')]:
    width=600*kib/12
    memory.extend([f'<text x="30" y="{y+28}" font-size="18">{label}</text>',
                   f'<rect x="330" y="{y}" width="{width}" height="44" rx="5" fill="{color}"/>',
                   f'<text x="{340+width}" y="{y+29}" font-size="18">{kib} KiB</text>'])
memory += ['<text x="30" y="295" font-size="19" font-weight="bold">Saved payload: 9 KiB. Complete integrated declared storage: approximately 3.344 KiB.</text>',
           '<text x="30" y="325" class="small">This comparison does not establish fitted M10K counts or whole-signer FPGA resource savings.</text>', '</svg>']
payload = '\n'.join(memory)
ET.fromstring(payload)
(ASSETS / 'expanda_memory.svg').write_text(payload, encoding='utf-8')
print('Rendered and XML-validated system and memory SVG figures.')
