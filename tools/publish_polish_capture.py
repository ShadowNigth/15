"""Transport real OpenGL framebuffer samples via bounded check annotations."""
from pathlib import Path
from PIL import Image
import base64, io
for name in ['deathmatch_firing', 'deathmatch_frag', 'he_animated_burst', 'smoke_live_volume']:
    path = Path('/tmp/dm-polish-review') / (name + '.png')
    if not path.exists():
        print('Missing framebuffer: ' + name)
        continue
    image = Image.open(path).convert('RGB')
    image.thumbnail((960, 540))
    for quality in (65, 55, 45, 35, 25):
        data = io.BytesIO()
        image.save(data, 'JPEG', quality=quality)
        text = base64.b64encode(data.getvalue()).decode()
        if len(text) <= 28000:
            break
    while len(text) > 28000:
        image = image.resize((int(image.width * 0.85), int(image.height * 0.85)))
        data = io.BytesIO()
        image.save(data, 'JPEG', quality=40)
        text = base64.b64encode(data.getvalue()).decode()
    chunks = [text[i:i+3500] for i in range(0, len(text), 3500)]
    for i, chunk in enumerate(chunks):
        print(f'::notice title=Polish JPEG {name} {i+1}/{len(chunks)}::{chunk}')
