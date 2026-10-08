"""Golden matrices and XOF prefixes; RTL runs the actual supplied SHAKE engine."""
import hashlib
import json
from pathlib import Path
root = Path(__file__).resolve().parents[1]
out = root / 'vectors'
out.mkdir(exist_ok=True)
seeds = [bytes(range(32)), bytes(32), hashlib.sha256(b'ExpandA integrated regression').digest()]
coefficients, streams = [], []
for seed in seeds:
    for row in range(4):
        for col in range(4):
            raw = hashlib.shake_128(seed + bytes([col, row])).digest(1200)
            streams.extend(raw)
            accepted = []
            for i in range(0, 1200, 3):
                candidate = int.from_bytes(raw[i:i+3], 'little') & 0x7fffff
                if candidate < 8380417:
                    accepted.append(candidate)
                    if len(accepted) == 256:
                        break
            assert len(accepted) == 256
            coefficients.extend(accepted)
(out / 'integrated_seeds.hex').write_text(''.join(seed[::-1].hex() + '\n' for seed in seeds))
(out / 'integrated_coeffs.hex').write_text(''.join(f'{value:06x}\n' for value in coefficients))
(out / 'integrated_xof.hex').write_text(''.join(f'{value:02x}\n' for value in streams))
(out / 'integrated_manifest.json').write_text(json.dumps({
    'reference': 'Python hashlib.shake_128, rho || col || row',
    'seed_bytes_hex': [seed.hex() for seed in seeds], 'jobs': len(seeds),
    'polynomials_per_job': 16, 'coefficients': len(coefficients),
    'xof_prefix_bytes_per_polynomial': 1200,
}, indent=2) + '\n')
print(f'Generated {len(coefficients)} integrated golden coefficients for {len(seeds)} seeds.')
