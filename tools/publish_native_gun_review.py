#!/usr/bin/env python3
"""Publish real Godot poses in a bounded per-batch check, never synthesized art."""
import base64
import json
from pathlib import Path
import sys
from PIL import Image, ImageDraw

batch = int(sys.argv[1])
root = Path('/tmp/native-gun-captures')
reports = json.loads(Path('data/native_gun_animation_report.json').read_text())
names = list(reports)[batch*6:(batch+1)*6]
assert len(names) == 6
plate = Image.new('RGB',(1440,450),(12,15,19))
draw = ImageDraw.Draw(plate)
for col,wid in enumerate(names):
    poses = ['idle','inspect','reload' if (root/(wid+'_reload.png')).exists() else 'pressbutton' if wid=='c4' else 'throw' if (root/(wid+'_throw.png')).exists() else 'shoot1']
    for row,pose in enumerate(poses):
        image = Image.open(root/(wid+'_'+pose+'.png')).convert('RGB')
        # Retain the complete weapon/arms portion of the real 960x540 framebuffer.
        image = image.crop((280,90,960,540))
        image.thumbnail((240,132))
        x,y = col*240,row*150
        plate.paste(image,(x,y+18))
        draw.text((x+4,y+3),wid+' / '+pose,fill='white')
path = root/f'native_batch_{batch}.jpg'
for quality in [35,28,22,16,10,5]:
    plate.save(path,quality=quality,optimize=True)
    if path.stat().st_size <= 24000: break
assert path.stat().st_size <= 26000


def publish(image,name):
    encoded = base64.b64encode(image.read_bytes()).decode('ascii')
    chunks = [encoded[i:i+3500] for i in range(0,len(encoded),3500)]
    assert len(chunks) <= 10
    for i,chunk in enumerate(chunks):
        print(f'::notice title=Native JPEG {name} {i+1}/{len(chunks)}::{chunk}')

publish(path,f'native_batch_{batch}')
# Additional full-frame detail on the mechanically difficult rigs.
for wid,pose in [('revolver','prepare'),('m4a1','add_silencer'),('elite','reload'),('cz75','reload'),('molotov','throw'),('awp','reload'),('m3','reload')]:
    if wid in names:
        publish(root/(wid+'_'+pose+'.jpg'),wid+'_'+pose)
