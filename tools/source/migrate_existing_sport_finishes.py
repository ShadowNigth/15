"""Keep existing optional finish IDs, now on cs2go's original Sport skeleton/UVs.
Does NOT add the removed native catalogue options. Only migrate existing IDs.
"""
import concurrent.futures,json,subprocess
import numpy as np
from PIL import Image
from .expand_cs2go_cosmetics import ROOT,CACHE,PUBLIC,fetch
from .build_native_view_rigs import export

def main():
    catalog=json.loads((ROOT/'data/sport_gloves.json').read_text())
    existing=[o for o in catalog['options'] if 'family' in o and o['id']!='5033_10078']
    native=json.loads(fetch(PUBLIC+'skins/gloves/catalog.json').read_text())
    families={o['name'].split(' | ')[-1]:o for o in native if o['id'].startswith('5030_')}
    paths={family:'skins/gloves/paints/'+families[family]['id']+'.json' for family in {o['family'] for o in existing}}
    assets={'apps/game/src/skin-baker.ts','apps/game/src/skin-paint.ts'}
    def urls(v):
        if isinstance(v,str) and v.startswith('/skins/'):assets.add(PUBLIC+v[1:])
        elif isinstance(v,dict):
            for c in v.values(): urls(c)
        elif isinstance(v,list):
            for c in v: urls(c)
    for path in paths.values():urls(json.loads(fetch(PUBLIC+path).read_text()))
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:list(pool.map(fetch,sorted(assets)))
    wear={'BS':.8,'FT':.25,'WW':.4,'MW':.12}
    jobs=[{'id':'preserved_'+o['id'],'paint':paths[o['family']],'wear':wear[o['wear_code']],'seed':1} for o in existing]
    (CACHE/'bake-jobs.json').write_text(json.dumps(jobs))
    subprocess.run(['node','tools/source/cosmetics/bake.mjs',str(CACHE)],cwd=ROOT,check=True)
    for option in existing:
        directory=ROOT/'assets/textures/native_sport'/option['id'];directory.mkdir(parents=True,exist_ok=True)
        baked=CACHE/'baked'/('preserved_'+option['id'])
        textures={};native_maps={}
        for row in json.loads((baked/'manifest.json').read_text()):
            name=row['material'].split('/')[-1].removesuffix('.vmat')
            if not name.startswith('glove_sporty_'):continue
            def pixels(key,size=1024):
                raw=(baked/row['maps'][key]).read_bytes();width=int((len(raw)//4)**.5)
                return np.array(Image.frombytes('RGBA',(width,width),raw).resize((size,size),Image.Resampling.LANCZOS))
            color_path=directory/(name+'.webp')
            Image.fromarray(pixels('g_tColor')[:,:,:3]).save(color_path,format='WEBP',quality=95)
            textures[name]='res://'+color_path.relative_to(ROOT).as_posix()
            normal=pixels('g_tNormal',512)
            xy=normal[:,:,:2].astype(float)/127.5-1
            z=(np.sqrt(np.maximum(0,1-(xy*xy).sum(2)))*.5+.5)*255
            normal_path=directory/(name+'_normal.webp')
            Image.fromarray(np.dstack([normal[:,:,0],normal[:,:,1],z.astype('uint8')])).save(normal_path,format='WEBP',lossless=True)
            orm=np.dstack([pixels('g_tAmbientOcclusion',512)[:,:,0],normal[:,:,2],pixels('g_tMetalness',512)[:,:,0]])
            orm_path=directory/(name+'_orm.webp');Image.fromarray(orm).save(orm_path,format='WEBP',lossless=True)
            native_maps[name]={'normal':'res://'+normal_path.relative_to(ROOT).as_posix(),'orm':'res://'+orm_path.relative_to(ROOT).as_posix()}
        assert len(textures)==2,option['id']
        option.update(native_model='sport_native',native_textures=textures,native_maps=native_maps,native_source_finish=families[option['family']]['id'],native_wear=wear[option['wear_code']])
    catalog['conversion']='Original cs2go skeletons: existing optional Sport IDs preserved, Smoke Out added separately. No removed catalogue options restored.'
    (ROOT/'data/sport_gloves.json').write_text(json.dumps(catalog,indent=2)+'\n')
    report=json.loads((ROOT/'data/native_view_rigs.json').read_text())
    report['gloves']['sport_native']=export('sport_native','gloves/5030',True)
    (ROOT/'data/native_view_rigs.json').write_text(json.dumps(report,separators=(',',':'))+'\n')
if __name__=='__main__':main()
