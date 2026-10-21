"""Write release checksums and metadata for locally built packages."""
import hashlib
import json
from pathlib import Path

out = Path(__file__).resolve().parent / 'dist'
packages = []
for extension in ('pkg', 'dmg'):
    path = out / f'Suyin-Collector-0.2.0-universal.{extension}'
    packages.append({
        'filename': path.name,
        'version': '0.2.0',
        'architectures': ['arm64', 'x86_64'],
        'minimumOS': 'macOS 13.0',
        'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
        'size': path.stat().st_size,
        'signing': 'ad-hoc app; unsigned package',
        'notarized': False,
    })
(out / 'download-info.json').write_text(json.dumps({'packages': packages}, indent=2) + '\n')
(out / 'SHA256SUMS.txt').write_text(''.join(f"{p['sha256']}  {p['filename']}\n" for p in packages))
print(json.dumps(packages, indent=2))
