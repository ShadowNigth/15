"""User-requested Smoke Out left/right texture exchange and palm/back reversal.
Repaint atlases via the opposite native hand surface, without editing mesh UVs,
geometry, bones or animations. A flat atlas flip would scramble UV islands.
"""
import json
from pathlib import Path
import numpy as np
import trimesh
from PIL import Image
from scipy.ndimage import distance_transform_edt
from .glb_read import load, acc
from .import_smoke_out import anatomical
from .weapon_skin_reprojection import _raster_surface, sample_rgb
ROOT=Path(__file__).resolve().parents[2]


def normalize(v):
    return v/np.maximum(np.linalg.norm(v,axis=-1,keepdims=True),1e-12)


def tangent_frames(surface):
    f=surface['faces'];p=surface['positions'][f];uv=surface['uvs'][f]
    e1=p[:,1]-p[:,0];e2=p[:,2]-p[:,0]
    d1=uv[:,1]-uv[:,0];d2=uv[:,2]-uv[:,0]
    det=d1[:,0]*d2[:,1]-d1[:,1]*d2[:,0]
    safe=np.where(abs(det)>1e-12,det,1)
    n=normalize(surface['normals'][f].mean(1))
    t=(e1*d2[:,1,None]-e2*d1[:,1,None])/safe[:,None]
    t=normalize(t-n*(t*n).sum(1)[:,None])
    b=normalize(np.cross(n,t))*np.where(det>=0,1,-1)[:,None]
    return np.stack([t,b,n],axis=2)


