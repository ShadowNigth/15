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
    # The shared importer only handles UV/material preservation and GLB writing.
    # Replace its bone-roll calibration for this one fresh mesh build.
    original_frame = arms.frame
    td,tb=read_glb(arms.ROOT/'assets/models/weapons/v_ak47.glb')
    # Build a fresh source using explicit anatomical bind matrices on both rigs.
    def frames(doc, blob, skin):
        raw = original_frame(doc,blob,skin)
        # Source has native names; destination is translated by target_frames.
        native = {arms.native(n) or n:m for n,m in raw.items()}
        result={}
        for n,m in raw.items():
            key=arms.native(n) or n
            if key.endswith(('_L','_R')) and key in native and ('hand_'+key[-1]) in native:
                result[n]=anatomical(native,key)
            else: result[n]=m
        return result
    arms.frame=frames
    # Anatomical bases are already aligned: only the documented unit scale remains.
    arms.axis_between=lambda a,b:np.eye(4)
    report=json.loads((arms.ROOT/'data/agent_view_arms.json').read_text())
    report['agents']['sport']=arms.build('sport','gloves/5030',td,tb)
    # Output skin must retain the real target bind, not the calibration frames.
    from .import_modern_agents import write_glb
    from .smd_converter import GlbWriter
    path=arms.OUT/'sport.glb'
    doc,blob=read_glb(path)
    actual=original_frame(td,tb,0)
    skin=doc['skins'][0]
    inv=np.array([np.linalg.inv(actual[td['nodes'][i]['name']]).T for i in skin['joints']],dtype='<f4')
    writer=GlbWriter();writer.bin=bytearray(blob);writer.views=doc['bufferViews'];writer.accessors=doc['accessors']
    skin['inverseBindMatrices']=writer.acc(inv.reshape(-1,16),5126,'MAT4')
    doc['asset']['generator']='Sport rebuild: anatomical same-side retarget, native UV'
    write_glb(path,doc,writer.bin)
    import hashlib
    report['agents']['sport']['sha256']=hashlib.sha256(path.read_bytes()).hexdigest()
    report['agents']['sport']['retarget']='anatomical-same-side-v3'
    (arms.ROOT/'data/agent_view_arms.json').write_text(json.dumps(report,separators=(',',':'))+'\n')
if __name__=='__main__': main()
