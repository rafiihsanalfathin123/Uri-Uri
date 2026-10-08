"""Render the current design documentation from checked simulation metrics."""
from pathlib import Path
import json
import shutil

root = Path(__file__).resolve().parents[1]
m = json.loads((root/'results/v2_analysis.json').read_text())
q = json.loads((root/'results/v2_quartus_resources.json').read_text())
archive = root/'docs/legacy_v1'
archive.mkdir(exist_ok=True)
names = ['EXPANDA_INTERFACE.md','EXPANDA_INTEGRATED.md','EXPANDA_MEMORY_EVALUATION.md',
         'EXPANDA_LATENCY.md','EXPANDA_VERIFICATION_AND_COMPARISON.md','QUARTUS_STEP_BY_STEP.md']
for name in names:
    original = root/'docs'/name
    if original.exists() and not (archive/name).exists():
        shutil.copyfile(original,archive/name)

interface = '''# ExpandA V2 interface: tightly packed 23-bit coefficients

Top: `rtl/expanda_top.v`. Fixed ML-DSA-44 parameters: k=l=4, n=256, q=8380417. Clocked ready/valid interfaces accept data only on a rising edge with both signals high. `rst` is synchronous, active high; hold it for at least one rising edge. A reset aborts the job and discards partial seed, XOF and output data.

| Port | Direction | Width | Contract |
|---|---|---:|---|
| clk, rst | in | 1 each | Clock and synchronous reset |
| rho_data | in | 128 | Two accepted words form the 32-byte public seed |
| rho_valid / rho_ready | in / out | 1 each | Seed word handshake; hold data and valid until accepted |
| rho_loaded | out | 1 | Both seed words captured; cleared when the job starts |
| expand_a_start / expand_a_ready | in / out | 1 each | Start accepted when both high; pulse start for one cycle |
| expand_a_busy | out | 1 | Active job |
| expand_a_done | out | 1 | One-cycle pulse after the final matrix output word is accepted |
| expand_a_error | out | 1 | Sticky internal protocol error; reset required for recovery |
| sampled_poly_data | out | 128 | Continuous coefficient bitstream, low bits first |
| sampled_poly_valid / sampled_poly_ready | out / in | 1 each | Output handshake; all data/tags remain stable through a stall |
| sampled_poly_idx | out | 4 | `{row_idx[1:0], col_idx[1:0]}`: values 0..15 in row-major order |
| sampled_word_idx | out | 6 | Word 0..45 within this polynomial |
| sampled_poly_last | out | 1 | High with word 45; meaningful only with valid |

For seed bytes `00 01 ... 1f`, send `rho_data=128'h0f0e0d0c0b0a09080706050403020100`, then `128'h1f1e1d1c1b1a19181716151413121110`. Byte 0 occupies bits [7:0]. Wait for `expand_a_ready`, pulse start, and consume 736 output words. Seed/start requests during busy are not accepted. Supply a fresh two-word seed for the next job, even if rho is unchanged. Holding start high beyond its accepted edge is unnecessary.

## Internal SHAKE interface

Each polynomial absorbs exactly `rho || byte(col) || byte(row)`, in three accepted input words of 16, 16 and 2 bytes. `shake_in_nbytes[4:0]` encodes an ordinary byte count (1..16), not count-minus-one. Earliest input byte is in bits [7:0]; the two-byte final word has col in [7:0] and row in [15:8]. SHAKE128 uses a 168-byte rate and standard SHAKE padding. Squeeze outputs are full 16-byte words, earliest byte in [7:0]. The diagram's `shake_out_nbytes` is unnecessary for this engine: every accepted squeeze word has 16 valid bytes. Unused tail bytes are flushed after coefficient 255. Bytes spanning both 128-bit words and 168-byte rate blocks remain consecutive.

The XOF buffer emits 24-bit triples. RejNTTPoly uses `sample_data[22:0]`, thereby ignoring bit 23, and accepts only candidates below q. The sampler emits unsigned `coeff_data[22:0]`, indices 0..255 and ready/valid. This is the standard sampled NTT-domain representation of A; no extra NTT is performed on these coefficients.

## Packed output definition

Let a polynomial contain unsigned coefficients c[0]..c[255]. Define:

```python
P = sum(c[i] << (23*i) for i in range(256))
word[j] = (P >> (128*j)) & ((1 << 128)-1)   # j = 0..45
c[i] = (P >> (23*i)) & 0x7fffff
```

This is **tight continuous packing**, with no 32-bit slots and no padding between coefficients. Word 0 holds coefficients 0..4 in bits [114:0], then the low 13 bits of coefficient 5 in [127:115]. Word 1 starts with coefficient 5's remaining 10 bits. Each polynomial starts at a new word: 256*23=5888 bits=46*128 bits, so no partial final word or keep mask is needed. A polynomial is 736 bytes, a row is 2944 bytes, and a complete matrix is 11776 bytes. Hex dumps print the most significant digit first; the stream still consumes the least significant byte/bit first.

## Optional row/full memory wrapper

`expanda_buffered_top` has parameters ROWS=1 (one reusable row) or ROWS=4 (full matrix), and the same seed/job ports. It replaces streaming output with `buffer_valid`, `buffer_first_row[1:0]`, `buffer_release`, `read_enable`, `read_addr[9:0]`, `read_data[127:0]`, `read_valid`. RAM depths are 184 and 736 words respectively. A synchronous read accepted while buffer_valid returns data and read_valid after that rising edge. Reads outside depth are ignored; read_data is unspecified unless read_valid is high.

Consumer ownership begins at buffer_valid. Read every needed word before pulsing buffer_release; release on the final operand's use, including any downstream pipeline drain. While owned, the RAM is not overwritten. ROWS=1 publishes each of four rows separately; ROWS=4 publishes the entire matrix once. Buffer address is `46*col + word_idx` for a row and `184*row + 46*col + word_idx` for a full matrix. This wrapper gates new seed/start handshakes until the buffer is empty. `expand_a_done` indicates all words reached the RAM, not that the consumer has finished reading the final row. Completing the consumer lifetime is a separate event.
'''

