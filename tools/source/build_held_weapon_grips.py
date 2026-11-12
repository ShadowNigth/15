"""Bake held-only weapon geometry from installed native idle grips, offline.
No downloads, no edits to viewmodels, dropped props, animations or materials.
Run: python -m tools.source.build_held_weapon_grips (numpy + pillow).
"""
import copy
import hashlib
import json
from pathlib import Path
import numpy as np
from .add_cs2_knives import original_pose, read_glb, write_glb, append_array, append_view
from .build_sport_gloves import _accessor
from .calibrate_weapon_world_scale import TARGET_LENGTHS
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/models/held'


def frame(doc, poses, side, modern=False):
    names = {n.get('name'): i for i,n in enumerate(doc['nodes'])}
    hand = poses[names['hand_'+side if modern else 'v_weapon.Bip01_'+side+'_Hand']][:3,3]
    prefix = 'finger_' if modern else 'v_weapon.Bip01_'+side+'_Finger'
    keys = ['middle_0_'+side, 'index_0_'+side, 'pinky_0_'+side] if modern else ['2','1','4']
    points = [poses[names[prefix+k]][:3,3] - hand for k in keys]
    y = points[0] / np.linalg.norm(points[0])
    x = points[1] - points[2]
    x -= y * np.dot(x,y)
    x /= np.linalg.norm(x)
    z = np.cross(x,y)
    return hand, np.column_stack((x,y,z))


