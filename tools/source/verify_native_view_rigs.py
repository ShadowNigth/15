"""Check imported native assets against decoded pinned source, not legacy rigs.
Run after build_native_view_rigs (cached source required; build-time network only).
"""
import hashlib, json
import numpy as np
from .expand_cs2go_cosmetics import decode, ROOT
from .import_modern_agents import read_glb
from .build_sport_gloves import _accessor

def primitive_table(doc, blob):
    result={}
    for node in doc['nodes']:
        if 'mesh' not in node: continue
        for primitive in doc['meshes'][node['mesh']]['primitives']:
            key=(node['name'], doc['materials'][primitive['material']]['name'])
            arrays={name:_accessor(doc,blob,index) for name,index in primitive['attributes'].items()}
            arrays['indices']=_accessor(doc,blob,primitive['indices'])
            skin=doc['skins'][node['skin']]
            names=[doc['nodes'][index]['name'] for index in skin['joints']]
            arrays['binds']=_accessor(doc,blob,skin['inverseBindMatrices'])
            result[key]=(arrays,names)
    return result

def main():
    report=json.loads((ROOT/'data/native_view_rigs.json').read_text())
    count=0
    for key,entry in {**report['agents'],**report['gloves']}.items():
        sd,sb=read_glb(decode('models/'+entry['source']+'.glb'))
        target=ROOT/entry['model'][6:]
        assert hashlib.sha256(target.read_bytes()).hexdigest()==entry['sha256']
        td,tb=read_glb(target)
        original=primitive_table(sd,sb)
        imported=primitive_table(td,tb)
        assert imported
        for name,(arrays,bones) in imported.items():
            source_arrays,source_bones=original[name]
            assert bones==source_bones,(key,name,'bone names/order')
            assert set(source_arrays)-set(arrays) <= {"TEXCOORD_1"} # unused secondary UV may be pruned
            for attribute,array in arrays.items():
                assert np.array_equal(array,source_arrays[attribute]),(key,name,attribute)
                count+=1
        for model,drivers in entry['drivers'].items():
            for name,(arrays,bones) in imported.items():
                weights=arrays['WEIGHTS_0'];joints=arrays['JOINTS_0']
                used={bones[int(i)] for i in np.unique(joints[weights>1e-5])}
                assert used.issubset(drivers),(key,model,used-set(drivers))
        print('NATIVE SOURCE IDENTICAL',key,len(imported),'primitives')
    print('PASS:',count,'native attribute/index/inverse-bind arrays identical to source; all weighted bones mapped across all weapon rigs')
if __name__=='__main__': main()