memory = f'''# Memory evaluation: V2 packed streaming ExpandA

The main design is a producer with no A RAM. It uses fixed-size registers and supports backpressure so it need not retain a full polynomial. Optional matched row/full wrappers isolate the cost of retaining A. These are RTL storage counts, not FPGA block allocation.

| Main core storage | Declared bits |
|---|---:|
| SHAKE state | 1600 |
| Reused theta/chi scratch | 320 |
| In-place rho/pi carry | 64 |
| Shared SHAKE input/output staging | 128 |
| SHAKE controls | 51 |
| Seed capture and controls | 262 |
| XOF byte reservoir and counter | 149 |
| Sampler coefficient, index and controls | 43 |
| Output bit reservoir and controls | 180 |
| Controller, row/col and status | 9 |
| **Total producer** | **2806 = 350.75 byte-equivalent** |

Temporary combinational expressions, wires, constants and simulation arrays are excluded. The 144-bit XOF reservoir holds up to 18 bytes. The 150-bit packer reservoir can retain an output word plus coefficient-boundary spill. They do not store a polynomial. There is one SHAKE engine, not one engine per polynomial.

| Comparable configuration | A payload | Extra buffer controls/read register | Total including producer |
|---|---:|---:|---:|
| Streaming producer | 0 | 0 | 2806 bits / 350.75 B |
| ROWS=1: 184 x 128 | 23552 bits / 2944 B / 2.875 KiB | 140 bits | 26498 bits / 3312.25 B |
| ROWS=4: 736 x 128 | 94208 bits / 11776 B / 11.5 KiB | 142 bits | 97156 bits / 12144.5 B |

The matched A-payload reduction is `1-2944/11776 = 75%`. Including declared producer/control storage, reduction is `{100*(1-26498/97156):.3f}%`. The main streaming core avoids retaining A locally; system-wide savings depend on the receiver consuming this stream without reconstructing a full A elsewhere.

## Comparison with ML-DSA-OSH

Pinned upstream commit: `2db2d1500267e7547e380993f2f57e5072a43e31`.

* A44 uses 4096 coefficients in padded 24-bit slots: 12288 B / 12 KiB. This design's full packed A is 11776 B, a 4.167% packing reduction. Its row is 2944 B, a **76.042%** reduction against that full-A payload. The 75% row reduction and the packing saving must not be added as independent percentages.
* Upstream RAM0 is 96 x 4096 = 48 KiB and also accommodates broader parameter sets and challenge data. That physical allocation is not the isolated A44 denominator.
* Selected upstream SHAKE data banks comprise state 1600 + SIPO 1344 + PISO 1344 = 4288 bits. The supplied compact engine retains 2112 data bits, **50.746% less** on this data-bank-only comparison. Both engines' controls and other SHAKE instances are excluded. The fast derivative keeps these same 2112 data bits.
* Upstream ExpandA has two sampler channels; this design uses one SHAKE/sampler channel. Neither storage accounting nor the matched wrapper timing establishes a speed ratio against the complete upstream signer.

## FPGA measurement boundaries

Actual fitted results: stream 5881 ALMs / 2815 registers / 0 M10K; row 5985 ALMs / 2825 registers / 4 M10K; full 5922 ALMs / 2827 registers / 13 M10K. Physical M10K saving is **69.231%**, while payload saving is 75%. The blocks allocate 5 KiB for a row and 16.25 KiB for full A; the useful payload is smaller.

See [Quartus resource results](../results/v2_quartus_resources.md) for current synthesis/fitting evidence, including physical memory allocation. Register inference/FSM recoding can make synthesized registers differ from the declared 2806-bit inventory. M10K blocks allocate in discrete shapes; payload savings need not equal the percentage reduction in M10K blocks. Fit/STA targets a standalone virtual-pin IP on Cyclone V 5CSEBA6U23I7; it is not a board pin map or ASIC-area result. All three internal timing checks pass at 100 MHz; external I/O remains unconstrained.

For repeated matrix-vector products with the same rho, a retained full matrix can be reused. A released row must be regenerated. The contribution needs a real consumer and repeated-product evaluation before making a whole-signer peak-memory or latency claim.
'''

