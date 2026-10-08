"""One-time, workspace-local migration; preserves third-party originals."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
legacy = root / 'README_LEGACY.md'
if not legacy.exists():
    legacy.write_bytes((root / 'README.md').read_bytes())
for folder in ['rtl', 'tb']:
    for source in (root / folder).glob('*.sv'):
        target = source.with_suffix('.v')
        assert source.resolve().is_relative_to(root) and target.resolve().is_relative_to(root)
        assert not target.exists(), target
        text = source.read_text()
        text = re.sub(r'\$fatal\(1\s*,\s*(.*?)\);',
                      lambda m: 'begin $display("FAIL: " , '+m.group(1)+'); $finish; end', text, flags=re.S)
        if source.name == 'expanda_word_to_byte.sv':
            text = text.replace('localparam INDEX_BITS = $clog2(WORD_BYTES);', '''function integer index_width;
        input integer value;
        integer count;
        begin
            value = value - 1;
            for (count = 0; value > 0; count = count + 1) value = value >> 1;
            index_width = count;
        end
    endfunction
    localparam INDEX_BITS = index_width(WORD_BYTES);''')
        source.write_text(text)
        source.rename(target)
for folder in ['scripts', 'docs', 'results/quartus_memory']:
    for source in (root / folder).rglob('*'):
        if source.suffix not in ['.py', '.ps1', '.md', '.qsf'] or source.name == Path(__file__).name:
            continue
        text = source.read_text(encoding='utf-8')
        changed = re.sub(r'\.sv\b', '.v', text).replace('-g2012', '-g2001').replace('.vg', '.svg')
        changed = changed.replace('SYSTEMVERILOG_FILE', 'VERILOG_FILE')
        if changed != text:
            source.write_text(changed, encoding='utf-8')
for name in ['README.md', 'README_LEGACY.md', 'BASELINE_SCOPE_REVIEW.md']:
    source = root / name
    source.write_text(re.sub(r'\.sv\b', '.v', source.read_text(encoding='utf-8')).replace('.vg', '.svg'), encoding='utf-8')
for source in (root/'tb').glob('*.v'):
    text = source.read_text().replace('$display("FAIL: " , "', '$display("FAIL: ').replace('endend','end end')
    source.write_text(text)

source = (root / 'third_party/shake128_package/shake128_memory/shared_shake128_mem.v').read_text()
source = source.replace('module shared_shake128_mem (', 'module expanda_shake128 #(parameter PARALLEL_LANES = 5) (')
source = source.replace('`default_nettype none', '''// Project derivative: PARALLEL_LANES=5 parallelizes theta and chi rows.
// PARALLEL_LANES=1 preserves the supplied serial schedule for comparison.
// Main writable data banks remain 2112 bits; third-party original is unchanged.
`timescale 1ns/1ps
`default_nettype none''')

def replace_state(text, name, next_name, parallel):
    start = text.index('                    '+name+': begin')
    end = text.index('                    '+next_name+': begin', start)
    old = text[start:end]
    body = old[old.index('begin')+5:old.rfind('end')]
    new = '                    '+name+': begin\n'
    new += '                        if (PARALLEL_LANES == 5) begin\n'+parallel
    new += '                        end else begin\n'+body+'                        end\n'
    new += '                    end\n\n'
    return text[:start]+new+text[end:]

source = replace_state(source, 'ST_THETA_ACC', 'ST_THETA_WRITE', '''                            for (k = 0; k < 5; k = k + 1)
                                case (lane_index)
                                    0: scratch[k*64 +: 64] <= scratch[k*64 +: 64] ^ a[k*64 +: 64];
                                    5: scratch[k*64 +: 64] <= scratch[k*64 +: 64] ^ a[(5+k)*64 +: 64];
                                    10: scratch[k*64 +: 64] <= scratch[k*64 +: 64] ^ a[(10+k)*64 +: 64];
                                    15: scratch[k*64 +: 64] <= scratch[k*64 +: 64] ^ a[(15+k)*64 +: 64];
                                    20: scratch[k*64 +: 64] <= scratch[k*64 +: 64] ^ a[(20+k)*64 +: 64];
                                    default: begin shake_error <= 1; fsm <= ST_ERROR; end
                                endcase
                            if (lane_index == 20) begin
                                lane_index <= 0;
                                fsm <= ST_THETA_WRITE;
                            end else lane_index <= lane_index + 5'd5;
''')
source = replace_state(source, 'ST_THETA_WRITE', 'ST_RPI_LOAD', '''                            for (k = 0; k < 25; k = k + 1)
                                if (lane_index == (k/5)*5)
                                    a[k*64 +: 64] <= a[k*64 +: 64] ^ scratch[((k+4)%5)*64 +: 64] ^
                                        rol64(scratch[((k+1)%5)*64 +: 64], 6'd1);
                            if (lane_index == 20) fsm <= ST_RPI_LOAD;
                            else lane_index <= lane_index + 5'd5;
''')
source = replace_state(source, 'ST_CHI_LOAD', 'ST_CHI_WRITE', '''                            for (k = 0; k < 5; k = k + 1)
                                case (row_base)
                                    0: scratch[k*64 +: 64] <= a[k*64 +: 64];
                                    5: scratch[k*64 +: 64] <= a[(5+k)*64 +: 64];
                                    10: scratch[k*64 +: 64] <= a[(10+k)*64 +: 64];
                                    15: scratch[k*64 +: 64] <= a[(15+k)*64 +: 64];
                                    20: scratch[k*64 +: 64] <= a[(20+k)*64 +: 64];
                                    default: begin shake_error <= 1; fsm <= ST_ERROR; end
                                endcase
                            column_index <= 0;
                            fsm <= ST_CHI_WRITE;
''')
source = replace_state(source, 'ST_CHI_WRITE', 'ST_IOTA', '''                            for (k = 0; k < 25; k = k + 1)
                                if (row_base == (k/5)*5)
                                    a[k*64 +: 64] <= scratch[(k%5)*64 +: 64] ^
                                        ((~scratch[((k+1)%5)*64 +: 64]) & scratch[((k+2)%5)*64 +: 64]);
                            if (row_base == 20) fsm <= ST_IOTA;
                            else begin row_base <= row_base + 5'd5; fsm <= ST_CHI_LOAD; end
''')
(root / 'rtl/expanda_shake128.v').write_text(source)
print('Migrated project RTL/testbenches to .v; created parameterized SHAKE derivative.')
