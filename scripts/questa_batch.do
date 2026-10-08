transcript file results/questa/transcript.log
do scripts/questa_compile.do
run -all
if {[examine -radix unsigned /tb_expanda_v2/tb_pass] != 1} {quit -code 1}
quit -code 0
