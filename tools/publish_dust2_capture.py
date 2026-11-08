"""Bound each comparison to four annotations; keep full PNGs in the CI artifact.
GitHub caps annotations per job; eight views plus two gameplay samples must fit.
"""
import base64
import io
from pathlib import Path
import sys
from PIL import Image
for name in sys.argv[1:]:
    path = Path('/tmp/dm-polish-review') / (name+'.png')
    if not path.exists():
        print('Missing framebuffer: '+name)
        continue
    image = Image.open(path).convert('RGB')
    image.thumbnail((640, 360))
    while True:
        data = io.BytesIO()
        image.save(data, 'JPEG', quality=45)
        text = base64.b64encode(data.getvalue()).decode()
        if len(text) <= 12000:
            break
        image = image.resize((int(image.width*.9), int(image.height*.9)))
    pieces = [text[i:i+3500] for i in range(0, len(text), 3500)]
    for i, piece in enumerate(pieces):
        print(f'::notice title=Polish JPEG {name} {i+1}/{len(pieces)}::{piece}')
