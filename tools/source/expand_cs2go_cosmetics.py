#!/usr/bin/env python3
"""Pinned compatible batch. Build-time fetch/bake only; game runs fully offline.
Run: python -m tools.source.expand_cs2go_cosmetics
"""
import concurrent.futures as futures
import copy, hashlib, json, subprocess
from pathlib import Path
import numpy as np
from PIL import Image
from scipy.ndimage import distance_transform_edt
from .import_modern_agents import read_glb, write_glb
from .build_sport_gloves import _accessor
from . import weapon_skin_reprojection as uv
ROOT=Path(__file__).resolve().parents[2]
CACHE=ROOT/'.cache/cs2go'; PUBLIC='packages/assets/public/'
PIN='fb970df0ee8175d9b212d310f6a928f9f61014f2'
SOURCE='https://github.com/3kh0/cs2go'
GUNS={1:('deagle','deagle'),2:('elite','elite'),3:('fiveseven','fiveseven'),4:('glock18','glock'),7:('ak47','ak-47'),8:('aug','aug'),9:('awp','awp'),10:('famas','famas'),11:('g3sg1','g3sg1'),13:('galil','galilar'),14:('m249','m249'),16:('m4a4','m4a4'),17:('mac10','mac10'),19:('p90','p90'),23:('mp5navy','mp5sd'),24:('ump45','ump45'),25:('xm1014','xm1014'),26:('bizon','bizon'),27:('mag7','mag7'),28:('negev','negev'),29:('sawedoff','sawedoff'),30:('tec9','tec9'),31:('taser','taser'),32:('p2000','hkp2000'),33:('mp7','mp7'),34:('tmp','mp9'),35:('m3','nova'),36:('p228','p250'),38:('sg550','scar20'),39:('sg552','sg556'),40:('scout','ssg08'),60:('m4a1','m4a1_s'),61:('usp','usp-s'),63:('cz75','cz75a'),64:('revolver','revolver')}
AGENTS={'fbi':('CT','urban','ctm-fbi.glb','FBI'), 'st6':('CT','gsg9','ctm-st6-variante.glb','Seal Team 6 Soldier | NSWC SEAL'), 'sas_officer':('CT','gign','ctm-sas-variantf.glb','B Squadron Officer | SAS'), 'leet':('T','leet','tm-leet-variante.glb','Elite Crew | Variant E'), 'dragomir':('T','arctic','tm-balkan-variantf.glb','Dragomir | Sabre'), 'phoenix_a':('T','guerilla','tm-phoenix-varianta.glb','Phoenix | Variant A')}

def fetch(path):
    dest=CACHE/path
    if not dest.exists():
        dest.parent.mkdir(parents=True,exist_ok=True)
        data=subprocess.check_output(['gh','api','-H','Accept: application/vnd.github.raw+json',f'repos/3kh0/cs2go/contents/{path}?ref={PIN}'])
        dest.write_bytes(data)
    return dest

def decode(relative):
    src=fetch(PUBLIC+relative); out=src.with_suffix('.decoded.glb')
    if not out.exists():subprocess.run(['node','tools/source/modern_agents/decode.mjs',str(src),str(out)],cwd=ROOT,check=True)
    return out

