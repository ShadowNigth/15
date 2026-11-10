"""Publish one actual Godot menu framebuffer, independently of test logs."""
import base64
import io
import sys
from pathlib import Path
from PIL import Image
name = sys.argv[1]
page = int(sys.argv[2]) if len(sys.argv) > 2 else None
limit = 39000 if page is not None else 23000
assert '/' not in name and '..' not in name
path = Path('/tmp/modern-captures') / (name + '.png')
if not path.exists():
    raise SystemExit(0)
image = Image.open(path).convert('RGB')
image.thumbnail((1100, 760))
while True:
    for quality in [80, 65, 50, 35, 20]:
        out = io.BytesIO()
        image.save(out, 'JPEG', quality=quality)
        if len(out.getvalue()) < limit:
            break
    if len(out.getvalue()) < limit:
        break
    image.thumbnail((int(image.width * .85), int(image.height * .85)))
encoded = base64.b64encode(out.getvalue()).decode()
parts = [encoded[i:i+3500] for i in range(0, len(encoded), 3500)]
assert len(parts) <= (15 if page is not None else 9)
for i, part in enumerate(parts):
    if page is not None and i // 8 != page:
        continue
    print(f'::notice title=Modern JPEG {name} {i+1}/{len(parts)}::{part}')
