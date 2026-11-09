"""Transport one actual Godot framebuffer; each invocation stays below annotation limits."""
import base64
import io
import sys
from pathlib import Path

name = sys.argv[1]
assert name in {"corridor_before", "corridor_yield", "corridor_after", "classic_pose_and_weapon", "melee_before", "melee_after"}
path = Path("/tmp/squad-captures") / (name + ".png")
if not path.exists():
    raise SystemExit(0)
from PIL import Image
image = Image.open(path).convert("RGB")
image.thumbnail((960, 540))
quality = 75
while True:
    stream = io.BytesIO()
    image.save(stream, format="JPEG", quality=quality)
    data = stream.getvalue()
    if len(data) < 21000 or quality <= 15:
        break
    quality -= 10
encoded = base64.b64encode(data).decode()
parts = [encoded[i:i + 3500] for i in range(0, len(encoded), 3500)]
assert len(parts) <= 9
for i, part in enumerate(parts):
    print(f"::notice title=Squad JPEG {name} {i + 1}/{len(parts)}::{part}")
