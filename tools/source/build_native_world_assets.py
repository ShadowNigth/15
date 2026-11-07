#!/usr/bin/env python3
"""Build pinned cosmetic world assets without modifying existing weapon/player GLBs.
Usage: python -m tools.source.build_native_world_assets UPSTREAM_DIRECTORY GUN_JSON_DIRECTORY
Inputs: ScCsgoKnives 1eb8067 (see manifest); development-only numpy/scipy.
"""
import hashlib,json,struct,sys,shutil
from pathlib import Path
import numpy as np
from scipy.spatial.transform import Rotation
from . import add_cs2_knives as gl
from . import import_native_knife_animations as native
from .refine_weapon_animations import write_glb
ROOT=Path(__file__).resolve().parents[2]
PIN='1eb8067fd0b7214df5bccf3ac3807fbaa3aee70d'

def main(source,guns):
    source=Path(source);guns=Path(guns);entries=[]
    def record(src,dst,operation):
        entries.append(dict(source=str(src.relative_to(source)),path='res://'+str(dst.relative_to(ROOT)),source_sha256=hashlib.sha256(src.read_bytes()).hexdigest(),sha256=hashlib.sha256(dst.read_bytes()).hexdigest(),operation=operation))
    def copy(rel,target):
        src=source/rel;dst=ROOT/target;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dst);record(src,dst,'unchanged bytes');return dst
    assets='src/ScCsgoKnives/Assets/'
    for p in sorted((source/assets/'Textures/ScCsgoKnives').glob('hud_ammo_*.png')):
        copy(str(p.relative_to(source)),'assets/ui/native/'+p.name)
    for p in sorted((source/assets/'Models/ScCsgoKnives').glob('casing_*.obj')):
        name=p.stem;verts=[];norms=[];uv=[];outp=[];outn=[];outuv=[]
        for line in p.read_text().splitlines():
            t=line.split()
            if not t:continue
            if t[0]=='v':verts.append(list(map(float,t[1:4])))
            elif t[0]=='vn':norms.append(list(map(float,t[1:4])))
            elif t[0]=='vt':uv.append(list(map(float,t[1:3])))
            elif t[0]=='f':
                assert len(t)==4
                for v in t[1:]:
                    a,b,c=[int(s)-1 for s in v.split('/')];outp.append(verts[a]);outuv.append(uv[b]);outn.append(norms[c])
        d=dict(asset={'version':'2.0'},buffers=[{'byteLength':0}],bufferViews=[],accessors=[],scenes=[{'nodes':[0]}],scene=0,nodes=[{'name':name,'mesh':0}]);blob=bytearray()
        attr={k:gl.append_array(d,blob,v,kind) for k,v,kind in [('POSITION',outp,'VEC3'),('NORMAL',outn,'VEC3'),('TEXCOORD_0',outuv,'VEC2')]}
        d['accessors'][attr['POSITION']].update(min=np.min(outp,axis=0).tolist(),max=np.max(outp,axis=0).tolist())
        tex=source/assets/'Textures/ScCsgoKnives'/(name+'.png')
        d.update(images=[dict(bufferView=gl.append_view(d,blob,tex.read_bytes()),mimeType='image/png')],textures=[{'source':0}],materials=[{'name':name,'pbrMetallicRoughness':{'baseColorTexture':{'index':0},'metallicFactor':0.65,'roughnessFactor':0.42}}],meshes=[{'primitives':[{'attributes':attr,'material':0}]}])
        dst=ROOT/'assets/models/native'/f'{name}.glb';dst.parent.mkdir(parents=True,exist_ok=True);write_glb(str(dst),d,blob);record(p,dst,'OBJ triangle positions/normals/UV exact; embedded original PNG; no resize')
        entries.append(dict(source=str(tex.relative_to(source)),embedded_in='res://'+str(dst.relative_to(ROOT)),source_sha256=hashlib.sha256(tex.read_bytes()).hexdigest()))
    for name in ['chicken']:
        copy(assets+'Models/ScCsgoKnives/'+name+'.glb','assets/models/native/'+name+'.glb')
    for name in ['hostage','defuser_item']:
        copy('src/ScCsgoTactical/Assets/Models/ScCsgoTactical/'+name+'.glb','assets/models/native/'+name+'.glb')
    # Restore native cached local TRS samples to the original node names, not a fabricated idle.
    for role in ['ct','t']:
        src=source/f'src/ScCsgoTactical/Assets/Models/ScCsgoTactical/{role}.glb';d,blob=gl.read_glb(str(src));d['animations']=[]
        names={n['name']:i for i,n in enumerate(d['nodes'])};cache=source/f'src/ScCsgoTactical/Assets/Animations/ScCsgoTactical/{role}.scanim';raw=cache.read_bytes();off=8;assert raw[:8]==b'SCACT001'
        def take(fmt):
            nonlocal off
            v=struct.unpack_from('<'+fmt,raw,off);off+=struct.calcsize('<'+fmt);return v[0] if len(v)==1 else v
        def text():
            nonlocal off
            n=s=0
            while True:
                v=take('B');n|=(v&127)<<s;s+=7
                if v<128:break
            t=raw[off:off+n].decode();off+=n;return t
        bones=[text() for _ in range(take('i'))]
        for _ in range(take('i')):
            name=text();duration=take('f');count=take('i');times=np.frombuffer(raw,dtype='<f4',count=count,offset=off).copy();off+=count*4
            a=dict(name=name,samplers=[],channels=[]);ta=gl.append_array(d,blob,times,'SCALAR');d['accessors'][ta].update(min=[float(times.min())],max=[float(times.max())])
            for __ in range(take('i')):
                bone=take('i');prop=take('B');width=4 if prop==1 else 3
                values=np.frombuffer(raw,dtype='<f4',count=count*width,offset=off).copy().reshape(count,width);off+=count*width*4
                node=names.get(bones[bone]);path=['translation','rotation','scale'][prop]
                if node is None or (bones[bone]=='root_motion' and prop==0):continue
                va=gl.append_array(d,blob,values,'VEC4' if width==4 else 'VEC3');si=len(a['samplers']);a['samplers'].append(dict(input=ta,output=va,interpolation='LINEAR'));a['channels'].append(dict(sampler=si,target=dict(node=node,path=path)))
            if a['channels']:d['animations'].append(a)
        assert off==len(raw) and len(d['animations'])==170
        dst=ROOT/f'assets/models/native/{role}.glb';write_glb(str(dst),d,blob);record(src,dst,'Geometry, skins and embedded images exact; restore 170 external local-TRS clips; root travel omitted')
        entries.append(dict(source=str(cache.relative_to(source)),source_sha256=hashlib.sha256(raw).hexdigest(),embedded_in='res://'+str(dst.relative_to(ROOT))))
    definitions=json.loads((source/'src/ScCsgoKnives/AnimationData/cs2_casings.json').read_text());report=json.loads((ROOT/'data/native_gun_animation_report.json').read_text());weapons=json.loads((ROOT/'data/weapons.json').read_text())['weapons'];routes={}
    for wid,r in report.items():
        sw=r['source_weapon'];events={}
        if not any(k.startswith(sw+':') for k in definitions['Cues']):continue
        anim=json.loads((guns/(sw+'.cs2.animation.json')).read_text());sn=native.source_nodes(anim);sidx={n['name']:i for i,n in enumerate(sn)};idle=next(c for n,c in anim['Clips'].items() if c.get('Alias')=='idle' or n.startswith(('idle_','idle1_')));sp=native.sample_poses(sn,idle,np.array([0.0]))[0]
        d,b=gl.read_glb(str(ROOT/('assets/models/weapons/'+weapons[wid]['v_model']+'.glb')));op=gl.original_pose(d,b,'idle');nodeidx={n['name']:i for i,n in enumerate(d['nodes'])};placement=np.array(r['placement_matrix'])
        for clip,source_clip in r['clips'].items():
            cues=definitions['Cues'].get(sw+':'+source_clip,[])
            if not cues:continue
            for cue in cues:
                candidates=[(name,nodeidx[name]) for name,bone in r['mechanical_bones'].items() if bone==cue['Bone']]
                assert candidates,(wid,cue['Bone']);bone,ni=candidates[0]
                attachment=np.eye(4);attachment[:3,:3]=Rotation.from_quat(cue['Rotation']).as_matrix();attachment[:3,3]=cue['Offset']
                frame=np.linalg.inv(op[ni])@native.C@sp[sidx[cue['Bone']]]@attachment
                # The installed idle is already in its port coordinate space, no second placement.
                events.setdefault(clip,[]).append(dict(at=cue['At'],model=cue['Model'],bone=bone,frame=np.round(frame,9).tolist(),speed_min=cue['SpeedMin'],speed_max=cue['SpeedMax'],source_clip=source_clip,source_bone=cue['Bone'],attachment=cue['Attachment']))
        routes[wid]=dict(source_weapon=sw,clips=events)
    out=dict(source_commit=PIN,models=definitions['Models'],weapons=routes,source_cues=definitions['Cues'])
    (ROOT/'data/native_casings.json').write_text(json.dumps(out,indent=2)+'\n')
    entries.append(dict(source='src/ScCsgoKnives/AnimationData/cs2_casings.json',source_sha256=hashlib.sha256((source/'src/ScCsgoKnives/AnimationData/cs2_casings.json').read_bytes()).hexdigest(),path='res://data/native_casings.json',sha256=hashlib.sha256((ROOT/'data/native_casings.json').read_bytes()).hexdigest(),operation='Source timing/attachment/velocity preserved; per-bone idle frame calibration onto existing native viewmodels'))
    (ROOT/'data/native_world_manifest.json').write_text(json.dumps(dict(repository='zh667/ScCsgoKnives',commit=PIN,files=entries),indent=2)+'\n')
    print('Built',len(entries),'provenance records;',len(routes),'weapon routes; 8 shells, 8 HUD icons, chicken, kit, hostage, 340 agent clips')
if __name__=='__main__':main(*sys.argv[1:])
