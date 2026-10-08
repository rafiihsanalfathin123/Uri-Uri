# Standalone IP clock target: 100 MHz, not a measured Fmax.
# A board wrapper must add its actual clocks and external interface constraints.
create_clock -name clk -period 10.000 [get_ports {clk}]
derive_clock_uncertainty
