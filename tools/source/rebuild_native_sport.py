"""Rebuild Sport from the upstream view mesh, using anatomical frames, not bone roll.
No opposite-hand mapping, reflection, or post-import palm correction is used.
"""
import json
import numpy as np
from . import build_agent_view_arms as arms
from .import_modern_agents import read_glb

def anatomical(frames, name):
    side = name[-1]
    wrist = frames['hand_'+side][:3, 3]
    index = frames['finger_index_0_'+side][:3, 3]
    pinky = frames['finger_pinky_0_'+side][:3, 3]
    middle = frames['finger_middle_0_'+side][:3, 3]
    origin = frames[name][:3, 3]
    along = middle-wrist
    if name.startswith('finger_'):
        parts = name.split('_')
        segment = parts[-2]
        if segment.isdigit():
            step = int(segment)
            child = '_'.join(parts[:-2]+[str(step+1), side])
            parent = '_'.join(parts[:-2]+[str(step-1), side])
            if child in frames: along = frames[child][:3,3]-origin
            elif parent in frames: along = origin-frames[parent][:3,3]
    y = along/np.linalg.norm(along)
    x = index-pinky
    x -= y*np.dot(x,y)
    x /= np.linalg.norm(x)
    result = np.eye(4)
    result[:3,:3] = np.column_stack([x,y,np.cross(x,y)])
    result[:3,3] = origin
    return result

def main():
    td,tb=read_glb(arms.ROOT/'assets/models/weapons/v_ak47.glb')
    def calibration(source, target):
        side=next(n[-1] for n in source if n.startswith('hand_'))
        key='hand_'+side
        # Compare complete palm bases in each wrist's LOCAL coordinates.
        # The resulting constant basis converts the exporter conventions for
        # all joints; per-finger world frames would fold the weighted mesh.
        a=np.linalg.inv(source[key]) @ anatomical(source,key)
        b=np.linalg.inv(target[key]) @ anatomical(target,key)
        result=np.eye(4)
        result[:3,:3]=b[:3,:3] @ a[:3,:3].T
        return result
    original_axis=arms.axis_between
    arms.axis_between=calibration
    report=json.loads((arms.ROOT/'data/agent_view_arms.json').read_text())
    report['agents']['sport']=arms.build('sport','gloves/5030',td,tb)
    arms.axis_between=original_axis
    path=arms.OUT/'sport.glb'
    import hashlib
    report['agents']['sport']['sha256']=hashlib.sha256(path.read_bytes()).hexdigest()
    report['agents']['sport']['retarget']='anatomical-same-side-v3'
    (arms.ROOT/'data/agent_view_arms.json').write_text(json.dumps(report,separators=(',',':'))+'\n')
if __name__=='__main__': main()
