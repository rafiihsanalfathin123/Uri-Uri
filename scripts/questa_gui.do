do scripts/questa_compile.do
add wave -divider "Seed and job"
add wave /tb_expanda_v2/clk /tb_expanda_v2/rst /tb_expanda_v2/rho_valid /tb_expanda_v2/rho_ready /tb_expanda_v2/start /tb_expanda_v2/busy /tb_expanda_v2/done /tb_expanda_v2/error
add wave -radix hexadecimal /tb_expanda_v2/rho_data
add wave -divider "Packed polynomial output"
add wave /tb_expanda_v2/output_valid /tb_expanda_v2/output_ready /tb_expanda_v2/output_last
add wave -radix unsigned /tb_expanda_v2/poly_idx /tb_expanda_v2/word_idx
add wave -radix hexadecimal /tb_expanda_v2/output_data
add wave -divider "SHAKE and sampler"
add wave /tb_expanda_v2/dut/controller/state /tb_expanda_v2/dut/shake/fsm /tb_expanda_v2/dut/shake_in_valid /tb_expanda_v2/dut/shake_in_ready /tb_expanda_v2/dut/shake_out_valid /tb_expanda_v2/dut/shake_out_ready /tb_expanda_v2/dut/sample_valid /tb_expanda_v2/dut/sample_req /tb_expanda_v2/dut/coeff_valid /tb_expanda_v2/dut/coeff_ready
add wave -radix hexadecimal /tb_expanda_v2/dut/shake_out_data /tb_expanda_v2/dut/sample_data /tb_expanda_v2/dut/coeff_data
run -all
wave zoom full
# Keep the stopped simulation and WLF open for inspection.
