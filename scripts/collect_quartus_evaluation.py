"""Extract measured isolated-project resources/timing and check snapshot hashes."""
import csv
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'quartus/evaluation'
manifest = json.loads((BASE / 'source_manifest.json').read_text())
for source, expected in manifest.items():
    snapshot = BASE / 'rtl' / Path(source).name
    assert hashlib.sha256(snapshot.read_bytes()).hexdigest() == expected, snapshot

def resource(text, label):
    match = re.search(r'^' + re.escape(label) + r'\s*:\s*([\d,]+)', text, re.M)
    if not match:
        raise ValueError(label)
    return int(match.group(1).replace(',', ''))

result = {'method': 'Standalone virtual-pin IP; clock-only SDC; no board I/O timing',
          'device': '5CSEBA6U23I7', 'target_clock_mhz': 100, 'fitter_seed': 1,
          'parallel_lanes': 5, 'source_sha256': manifest, 'variants': {}}
for variant in ('row', 'full'):
    folder = BASE / variant / 'output_files'
    revision = 'evaluation_' + variant
    fit = (folder / (revision + '.fit.summary')).read_text()
    assert 'Fitter Status : Successful' in fit
    rpt = (folder / (revision + '.sta.rpt')).read_text()
    summary = (folder / (revision + '.sta.summary')).read_text()
    checks = re.findall(r'Type\s*:\s*(.*?)\nSlack\s*:\s*([-\d.]+)', summary)
    clocks = re.findall(r'; ([\d.]+) MHz\s*; ([\d.]+) MHz\s*; clk\s*;', rpt)
    assert len(clocks) == 2, clocks
    data = {name: resource(fit, label) for name, label in [
        ('alms', 'Logic utilization (in ALMs)'), ('registers', 'Total registers'),
        ('physical_pins', 'Total pins'), ('virtual_pins', 'Total virtual pins'),
        ('memory_payload_bits', 'Total block memory bits'),
        ('ram_blocks', 'Total RAM Blocks'), ('dsp_blocks', 'Total DSP Blocks')]}
    assert data['physical_pins'] == 1 and data['virtual_pins'] == 281
    data['tool_version'] = re.search(r'^Quartus Prime Version : (.*)', fit, re.M).group(1)
    data['timing_checks_ns'] = {name: float(slack) for name, slack in checks}
    data['worst_setup_ns'] = min(float(s) for n, s in checks if ' Setup ' in n)
    data['worst_hold_ns'] = min(float(s) for n, s in checks if ' Hold ' in n)
    data['slow_corner_fmax_mhz'] = dict(zip(['100C', '-40C'], [float(c[0]) for c in clocks]))
    data['slow_corner_restricted_fmax_mhz'] = dict(zip(['100C', '-40C'], [float(c[1]) for c in clocks]))
    data['unconstrained_ports'] = {}
    for direction in ('Input', 'Output'):
        m = re.search(r'; Unconstrained ' + direction + r' Ports\s*;\s*(\d+)\s*;\s*(\d+)', rpt)
        data['unconstrained_ports'][direction.lower()] = {'setup': int(m[1]), 'hold': int(m[2])}
    result['variants'][variant] = data
row, full = [result['variants'][v] for v in ('row', 'full')]
result['memory_payload_reduction_percent'] = 100 * (1-row['memory_payload_bits']/full['memory_payload_bits'])
result['ram_block_reduction_percent'] = 100 * (1-row['ram_blocks']/full['ram_blocks'])
with (ROOT / 'results/v2_fast/latency.csv').open(newline='') as f:
    cycles = [int(r['done_cycles']) for r in csv.DictReader(f) if r['stress'] == '0']
result['unstalled_producer_done_cycles'] = cycles
result['mean_cycles'] = sum(cycles)/len(cycles)
result['projected_latency_ms_at_100mhz'] = result['mean_cycles']/100000
result['development_sources_still_match_snapshot'] = all(
    hashlib.sha256((ROOT / source).read_bytes()).hexdigest() == digest
    for source, digest in manifest.items())
out = ROOT / 'results/quartus_evaluation_summary.json'
out.write_text(json.dumps(result, indent=2)+'\n')
print(out)
print(json.dumps({v: {k: result['variants'][v][k] for k in
    ('alms','registers','ram_blocks','worst_setup_ns','worst_hold_ns','slow_corner_fmax_mhz')}
    for v in ('row','full')}, indent=2))
print('Development sources match snapshot:', result['development_sources_still_match_snapshot'])