def prepare():
    CACHE.mkdir(parents=True,exist_ok=True)
    skins=json.loads(fetch(PUBLIC+'skins/catalog.json').read_text())
    gloves=json.loads(fetch(PUBLIC+'skins/gloves/catalog.json').read_text())
    old=json.loads((ROOT/'data/weapon_skins.json').read_text())
    selected=[]
    for item,(wid,model) in GUNS.items():
        existing={o.get('finish','').casefold() for o in old['weapons'].get(wid,{}).get('options',[]) if not o['id'].startswith('cs2go_')}
        rows=[s for s in skins if int(s['id'].split('_')[0])==item and s['body']=='hd' and s['name'].casefold() not in existing]
        for s in rows[:2]:selected.append(dict(s,kind='weapon',wid=wid,model=model,paint_path='skins/paints/'+s['id']+'.json'))
    def load(s):return json.loads(fetch(PUBLIC+s['paint_path']).read_text())
    with futures.ThreadPoolExecutor(max_workers=8) as pool: paints=list(pool.map(load,selected))
    assets=set()
    def urls(v):
        if isinstance(v,str) and v.startswith('/skins/'):assets.add(PUBLIC+v[1:])
        elif isinstance(v,dict):
            for e in v.values():urls(e)
        elif isinstance(v,list):
            for e in v:urls(e)
    for p in paints:urls(p)
    assets.update('apps/game/src/'+f for f in ['skin-baker.ts','skin-paint.ts'])
    with futures.ThreadPoolExecutor(max_workers=8) as pool:list(pool.map(fetch,sorted(assets)))
    jobs=[{'id':s['id'],'paint':s['paint_path']} for s in selected]
    (CACHE/'bake-jobs.json').write_text(json.dumps(jobs))
    (CACHE/'selected.json').write_text(json.dumps(selected,indent=2))
    print('Selected',sum(s['kind']=='weapon' for s in selected),'weapon finishes;',sum(s['kind']=='glove' for s in selected),'Sport finishes;',len(assets),'bake assets',flush=True)
    subprocess.run(['node','tools/source/cosmetics/bake.mjs',str(CACHE)],cwd=ROOT,check=True)
    return selected

def painted_images(row):
    base=CACHE/'baked'/row['id']; manifest=json.loads((base/'manifest.json').read_text())
    result={}
    for t in manifest:
        file=t['maps'].get('g_tColor')
        if file: image=Image.frombytes('RGBA',(1024,1024),(base/file).read_bytes()).convert('RGB')
        else:
            import gzip,struct
            url=t['direct'].get('g_tColor'); assert url,'No colour output '+row['id']
            data=gzip.decompress(fetch(PUBLIC+url.lstrip('/')).read_bytes());w,h=struct.unpack_from('<II',data)
            image=Image.frombytes('RGBA',(w,h),data[8:]).convert('RGB')
        # WebGPU output has top-row zero and the original runtime sets flipY=false.
        result[t['material'].split('/')[-1].replace('.vmat','')]=image
    return result

def part_name(name,dual=False):
    name=name.lower()
    prefix=("left_" if "_l_" in name or name.endswith("_l") else "right_") if dual else ""
    if 'bullet' in name or 'shell' in name:return prefix+'hardware'
    for key in ['magazine2','clip2','magazine','slide','bolt','trigger','hammer','pump','silencer','scope','clip']:
        if key in name:return prefix+('magazine2' if key=='clip2' else 'magazine' if key=='clip' else key)
    return prefix+'body'

def surface(document,binary,material,glove=False):
    positions=[];texcoords=[];triangles=[];owners=[];normals=[]
    for mesh in document['meshes']:
        for p in mesh['primitives']:
            if document['materials'][p.get('material',0)].get('name') not in material:continue
            a=p['attributes'];v=_accessor(document,binary,a['POSITION']);t=_accessor(document,binary,a['TEXCOORD_0'])
            transform=document['materials'][p.get('material',0)].get('pbrMetallicRoughness',{}).get('baseColorTexture',{}).get('extensions',{}).get('KHR_texture_transform',{})
            t=t*np.array(transform.get('scale',[1,1]))+np.array(transform.get('offset',[0,0]))
            faces=_accessor(document,binary,p['indices']).reshape(-1,3)
            if 'JOINTS_0' in a:
                joints=_accessor(document,binary,a['JOINTS_0']);weights=_accessor(document,binary,a['WEIGHTS_0'])
                bone_nodes=document['skins'][0]['joints']
                labels=[glove_part(document['nodes'][bone_nodes[int(j)]]['name']) if glove else part_name(document['nodes'][bone_nodes[int(j)]]['name'],any('elite' in m.get('name','') for m in document['materials'])) for j in joints[np.arange(len(joints)),weights.argmax(1)]]
            else: labels=['body']*len(v)
            triangles.extend(faces+len(positions));positions.extend(v);texcoords.extend(t);owners.extend(labels);normals.extend(_accessor(document,binary,a['NORMAL']))
    assert positions,material
    return {'positions':np.array(positions),'uvs':np.array(texcoords),'faces':np.array(triangles),'owners':np.array(owners),'normals':np.array(normals)}

