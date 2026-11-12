"""Contact sheets made exclusively from actual Godot framebuffers."""
from PIL import Image, ImageDraw
from pathlib import Path
root=Path('/tmp/modern-captures')
groups={
 'firearms':['ak47','m4a1','awp','mp5navy','tec9','mag7','glock18','elite','m249'],
 'tools':['hegrenade','flashbang','smokegrenade','molotov','incendiary','decoy','knife','c4','crouch_turn'],
 'knives':['knife_karambit','knife_m9','knife_bayonet','knife_push','knife_butterfly','knife_talon','knife_kukri','knife_css','knife_stiletto']}
for group,names in groups.items():
 out=Image.new('RGB',(1200,840),(24,28,34));draw=ImageDraw.Draw(out)
 for i,name in enumerate(names):
  path=root/('held_'+name+'.png')
  if not path.exists():continue
  im=Image.open(path).convert('RGB');im.thumbnail((400,250))
  x=i%3*400;y=i//3*280
  out.paste(im,(x,y+24));draw.text((x+12,y+6),name,fill='white')
 out.save(root/('held_'+group+'.png'))