def main():
    doc,blob=load(ROOT/'assets/models/native_view/moto_smoke_out.glb')
    node=next(n for n in doc['nodes'] if 'mesh' in n)
    skin=doc['skins'][node['skin']]
    ib=acc(doc,blob,skin['inverseBindMatrices']).reshape(-1,4,4).transpose(0,2,1)
    rests={doc['nodes'][i]['name']:np.linalg.inv(m) for i,m in zip(skin['joints'],ib)}
    surfaces={};bases={};origins={}
    for side,letter in [('left','L'),('right','R')]:
        origin=rests['hand_'+letter][:3,3]
        y=normalize(rests['finger_middle_0_'+letter][:3,3]-origin)
        x=rests['finger_index_0_'+letter][:3,3]-rests['finger_pinky_0_'+letter][:3,3]
        x=normalize(x-y*np.dot(x,y));basis=np.column_stack([x,y,np.cross(x,y)])
        p=next(p for p in doc['meshes'][node['mesh']]['primitives'] if doc['materials'][p['material']]['name']=='glove_motorcycle_'+side)
        a=p['attributes']
        surfaces[side]={'positions':(acc(doc,blob,a['POSITION'])-origin)@basis,'uvs':acc(doc,blob,a['TEXCOORD_0']),'faces':acc(doc,blob,p['indices']).reshape(-1,3),'normals':acc(doc,blob,a['NORMAL'])@basis}
        surfaces[side]['joints']=acc(doc,blob,a['JOINTS_0'])
        surfaces[side]['weights']=acc(doc,blob,a['WEIGHTS_0'])
        bases[side]=basis;origins[side]=origin
    # Flatten each finger around its own articulated chain before exchanging
    # sides. A single wrist rotation would project bent fingertips onto the
    # palm and smear them; the native left/right bind poses are not identical.
    joint_names=[doc['nodes'][i]['name'] for i in skin['joints']]
    def canonical(name):
        side='left' if '_L' in name else 'right'
        letter='L' if side=='left' else 'R'
        ref=name.split('_TWIST')[0]
        if ref.startswith('attachHand_'): ref='hand_'+letter
        local=(rests[ref][:3,3]-origins[side])@bases[side]
        point=np.array([local[0],local[1],0.],float)
        direction=np.array([0.,1.,0.])
        if ref.startswith('finger_'):
            parts=ref.split('_');finger=parts[1];segment=parts[2]
            base='finger_'+finger+'_0_'+letter
            base_local=(rests[base][:3,3]-origins[side])@bases[side]
            direction=normalize(np.array([.8,.6,0.])) if finger=='thumb' else direction
            point=np.array([base_local[0],np.linalg.norm(rests[base][:3,3]-origins[side]),0.])
            if segment.isdigit():
                for step in range(int(segment)):
                    a=rests[f'finger_{finger}_{step}_{letter}'][:3,3]
                    b=rests[f'finger_{finger}_{step+1}_{letter}'][:3,3]
                    point+=direction*np.linalg.norm(b-a)
            else:
                point=np.array([local[0],local[1],0.])
        x=normalize(np.array([1.,0.,0.])-direction*direction[0])
        flat=np.eye(4);flat[:3,:3]=np.column_stack([x,direction,np.cross(x,direction)]);flat[:3,3]=point
        return flat@np.linalg.inv(anatomical(rests,ref))
    for side,surface in surfaces.items():
        # Undo the preliminary palm frame: canonical() consumes source bind space.
        positions=surface['positions']@bases[side].T+origins[side]
        normals=surface['normals']@bases[side].T
        flat_positions=np.zeros_like(positions);flat_normals=np.zeros_like(normals)
        for column in range(4):
            for bind in np.unique(surface['joints'][:,column]):
                mask=(surface['joints'][:,column]==bind)&(surface['weights'][:,column]>1e-7)
                if not mask.any():continue
                transform=canonical(joint_names[int(bind)])
                weights=surface['weights'][mask,column,None]
                flat_positions[mask]+=(positions[mask]@transform[:3,:3].T+transform[:3,3])*weights
                flat_normals[mask]+=(normals[mask]@transform[:3,:3].T)*weights
        surface['positions']=flat_positions;surface['normals']=normalize(flat_normals)
    original=ROOT/'assets/textures/moto_smoke_out'
    output=ROOT/'assets/textures/moto_smoke_out_swapped';output.mkdir(parents=True,exist_ok=True)
    report={'mode':'opposite-hand-palm-back-v1','mesh_edited':False,'hands':{}}
    textures={};maps={}
    for side,other in [('left','right'),('right','left')]:
        target=surfaces[side];source=surfaces[other]
        positions,face_ids=_raster_surface(target,1024)
        covered=face_ids>=0
        points=positions[covered]
        mesh=trimesh.Trimesh(vertices=source['positions'],faces=source['faces'],process=False)
        uv=np.zeros((len(points),2));source_face=np.zeros(len(points),int);distances=np.zeros(len(points))
        for start in range(0,len(points),4096):
            sl=slice(start,start+4096)
            closest,distance,face=trimesh.proximity.closest_point(mesh,points[sl])
            bary=trimesh.triangles.points_to_barycentric(mesh.triangles[face],closest)
            uv[sl]=np.einsum('ni,nij->nj',bary,source['uvs'][source['faces'][face]])
            source_face[sl]=face;distances[sl]=distance
        # Anatomical index-to-pinky axes reverse the palm normal between left
        # and right hands. Equal coordinates therefore exchange palm and back,
        # rather than merely mirroring the writing in the flat image.
        source_tbn=tangent_frames(source)[source_face]
        target_tbn=tangent_frames(target)[face_ids[covered]]
        nearest=distance_transform_edt(~covered,return_distances=False,return_indices=True)
        name='glove_motorcycle_'+side
        for suffix in ['', '_normal', '_orm']:
            src=np.asarray(Image.open(original/('glove_motorcycle_'+other+suffix+'.webp')).convert('RGB'))
            values=sample_rgb(src,uv).astype(float)
            if suffix=='_normal':
                local=normalize(values/127.5-1)-np.array([0,0,1])
                delta=np.einsum('nij,nj->ni',source_tbn,local)
                local=normalize(np.einsum('nji,nj->ni',target_tbn,delta)+np.array([0,0,1]))
                values=(local+1)*127.5
            image=np.zeros((1024,1024,3),np.uint8)
            image[covered]=np.clip(np.rint(values),0,255).astype('uint8')
            image[~covered]=image[tuple(nearest[:,~covered])]
            path=output/(name+suffix+'.webp');Image.fromarray(image).save(path,format='WEBP',lossless=True)
            resource='res://'+path.relative_to(ROOT).as_posix()
            if suffix=='':textures[name]=resource
            else:maps.setdefault(name,{})['normal' if suffix=='_normal' else 'orm']=resource
        report['hands'][side]={'source_texture_hand':other,'palm_back_reversed':True,'covered_texels':int(covered.sum()),'distance_p50_m':float(np.median(distances)),'distance_p99_m':float(np.percentile(distances,99))}
        print(side,'<-',other,report['hands'][side],flush=True)
    path=ROOT/'data/sport_gloves.json';catalog=json.loads(path.read_text())
    option=next(o for o in catalog['options'] if o['id']=='5033_10078')
    option.update(native_textures=textures,native_maps=maps,texture_layout=report['mode'])
    path.write_text(json.dumps(catalog,indent=2)+'\n')
    # Keep the historical installer consistent, without changing any other finish.
    path=ROOT/'data/agent_view_arms.json';catalog=json.loads(path.read_text())
    catalog['gloves']['moto_smoke_out'].update(textures=textures,native_maps=maps)
    path.write_text(json.dumps(catalog,separators=(',',':'))+'\n')
    (output/'mapping.json').write_text(json.dumps(report,indent=2)+'\n')
if __name__=='__main__':main()
