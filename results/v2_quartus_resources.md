# Quartus V2 fitted resources and timing

Actual Analysis & Synthesis, Fitter and Timing Analyzer runs completed successfully on Cyclone V 5CSEBA6U23I7 with Quartus Prime Lite 23.1std.1 Build 993. Identical current producer, five-lane SHAKE schedule and 100 MHz clock target; buffer ROWS differs.

| Variant | ALMs | Registers | A RAM payload bits | M10K blocks | Minimum reported internal Fmax | Minimum setup slack | Minimum hold slack |
|---|---:|---:|---:|---:|---:|---:|---:|
| stream | 5881 | 2815 | 0 | 0 | 105.35 MHz | 0.508 ns | 0.135 ns |
| row | 5985 | 2825 | 23552 | 4 | 105.20 MHz | 0.494 ns | 0.142 ns |
| full | 5922 | 2827 | 94208 | 13 | 107.62 MHz | 0.708 ns | 0.132 ns |

**Measured physical M10K reduction: 69.231% (13 blocks to 4).** Matched logical A payload falls 75%. These are distinct measurements. 13 M10Ks allocate 133120 physical bits (16.25 KiB), while four allocate 40960 bits (5 KiB); unused capacity reflects width/depth mapping. No MLAB memory or DSP blocks are used in these variants.

All modeled internal setup/hold checks pass at the 10 ns clock target. Reported Fmax describes same-clock internal paths; it is not a demonstrated board clock or complete interface timing closure. External ports are virtual and unconstrained. The physical clock is automatically placed: reports warn about its missing exact pin location and non-dedicated routing. A board wrapper needs a valid clock source/location and I/O delays. An explicit Virtual Pin OFF assignment on clk is ignored; clk still remains physical because it is excluded from the virtual-input list. A Lite LogicLock feature warning is also present. No assembler image or board test was produced.

Stream synthesis: 7960 combinational ALUTs, 2815 registers, zero RAM payload bits. Declared producer storage is 2806 bits; synthesis FSM recoding/logic transformations explain why register counts are not identical. Fitted ALMs are authoritative for this FPGA run; they are not ASIC gates or bytes. The compact-bank optimization reduces storage, but five-lane parallel logic has an area cost. A matched serial fit and a full upstream signer fit have not been measured.

Small row/full ALM differences reflect control/address logic and fitter packing/placement; do not interpret them as an arithmetic throughput gain. The row/full payload and physical M10K comparison uses the same tested producer and format.

Raw evidence:

* stream: [fit summary](../quartus/expanda_stream/output_files/expanda_stream.fit.summary), [fit report](../quartus/expanda_stream/output_files/expanda_stream.fit.rpt), [timing summary](../quartus/expanda_stream/output_files/expanda_stream.sta.summary), [timing report](../quartus/expanda_stream/output_files/expanda_stream.sta.rpt).
* row: [fit summary](../quartus/expanda_row/output_files/expanda_row.fit.summary), [fit report](../quartus/expanda_row/output_files/expanda_row.fit.rpt), [timing summary](../quartus/expanda_row/output_files/expanda_row.sta.summary), [timing report](../quartus/expanda_row/output_files/expanda_row.sta.rpt).
* full: [fit summary](../quartus/expanda_full/output_files/expanda_full.fit.summary), [fit report](../quartus/expanda_full/output_files/expanda_full.fit.rpt), [timing summary](../quartus/expanda_full/output_files/expanda_full.sta.summary), [timing report](../quartus/expanda_full/output_files/expanda_full.sta.rpt).

[Machine-readable values and RTL hashes](v2_quartus_resources.json).
