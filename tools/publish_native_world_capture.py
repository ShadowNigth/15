"""Bounded real-framebuffer transport through GitHub annotations (not mockups)."""
import base64,sys
from pathlib import Path
name=sys.argv[1]
assert name in ['ct_0','t_0','hostage_0','chicken_0','defuser_item_0','italy_hud_chicken']
p=Path('/tmp/native-world-review')/(name+'.jpg')
if not p.exists():raise SystemExit('Missing actual framebuffer '+str(p))
s=base64.b64encode(p.read_bytes()).decode()
parts=[s[i:i+3500] for i in range(0,len(s),3500)]
assert len(parts)<=10
for i,part in enumerate(parts):print(f'::notice title=Native world JPEG {name} {i+1}/{len(parts)}::{part}')
