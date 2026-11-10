#!/usr/bin/env python3
"""Retarget existing classic reactions/deaths to modern proportions, offline.
No new upstream assets. Global rotation deltas avoid copying incompatible local
bone axes, translations or classic limb lengths. Native locomotion stays intact.
"""
import json
import hashlib
from pathlib import Path
import numpy as np
from scipy.spatial.transform import Rotation, Slerp
from tools.source.import_modern_agents import read_glb, write_glb
from tools.source.add_cs2_knives import original_pose, matrices, append_array
from tools.source.build_sport_gloves import _accessor
ROOT = Path(__file__).resolve().parents[2]
BONES = {'pelvis':'Pelvis','spine_0':'Spine','spine_1':'Spine1','spine_2':'Spine2',
         'spine_3':'Spine3','neck_0':'Neck','head_0':'Head'}
for side in ['L','R']:
    for modern,classic in [('clavicle','Clavicle'),('arm_upper','UpperArm'),('arm_lower','Forearm'),
                           ('hand','Hand'),('leg_upper','Thigh'),('leg_lower','Calf'),('ankle','Foot')]:
        BONES[modern+'_'+side] = side+' '+classic
CLIPS = ['death1','death2','death3','head','gutshot','left','back','right','forward','crouch_die','head_flinch','gut_flinch']

def rot(matrix):
    basis = matrix[:3,:3]
    return basis / np.linalg.norm(basis,axis=0)

def sample(doc, blob, clip, time):
    override = {}
    for channel in clip['channels']:
        sampler = clip['samplers'][channel['sampler']]
        times = _accessor(doc,blob,sampler['input']).ravel()
        values = _accessor(doc,blob,sampler['output'])
        t = float(np.clip(time,times[0],times[-1]))
        path = channel['target']['path']
        if len(times) == 1:
            value = values[0]
        elif path == 'rotation':
            value = Slerp(times,Rotation.from_quat(values))(t).as_quat()
        else:
            value = np.array([np.interp(t,times,values[:,i]) for i in range(values.shape[1])])
        override.setdefault(channel['target']['node'],{})[path] = value.tolist()
    return matrices(doc['nodes'],override)

def refine():
    sockets = json.loads((ROOT/'data/modern_agent_sockets.json').read_text())
    report = json.loads((ROOT/'data/modern_agents_import.json').read_text())
    for avatar,classic in [('sas','urban'),('phoenix','terror')]:
        path = ROOT/f'assets/models/modern/{avatar}.glb'
        target,blob = read_glb(path)
        source,srcblob = read_glb(ROOT/f'assets/models/players/{classic}.glb')
        names = {n.get('name'):i for i,n in enumerate(target['nodes'])}
        srcnames = {n.get('name'):i for i,n in enumerate(source['nodes'])}
        mapping = {names[k]:srcnames['Bip01 '+v] for k,v in BONES.items() if k in names and 'Bip01 '+v in srcnames}
        parents = {c:p for p,n in enumerate(target['nodes']) for c in n.get('children',[])}
        neutral = original_pose(target,blob,'ref_aim_carbine')
        srcneutral = original_pose(source,srcblob,'idle1')
        facing=Rotation.from_euler('y',90,degrees=True).as_matrix()
        target['animations'] = [a for a in target['animations'] if a['name'] not in CLIPS]
        for clip_name in CLIPS:
            clip = next(a for a in source['animations'] if a['name']==clip_name)
            duration = max(float(_accessor(source,srcblob,s['input']).max()) for s in clip['samplers'])
            times = np.linspace(0,duration,max(2,int(duration*24)+1))
            rotations = {n:[] for n in mapping}
            pelvis_positions = []
            for time in times:
                poses = sample(source,srcblob,clip,time)
                wanted = {n:facing @ rot(poses[s]) @ rot(srcneutral[s]).T @ facing.T @ rot(neutral[n]) for n,s in mapping.items()}
                global_rot = {}
                def get(n):
                    if n not in global_rot:
                        if n in wanted:
                            global_rot[n]=wanted[n]
                        elif n in parents:
                            global_rot[n]=get(parents[n]) @ (rot(neutral[parents[n]]).T @ rot(neutral[n]))
                        else:
                            global_rot[n]=rot(neutral[n])
                    return global_rot[n]
                for n in mapping:
                    parent = get(parents[n]) if n in parents else np.eye(3)
                    q = Rotation.from_matrix(parent.T @ get(n)).as_quat()
                    if rotations[n] and np.dot(q,rotations[n][-1])<0:q=-q
                    rotations[n].append(q)
                p=names['pelvis']; s=mapping[p]
                # Only root-of-body translation is retargeted, never limb lengths.
                delta=facing@(poses[s][:3,3]-srcneutral[s][:3,3])
                if clip_name=='crouch_die': delta[1] -= 0.5625
                value=(np.linalg.inv(neutral[parents[p]]) @ np.append(neutral[p][:3,3]+delta,1))[:3]
                pelvis_positions.append(value)
            animation={'name':clip_name,'samplers':[],'channels':[]}
            ti=append_array(target,blob,times,'SCALAR')
            for n,values in rotations.items():
                si=len(animation['samplers'])
                animation['samplers'].append({'input':ti,'output':append_array(target,blob,values,'VEC4'),'interpolation':'LINEAR'})
                animation['channels'].append({'sampler':si,'target':{'node':n,'path':'rotation'}})
            animation['samplers'].append({'input':ti,'output':append_array(target,blob,pelvis_positions,'VEC3'),'interpolation':'LINEAR'})
            animation['channels'].append({'sampler':len(animation['samplers'])-1,'target':{'node':names['pelvis'],'path':'translation'}})
            target['animations'].append(animation)
        weapons=json.loads((ROOT/'data/weapons.json').read_text())['weapons']
        facing=Rotation.from_euler('y',90,degrees=True).as_matrix()
        for wid,entry in sockets[avatar].items():
            spec=weapons[wid]
            ext='dualpistols' if wid=='elite' else 'onehanded' if spec.get('slot')==2 else 'knife' if wid=='knife' else 'ak47' if wid=='ak47' else 'carbine'
            srcpose=original_pose(source,srcblob,'ref_aim_'+ext)
            pose=original_pose(target,blob,entry['clips']['idle'])
            r=pose[names['hand_R']]; l=pose[names['hand_L']]
            oldr=srcpose[srcnames['Bip01 R Hand']]; oldl=srcpose[srcnames['Bip01 L Hand']]
            entry['basis']=(np.linalg.inv(r[:3,:3])@facing@oldr[:3,:3]).tolist()
            entry['support']=(np.linalg.inv(r[:3,:3])@facing@(oldl[:3,3]-oldr[:3,3])).tolist()
            entry['support_rotation']=Rotation.from_matrix(rot(r).T@rot(l)).as_quat().tolist()
        write_glb(path,target,blob)
        for m in report['models']:
            if m['name']==avatar:
                m['output_sha256']=hashlib.sha256(path.read_bytes()).hexdigest()
                m['clips']=len(target['animations'])
                m['retargeted_classic_reactions']=CLIPS
        print(avatar,len(target['animations']),'clips; retargeted',len(CLIPS))
    (ROOT/'data/modern_agent_sockets.json').write_text(json.dumps(sockets,indent=2)+'\n')
    (ROOT/'data/modern_agents_import.json').write_text(json.dumps(report,indent=2)+'\n')
if __name__=='__main__': refine()