def correspondence(target, source, size):
    pos,faces=uv._raster_surface(target,size);covered=faces>=0
    assert covered.any()
    import trimesh
    points=pos[covered];coords=np.empty((len(points),2),np.float32);distance=np.empty(len(points),np.float32)
    point_owners=target['owners'][target['faces'][faces[covered],0]]
    normal_points=None
    if target.get('normal_matching',False):
        normal_surface=dict(target,positions=target['normals'])
        normal_image,_=uv._raster_surface(normal_surface,size)
        normal_points=normal_image[covered]
        normal_points/=np.maximum(np.linalg.norm(normal_points,axis=1,keepdims=True),1e-10)
    source_owners=source['owners'][source['faces'][:,0]]
    tri=source['positions'][source['faces']]
    valid=np.linalg.norm(np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]),axis=1)>1e-12
    for part in np.unique(point_owners):
        selection=valid&(source_owners==part)
        if not selection.any():selection=valid
        mesh=trimesh.Trimesh(vertices=source['positions'],faces=source['faces'][selection],process=False)
        indexes=np.flatnonzero(point_owners==part)
        for start in range(0,len(indexes),128):
            ix=indexes[start:start+128]
            if normal_points is None:
                closest,dist,face=trimesh.proximity.closest_point(mesh,points[ix])
            else:
                # Anatomy alone cannot distinguish back-of-hand from palm.
                # Evaluate nearby triangles with a same-facing normal penalty.
                from scipy.spatial import cKDTree
                if start==0:
                    tree=cKDTree(mesh.triangles_center)
                    face_normals=source['normals'][mesh.faces].mean(1)
                    face_normals/=np.maximum(np.linalg.norm(face_normals,axis=1,keepdims=True),1e-10)
                _,candidates=tree.query(points[ix],k=min(24,len(mesh.faces)))
                if candidates.ndim==1:candidates=candidates[:,None]
                k=candidates.shape[1]
                samples=np.repeat(points[ix],k,axis=0)
                near=trimesh.triangles.closest_point(mesh.triangles[candidates.reshape(-1)],samples).reshape(-1,k,3)
                distances=np.linalg.norm(near-points[ix,None],axis=2)
                facing=np.einsum('nij,nj->ni',face_normals[candidates],normal_points[ix])
                score=distances+np.maximum(0,0.3-facing)*0.08
                pick=score.argmin(1);row=np.arange(len(ix))
                closest=near[row,pick];dist=distances[row,pick];face=candidates[row,pick]
            bary=trimesh.triangles.points_to_barycentric(mesh.triangles[face],closest)
            coords[ix]=np.einsum('ni,nij->nj',bary,source['uvs'][mesh.faces[face]])
            distance[ix]=dist
    assert np.isfinite(coords).all()
    mapping=np.zeros((size,size,2),np.float32);mapping[covered]=coords
    nearest=distance_transform_edt(~covered,return_distances=False,return_indices=True)
    return mapping[tuple(nearest)], {'median_distance':float(np.median(distance)),'p99_distance':float(np.quantile(distance,.99)),'covered_pixels':int(covered.sum())}

def sample(image,mapping):
    return Image.fromarray(np.clip(uv.sample_rgb(np.asarray(image).astype(float),mapping),0,255).astype('uint8'))

