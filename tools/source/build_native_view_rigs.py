"""Import untouched cs2go first-person geometry, skins and bone hierarchies.
Only select meshgroups, decode textures, and serialize animation adapters.
No vertex retargeting, cuff generation, reweighting or bone renaming.
"""
import copy, hashlib, json, subprocess
import numpy as np
from .build_agent_view_arms import SOURCES, frame, target_frames, native
from .expand_cs2go_cosmetics import decode, ROOT, PIN
from .import_modern_agents import read_glb, write_glb
from .import_smoke_out import bone_transform

OUT = ROOT / 'assets/models/native_view'

def export(key, path, glove=False):
    doc, blob = read_glb(decode('models/'+path+'.glb'))
    original = copy.deepcopy(doc)
    chosen=[]
    for i,node in enumerate(doc['nodes']):
        if 'mesh' not in node: continue
        name=node.get('name','')
        keep=('viewmodel' in name) if glove else name.startswith(('agent_hands_', 'agent_sleeves_'))
        if key == 'leet' and name.startswith('agent_sleeves_'):
            keep=False # Native Leet sleeve group is torso/neck clothing, not bare arms.
        if keep:
            chosen.append(i)
        else:
            node.pop('mesh',None);node.pop('skin',None)
    # Preserve original native inverse binds, nodes, JOINTS and WEIGHTS.
    doc.pop('animations',None)
    doc['asset']['generator']='cs2go native skeleton; source geometry and weights retained'
    output=OUT/(key+'.glb')
    write_glb(output,doc,blob)
    subprocess.run(['node','tools/source/modern_agents/prune.mjs',str(output)],check=True,cwd=ROOT)
    source_frames={}
    for index in chosen:
        source_frames.update(frame(original,blob,original['nodes'][index]['skin']))
    result={'model':'res://'+output.relative_to(ROOT).as_posix(),'source':path,'sha256':hashlib.sha256(output.read_bytes()).hexdigest(),'drivers':{}}
    models=json.loads((ROOT/'data/agent_view_arms.json').read_text())['targets']
    for model in models:
        td,tb=read_glb(ROOT/f'assets/models/weapons/{model}.glb')
        tf=target_frames(td,tb)
        names={native(n):n for n in frame(td,tb,0) if native(n)}
        drivers={}
        for name,rest in source_frames.items():
            mapped=name
            reference=name
            if name.startswith('attachHand_'):
                reference='hand_'+name[-1]
                mapped=reference
            if '_TWIST' in name and name.startswith('arm_'):
                reference=name.split('_TWIST')[0]
                mapped=reference
            if name.startswith('scapula_'):
                mapped='arm_upper_'+name[-1]
                reference=mapped
            if mapped not in tf:
                side=reference[-1]
                if side not in ['L','R']: continue
                if name.startswith('finger_') and '_meta_' in name:
                    mapped='hand_'+side
                elif name.startswith(('arm_','clavicle_')):
                    mapped='arm_lower_'+side
                else: continue
            x=bone_transform(source_frames,tf,reference,mapped)
            correction=np.linalg.inv(tf[mapped]) @ x @ rest
            drivers[name]={'target':names[mapped],'correction':correction[:3,:].reshape(-1).tolist()}
        result['drivers'][model]=drivers
    return result

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    report={'commit':PIN,'mode':'native-skeleton-v1','agents':{},'gloves':{}}
    for avatar,path in SOURCES.items():
        report['agents'][avatar]=export(avatar,path)
        print('NATIVE',avatar,flush=True)
    report['gloves']['moto_smoke_out']=export('moto_smoke_out','gloves/5033',True)
    (ROOT/'data/native_view_rigs.json').write_text(json.dumps(report,separators=(',',':'))+'\n')
if __name__=='__main__': main()
