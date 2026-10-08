"""True 23-bit little-endian polynomial bitstream, 46 128-bit words/poly."""
from pathlib import Path
import json

root = Path(__file__).resolve().parents[1]
values = [int(line, 16) for line in (root/'vectors/integrated_coeffs.hex').read_text().splitlines()]
assert len(values) == 12288
words = []
for offset in range(0, len(values), 256):
    polynomial = sum(value << (23*i) for i, value in enumerate(values[offset:offset+256]))
    words.extend((polynomial >> (128*i)) & ((1 << 128)-1) for i in range(46))
(root/'vectors/packed_words.hex').write_text(''.join(f'{word:032x}\n' for word in words))
(root/'vectors/packed_manifest.json').write_text(json.dumps(dict(
    coefficient_bits=23, coefficients_per_polynomial=256, word_bits=128,
    words_per_polynomial=46, bytes_per_polynomial=736,
    words_per_matrix=736, bytes_per_matrix=11776,
    ordering='coefficients appended least-significant bit first; polynomial boundaries word-aligned',
    vector_jobs=3, words=len(words)), indent=2)+'\n')
print(f'Generated {len(words)} tightly packed golden output words.')
# Directed rejection/high-bit cases, including candidates spanning 128-bit beats.
raw_candidates=[8380417,8380418,0xffffff,0x800000,8380416]
for i in range(270):
    if i%17==0: raw_candidates.append(8380417)
    raw_candidates.append(((i*65537+3)%8380417) | (0x800000 if i%2 else 0))
accepted=[value & 0x7fffff for value in raw_candidates if (value & 0x7fffff)<8380417][:256]
assert len(accepted)==256
raw=b''.join(value.to_bytes(3,'little') for value in raw_candidates)
raw=raw.ljust(64*16,b'\0')
assert len(raw)==64*16
unit_input=[int.from_bytes(raw[i:i+16],'little') for i in range(0,len(raw),16)]
packed=sum(value << (23*i) for i,value in enumerate(accepted))
unit_expected=[(packed>>(128*i)) & ((1<<128)-1) for i in range(46)]
(root/'vectors/unit_xof_words.hex').write_text(''.join(f'{word:032x}\n' for word in unit_input))
(root/'vectors/unit_packed_words.hex').write_text(''.join(f'{word:032x}\n' for word in unit_expected))