latency = f'''# ExpandA V2 latency

Cycles are measured from the rising edge that accepts start. The seed is already captured; seed transfer time is excluded. Default SHAKE PARALLEL_LANES=5, always-ready output, 100 MHz testbench clock. Clock-frequency conversion is an assumption until timing results support it.

| Seed job | First packed word | Last packed word accepted | Done pulse |
|---|---:|---:|---:|
| 00..1f | 1187 | 103068 | 103069 |
| All zero | 1187 | 103121 | 103122 |
| Regression seed | 1187 | 103121 | 103122 |
| 00..1f, output stalls | 1337 | 108197 | 108198 |

Mean unstalled done: **{m['mean_done_fast_cycles']:.3f} cycles = {m['matrix_ms_at_100MHz']:.6f} ms at 100 MHz**. First packed word: 11.87 us. Mean first row publication: {m['first_row_mean_cycles']:.3f} cycles, or {m['first_row_mean_cycles']/100:.3f} us; a full buffer publishes after approximately 1.031 ms. The tested row reader keeps pace, so row ownership adds no generation delay in this test. A slower consumer adds backpressure.

Post-fit internal Fmax summaries report minimum values of 105.35 MHz (stream), 105.20 MHz (row) and 107.62 MHz (full). All modeled internal setup/hold checks pass for the 10 ns clock target. This supports the 100 MHz internal-path estimate in the standalone run; it does not establish board operation or constrained external I/O timing. See [actual resource/timing evidence](../results/v2_quartus_resources.md).

At equal 100 MHz and without seed/inter-job overhead, the observed generation rate is {m['matrices_per_second_at_100MHz']:.3f} matrices/s, {m['coefficients_per_second_at_100MHz']/1e6:.3f} million coefficients/s, or {m['packed_MB_per_second_at_100MHz']:.3f} MB/s of packed payload. Divide latency cycles by your actual clock frequency; do not infer equal timing closure for different architectures.

## Controlled fast-versus-serial SHAKE comparison

The same top, sampler, output packing, vectors and stalls were tested with PARALLEL_LANES=1. Serial done cycles are 218269, 218322, 218322 (mean {m['mean_done_serial_cycles']:.3f}). The five-lane schedule takes 1105 cycles per permutation versus 2545 for serial. All tested matrices require 80 permutations. Their exact difference is `80*(2545-1105)=115200` cycles, including the stress job. The matched cycle reduction is **{m['matched_cycle_reduction_percent']:.3f}%**, or {m['speedup_at_equal_frequency']:.3f} times faster at equal frequency.

The optimization parallelizes theta accumulation/write and chi write across five lanes, while retaining the shared 320-bit scratch and in-place rho/pi. It trades combinational logic for cycles without duplicating a 1600-bit state. Report the resource/timing tradeoff alongside latency. This parameter comparison preserves the supplied serial schedule; it is not a measured full-OSH ExpandA comparison.

The mean fast job spends 88400 cycles ({m['permutation_cycle_share_percent']:.3f}%) in permutations. Remaining time includes serialized absorb/squeeze, candidate movement, packing and control. Do not add measured pipeline stage durations blindly: operations can overlap.

## Rejection and bounds

Acceptance probability is q/2^23 = 8380417/8388608. Expected candidates per polynomial are `256*2^23/q`, approximately 256.25; expected bytes are approximately 768.75. Probability is a statistical model, not a fixed bound. The tested contexts use five 168-byte squeeze blocks each (one finalized block and four additional permutations). More rejection can require another block; there is no finite deterministic worst-case number of candidates for all possible streams. Arbitrary downstream stalls likewise make latency unbounded. Additional required blocks add permutation and streaming time.

## Historical and upstream comparison

The older 96-bit row-buffer design measured mean generation 221457 cycles and completion 222849 cycles with its old consumer. New completion is roughly 53.4% below that historical generation count, but interface, schedule and endpoint have changed. Use the matched serial/fast comparison above to attribute SHAKE schedule gains.

Historical sampler-only comparison (SHAKE excluded): upstream one-channel sampler 2594 cycles versus the older byte-serialized path 17443 cycles, for 16 sequential polynomials. Those figures do not benchmark this revised packer or whole ExpandA. A full upstream speed/Fmax ratio remains unmeasured. Full KeyGen/Sign/Verify, transfers and multiplication are outside this timing result.

Raw evidence: [fast CSV](../results/v2_fast/latency.csv), [serial CSV](../results/v2_serial/latency.csv), [row publications](../results/v2_row/latency.csv), [polynomial counters](../results/v2_fast/polynomials.csv), [calculated metrics](../results/v2_analysis.json).
'''

