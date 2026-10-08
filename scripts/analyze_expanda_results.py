"""Summarize measured output, storage, latency, and arithmetic-derived metrics."""
import csv
import hashlib
import json
from pathlib import Path
from statistics import mean

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'results'

def rows(name):
    with (OUT / name).open() as stream:
        return list(csv.DictReader(stream))

coeff = rows('expanda_output_comparison.csv')
xof = rows('expanda_xof_comparison.csv')
stats = rows('expanda_polynomial_stats.csv')
latency = json.loads((OUT / 'expanda_latency.json').read_text())
memory = json.loads((OUT / 'expanda_memory_inventory.json').read_text())
manifest = json.loads((ROOT / 'vectors/integrated_manifest.json').read_text())
gold = [int(line, 16) for line in (ROOT / 'vectors/integrated_coeffs.hex').read_text().splitlines()]
seeds = [bytes.fromhex(seed) for seed in manifest['seed_bytes_hex']]
assert len(coeff) == len(gold) == 12288 and len(stats) == 48
assert all(int(r['match']) == 1 for r in coeff + xof)
for index, row in enumerate(coeff):
    assert int(row['expected_hex'], 16) == int(row['actual_hex'], 16) == gold[index]
    assert (int(row['job']), int(row['row']), int(row['col']), int(row['coefficient'])) == (
        index // 4096, (index % 4096) // 1024, (index % 1024) // 256, index % 256)
for row in xof:
    job, r, c, offset = (int(row[key]) for key in ['job', 'row', 'col', 'byte_offset'])
    expected = hashlib.shake_128(seeds[job] + bytes([c, r])).digest(offset + 16)[offset:]
    assert int.from_bytes(expected, 'little') == int(row['actual_word_hex'], 16) == int(row['expected_word_hex'], 16)

jobs = []
for job in range(3):
    poly_stats = [{key: int(value) for key, value in row.items()} for row in stats if int(row['job']) == job]
    assert len(poly_stats) == 16
    for row in poly_stats:
        raw = hashlib.shake_128(seeds[job] + bytes([row['col'], row['row']])).digest(1200)
        accepted, rejected, consumed = 0, 0, 0
        for offset in range(0, len(raw), 3):
            consumed += 3
            if int.from_bytes(raw[offset:offset+3], 'little') & 0x7fffff < 8380417:
                accepted += 1
            else:
                rejected += 1
            if accepted == 256:
                break
        assert row['sampler_bytes'] == consumed and row['rejected_candidates'] == rejected
        assert row['accepted_coefficients'] == accepted == 256 and row['absorb_bytes'] == 34
        assert row['xof_transfer_bytes'] >= consumed and row['xof_transfer_bytes'] % 16 == 0
        actual_words = [r for r in xof if (int(r['job']), int(r['row']), int(r['col'])) == (job, row['row'], row['col'])]
        assert len(actual_words) * 16 == row['xof_transfer_bytes']
    sums = {key: sum(row[key] for row in poly_stats) for key in poly_stats[0] if key not in ['job', 'row', 'col']}
    actual = b''.join(int(row['actual_hex'], 16).to_bytes(3, 'little') for row in coeff if int(row['job']) == job)
    expected = b''.join(value.to_bytes(3, 'little') for value in gold[job*4096:(job+1)*4096])
    assert actual == expected
    elapsed = latency['jobs'][job]
    jobs.append(dict(job=job, **sums,
                     discarded_transferred_tail_bytes=sums['xof_transfer_bytes']-sums['sampler_bytes'],
                     generation_cycles=elapsed['generation_cycles'],
                     permutation_share_percent=100*sums['permutation_cycles']/elapsed['generation_cycles'],
                     expected_output_sha256=hashlib.sha256(expected).hexdigest(),
                     actual_output_sha256=hashlib.sha256(actual).hexdigest()))

cycles = latency['mean_generation_cycles']
done = mean(job['job_done_cycles'] for job in latency['jobs'])
baseline = rows('expanda_benchmark.csv')
old_cycles = sum(int(row['baseline_cycles']) for row in baseline)
new_cycles = sum(int(row['new_cycles']) for row in baseline)
p = 8380417 / 2**23
metrics = dict(
    A_payload_saved_bytes=12288-3072, A_payload_reduction_percent=75,
    A_padding_bits_per_coefficient=1, A_padding_fraction_percent=100/24,
    tightly_packed_23bit_full_A_bytes=4096*23/8,
    tightly_packed_23bit_row_A_bytes=1024*23/8,
    integrated_other_storage_bytes=memory['other_clocked_bits']/8,
    integrated_overhead_relative_to_A_RAM_percent=100*memory['other_clocked_bits']/memory['ram_bits'],
    A_RAM_share_of_declared_total_percent=100*memory['ram_bits']/memory['total_bits'],
    SHAKE_main_data_reduction_percent=100*(4288-2112)/4288,
    SHAKE_plus_serializer_data_reduction_percent=100*(4288-2240)/4288,
    coefficient_accept_probability=p, rejection_probability=1-p,
    expected_candidates_per_polynomial=256/p,
    expected_sampler_bytes_per_polynomial=768/p,
    expected_rejections_per_matrix=4096*(1-p)/p,
    coefficient_cycles_average=cycles/4096,
    amortized_polynomial_cycles=cycles/16,
    generation_matrices_per_second_at_100MHz=100_000_000/cycles,
    generation_coefficients_per_second_at_100MHz=4096*100_000_000/cycles,
    generation_24bit_payload_MB_per_second_at_100MHz=12288*100_000_000/cycles/1_000_000,
    testbench_completed_jobs_per_second_at_100MHz=100_000_000/done,
    testbench_consumer_share_percent=100*1392/done,
    row_ideal_read_requests=256, matrix_ideal_read_requests=1024,
    row_read_peak_bytes_per_clock=12,
    row_read_peak_MB_per_second_at_100MHz=1200,
    post_SHAKE_benchmark_baseline_cycles=old_cycles,
    post_SHAKE_benchmark_new_cycles=new_cycles,
    post_SHAKE_benchmark_cycle_ratio=new_cycles/old_cycles,
    future_NTT_domain_products_per_matrix=16*256,
    future_NTT_domain_accumulation_additions_per_matrix=4*3*256)
result = dict(method='CSV output comparisons cross-checked with independent hashlib and golden coefficients; VCD latency and declared memory inventories',
              coefficients_checked=len(coeff), coefficient_mismatches=0,
              xof_words_checked=len(xof), xof_bytes_checked=len(xof)*16, xof_word_mismatches=0,
              jobs=jobs, derived_metrics=metrics,
              limits=['Rates at 100 MHz are cycle-to-time projections, not measured FPGA Fmax.',
                      'Random candidate expectation assumes independent uniform SHAKE bytes; not a worst-case bound.',
                      'Ideal RAM-port bandwidth is not the sustained integrated generation rate.',
                      'Full upstream integrated latency/resources, power, energy, and signing performance are unmeasured.'])
(OUT / 'expanda_analysis.json').write_text(json.dumps(result, indent=2)+'\n')
print(f'PASS: {len(coeff)} actual coefficients and {len(xof)} actual SHAKE words match; independent byte-count checks pass.')
for job in jobs:
    print(json.dumps(job))
print(json.dumps(metrics, indent=2))
