"""Rebuild 19 native-UV Sport paints from pinned upstream shaders; lossless WebP."""
from .expand_cs2go_cosmetics import *
rows=json.loads(fetch(PUBLIC+'skins/gloves/catalog.json').read_text());rows=[dict(g,kind='glove',paint_path='skins/gloves/paints/'+g['id']+'.json') for g in rows if g['item']==5030]
assets=set()
def urls(v):
 if isinstance(v,str) and v.startswith('/skins/'):assets.add(PUBLIC+v[1:])
 elif isinstance(v,dict):
  for a in v.values():urls(a)
 elif isinstance(v,list):
  for a in v:urls(a)
for r in rows:urls(json.loads(fetch(PUBLIC+r['paint_path']).read_text()))
assets.update('apps/game/src/'+p for p in ['skin-baker.ts','skin-paint.ts'])
with futures.ThreadPoolExecutor(max_workers=6) as pool:list(pool.map(fetch,sorted(assets)))
(CACHE/'bake-jobs.json').write_text(json.dumps([{'id':r['id'],'paint':r['paint_path']} for r in rows]))
subprocess.run(['node','tools/source/cosmetics/bake.mjs',str(CACHE)],check=True)
catalog=json.loads((ROOT/'data/sport_gloves.json').read_text())
for r in rows:
 option=next(o for o in catalog['options'] if o['id']=='cs2go_'+r['id'])
 textures={}
 for name,img in painted_images(r).items():
  rel=Path('assets/textures/native_sport')/r['id']/(name+'.webp');(ROOT/rel).parent.mkdir(parents=True,exist_ok=True);img.save(ROOT/rel,format="WEBP",lossless=True,quality=100,method=6);textures[name]='res://'+rel.as_posix()
 option['native_textures']=textures;option['native_uv']=True
catalog['native_uv_revision']='cs2go-viewmodel-original-uv-v1'
(ROOT/'data/sport_gloves.json').write_text(json.dumps(catalog,indent=2,ensure_ascii=False)+'\n')