verification = '''# Verification and expected versus actual output

The DUT receives only clk/reset, the two seed words, start and output readiness. It computes SHAKE itself. Golden SHAKE/coefficient files are scoreboard inputs to the testbench, not replacements for the hardware engine.

## Independent reference

`scripts/generate_integrated_vectors.py` uses Python hashlib.shake_128 for `rho || col || row`, parses consecutive little-endian triples, masks to 23 bits and rejects t >= 8380417. `scripts/generate_packed_vectors.py` then packs accepted coefficients at successive 23-bit offsets. `scripts/analyze_v2.py` independently decodes the simulator's 128-bit output records back to coefficients and checks them against the unpacked reference.

Seeds: bytes 00..1f; 32 zero bytes; and SHA256("ExpandA integrated regression") = `87ea2a4cfedcedb40b09d7e6d7944f8b9b27aa9c77fe8c53ace683db77a2174b`. Job 3 repeats the first seed with downstream stalls.

| Job 0, polynomial 0 | Expected hex | Actual hex |
|---|---|---|
| Packed word 0 | 944f7cbb985428e4dd66bbff5578a1e1 | 944f7cbb985428e4dd66bbff5578a1e1 |
| Packed word 1 | 77e84b6891b0642d908f9f12a56e6e06 | 77e84b6891b0642d908f9f12a56e6e06 |

Each of the fast and serial main tests passes 2944 packed words, 16384 decoded coefficients and 64 polynomial contexts, including the stressed fourth job. The first three are performance jobs (12288 coefficients). Checked items include every output/tag, all 34 absorbed bytes per context, raw SHAKE output prefixes, exact coefficient count, rejection/permutation counters, stable data and metadata through output/SHAKE stalls, ignored busy seed/start, reset during permutation, reset while a packed word is outstanding, and forced internal error with sticky-error recovery. The force test validates the error path; it is not physical fault-injection evidence.

The synthetic units test accepts 256 coefficients and deliberately rejects 18 candidates. It covers t=q-1, q, q+1, high-bit masking, candidates crossing input word boundaries, coefficients crossing output word boundaries, output stalls and reset of partial data. Both row/full cache tests pass 2208 packed words / 12288 coefficients over three jobs, including ownership, synchronous read latency and address bounds.

Standalone SHAKE tests pass all 81 supplied vectors under both schedules: empty and nonempty messages, absorption/rate boundaries, multi-block output and handshake pauses. Fast run: 528435 cycles; serial: 1114663 cycles. These totals describe the whole supplied regression, not one ExpandA job.

Questa Intel FPGA Starter Edition 2023.3 compiles the .v sources as Verilog and passes the four-job main test. Icarus uses strict `-g2001` for all project tests. Legacy tests also remain available after migration to .v; their interfaces and results are historical.

## Evidence files

* `results/v2_fast/output.csv`: every expected/actual packed word and match flag.
* `results/v2_fast/xof.csv`: raw SHAKE expected/actual words.
* `results/v2_fast/polynomials.csv`: candidates, rejects, coefficients, permutations and cycles.
* `results/v2_fast/latency.csv`, `results/v2_serial/latency.csv`: start-to-output/done intervals.
* `results/v2_fast/simulation.log`, `results/v2_serial/simulation.log`, `results/v2_units/simulation.log`, `results/v2_row/simulation.log`, `results/v2_full/simulation.log`: PASS evidence.
* `results/v2_fast/shake.log`, `results/v2_serial/shake.log`: all 81 SHAKE checks.
* `results/questa/transcript.log` and `results/questa/expanda.wlf`: actual native simulator transcript/waveform.
* `results/v2_fast/expanda.vcd`, `results/v2_serial/expanda.vcd`: portable waveforms.
* `results/v2_packed_stall_waveform.svg`: static extract of actual Questa VCD transitions, showing packed word stability during backpressure.
* `results/v2_analysis.json`: verified aggregate metrics and RTL source hashes.

These are functional subsystem regressions, not NIST validation or a complete signature KAT. A matrix-vector consumer, full signature verification, FPGA board demonstration and side-channel countermeasures remain outside the implemented diagram.
'''

