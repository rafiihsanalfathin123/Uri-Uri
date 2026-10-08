"""Independent SHAKE128 oracle plus synthetic rejection/masking edge cases."""
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'vectors'
OUT.mkdir(exist_ok=True)
Q = 8380417
streams, expected = [], []
for job in range(2):
    for row in range(4):
        for col in range(4):
            if job == 0:
                candidates = [Q, Q + 1, 0xffffff, 0x800000, Q - 1]
                candidates += [((row * 4 + col) * 256 + i) | (0x800000 if i % 2 else 0)
                               for i in range(300)]
                raw = b''.join(t.to_bytes(3, 'little') for t in candidates)
                raw = raw.ljust(1200, b'\xff')
            else:
                raw = hashlib.shake_128(bytes(range(32)) + bytes([col, row])).digest(1200)
            accepted = []
            for offset in range(0, len(raw), 3):
                value = int.from_bytes(raw[offset:offset+3], 'little') & 0x7fffff
                if value < Q:
                    accepted.append(value)
                    if len(accepted) == 256:
                        break
            assert len(accepted) == 256
            streams.extend(raw)
            expected.extend(accepted)
(OUT / 'expanda_bytes.hex').write_text(''.join(f'{b:02x}\n' for b in streams))
(OUT / 'expanda_coeffs.hex').write_text(''.join(f'{v:06x}\n' for v in expected))
print('Generated 32 polynomial streams and 8192 expected coefficients.')
