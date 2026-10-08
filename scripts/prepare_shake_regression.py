"""Adapt supplied MIT regression for the project derivative; original unchanged."""
from pathlib import Path
import re
root=Path(__file__).resolve().parents[1]
text=(root/'third_party/shake128_package/shake128_memory/tests/tb_shared_shake128_mem.v').read_text()
text=text.replace('module tb_shared_shake128_mem;', '''`ifndef SHAKE_LANES
`define SHAKE_LANES 5
`endif
// Adapted from the supplied MIT SHAKE regression; original preserved.
module tb_expanda_shake128;
    reg tb_pass=0;''')
text=text.replace('shared_shake128_mem dut (', 'expanda_shake128 #(.PARALLEL_LANES(`SHAKE_LANES)) dut (')
text=re.sub(r'\$fatal\(1\s*,\s*(.*?)\);',
    lambda m: 'begin $display("FAIL: '+m.group(1)[1:]+'); $finish; end',text,flags=re.S)
text=text.replace('$display("PASS ALL', 'tb_pass=1;\n        $display("PASS ALL')
(root/'tb/tb_expanda_shake128.v').write_text(text)
print('Prepared Verilog-2001 81-vector SHAKE regression for both schedules.')