quartus = r'''# Quartus and Questa simulation

Project HDL and testbenches are plain Verilog-2001 `.v`. The new top is `expanda_top`, not the historical `expanda_integrated_top`. Quartus Prime Lite 23.1 and Questa Intel FPGA Starter Edition 2023.3 are installed here. The Questa batch flow has actually passed; its native waveform is `results/questa/expanda.wlf`.

Quartus uses a third-party HDL simulator; simulation does not run inside the synthesis engine. See [Intel's simulation tools guide](https://www.intel.com/content/www/us/en/docs/programmable/683463/22-4/third-party-simulation-tools.html).

## Reproduce the verified simulation

From PowerShell in the project root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run_questa.ps1
```

The script generates golden files, compiles all current main modules without `-sv`, runs the testbench and requires tb_pass=1. It exits on failure. It creates the WLF, VCD and CSV scoreboards. If installed elsewhere, pass `-Simulator 'D:\path\to\vsim.exe'`. A valid Starter simulator license is needed; the license on this machine worked.

To run the same simulation with an interactive waveform window:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run_questa.ps1 -Gui
```

To open the saved WLF without regenerating it:

```powershell
& 'C:\intelFPGA_lite\23.1std\questa_fse\win64\vsim.exe' -view results/questa/expanda.wlf
```

In the GUI, add signals from the dataset to Wave; show `output_valid`, `output_ready`, `output_data`, `poly_idx`, `word_idx`, `output_last`, start/busy/done and the SHAKE interfaces. Radix hexadecimal is appropriate for data; unsigned decimal for indices. At valid=1/ready=0, data and tags must stay unchanged. Word index 45 has last=1. A completed matrix has 736 accepted words.

The `.wlf` is a Questa/ModelSim waveform, not a `.vwf` stimulus file. `.vcd` is the portable alternative. CSVs are useful for proposal tables without screenshots.

## Quartus projects

Open `quartus/expanda_stream/expanda_stream.qpf` for the streaming core, `quartus/expanda_row/expanda_row.qpf` for ROWS=1, or `quartus/expanda_full/expanda_full.qpf` for the matched full matrix. All use Cyclone V 5CSEBA6U23I7 and a 10 ns clock target. They have virtual data pins and a physical clock for standalone IP resource evaluation. They are not board pin assignments. No programming image is provided.

The stream QSF includes Questa testbench metadata. For a dependable simulation from Quartus, launch Questa and execute the provided `.do` script from the project root (`do scripts/questa_gui.do`), or use the verified PowerShell command above. Automatic NativeLink execution was not used to generate the supplied WLF. A NativeLink-generated working directory must be adjusted to the project root for relative `vectors/...` and `results/...` paths; copying only HDL files into a simulation folder is insufficient.

To reproduce synthesis or synthesis+fit+STA:

```powershell
py -3 scripts/create_quartus_projects.py
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run_quartus.ps1 -Variant stream -Stage synthesis
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run_quartus.ps1 -Variant row -Stage fit
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run_quartus.ps1 -Variant full -Stage fit
```

Reports are in each project's `output_files`; console logs are in `run_logs`. A successful fitter exit does not establish timing closure. Review setup/hold slack, internal clock Fmax and unconstrained paths. External I/O timing and a board wrapper are not constrained by this out-of-context setup. Use measured timing to justify an FPGA frequency; the 100 MHz simulation clock alone proves no Fmax.

## Portable regression

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test_all_verilog.ps1
```

Requires Python, Icarus Verilog (`iverilog`, `vvp`) and optionally the installed Questa flow. All Icarus compilations use `-g2001`. Testbench failures are explicit FAIL messages, and scripts check both the exit code and PASS/FAIL text so `$finish` cannot hide a failed assertion.
'''

