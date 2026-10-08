"""Verify packed simulation records and calculate reproducible V2 metrics."""
import csv
import hashlib
import json
import statistics
from pathlib import Path

root = Path(__file__).resolve().parents[1]
def records(path):
    with (root/path).open(encoding='utf-8-sig') as stream:
        return list(csv.DictReader(stream))

gold = [int(x,16) for x in (root/'vectors/integrated_coeffs.hex').read_text().split()]
verification = {}
for variant in ['v2_fast','v2_serial']:
    output = records(f'results/{variant}/output.csv')
    assert len(output) == 2944
    decoded = 0
    for job in range(4):
        for poly in range(16):
            rows = [r for r in output if int(r['job']) == job and int(r['poly']) == poly]
            assert [int(r['word']) for r in rows] == list(range(46))
            assert all(r['expected_hex'] == r['actual_hex'] and r['match'] == '1' for r in rows)
            bits = sum(int(r['actual_hex'],16) << (128*i) for i,r in enumerate(rows))
            seed_job = job if job < 3 else 0
            expected = gold[seed_job*4096+poly*256:seed_job*4096+(poly+1)*256]
            actual = [(bits >> (23*i)) & 0x7fffff for i in range(256)]
            assert actual == expected
            decoded += 256
    xof = records(f'results/{variant}/xof.csv')
    assert all(r['expected_hex'] == r['actual_hex'] for r in xof)
    polys = records(f'results/{variant}/polynomials.csv')
    assert len(polys) == 64
    assert all(int(r['coefficients']) == 256 and int(r['candidates']) == 256+int(r['rejected']) for r in polys)
    verification[variant] = {'packed_words':len(output),'decoded_coefficients':decoded,
        'xof_words_checked':len(xof),'contexts':len(polys),'all_match':True}

fast = records('results/v2_fast/latency.csv')
serial = records('results/v2_serial/latency.csv')
for f,s in zip(fast,serial):
    assert int(s['done_cycles']) - int(f['done_cycles']) == 115200
mean_fast = statistics.mean(int(r['done_cycles']) for r in fast if r['stress']=='0')
mean_serial = statistics.mean(int(r['done_cycles']) for r in serial if r['stress']=='0')
inventory = {'controller':9,'seed_capture':262,'shake_data':2112,'shake_control':51,
             'xof_buffer':149,'sampler':43,'packer':180}
assert sum(inventory.values()) == 2806
data = {'scope':'ML-DSA-44 ExpandA producer, no matrix-vector arithmetic',
    'declared_storage_bits':inventory,'stream_bits':2806,'stream_bytes':350.75,
    'row_payload_bits':23552,'row_payload_bytes':2944,'row_total_bits':26498,
    'full_payload_bits':94208,'full_payload_bytes':11776,'full_total_bits':97156,
    'matched_A_payload_reduction_percent':75.0,
    'row_vs_OSH_24bit_A44_payload_reduction_percent':100*(1-2944/12288),
    'verification':verification,'latency_fast':fast,'latency_serial':serial,
    'mean_done_fast_cycles':mean_fast,'mean_done_serial_cycles':mean_serial,
    'matched_cycle_reduction_percent':100*(1-mean_fast/mean_serial),
    'speedup_at_equal_frequency':mean_serial/mean_fast,
    'matrix_ms_at_100MHz':mean_fast/100000,
    'matrices_per_second_at_100MHz':100000000/mean_fast,
    'coefficients_per_second_at_100MHz':4096*100000000/mean_fast,
    'packed_MB_per_second_at_100MHz':11776*100/mean_fast,
    'permutation_cycles_fast':1105,'permutation_cycles_serial':2545,
    'permutations_per_matrix_observed':80,
    'permutation_cycle_share_percent':88400/mean_fast*100,
    'first_row_mean_cycles':statistics.mean(int(r['cycles_since_start']) for r in records('results/v2_row/latency.csv') if r['event']=='published' and r['first_row']=='0'),
    'first_packed_word_hex':records('results/v2_fast/output.csv')[0]['actual_hex'],
    'source_sha256':{str(p.relative_to(root)).replace('\\','/'):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((root/'rtl').glob('expanda_*.v'))},
    'quartus_reports':{}}
for name in ['expanda_stream','expanda_row','expanda_full']:
    reports = root/'quartus'/name/'output_files'
    data['quartus_reports'][name] = {p.name:str(p.relative_to(root)).replace('\\','/') for p in sorted(reports.glob('*.rpt')) if p.suffix=='.rpt'}
(root/'results/v2_analysis.json').write_text(json.dumps(data,indent=2)+'\n')
print(f'PASS: both schedules decoded {16384} matching 23-bit coefficients each; mean fast {mean_fast:.3f} cycles; matched reduction {data["matched_cycle_reduction_percent"]:.3f}%.')
