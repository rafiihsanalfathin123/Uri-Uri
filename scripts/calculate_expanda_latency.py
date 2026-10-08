"""Measure elapsed edge-to-edge ExpandA latency from the actual integration VCD."""
import csv
import json
from pathlib import Path
from statistics import mean

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'results'
VCD = OUT / 'expanda_integrated.vcd'
TOP = 'tb_expanda_integrated'
names = ['clk', 'rst', 'checking', 'job_valid', 'job_ready', 'row_valid',
         'row_index', 'release_row', 'done']
wanted = {TOP + '.' + name: name for name in names}
for name in ['req_valid', 'req_ready', 'req_row', 'req_col', 'cancel']:
    wanted[TOP + '.dut.' + name] = name


def events():
    """Group all delta-cycle changes at a timestamp; units are integer ps."""
    scope, codes = [], {}
    timestamp, changes = 0, {}
    with VCD.open() as stream:
        for raw in stream:
            line = raw.strip()
            parts = line.split()
            if line.startswith('$scope'):
                scope.append(parts[2])
            elif line.startswith('$upscope'):
                scope.pop()
            elif line.startswith('$var'):
                full = '.'.join(scope + [parts[4]])
                if full in wanted:
                    codes[parts[3]] = wanted[full]
            elif line.startswith('$enddefinitions'):
                assert set(codes.values()) == set(wanted.values())
                break
        for raw in stream:
            line = raw.strip()
            if line.startswith('#'):
                yield timestamp, changes
                timestamp, changes = int(line[1:]), {}
            elif line and line[0] in '01xz' and line[1:] in codes:
                changes[codes[line[1:]]] = line[0]
            elif line and line[0] in 'bB':
                value, code = line[1:].split()
                if code in codes:
                    changes[codes[code]] = value
        yield timestamp, changes


state, jobs, active, polynomial = {}, [], None, None
previous_rise, period_ps = None, None
for time_ps, changes in events():
    previous = state.copy()
    state.update(changes)
    rising_clock = previous.get('clk') == '0' and state.get('clk') == '1'
    if not rising_clock:
        continue
    if previous_rise is not None:
        interval = time_ps - previous_rise
        if period_ps is None:
            period_ps = interval
        assert interval == period_ps, 'Variable clock period'
    previous_rise = time_ps
    if previous.get('rst') != '0' or previous.get('checking') != '1':
        continue
    if previous.get('job_valid') == '1' and previous.get('job_ready') == '1':
        assert active is None
        active = dict(job=len(jobs), acceptance_ps=time_ps, rows=[], polynomials=[])
    if active is None:
        continue
    if previous.get('req_valid') == '1' and previous.get('req_ready') == '1':
        assert polynomial is None
        polynomial = dict(row=int(previous['req_row'], 2),
                          col=int(previous['req_col'], 2), request_ps=time_ps)
    if previous.get('cancel') != '1' and state.get('cancel') == '1':
        assert polynomial is not None
        polynomial['completion_ps'] = time_ps
        polynomial['cycles'] = (time_ps - polynomial['request_ps']) // period_ps
        active['polynomials'].append(polynomial)
        polynomial = None
    if previous.get('row_valid') != '1' and state.get('row_valid') == '1':
        start = active['acceptance_ps'] if not active['rows'] else active['rows'][-1]['release_ps']
        assert (time_ps - start) % period_ps == 0
        active['rows'].append(dict(row=int(state['row_index'], 2), publication_ps=time_ps,
                                  generation_cycles=(time_ps - start) // period_ps,
                                  cycles_since_acceptance=(time_ps - active['acceptance_ps']) // period_ps))
    if previous.get('row_valid') == '1' and previous.get('release_row') == '1':
        row = active['rows'][-1]
        row['release_ps'] = time_ps
        row['consumer_hold_cycles'] = (time_ps - row['publication_ps']) // period_ps
    if previous.get('done') != '1' and state.get('done') == '1':
        assert len(active['rows']) == 4 and len(active['polynomials']) == 16
        active['generation_cycles'] = sum(r['generation_cycles'] for r in active['rows'])
        active['final_publication_cycles'] = active['rows'][-1]['cycles_since_acceptance']
        active['consumer_hold_cycles'] = sum(r['consumer_hold_cycles'] for r in active['rows'])
        active['job_done_cycles'] = (time_ps - active['acceptance_ps']) // period_ps
        assert active['job_done_cycles'] == active['generation_cycles'] + active['consumer_hold_cycles']
        jobs.append(active)
        active = None

assert len(jobs) == 3 and active is None and polynomial is None
# Cross-check the original testbench counters. They start at the preceding
# falling edge's cycle counter, adding one count per recorded interval.
with (OUT / 'expanda_integrated_cycles.csv').open() as stream:
    legacy = list(csv.DictReader(stream))
assert len(legacy) == 12
for entry in legacy:
    row = jobs[int(entry['job'])]['rows'][int(entry['row'])]
    assert int(entry['generation_cycles']) == row['generation_cycles'] + 1
    assert int(entry['cycles_since_job_start']) == row['cycles_since_acceptance'] + 1

result = dict(source='results/expanda_integrated.vcd', time_unit='ps',
              simulated_clock_period_ps=period_ps, jobs=jobs,
              mean_generation_cycles=mean(j['generation_cycles'] for j in jobs),
              frequency_assumptions_MHz=[50, 100, 200],
              note='Clock-to-time projections are conditional; FPGA Fmax is unmeasured.')
(OUT / 'expanda_latency.json').write_text(json.dumps(result, indent=2) + '\n')
fields = ['job', 'generation_cycles', 'final_publication_cycles',
          'consumer_hold_cycles', 'job_done_cycles']
with (OUT / 'expanda_latency.csv').open('w', newline='') as stream:
    writer = csv.DictWriter(stream, fieldnames=fields)
    writer.writeheader()
    writer.writerows({name: job[name] for name in fields} for job in jobs)

print(f'Clock period: {period_ps} ps ({1_000_000 / period_ps:g} MHz in simulation)')
for job in jobs:
    print(f"Job {job['job']}: generation={job['generation_cycles']} cycles; "
          f"final row={job['final_publication_cycles']} cycles; "
          f"job_done={job['job_done_cycles']} cycles; "
          f"consumer holds={job['consumer_hold_cycles']} cycles")
average = result['mean_generation_cycles']
print(f'Mean generation: {average:.3f} cycles')
for mhz in result['frequency_assumptions_MHz']:
    print(f'At {mhz} MHz: mean generation {average / (mhz * 1000):.6f} ms (conditional)')