def bake(vmodel, dual=False):
    path = ROOT / ('assets/models/weapons/'+vmodel+'.glb')
    doc, blob = read_glb(str(path))
    idle = next(a['name'] for a in doc['animations'] if a['name'] in ['idle','idle1'])
    poses = original_pose(doc,blob,idle)
    skin = doc['skins'][0]
    ib = _accessor(doc,blob,skin['inverseBindMatrices']).reshape(-1,4,4).transpose(0,2,1)
    transforms = np.array([poses[n]@m for n,m in zip(skin['joints'],ib)])
    parents = {c:i for i,n in enumerate(doc['nodes']) for c in n.get('children',[])}
    def left_joint(index):
        while True:
            name = doc['nodes'][index].get('name','').lower()
            if name in ['weapon_hand_l','cs2_mechanical_weapon_l','v_weapon.bip01_l_hand']:
                return True
            if index not in parents: return False
            index = parents[index]
    left = np.array([left_joint(i) for i in skin['joints']])
    frames = {side:frame(doc,poses,side) for side in ['R','L']}
    result = {}
    for side in ['R','L'] if dual else ['R']:
        out = {'asset':{'version':'2.0','generator':'native-idle-held-grip-v1'}, 'scene':0,
               'scenes':[{'nodes':[0]}], 'nodes':[{'name':vmodel+'_'+side,'mesh':0}],
               'meshes':[{'primitives':[]}], 'buffers':[{}], 'bufferViews':[], 'accessors':[],
               'materials':copy.deepcopy(doc['materials']), 'textures':copy.deepcopy(doc.get('textures',[])),
               'samplers':copy.deepcopy(doc.get('samplers',[])), 'images':copy.deepcopy(doc.get('images',[]))}
        binary=bytearray()
        bounds=[]
        for mesh in doc['meshes']:
            for primitive in mesh['primitives']:
                material=doc['materials'][primitive['material']].get('name','').lower()
                if any(s in material for s in ['glove','arms','sleeve','hand.bmp']): continue
                if 'lighter' in material or 'flame' in material: continue
                attrs=primitive['attributes']
                if 'JOINTS_0' not in attrs: continue
                pos=_accessor(doc,blob,attrs['POSITION']); norm=_accessor(doc,blob,attrs['NORMAL'])
                js=_accessor(doc,blob,attrs['JOINTS_0']); weights=_accessor(doc,blob,attrs['WEIGHTS_0'])
                matrices=(transforms[js]*weights[:,:,None,None]).sum(axis=1)
                points=np.einsum('nij,nj->ni',matrices,np.column_stack((pos,np.ones(len(pos)))))[:,:3]
                normals=np.einsum('nij,nj->ni',np.linalg.inv(matrices[:,:3,:3]).transpose(0,2,1),norm)
                indices=_accessor(doc,blob,primitive['indices']).reshape(-1,3)
                is_left=(left[js]*weights).sum(axis=1)>.5
                # Never retain a second pistol/dagger floating in the right hand frame.
                indices=indices[np.all(is_left[indices] if side=='L' else ~is_left[indices],axis=1)]
                if not len(indices): continue
                used, inverse=np.unique(indices,return_inverse=True)
                points=points[used]-frames[side][0]
                normals=normals[used]; normals/=np.maximum(np.linalg.norm(normals,axis=1)[:,None],1e-10)
                tri=inverse.reshape(-1,3)
                if np.median(np.linalg.det(matrices[used,:3,:3]))<0: tri=tri[:,[0,2,1]]
                prim={'attributes':{'POSITION':append_array(out,binary,points,'VEC3'),
                    'NORMAL':append_array(out,binary,normals,'VEC3'),
                    'TEXCOORD_0':append_array(out,binary,_accessor(doc,blob,attrs['TEXCOORD_0'])[used],'VEC2')},
                    'indices':append_array(out,binary,tri.ravel(),'SCALAR',5125), 'material':primitive['material']}
                out['meshes'][0]['primitives'].append(prim); bounds.extend(points)
        assert bounds, (vmodel,side,'empty weapon')
        name=vmodel.removeprefix('v_')+'_'+side.lower()
        # Copy only weapon textures, not the unused arm/glove atlases and buffers.
        old_materials=out['materials']; out['materials']=[]; out['images']=[]; out['textures']=[]
        material_map={}; texture_map={}; image_map={}
        def texture(index):
            if index in texture_map: return texture_map[index]
            item=copy.deepcopy(doc['textures'][index]); original=item['source']
            if original not in image_map:
                image=copy.deepcopy(doc['images'][original])
                if 'bufferView' in image:
                    view=doc['bufferViews'][image.pop('bufferView')]; start=view.get('byteOffset',0)
                    payload=blob[start:start+view['byteLength']]
                    image['bufferView']=append_view(out,binary,payload)
                image_map[original]=len(out['images']); out['images'].append(image)
            item['source']=image_map[original]
            texture_map[index]=len(out['textures']); out['textures'].append(item)
            return texture_map[index]
        def remap(value):
            if isinstance(value,dict):
                for key,child in value.items():
                    if key.endswith('Texture') and isinstance(child,dict) and 'index' in child:
                        child['index']=texture(child['index'])
                    else: remap(child)
        for primitive in out['meshes'][0]['primitives']:
            index=primitive['material']
            if index not in material_map:
                material=copy.deepcopy(old_materials[index]); remap(material)
                material_map[index]=len(out['materials']); out['materials'].append(material)
            primitive['material']=material_map[index]
        write_glb(str(OUT/(name+'.glb')),out,binary)
        bounds=np.array(bounds)
        tip=bounds[bounds[:,2]<bounds[:,2].min()+0.008].mean(axis=0)
        result[side]={'model':'held/'+name, 'bounds_m':np.ptp(bounds,axis=0).tolist(), 'tip':tip.tolist()}
    return doc,poses,frames,result,hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    weapons=json.loads((ROOT/'data/weapons.json').read_text())['weapons']
    options=json.loads((ROOT/'data/knife_models.json').read_text())['options']
    specs={s['v_model']:('knife',s) for s in options}
    specs.update({s['v_model']:(wid,s) for wid,s in weapons.items() if wid!='knife'})
    agents=json.loads((ROOT/'data/modern_agents.json').read_text())['agents']
    sockets=json.loads((ROOT/'data/modern_agent_sockets.json').read_text())
    rigs={name:read_glb(str(ROOT/('assets/models/modern/'+name+'.glb'))) for name in agents}
    data={'generator':'native-idle-held-grip-v1','models':{}}
    for vmodel,(wid,spec) in specs.items():
        dual=wid=='elite' or vmodel=='v_knife_push'
        source,pose,frames,parts,sha=bake(vmodel,dual)
        length=max(parts['R']['bounds_m'])
        targets={**TARGET_LENGTHS,'usp':0.42,'m4a1':1.0,'ump45':0.69,'mp7':0.415}
        scale=0.90 if weapons[wid].get('grenade') else min(1.0,targets.get(wid,length)/length) if wid!='knife' else 1.0
        entry={'wid':wid,'source_sha256':sha,'scale':scale,'parts':parts,'agents':{}}
        for avatar,(target,tblob) in rigs.items():
            family=agents[avatar]['family']
            motion,mblob=rigs[family]
            clip=sockets[avatar][wid]['clips']['idle']
            # Variant rigs inherit native motion by bone name, just like prepare_model.
            if avatar!=family:
                target=copy.deepcopy(target)
                name_to_i={n.get('name'):i for i,n in enumerate(target['nodes'])}
                # Copy sampled local channels onto the variant's own proportions.
                from .add_cs2_knives import matrices
                overrides={}
                anim=next(a for a in motion['animations'] if a['name']==clip)
                for channel in anim['channels']:
                    name=motion['nodes'][channel['target']['node']].get('name')
                    if name not in name_to_i: continue
                    sampler=anim['samplers'][channel['sampler']]
                    overrides.setdefault(name_to_i[name],{})[channel['target']['path']]=_accessor(motion,mblob,sampler['output'])[0].tolist()
                tpose=matrices(target['nodes'],overrides)
            else: tpose=original_pose(target,tblob,clip)
            tnames={n.get('name'):i for i,n in enumerate(target['nodes'])}
            settings={}
            for side in parts:
                hand,axes=frame(target,tpose,side,True)
                rotation=axes@frames[side][1].T
                hand_matrix=tpose[tnames['hand_'+side]]
                basis=np.linalg.inv(hand_matrix[:3,:3])@rotation
                settings[side]={'basis':(basis*scale).tolist()}
                assert np.linalg.det(rotation)>.999
                if side=='R' and int(weapons[wid]['slot'])==1:
                    support=rotation@(frames['L'][0]-frames['R'][0])*scale
                    settings['support']=(np.linalg.inv(hand_matrix[:3,:3])@support).tolist()
            entry['agents'][avatar]=settings
        data['models'][vmodel]=entry
        print(vmodel, {side:np.round(part['bounds_m'],3).tolist() for side,part in parts.items()})
    (ROOT/'data/held_weapon_grips.json').write_text(json.dumps(data,indent=2)+'\n')

if __name__=='__main__': main()
