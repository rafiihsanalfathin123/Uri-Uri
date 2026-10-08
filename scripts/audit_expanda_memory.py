"""Source-backed declared clocked storage inventory, not a synthesis report."""
import json
import hashlib
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
shake = 'third_party/shake128_package/shake128_memory/shared_shake128_mem.v'
specs = [
    (shake, 'SHAKE data', dict(a=1600, scratch=320, rpi_carry=64, io_word=128)),
    (shake, 'SHAKE control', dict(fsm=4, perm_return=2, in_remaining=5, out_fill=4,
         byte_pos=8, lane_index=5, column_index=3, round_index=5, rpi_step=5,
         row_base=5, absorbing=1, finalize_pending=1, squeeze_block_exhausted=1,
         shake_phase_done=1, shake_error=1)),
    ('rtl/expanda_integrated_top.v', 'Integration control', dict(ctrl_state=3,input_word=2,job_error=1)),
    ('rtl/expanda_word_to_byte.v', '128-bit serializer', dict(held_word=128,index=4,occupied=1)),
    ('rtl/expanda_rejection_sampler.v', 'Rejection sampler', dict(coeff_data=23,coeff_valid=1,
         byte_index=2,candidate_low=16,accepted_count=9,busy=1,done=1)),
    ('rtl/expanda_stream_top.v', 'Row scheduling and packing', dict(xof_rho=256,xof_row=2,
         xof_col=2,state=2,lane=2,word_index=6,packed_word=96,job_done=1)),
    ('rtl/expanda_row_buffer.v', 'RAM read response', dict(read_data=96,read_valid=1)),
    ('rtl/expanda_row_buffer.v', 'A row RAM', dict(memory=96*256)),
]
entries=[]
for filename,group,registers in specs:
    source=(root/filename).read_text()
    for name in registers:
        declarations=re.findall(r'\breg\s+([^;]+);',source)
        assert any(re.search(r'\b'+re.escape(name)+r'\b',decl) for decl in declarations), (filename,name)
    entries.append(dict(source=filename,group=group,signals=registers,bits=sum(registers.values())))
total=sum(row['bits'] for row in entries)
ram=96*256
baseline_a=96*1024
result=dict(method='Declared clocked storage widths for instantiated integrated hierarchy; no tool mapping',
    entries=entries,total_bits=total,total_bytes=total/8,
    ram_bits=ram,other_clocked_bits=total-ram,
    baseline_A44_payload_bits=baseline_a,A_payload_reduction_percent=100*(baseline_a-ram)/baseline_a,
    baseline_per_keccak_main_data_bits=4288,new_per_shake_main_data_bits=2112,
    new_shake_and_serializer_main_data_bits=2112+128,
    limitations=['Combinational reg declarations and loop integers excluded.',
                'Declaration widths include constant/unused bits that synthesis may remove.',
                'FSM encoding, memory mapping, replication, and read-register absorption are tool-dependent.',
                'Does not include arithmetic consumer, vector storage, host/bridge, or debug/testbench data.'])
# Keep tool results separate from the declared-width inventory. This is only
# Analysis & Synthesis: RAM payload bits do not establish allocated M10K blocks.
report=root/'results/quartus_memory/output_files/expanda_memory.map.rpt'
summary=report.with_suffix('.summary')
if report.exists() and summary.exists():
    report_text=report.read_text(errors='replace')
    summary_text=summary.read_text(errors='replace')
    sources=sorted({row['source'] for row in entries})
    fresh=all((root/name).stat().st_mtime <= report.stat().st_mtime for name in sources)
    if 'Analysis & Synthesis Status : Successful' in summary_text and fresh:
        def summary_field(label):
            return re.search(r'^'+re.escape(label)+r'\s*:\s*(.+)$',summary_text,re.M).group(1).strip()
        result['quartus_analysis_and_synthesis']=dict(
            tool=summary_field('Quartus Prime Version'), device='5CSEBA6U23I7',
            registers=int(summary_field('Total registers').replace(',','')),
            block_memory_payload_bits=int(summary_field('Total block memory bits').replace(',','')),
            estimated_ALMs=int(re.search(r'ALMs needed\)\s*;\s*(\d+)',report_text).group(1)),
            report=str(report.relative_to(root)),
            source_sha256={name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in sources},
            limitations=['No fitter, routing, M10K allocation, or Fmax measurement.',
                         'No matched integrated OSH synthesis was performed.'])
    else:
        print('Quartus report is failed or older than RTL; omitting synthesis measurements.')
out=root/'results'
out.mkdir(exist_ok=True)
(out/'expanda_memory_inventory.json').write_text(json.dumps(result,indent=2)+'\n')
print('Declared integrated clocked storage:')
for row in entries: print(f"  {row['group']}: {row['bits']} bits ({row['bits']/8:g} bytes)")
print(f'Total: {total} bits = {total/8:g} bytes; RAM {ram} bits; other {total-ram} bits.')
print(f'A payload: {baseline_a//8} -> {ram//8} bytes, 75% reduction.')