integration = '''# Current integration and source map

The diagram's six blocks are implemented in `expanda_top`:

| Diagram block | Verilog source | Main job |
|---|---|---|
| Controller and index generator | expanda_controller.v | 16 contexts, row/col, flush, errors and final completion |
| Seed capture / absorb scheduler | expanda_seed_absorb.v | Two seed words; absorb rho, col, row |
| SHAKE128 engine | expanda_shake128.v | Compact data banks; default five-lane theta/chi schedule |
| XOF byte/bit buffer | expanda_xof_buffer.v | 16-byte words to consecutive 24-bit candidates |
| RejNTTPoly sampler | expanda_rej_ntt_poly.v | Mask high bit, reject >=q, emit exactly 256 coefficients |
| 128-bit output packer | expanda_output_packer.v | Tight 23-bit stream with polynomial/word tags |

`expanda_matrix_buffer.v` and `expanda_buffered_top.v` supply optional one-row/full-matrix storage. They sit after the diagram's output. The streaming core itself has no row RAM.

Controller phases: IDLE -> INIT -> SEED_START -> ABSORB -> FINALIZE -> WAIT_FINAL -> SQUEEZE -> DRAIN. Each context initializes SHAKE, sampler, XOF and packer. Sampler completion means coefficient 255 entered the packer; it aborts extra squeeze work and flushes unused XOF bytes. Controller waits for the packer's final word handshake before advancing. Final matrix done is one cycle after the last output transfer.

## SHAKE provenance

Your supplied original is retained unchanged at `third_party/shake128_package/shake128_memory/shared_shake128_mem.v`, with MIT header. Its SHA256 is `4ea401038113da0b63f727f143ad1040cd1a3b8931eea0ffa62c991490531166`. The main project derivative `rtl/expanda_shake128.v` retains the compact 1600+320+64+128 data organization and standard SHAKE behavior. PARALLEL_LANES=1 retains the serial schedule; default 5 parallelizes selected steps. Both pass the 81 original vectors and full matrix tests. This is a modified derivative, not a claim that the supplied file itself had the faster schedule.

Runtime behavior is fixed by the compile-time parameter. Supported values are 1 and 5; use those configurations.

## Baseline and arithmetic integration

The reviewed OSH source is pinned and unchanged under `third_party/ML-DSA-OSH`. Relevant files are rejection_a.v, sampler_a_ext.v, gen_a_ext.v, combined_top.v, dual_port_ram.v and operation_module.v. Its A packing uses four 24-bit slots per 96-bit word. This new 128-bit tight bitstream is **not directly pin-compatible**: a consumer must reconstruct successive 23-bit coefficients and translate addressing before using the upstream operation module.

These coefficients represent sampled A in the NTT domain. A future consumer computes each row's sum of coefficientwise products with NTT(y), then performs the required inverse transform. It must retain y and each result/accumulator for their own lifetimes. RAM release must follow the last operand use. No multiplier, accumulator or output w is implemented in this revision, so the RAM test reader is a functional consumer proxy, not a proven signing datapath.

The old expanda_integrated_top and stream wrappers remain available as historical comparisons. They use different interfaces and the old packing format. See README_LEGACY.md and archived docs; use the new top/projects for the requested diagram.
'''

