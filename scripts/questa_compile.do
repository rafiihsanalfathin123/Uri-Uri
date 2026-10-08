# Run from the workspace root; directories contain no simulation libraries/IP.
onerror {quit -code 1}
file mkdir results/questa
file mkdir results/v2_fast
if {![file exists results/questa/work]} {vlib results/questa/work}
vmap work results/questa/work
vlog -work work rtl/expanda_controller.v rtl/expanda_seed_absorb.v rtl/expanda_shake128.v rtl/expanda_xof_buffer.v rtl/expanda_rej_ntt_poly.v rtl/expanda_output_packer.v rtl/expanda_top.v tb/tb_expanda_v2.v
vsim -voptargs=+acc -onfinish stop -wlf results/questa/expanda.wlf work.tb_expanda_v2
log /tb_expanda_v2/clk /tb_expanda_v2/rst /tb_expanda_v2/rho_data /tb_expanda_v2/rho_valid /tb_expanda_v2/rho_ready /tb_expanda_v2/start /tb_expanda_v2/ready /tb_expanda_v2/busy /tb_expanda_v2/done /tb_expanda_v2/error
log /tb_expanda_v2/output_data /tb_expanda_v2/output_valid /tb_expanda_v2/output_ready /tb_expanda_v2/poly_idx /tb_expanda_v2/word_idx /tb_expanda_v2/output_last
log /tb_expanda_v2/dut/controller/state /tb_expanda_v2/dut/shake/fsm /tb_expanda_v2/dut/shake_init /tb_expanda_v2/dut/shake_finalize /tb_expanda_v2/dut/shake_in_valid /tb_expanda_v2/dut/shake_in_ready /tb_expanda_v2/dut/shake_in_data /tb_expanda_v2/dut/shake_in_nbytes
log /tb_expanda_v2/dut/shake_out_valid /tb_expanda_v2/dut/shake_out_ready /tb_expanda_v2/dut/shake_out_data /tb_expanda_v2/dut/sample_valid /tb_expanda_v2/dut/sample_req /tb_expanda_v2/dut/sample_data /tb_expanda_v2/dut/coeff_valid /tb_expanda_v2/dut/coeff_ready /tb_expanda_v2/dut/coeff_data /tb_expanda_v2/dut/coeff_idx