def align_surface(source,target):
    from scipy.spatial import cKDTree
    import itertools
    a=source['positions']/32; b=target['positions']
    tree=cKDTree(b);take=a[::max(1,len(a)//6000)]
    center=(b.min(0)+b.max(0))/2
    best=None
    _,pa=np.linalg.eigh(np.cov(a.T));_,pb=np.linalg.eigh(np.cov(b.T))
    for frame_a,frame_b in [(np.eye(3),np.eye(3)),(pa,pb)]:
        for perm in itertools.permutations(range(3)):
            for signs in itertools.product([-1,1],repeat=3):
                local=np.eye(3)[list(perm)]*np.array(signs)[:,None]
                matrix=frame_b@local@frame_a.T
                if np.linalg.det(matrix)>0:continue
                trial=take@matrix.T
                offset=center-(trial.min(0)+trial.max(0))/2
                dist,_=tree.query(trial+offset)
                score=np.quantile(dist,.75)
                if best is None or score<best[0]:best=(score,matrix,offset)
    _,matrix,offset=best
    for _ in range(30):
        points=take@matrix.T+offset;dist,ix=tree.query(points)
        keep=dist<np.quantile(dist,.85)
        x=points[keep];y=b[ix[keep]]
        cx=x.mean(0);cy=y.mean(0);u,_,vt=np.linalg.svd((x-cx).T@(y-cy))
        delta=vt.T@u.T
        if np.linalg.det(delta)<0:vt[-1]*=-1;delta=vt.T@u.T
        move=cy-delta@cx
        matrix=delta@matrix;offset=delta@offset+move
        if np.linalg.norm(move)<1e-7:break
    source['positions']=a@matrix.T+offset
    return {'matrix':matrix.tolist(),'offset':offset.tolist(),'method':'reflection-preserving rigid ICP; fixed 1/32 scale'}

def weapons(selected,report):
    catalog_path=ROOT/'data/weapon_skins.json'; catalog=json.loads(catalog_path.read_text())
    specs=json.loads((ROOT/'data/weapons.json').read_text())['weapons']
    for wid in sorted({s['wid'] for s in selected if s['kind']=='weapon'}):
        rows=[s for s in selected if s.get('wid')==wid];entry=catalog['weapons'][wid]
        target_path=ROOT/('assets/models/weapons/'+specs[wid]['v_model']+'.glb')
        td,tb=read_glb(target_path);sd,sb=read_glb(decode('models/viewmodels/'+rows[0]['model']+'-hd.glb'))
        source=surface(sd,sb,[m['name'] for m in sd['materials'] if m['name'] in entry['materials']] or [sd['materials'][0]['name']])
        target=surface(td,tb,entry['materials'])
        alignment={}
        original=source['positions'].copy()
        for part in np.unique(source['owners']):
            smask=source['owners']==part;tmask=target['owners']==part
            if not tmask.any() or smask.sum()<4:continue
            small={'positions':original[smask].copy()}
            alignment[part]=align_surface(small,{'positions':target['positions'][tmask]})
            source['positions'][smask]=small['positions']
        # Parts unique to Source 2 inherit the receiver frame rather than keeping inch units.
        for part in np.unique(source['owners']):
            if part in alignment:continue
            base=alignment.get('body',next(iter(alignment.values())))
            smask=source['owners']==part
            source['positions'][smask]=original[smask]/32@np.array(base['matrix']).T+base['offset']
        cached=CACHE/(wid+'-uv3.npz')
        if cached.exists():
            data=np.load(cached);mapping=data['uv'];stats=json.loads(str(data['stats']))
        else:
            mapping,stats=correspondence(target,source,512)
            stats['alignment']=alignment
            np.savez_compressed(cached,uv=mapping,stats=json.dumps(stats))
        if stats['median_distance']>.012: raise ValueError('Unaligned source geometry '+wid+str(stats))
        preserve,hardware=uv.hardware_mask(target_path,entry['materials'],512)
        default_path=ROOT/json.loads((ROOT/'data/archi_materials.json').read_text())['materials'][entry['materials'][0]]['color'].removeprefix('res://')
        default=np.array(Image.open(default_path).convert('RGB').resize((512,512)))
        entry['options']=[o for o in entry['options'] if not o['id'].startswith('cs2go_')]
        for row in rows:
            maps=painted_images(row);image=sample(next(iter(maps.values())),mapping)
            pixels=np.array(image);pixels[preserve]=default[preserve];image=Image.fromarray(pixels)
            relative=Path('assets/textures/cs2go/weapons')/wid/(row['id']+'.png');(ROOT/relative).parent.mkdir(parents=True,exist_ok=True);image.save(ROOT/relative,optimize=True)
            option={'id':'cs2go_'+row['id'],'name':entry['display_name']+' | '+row['name'],'finish':row['name'],'menu_label':row['name']+' (cs2go)','texture':'res://'+relative.as_posix(),'paint_id':row['paint'],'uv_layout':'cs2go_hd_to_current','uv_algorithm':'cs2go-hd-surface-v1','source_sha256':hashlib.sha256(fetch(PUBLIC+row['paint_path']).read_bytes()).hexdigest(),'source':SOURCE+'@'+PIN,'wear':.07,'seed':1}
            entry['options'].append(option);report['weapons'].append(dict(option,weapon=wid,uv_report=stats,hardware_preserved=hardware))
        print('WEAPON',wid,stats['median_distance'],stats['p99_distance'],flush=True)
    catalog['cs2go_batch']={'commit':PIN,'count':len(report['weapons']),'report':'res://data/cs2go_cosmetics.json','wear':.07,'seed':1,'limitations':'Offline fixed seed/wear bake, UV transfer; no WebGPU runtime or dynamic wear.'}
    catalog_path.write_text(json.dumps(catalog,indent=2,ensure_ascii=False)+'\n')


def glove_bone(name):
    name=name.split('Bip01_')[-1]
    if name.endswith('_Hand'):return 'hand_'+name[0]
    if name.endswith(('_Forearm','_ForeTwist')):return 'arm_lower_'+name[0]
    if '_Finger' in name:
        side,finger=name.split('_Finger');names=['thumb','index','middle','ring','pinky']
        return 'finger_'+names[int(finger[0])]+'_'+str(int(finger[1]) if len(finger)>1 else 0)+'_'+side
    return ''

def glove_part(name):
    bone=glove_bone(name) if 'Bip01' in name else name
    side=bone[-1:] if bone[-1:] in ['L','R'] else ('L' if '_L' in bone else 'R')
    if 'meta' in bone or 'arm_' in bone:return 'hand_'+side
    return bone

def gloves(selected,report):
    from .add_cs2_knives import matrices
    path=ROOT/'data/sport_gloves.json';catalog=json.loads(path.read_text())
    td,tb=read_glb(ROOT/'assets/models/sport_gloves/v_ak47.glb')
    sd,sb=read_glb(decode('models/gloves/5030.glb'))
    # Never merge worldmodel and viewmodel primitives: they have separate skins
    # (different joint order/bind space) but duplicate material names. The old
    # generic surface() silently interpreted both using skin 0, folding paint
    # onto unrelated fingers/palm triangles. Select one consistent bind domain.
    source_node=next(n for n in sd['nodes'] if 'viewmodel' in n.get('name','') and 'mesh' in n)
    sd['meshes']=[sd['meshes'][source_node['mesh']]]
    sd['skins']=[sd['skins'][source_node['skin']]]
    tn={n.get('name'):i for i,n in enumerate(td['nodes'])};sn={n.get('name'):i for i,n in enumerate(sd['nodes'])}
    tg=matrices(td['nodes']);sg=matrices(sd['nodes'])
    # Installed Sport vertices use native-bind matrices, not the legacy scene's
    # reference node transforms. Reconstruct their actual bind frame.
    for doc,blob,globals_ in [(td,tb,tg),(sd,sb,sg)]:
        skin=doc['skins'][0]
        inverse=_accessor(doc,blob,skin['inverseBindMatrices']).reshape(-1,4,4).transpose(0,2,1)
        for ni,bind in zip(skin['joints'],inverse):globals_[ni]=np.linalg.inv(bind.astype(float))
    paired={i:sn[glove_bone(n['name'])] for i,n in enumerate(td['nodes']) if glove_bone(n.get('name','')) in sn}
    # Infer local hand-axis conversion from corresponding finger phalanges.
    tp={c:p for p,n in enumerate(td['nodes']) for c in n.get('children',[])}
    sp={c:p for p,n in enumerate(sd['nodes']) for c in n.get('children',[])}
    a=[];b=[]
    for ti,si in paired.items():
        if 'Finger' not in td['nodes'][ti]['name'] or len(td['nodes'][ti]['name'].split('Finger')[-1])!=2:continue
        tv=(np.linalg.inv(tg[tp[ti]])@tg[ti])[:3,3];sv=(np.linalg.inv(sg[sp[si]])@sg[si])[:3,3]
        if np.linalg.norm(tv)>.00001 and np.linalg.norm(sv)>.00001:a.append(tv/np.linalg.norm(tv));b.append(sv/np.linalg.norm(sv))
    u,_,vt=np.linalg.svd(np.array(a).T@np.array(b));axis=u@vt
    if np.linalg.det(axis)<0:u[:,-1]*=-1;axis=u@vt
    joint_nodes=td['skins'][0]['joints'];mappings={};stats={}
    for mat in [m['name'] for m in td['materials']]:
        side='right' if '_l_' in mat else 'left'
        target=surface(td,tb,[mat],glove=True);canonical=[];canonical_owners=[];canonical_normals=[]
        # Sport output has one rigid owning joint per vertex, unchanged by this pass.
        matching=[p for m in td['meshes'] for p in m['primitives'] if td['materials'][p['material']]['name']==mat]
        for p in matching:
            positions=_accessor(td,tb,p['attributes']['POSITION']);normals=_accessor(td,tb,p['attributes']['NORMAL']);joints=_accessor(td,tb,p['attributes']['JOINTS_0'])[:,0]
            for v,j,normal in zip(positions,joints,normals):
                bone=joint_nodes[int(j)]
                if 'Forearm' in td['nodes'][bone]['name'] or 'ForeTwist' in td['nodes'][bone]['name']:
                    hand_name=td['nodes'][bone]['name'].replace('_Forearm','_Hand').replace('_ForeTwist','_Hand')
                    bone=tn[hand_name]
                source=paired[bone]
                local=(np.linalg.inv(tg[bone])@np.append(v,1))[:3]@axis * (0.0254 / 0.03125)
                canonical.append((sg[source]@np.append(local,1))[:3])
                local_normal=np.linalg.inv(tg[bone])[:3,:3]@normal
                canonical_normals.append(sg[source][:3,:3]@(local_normal@axis))
                canonical_owners.append(glove_part(sd['nodes'][source]['name']))
        target['positions']=np.array(canonical)
        target['owners']=np.array(canonical_owners)
        target['normals']=np.array(canonical_normals)
        target['normal_matching']=True
        source=surface(sd,sb,['glove_sporty_'+side],glove=True)
        mappings[mat],stats[mat]=correspondence(target,source,512)
        print('SPORT UV',mat,stats[mat],flush=True)
        if stats[mat]['median_distance']>.04:raise ValueError('Unaligned Sport surface '+mat+str(stats[mat]))
    catalog['options']=[o for o in catalog['options'] if not o['id'].startswith('cs2go_')]
    for row in selected:
        if row['kind']!='glove':continue
        maps=painted_images(row);textures={}
        for mat,mapping in mappings.items():
            side='right' if '_l_' in mat else 'left'
            key=next(k for k in maps if side in k)
            relative=Path('assets/textures/cs2go/gloves')/row['id']/(mat+'.png');(ROOT/relative).parent.mkdir(parents=True,exist_ok=True)
            sample(maps[key],mapping).save(ROOT/relative,optimize=True);textures[mat]='res://'+relative.as_posix()
        option={'id':'cs2go_'+row['id'],'name':row['name']+' — Minimal Wear (cs2go)','family':row['name'].split('|')[-1].strip(),'wear':'Minimal Wear','textures':textures,'source':SOURCE+'@'+PIN,'paint_id':row['paint'],'seed':1,'wear_value':.07}
        catalog['options'].append(option);report['gloves'].append(dict(id=option['id'],name=row['name'],paint_id=row['paint'],uv_report=stats))
        print('GLOVE',row['name'],flush=True)
    catalog['cs2go_batch']={'commit':PIN,'count':len(report['gloves']),'geometry':'unchanged original Sport meshes','uv_revision':'single-skin-facing-aware-512-v3','report':'res://data/cs2go_cosmetics.json'}
    path.write_text(json.dumps(catalog,indent=2,ensure_ascii=False)+'\n')

def agents(report):
    manifest={'source':SOURCE,'commit':PIN,'classes':{'sas':'sas','terror':'phoenix'},'agents':{'sas':{'team':'CT','family':'sas','name':'SAS'},'phoenix':{'team':'T','family':'phoenix','name':'Phoenix'}}}
    sockets=json.loads((ROOT/'data/modern_agent_sockets.json').read_text())
    classes=json.loads((ROOT/'data/classes.json').read_text())
    for avatar,(team,cls,model,name) in AGENTS.items():
        source=decode('models/agents/roster/'+model);doc,blob=read_glb(source)
        doc.pop('animations',None)
        roots=doc['scenes'][doc.get('scene',0)]['nodes'];doc['nodes'].append({'name':'GodotForward','rotation':[0,1,0,0],'children':roots});doc['scenes'][doc.get('scene',0)]['nodes']=[len(doc['nodes'])-1]
        target=ROOT/f'assets/models/modern/{avatar}.glb';write_glb(target,doc,blob)
        family='sas' if team=='CT' else 'phoenix';sockets[avatar]=copy.deepcopy(sockets[family]);manifest['classes'][cls]=avatar
        record={'team':team,'family':family,'class':cls,'name':name,'model':'res://assets/models/modern/'+avatar+'.glb','source':PUBLIC+'models/agents/roster/'+model,'source_sha256':hashlib.sha256(fetch(PUBLIC+'models/agents/roster/'+model).read_bytes()).hexdigest(),'sha256':hashlib.sha256(target.read_bytes()).hexdigest()}
        manifest['agents'][avatar]=record;report['agents'].append(record)
        for c in classes[team]:
            if c['id']==cls:c['name']=name;c['description']='Modern agent from cs2go; automatically selected within its faction.'
        print('AGENT',avatar,name,flush=True)
    (ROOT/'data/classes.json').write_text(json.dumps(classes,indent=2,ensure_ascii=False)+'\n')
    (ROOT/'data/modern_agents.json').write_text(json.dumps(manifest,indent=2,ensure_ascii=False)+'\n')
    (ROOT/'data/modern_agent_sockets.json').write_text(json.dumps(sockets,indent=2)+'\n')

def build():
    selected=prepare()
    report={'source':SOURCE,'commit':PIN,'wear':.07,'seed':1,'weapons':[],'gloves':[],'agents':[],'rights':'Valve/asset author rights remain separate. No general cs2go root license identified. Public access does not grant redistribution permission.','conversion':'Offline WebGPU paint compositing and geometric UV reprojection; fixed seed/wear; original runtime geometry/animations preserved.'}
    weapons(selected,report);agents(report)
    (ROOT/'data/cs2go_cosmetics.json').write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n')

if __name__=='__main__':build()
