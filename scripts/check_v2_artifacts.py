"""Check current documentation links, SVG syntax, source types and simulator evidence."""
from pathlib import Path
import hashlib
import json
import re
import xml.etree.ElementTree as ET
root=Path(__file__).resolve().parents[1]
current=[root/'README.md']+[root/'docs'/n for n in ['EXPANDA_INTERFACE.md','EXPANDA_INTEGRATED.md',
    'EXPANDA_MEMORY_EVALUATION.md','EXPANDA_LATENCY.md','EXPANDA_VERIFICATION_AND_COMPARISON.md','QUARTUS_STEP_BY_STEP.md']]+[root/'results/v2_quartus_resources.md']
for p in current:
    text=p.read_text(encoding='utf-8-sig')
    for target in re.findall(r'!?\[[^\]]*\]\(([^)]+)\)',text):
        target=target.strip('<>').split('#')[0]
        if not target or '://' in target: continue
        assert (p.parent/target).exists(), (p.name,target)
for p in [root/'docs/assets/expanda_system.svg',root/'results/v2_packed_stall_waveform.svg']:
    ET.parse(p)
assert not list((root/'rtl').glob('*.sv')) and not list((root/'tb').glob('*.sv'))
for p in list((root/'rtl').glob('*.v'))+list((root/'tb').glob('*.v')):
    assert not re.search(r'\b(always_ff|always_comb|always_latch|logic)\b|\$fatal\b|\$clog2\b|endend',p.read_text()), p.name
transcript=(root/'results/questa/transcript.log').read_text(encoding='utf-8-sig')
assert 'PASS: V2 Verilog lanes=5' in transcript and 'Errors: 0' in transcript
assert (root/'results/questa/expanda.wlf').stat().st_size>100000
metrics=json.loads((root/'results/v2_analysis.json').read_text())
for name,digest in metrics['source_sha256'].items():
    assert hashlib.sha256((root/name).read_bytes()).hexdigest()==digest,name
for variant in ['v2_fast','v2_serial','v2_units','v2_row','v2_full']:
    text=(root/'results'/variant/'simulation.log').read_text(encoding='utf-8-sig')
    assert 'PASS:' in text and 'FAIL:' not in text,variant
for variant in ['v2_fast','v2_serial']:
    assert 'PASS ALL 81' in (root/'results'/variant/'shake.log').read_text(encoding='utf-8-sig')
print('PASS: current links, vector SVGs, Verilog source formats/hashes, simulation logs and native WLF.')
