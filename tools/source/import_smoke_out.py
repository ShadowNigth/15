"""Import ONLY Moto Gloves Smoke Out 5033_10078, native view mesh and UVs.
Uses pinned cs2go source and its own offline paint baker; no runtime network.
"""
import concurrent.futures
import hashlib
import json
import subprocess
import numpy as np
from PIL import Image
from . import build_agent_view_arms as arms
from .expand_cs2go_cosmetics import fetch, PUBLIC, CACHE, ROOT, PIN
from .import_modern_agents import read_glb
ID = '5033_10078'


def palm(frames, side):
    wrist = frames['hand_'+side]
    y = frames['finger_middle_0_'+side][:3,3]-wrist[:3,3]
    y /= np.linalg.norm(y)
    x = frames['finger_index_0_'+side][:3,3]-frames['finger_pinky_0_'+side][:3,3]
    x -= y*np.dot(x,y)
    x /= np.linalg.norm(x)
    return np.column_stack([x,y,np.cross(x,y)])


def calibration(source, target):
    side = next(n[-1] for n in source if n.startswith('hand_'))
    a = np.linalg.inv(source['hand_'+side][:3,:3]) @ palm(source,side)
    b = np.linalg.inv(target['hand_'+side][:3,:3]) @ palm(target,side)
    result = np.eye(4)
    result[:3,:3] = b @ np.linalg.inv(a)
    return result


def anatomical(frames, name):
    side=name[-1]
    wrist=frames['hand_'+side][:3,3]
    middle=frames['finger_middle_0_'+side][:3,3]
    index=frames['finger_index_0_'+side][:3,3]
    pinky=frames['finger_pinky_0_'+side][:3,3]
    origin=frames[name][:3,3]
    along=middle-wrist
    if name.startswith('finger_'):
        parts=name.split('_')
        segment=parts[-2]
        if segment.isdigit():
            step=int(segment)
            child='_'.join(parts[:-2]+[str(step+1),side])
            parent='_'.join(parts[:-2]+[str(step-1),side])
            if child in frames:along=frames[child][:3,3]-origin
            elif parent in frames:along=origin-frames[parent][:3,3]
    elif name.startswith('arm_'):along=wrist-origin
    y=along/np.linalg.norm(along)
    x=index-pinky
    x-=y*np.dot(x,y)
    if np.linalg.norm(x)<1e-5:
        x=middle-wrist
        x-=y*np.dot(x,y)
    x/=np.linalg.norm(x)
    result=np.eye(4)
    result[:3,:3]=np.column_stack([x,y,np.cross(x,y)])
    result[:3,3]=origin
    return result


def bone_transform(source,target,source_name,target_name):
    a=anatomical(source,source_name)
    b=anatomical(target,target_name)
    scale=np.diag([1/0.8128]*3+[1])
    return b @ scale @ np.linalg.inv(a)


def main():
    paint_path = 'skins/gloves/paints/'+ID+'.json'
    paint = json.loads(fetch(PUBLIC+paint_path).read_text())
    assets = set()
    def urls(value):
        if isinstance(value,str) and value.startswith('/skins/'): assets.add(PUBLIC+value[1:])
        elif isinstance(value,dict):
            for child in value.values(): urls(child)
        elif isinstance(value,list):
            for child in value: urls(child)
    urls(paint)
    assets.update('apps/game/src/'+name for name in ['skin-baker.ts','skin-paint.ts'])
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool: list(pool.map(fetch,sorted(assets)))
    (CACHE/'bake-jobs.json').write_text(json.dumps([{'id':ID,'paint':paint_path}]))
    subprocess.run(['node','tools/source/cosmetics/bake.mjs',str(CACHE)],cwd=ROOT,check=True)
    textures = {}
    directory = ROOT/'assets/textures/moto_smoke_out'
    directory.mkdir(parents=True,exist_ok=True)
    baked = CACHE/'baked'/ID
    for row in json.loads((baked/'manifest.json').read_text()):
        name = row['material'].split('/')[-1].removesuffix('.vmat')
        if not name.startswith('glove_motorcycle_'): continue
        maps = row['maps']
        if 'g_tColor' in maps:
            data = (baked/maps['g_tColor']).read_bytes()
            size = int((len(data)//4)**.5)
            image = Image.frombytes('RGBA',(size,size),data).convert('RGB')
            image.thumbnail((1024,1024))
            path = directory/(name+'.webp')
            image.save(path,format='WEBP',lossless=True)
            textures[name] = 'res://'+path.relative_to(ROOT).as_posix()
    td,tb = read_glb(ROOT/'assets/models/weapons/v_ak47.glb')
    original = arms.axis_between
    arms.axis_between = calibration
    try: definition = arms.build('moto_smoke_out','gloves/5033',td,tb,glove_prefix='glove_motorcycle_',bone_transform=bone_transform)
    finally: arms.axis_between = original
    definition.update({'native_glove':True,'item':5033,'paint':10078,'textures':textures,'retarget':'anatomical-same-side','commit':PIN})
    path = ROOT/'data/agent_view_arms.json'
    catalog = json.loads(path.read_text())
    catalog.setdefault('gloves',{})['moto_smoke_out'] = definition
    path.write_text(json.dumps(catalog,separators=(',',':'))+'\n')
    path = ROOT/'data/sport_gloves.json'
    catalog = json.loads(path.read_text())
    catalog['options'] = [row for row in catalog['options'] if row['id'] != ID]
    catalog['options'].append({'id':ID,'name':'Moto Gloves | Smoke Out','family':'Smoke Out','native_model':'moto_smoke_out','native_textures':textures,'item':5033,'paint':10078,'wear':0.07,'seed':1})
    path.write_text(json.dumps(catalog,indent=2)+'\n')
    print('Imported Smoke Out:',definition['surfaces'],textures)

if __name__ == '__main__': main()
