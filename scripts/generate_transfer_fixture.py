"""Generate deterministic blocks with unique offsets to expose part reordering."""
from pathlib import Path
import struct
import sys

size_mib = int(sys.argv[2]) if len(sys.argv) > 2 else 32
if size_mib < 1:
    raise SystemExit("size must be positive MiB")
payload = bytes(range(256)) * 256
with Path(sys.argv[1]).open("wb") as file:
    for block in range(size_mib * 16):
        file.write(struct.pack("<Q", block) + payload[8:])
print(f'Generated {size_mib} MiB with unique 64 KiB block identifiers')