readme = f'''# Memory-efficient ML-DSA-44 ExpandA — Verilog implementation

This revision implements your ExpandA diagram, including hardware SHAKE128, a bounded XOF buffer, RejNTTPoly and a **128-bit output carrying tightly packed 23-bit coefficients**. All project HDL/testbenches are `.v` Verilog-2001. It generates all 16 ML-DSA-44 A polynomials from a 32-byte public seed. It is the ExpandA subsystem for ML-DSA; complete KeyGen, signing, verification and matrix-vector arithmetic are future integration work.

## Quick results

| Metric | Verified result |
|---|---|
| Main producer declared storage | 2806 bits / 350.75 byte-equivalent, no A RAM |
| Optional row A payload | 2944 B / 2.875 KiB |
| Matched full A payload | 11776 B / 11.5 KiB |
| Row/full A-payload reduction | 75% with identical producer and packing |
| Fitted row/full M10K blocks | 4 / 13; physical reduction 69.231% |
| Fitted streaming core | 5881 ALMs, 2815 registers, 0 M10K, 0 DSP |
| Mean unstalled matrix completion | 103104.333 cycles / 1.031043 ms at simulated 100 MHz |
| Matched serial-SHAKE completion | 218304.333 cycles; fast schedule reduces cycles 52.770% |
| Main regression, each schedule | 16384 coefficients / 2944 packed words / 64 contexts, all match |
| SHAKE regression | All 81 supplied vectors pass for both schedules |
| Intel simulator | Questa Intel FPGA Starter 2023.3: PASS; native WLF provided |

Use [physical Quartus resource results](results/v2_quartus_resources.md) separately from payload and declared storage. The simulated 100 MHz clock is not evidence of achieved FPGA Fmax. Complete upstream ML-DSA latency and system-wide memory reductions are not measured here.

Actual post-fit internal timing passes the 100 MHz target for all three variants. Minimum reported internal Fmax is 105.35 MHz for stream, 105.20 MHz for row and 107.62 MHz for full. This is standalone IP timing with virtual data pins and unconstrained external I/O; a board wrapper and demonstrated clock remain separate work.

## 1. What ExpandA does

For each row r=0..3 and column s=0..3, initialize SHAKE128 with `rho || byte(s) || byte(r)`. Take consecutive three-byte candidates in little-endian order, ignore the highest bit, and accept values below q=8380417 until there are 256. Rejecting, rather than reducing modulo q, follows RejNTTPoly. The resulting A_hat entries are already sampled in the NTT-domain representation used by ML-DSA. This follows [NIST FIPS 204, ExpandA and RejNTTPoly](https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.204.pdf).

## 2. System block diagram

![Current ExpandA block diagram](docs/assets/expanda_system.svg)

```mermaid
flowchart LR
    R["rho: two 128-bit words"] --> S["Seed capture / absorb scheduler"]
    S -->|"16 + 16 + 2 bytes: rho, col, row"| K["Compact SHAKE128"]
    K -->|"128-bit XOF words"| X["144-bit byte reservoir"]
    X -->|"24-bit triples"| J["RejNTTPoly: mask to 23 bits, reject >= q"]
    J -->|"23-bit coefficient + 8-bit index"| P["150-bit packer reservoir"]
    P -->|"128-bit tight stream + tags"| O["Downstream consumer"]
    P -.-> B["Optional row/full A RAM"]
    B -.-> O
    C["Controller / row and column indices"] --> S
    C --> K
    C --> X
    C --> J
    C --> P
```

The controller waits for SHAKE finalization, terminates after 256 accepted coefficients, flushes unused XOF bytes and waits for final packed-word acceptance before advancing. Ready/valid backpressure preserves data throughout the chain. Compared with the sketch, word_idx[5:0] is added; squeeze output byte count is implicit 16.

## 3. Input and output formats

See the full [port table and handshake contract](docs/EXPANDA_INTERFACE.md). Seed bytes 00..1f are supplied as two words, low byte first:

```verilog
128'h0f0e0d0c0b0a09080706050403020100
128'h1f1e1d1c1b1a19181716151413121110
```

After both handshakes, wait for expand_a_ready and pulse expand_a_start. Receive 736 words for a matrix. Output tags identify polynomial 0..15 and word 0..45; last is high on word 45 of each polynomial. Done pulses after word 45 of polynomial 15 is accepted. Reset aborts partial work; errors are sticky until reset.

**Packing:** `P = sum(c[i] << (23*i))`, `word[j] = (P >> (128*j)) & (2^128-1)`. Coefficients cross word boundaries. There are exactly 46 full words per polynomial because 256*23=46*128; no final padding or keep mask. Word 0 contains five complete coefficients and the low 13 bits of coefficient 5. A receiver must reconstruct the bitstream; treating words as four 32-bit slots gives wrong data.

## 4. Implementation and SHAKE integration

The entry point is [rtl/expanda_top.v](rtl/expanda_top.v). The [integration/source map](docs/EXPANDA_INTEGRATED.md) maps every diagram block to a .v file and explains the controller phases, original SHAKE provenance and consumer requirements.

Your supplied SHAKE file stays unchanged. The main derivative retains its 2112-bit data banks and uses a compile-time five-lane theta/chi schedule. It reduces permutation cycles from 2545 to 1105 without allocating a second Keccak state. PARALLEL_LANES=1 provides a matched serial configuration. Both are fully tested. This trades combinational area for lower latency; inspect Quartus resources rather than assuming the faster core is free.

Optional expanda_buffered_top ROWS=1 retains one row (184 x128) and publishes four buffers per matrix; ROWS=4 retains the full matrix (736 x128). Its RAM is synchronous and released explicitly by the consumer. The main top streams directly and has no matrix RAM. A real matrix-vector consumer must use/release rows safely and retain its own vector and accumulator data.

## 5. Memory and performance analysis

See [memory inventory and baseline denominators](docs/EXPANDA_MEMORY_EVALUATION.md), [latency calculations](docs/EXPANDA_LATENCY.md) and machine-readable [verified metrics](results/v2_analysis.json).

The producer's 2806 declared bits include state, seed, controls, reservoirs and coefficient staging. Including the RAM wrapper, row total is 26498 bits / 3312.25 B and full total is 97156 bits / 12144.5 B. Matched payload reduction is 75%; total declared storage reduction is {100*(1-26498/97156):.3f}%.

The OSH baseline stores A44 in padded 24-bit slots: 12 KiB. Tight full packing saves 4.167%; a packed row saves 76.042% against that full payload. OSH RAM0's 48 KiB serves more than A44, so it is not the denominator. Selected SHAKE state/SIPO/PISO banks total 4288 bits versus compact engine data banks 2112 bits, a separate 50.746% bank reduction. Do not combine these percentages into one system claim.

Measured fast matrix done cycles: 103069, 103122, 103122. Serial matched cycles: 218269, 218322, 218322. Difference is exactly 115200=80*(2545-1105) cycles. The 52.770% cycle reduction assumes equal clock frequency; it is not a comparison against the upstream two-channel full signer. The stressed job completes in 108198 cycles. Rejection and consumer stalls vary latency; no unconditional worst-case bound is asserted.

At an achieved 100 MHz, the observed unstalled rate would be {m['matrices_per_second_at_100MHz']:.2f} matrices/s or {m['packed_MB_per_second_at_100MHz']:.2f} MB/s of packed A. First word appears in 1187 cycles (11.87 us); first row becomes available around {m['first_row_mean_cycles']/100:.2f} us. Seed transfers, board I/O, multiplication, repeated signing attempts and final consumer drain are excluded.

## 6. Testbench inputs and functional evidence

See [verification details and expected/actual examples](docs/EXPANDA_VERIFICATION_AND_COMPARISON.md). Python hashlib is the independent XOF reference. The DUT receives seed/start/readiness; golden files are only testbench scoreboards. Three seeds plus a stalled repeat check 16384 coefficients and all 2944 output words per schedule. Additional tests target q boundaries, high-bit masking, bit/byte crossings, resets, errors and memory ownership.

Example for seed 00..1f, A_hat[0,0], word 0:

| Expected | Actual | Result |
|---|---|---|
| 944f7cbb985428e4dd66bbff5578a1e1 | 944f7cbb985428e4dd66bbff5578a1e1 | Match |

Full [packed comparison CSV](results/v2_fast/output.csv), [raw XOF comparison](results/v2_fast/xof.csv), [cycle CSV](results/v2_fast/latency.csv) and [Questa transcript](results/questa/transcript.log) are supplied. Tests establish subsystem functional equivalence, not a certified ML-DSA implementation.

## 7. Quartus simulation and waveforms

Open [stream Quartus project](quartus/expanda_stream/expanda_stream.qpf), [row project](quartus/expanda_row/expanda_row.qpf), or [matched full project](quartus/expanda_full/expanda_full.qpf). Follow [Quartus/Questa steps](docs/QUARTUS_STEP_BY_STEP.md). The supplied [native Questa WLF](results/questa/expanda.wlf) was generated by a passing Intel simulator run; [VCD](results/v2_fast/expanda.vcd) is also available.

![Actual packed-output stall waveform](results/v2_packed_stall_waveform.svg)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test_all_verilog.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run_questa.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run_questa.ps1 -Gui
```

Use the GUI command to inspect protocol edges and capture proposal screenshots. Quartus synthesizes the Verilog; Questa performs simulation. The verified scripted flow works from the workspace root. Automatic NativeLink working-directory setup was not used in the provided run.

## 8. Proposal / competition material

**Suggested title:** Memory-Efficient Streaming ExpandA for ML-DSA-44 Using Compact Hardware SHAKE128.

**Problem and contribution:** Generating a public matrix from a short seed can lead to unnecessary full-matrix storage. The design streams standard SHAKE128 rejection-sampled coefficients through bounded reservoirs and tight 23-bit packing. An optional reusable row cache reduces A payload by 75% against a matched full cache; selective five-lane SHAKE scheduling limits the latency cost while retaining compact state storage.

**Evidence to include:** the block diagram; port/packing example; row/full memory table with physical M10K results; expected/actual CSV extract; native waveform showing a stall and a polynomial boundary; the 81-vector SHAKE and matrix PASS logs; latency with clock assumption and measurement endpoints; baseline commit and separate comparison scopes.

**Application fit:** a building block for post-quantum digital-signature accelerators in identity/security systems. This repository demonstrates ExpandA, not an operational identity product. It contains no PERURI deployment or production certification claim.

**Remaining milestones for a complete accelerator:** implement a compatible coefficient unpacker and matrix-vector consumer; verify w against an independent arithmetic reference; measure repeated products and total peak storage; constrain and demonstrate the FPGA board interface; then integrate the other ML-DSA algorithms, full signature KATs and appropriate security protections. Power/energy, ASIC area and full-signing throughput are currently unmeasured. Check the current official [PERURI hackathon portal](https://summit.peruri.co.id/hackathon) and template for submission requirements; no eligibility or deadline claim is made here.

## 9. Baseline, licensing and history

Baseline [ML-DSA-OSH](https://github.com/KULeuven-COSIC/ML-DSA-OSH/tree/2db2d1500267e7547e380993f2f57e5072a43e31) is pinned and unchanged under third_party. The supplied compact SHAKE original and MIT header are retained. Preserve upstream LICENSE/NOTICE and per-file attribution when redistributing. Source details are in [scope review](BASELINE_SCOPE_REVIEW.md).

[README_LEGACY.md](README_LEGACY.md) and docs/legacy_v1 preserve the prior 96-bit design's measurements. Old interfaces, 3 KiB row payload and 221457-cycle generation figures are historical. `konteks_terbaru_v2.md` records earlier context, including a software-SHAKE partition; this latest revision follows your hardware-SHAKE diagram and packed-format choice.
'''

for name,text in {'EXPANDA_INTERFACE.md':interface,'EXPANDA_MEMORY_EVALUATION.md':memory,
                  'EXPANDA_LATENCY.md':latency,'EXPANDA_VERIFICATION_AND_COMPARISON.md':verification,
                  'QUARTUS_STEP_BY_STEP.md':quartus,'EXPANDA_INTEGRATED.md':integration}.items():
    (root/'docs'/name).write_text(text,encoding='utf-8')
(root/'README.md').write_text(readme,encoding='utf-8')
print('Updated README and six active documents; prior versions preserved in docs/legacy_v1.')
