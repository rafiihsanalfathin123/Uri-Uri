"""Extract actual fitted IP resources and timing; do not substitute payload for M10K."""
from pathlib import Path
import re
import json
import hashlib
root=Path(__file__).resolve().parents[1]
rows=[]
for variant in ['stream','row','full']:
    revision='expanda_'+variant
    folder=root/'quartus'/revision/'output_files'
    summary=(folder/(revision+'.fit.summary')).read_text()
    assert 'Fitter Status : Successful' in summary
    fit=(folder/(revision+'.fit.rpt')).read_text()
    sta=(folder/(revision+'.sta.rpt')).read_text()
    timing=(folder/(revision+'.sta.summary')).read_text()
    def count(label):
        return int(re.search(r'^'+re.escape(label)+r'\s*:\s*([\d,]+)',summary,re.M)[1].replace(',',''))
    fmax=[float(x) for x in re.findall(r';\s*([\d.]+) MHz\s*;\s*[\d.]+ MHz\s*;\s*clk',sta)]
    setup=[float(x) for x in re.findall(r"Type\s*:\s*[^\n]+Setup 'clk'\s*\nSlack\s*:\s*([-\d.]+)",timing)]
    hold=[float(x) for x in re.findall(r"Type\s*:\s*[^\n]+Hold 'clk'\s*\nSlack\s*:\s*([-\d.]+)",timing)]
    assert fmax and setup and hold and min(setup)>0 and min(hold)>0
    rows.append({'variant':variant,'ALMs':count('Logic utilization (in ALMs)'),
        'registers':count('Total registers'),'payload_bits':count('Total block memory bits'),
        'M10K':int(re.search(r'; M10K blocks\s*;\s*(\d+)',fit)[1]),
        'minimum_reported_Fmax_MHz':min(fmax),'minimum_setup_slack_ns':min(setup),
        'minimum_hold_slack_ns':min(hold),
        'fit_status':summary.splitlines()[0],
        'unconstrained_input_ports':int(re.search(r'; Unconstrained Input Ports\s*;\s*(\d+)',sta)[1]),
        'unconstrained_output_ports':int(re.search(r'; Unconstrained Output Ports\s*;\s*(\d+)',sta)[1])})
data={'tool':'Quartus Prime Lite 23.1std.1 Build 993','device':'5CSEBA6U23I7',
      'clock_target_MHz':100,'scope':'Out-of-context IP: virtual data pins, automatically placed physical clock, unconstrained external I/O',
      'results':rows,'M10K_reduction_percent':100*(1-rows[1]['M10K']/rows[2]['M10K']),
      'RTL_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((root/'rtl').glob('expanda_*.v'))}}
(root/'results/v2_quartus_resources.json').write_text(json.dumps(data,indent=2)+'\n')
lines=['# Quartus V2 fitted resources and timing','',
 'Actual Analysis & Synthesis, Fitter and Timing Analyzer runs completed successfully on Cyclone V 5CSEBA6U23I7 with Quartus Prime Lite 23.1std.1 Build 993. Identical current producer, five-lane SHAKE schedule and 100 MHz clock target; buffer ROWS differs.','',
 '| Variant | ALMs | Registers | A RAM payload bits | M10K blocks | Minimum reported internal Fmax | Minimum setup slack | Minimum hold slack |',
 '|---|---:|---:|---:|---:|---:|---:|---:|']
for r in rows:
    lines.append(f'| {r["variant"]} | {r["ALMs"]} | {r["registers"]} | {r["payload_bits"]} | {r["M10K"]} | {r["minimum_reported_Fmax_MHz"]:.2f} MHz | {r["minimum_setup_slack_ns"]:.3f} ns | {r["minimum_hold_slack_ns"]:.3f} ns |')
lines += ['',f'**Measured physical M10K reduction: {data["M10K_reduction_percent"]:.3f}% (13 blocks to 4).** Matched logical A payload falls 75%. These are distinct measurements. 13 M10Ks allocate 133120 physical bits (16.25 KiB), while four allocate 40960 bits (5 KiB); unused capacity reflects width/depth mapping. No MLAB memory or DSP blocks are used in these variants.',
 '', 'All modeled internal setup/hold checks pass at the 10 ns clock target. Reported Fmax describes same-clock internal paths; it is not a demonstrated board clock or complete interface timing closure. External ports are virtual and unconstrained. The physical clock is automatically placed: reports warn about its missing exact pin location and non-dedicated routing. A board wrapper needs a valid clock source/location and I/O delays. An explicit Virtual Pin OFF assignment on clk is ignored; clk still remains physical because it is excluded from the virtual-input list. A Lite LogicLock feature warning is also present. No assembler image or board test was produced.',
 '', 'Stream synthesis: 7960 combinational ALUTs, 2815 registers, zero RAM payload bits. Declared producer storage is 2806 bits; synthesis FSM recoding/logic transformations explain why register counts are not identical. Fitted ALMs are authoritative for this FPGA run; they are not ASIC gates or bytes. The compact-bank optimization reduces storage, but five-lane parallel logic has an area cost. A matched serial fit and a full upstream signer fit have not been measured.',
 '', 'Small row/full ALM differences reflect control/address logic and fitter packing/placement; do not interpret them as an arithmetic throughput gain. The row/full payload and physical M10K comparison uses the same tested producer and format.',
 '', 'Raw evidence:', '']
for r in rows:
    revision='expanda_'+r['variant']
    base='../quartus/'+revision+'/output_files/'+revision
    lines.append(f'* {r["variant"]}: [fit summary]({base}.fit.summary), [fit report]({base}.fit.rpt), [timing summary]({base}.sta.summary), [timing report]({base}.sta.rpt).')
lines += ['','[Machine-readable values and RTL hashes](v2_quartus_resources.json).']
(root/'results/v2_quartus_resources.md').write_text('\n'.join(lines)+'\n')
print(json.dumps(rows))
