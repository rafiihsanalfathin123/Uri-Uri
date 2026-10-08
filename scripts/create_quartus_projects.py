"""Standalone V2 IP evaluation projects; virtual data pins, physical clock."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
sources = ['expanda_controller','expanda_seed_absorb','expanda_shake128',
           'expanda_xof_buffer','expanda_rej_ntt_poly','expanda_output_packer','expanda_top']
for name, rows in [('expanda_stream',None),('expanda_row',1),('expanda_full',4)]:
    folder = root/'quartus'/name
    folder.mkdir(parents=True,exist_ok=True)
    top = 'expanda_top' if rows is None else 'expanda_buffered_top'
    qsf = ['set_global_assignment -name FAMILY "Cyclone V"',
           'set_global_assignment -name DEVICE 5CSEBA6U23I7',
           f'set_global_assignment -name TOP_LEVEL_ENTITY {top}',
           'set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files',
           'set_global_assignment -name NUM_PARALLEL_PROCESSORS 2',
           'set_global_assignment -name SEED 1',
           'set_global_assignment -name SDC_FILE ../../quartus/expanda.sdc',
           '# Out-of-context IP fitting. These are not board pin assignments.',
           'set_instance_assignment -name VIRTUAL_PIN OFF -to clk']
    files = sources + (['expanda_matrix_buffer','expanda_buffered_top'] if rows is not None else [])
    qsf += [f'set_global_assignment -name VERILOG_FILE ../../rtl/{name}.v' for name in files]
    if rows is not None:
        qsf += [f'set_parameter -name ROWS {rows}']
    else:
        qsf += ['set_global_assignment -name EDA_SIMULATION_TOOL "Questa Intel FPGA (Verilog)"',
                'set_global_assignment -name EDA_OUTPUT_DATA_FORMAT VERILOG -section_id eda_simulation',
                'set_global_assignment -name EDA_TEST_BENCH_ENABLE_STATUS TEST_BENCH_MODE -section_id eda_simulation',
                'set_global_assignment -name EDA_TEST_BENCH_NAME tb_expanda_v2 -section_id eda_simulation',
                'set_global_assignment -name EDA_TEST_BENCH_MODULE_NAME tb_expanda_v2 -section_id tb_expanda_v2',
                'set_global_assignment -name EDA_TEST_BENCH_DESIGN_INSTANCE_NAME dut -section_id tb_expanda_v2',
                'set_global_assignment -name EDA_TEST_BENCH_FILE ../../tb/tb_expanda_v2.v -section_id tb_expanda_v2',
                'set_global_assignment -name EDA_TEST_BENCH_RUN_SIM_FOR "20 ms" -section_id tb_expanda_v2']
    qsf += ['set_parameter -name PARALLEL_LANES 5',
            '# Standalone IP evaluation only: these are NOT board pin assignments.']
    ports = ['rst','rho_data[*]','rho_valid','rho_ready','rho_loaded','expand_a_start',
             'expand_a_ready','expand_a_busy','expand_a_done','expand_a_error']
    if rows is None:
        ports += ['sampled_poly_data[*]','sampled_poly_valid','sampled_poly_ready',
                  'sampled_poly_idx[*]','sampled_word_idx[*]','sampled_poly_last']
    else:
        ports += ['buffer_valid','buffer_first_row[*]','buffer_release',
                  'read_enable','read_addr[*]','read_data[*]','read_valid']
    qsf += [f'set_instance_assignment -name VIRTUAL_PIN ON -to "{port}"' for port in ports]
    qsf += ['set_instance_assignment -name VIRTUAL_PIN OFF -to clk']
    (folder/(name+'.qsf')).write_text('\n'.join(qsf)+'\n')
    (folder/(name+'.qpf')).write_text('QUARTUS_VERSION = "23.1"\nPROJECT_REVISION = "'+name+'"\n')
(root/'quartus/expanda.sdc').write_text('''# Standalone IP clock target: 100 MHz, not a measured Fmax.
# A board wrapper must add its actual clocks and external interface constraints.
create_clock -name clk -period 10.000 [get_ports {clk}]
derive_clock_uncertainty
''')
print('Created stream, compact-row and matched full-matrix Verilog Quartus projects.')
