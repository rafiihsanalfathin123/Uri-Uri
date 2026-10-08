"""Freeze V2 RTL and create isolated, explicitly clocked IP evaluation projects."""
import hashlib
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'quartus/evaluation'
SRC=BASE/'rtl'
SRC.mkdir(parents=True,exist_ok=True)
files=['expanda_controller','expanda_seed_absorb','expanda_shake128','expanda_xof_buffer',
       'expanda_rej_ntt_poly','expanda_output_packer','expanda_top',
       'expanda_matrix_buffer','expanda_buffered_top']
hashes={}
for name in files:
    data=(ROOT/'rtl'/(name+'.v')).read_bytes()
    (SRC/(name+'.v')).write_bytes(data)
    hashes['rtl/'+name+'.v']=hashlib.sha256(data).hexdigest()
(BASE/'source_manifest.json').write_text(json.dumps(hashes,indent=2)+'\n')
(BASE/'clock.sdc').write_text('create_clock -name clk -period 10.000 [get_ports {clk}]\nderive_clock_uncertainty\n')
scalars=['rst','rho_valid','rho_ready','rho_loaded','expand_a_start','expand_a_ready',
         'expand_a_busy','expand_a_done','expand_a_error','buffer_valid','buffer_release','read_enable','read_valid']
buses={'rho_data':128,'buffer_first_row':2,'read_addr':10,'read_data':128}
ports=scalars+[f'{name}[{i}]' for name,width in buses.items() for i in range(width)]
assert len(ports)==281
for variant,rows in [('row',1),('full',4)]:
    revision='evaluation_'+variant
    folder=BASE/variant
    folder.mkdir(exist_ok=True)
    qsf=['set_global_assignment -name FAMILY "Cyclone V"',
         'set_global_assignment -name DEVICE 5CSEBA6U23I7',
         'set_global_assignment -name TOP_LEVEL_ENTITY expanda_buffered_top',
         'set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files',
         'set_global_assignment -name NUM_PARALLEL_PROCESSORS 2',
         'set_global_assignment -name SEED 1',
         'set_global_assignment -name SDC_FILE ../clock.sdc',
         f'set_parameter -name ROWS {rows}',
         'set_parameter -name PARALLEL_LANES 5']
    qsf += [f'set_global_assignment -name VERILOG_FILE ../rtl/{name}.v' for name in files]
    qsf += ['# Explicit per-bit IP data pins; no wildcard and no virtual clock.']
    qsf += [f'set_instance_assignment -name VIRTUAL_PIN ON -to "{port}"' for port in ports]
    qsf += ['set_instance_assignment -name VIRTUAL_PIN OFF -to "clk"']
    (folder/(revision+'.qsf')).write_text('\n'.join(qsf)+'\n')
    (folder/(revision+'.qpf')).write_text(f'QUARTUS_VERSION = "23.1"\nPROJECT_REVISION = "{revision}"\n')
print('Created quartus/evaluation/{row,full} with frozen RTL, 281 virtual data pins and one physical clock.')
