"""Publish one actual Godot menu framebuffer, independently of test logs."""
import base64
import io
import sys
from pathlib import Path
from PIL import Image
name = sys.argv[1]
assert name in {'menu_home', 'menu_arsenal', 'menu_arsenal_4x3', 'menu_home_4x3'}
path = Path('/tmp/menu-captures') / (name + '.png')
if not path.exists():
    raise SystemExit(0)
image = Image.open(path).convert('RGB')
image.thumbnail((1100, 760))
for quality in [80, 65, 50, 35, 20]:
    out = io.BytesIO()
    image.save(out, 'JPEG', quality=quality)
    if len(out.getvalue()) < 23000:
        break
encoded = base64.b64encode(out.getvalue()).decode()
parts = [encoded[i:i+3500] for i in range(0, len(encoded), 3500)]
assert len(parts) <= 9
for i, part in enumerate(parts):
    print(f'::notice title=Menu JPEG {name} {i+1}/{len(parts)}::{part}')
