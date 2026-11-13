"""Match dedicated arm cuff skinning to the original forearm/glove seam.
Positions, UVs, materials and animation tracks are unchanged. Only the final
12 cm of sleeve/skin weights transition to the original wrist's twist/hand mix.
"""
import hashlib
import json
from pathlib import Path
import numpy as np
from scipy.spatial import cKDTree
from .import_modern_agents import read_glb, write_glb
from .build_sport_gloves import _accessor
from .smd_converter import GlbWriter
ROOT = Path(__file__).resolve().parents[2]
VERSION = 'original-wrist-weights-v1'


def repair(path, reference_doc, reference_blob):
    doc, blob = read_glb(path)
    if doc['asset'].get('extras', {}).get('wrist_seam') == VERSION:
        return
    skin = doc['skins'][0]
    names = [doc['nodes'][n]['name'] for n in skin['joints']]
    ref_skin = reference_doc['skins'][0]
    ref_names = [reference_doc['nodes'][n]['name'] for n in ref_skin['joints']]
    matrices = _accessor(reference_doc, reference_blob, ref_skin['inverseBindMatrices']).reshape(-1, 4, 4).transpose(0, 2, 1)
    frames = {name: np.linalg.inv(m) for name, m in zip(ref_names, matrices)}
    reference = []
    for mesh in reference_doc['meshes']:
        for primitive in mesh['primitives']:
            if reference_doc['materials'][primitive['material']]['name'] == 'ct_arms.bmp':
                a = primitive['attributes']
                reference.append(tuple(_accessor(reference_doc, reference_blob, a[k]) for k in ['POSITION', 'JOINTS_0', 'WEIGHTS_0']))
    rv, rj, rw = (np.concatenate([row[i] for row in reference]) for i in range(3))
    writer = GlbWriter()
    writer.bin = bytearray(blob)
    writer.views = doc['bufferViews']
    writer.accessors = doc['accessors']
    stats = []
    for mesh in doc['meshes']:
        for primitive in mesh['primitives']:
            a = primitive['attributes']
            v = _accessor(doc, blob, a['POSITION'])
            j = _accessor(doc, blob, a['JOINTS_0']).copy()
            w = _accessor(doc, blob, a['WEIGHTS_0']).copy()
            dominant = np.array([names[k] for k in j[np.arange(len(j)), w.argmax(1)]])
            ref_dominant = np.array([ref_names[k] for k in rj[np.arange(len(rj)), rw.argmax(1)]])
            for side in ['L', 'R']:
                prefix = 'v_weapon.Bip01_' + side + '_'
                wrist = frames[prefix+'Hand'][:3, 3]
                direction = wrist - frames[prefix+'Forearm'][:3, 3]
                direction /= np.linalg.norm(direction)
                u = (v-wrist) @ direction
                ru = (rv-wrist) @ direction
                ids = np.flatnonzero(np.char.find(dominant, '_'+side+'_') >= 0)
                ids = ids[u[ids] > -.12]
                ref_ids = np.flatnonzero((np.char.find(ref_dominant, '_'+side+'_') >= 0) & (ru > -.15))
                if not len(ids):
                    continue
                distances, nearest = cKDTree(rv[ref_ids]).query(v[ids])
                nearest = ref_ids[nearest]
                for vertex, ref_vertex in zip(ids, nearest):
                    blend = np.clip((u[vertex]+.12)/.075, 0, 1)
                    blend = blend*blend*(3-2*blend)
                    weights = {}
                    for bone, weight in zip(j[vertex], w[vertex]):
                        weights[int(bone)] = weights.get(int(bone), 0) + float(weight)*(1-blend)
                    for bone, weight in zip(rj[ref_vertex], rw[ref_vertex]):
                        if weight <= 0:
                            continue
                        mapped = names.index(ref_names[int(bone)])
                        weights[mapped] = weights.get(mapped, 0) + float(weight)*blend
                    ranked = sorted(weights, key=weights.get, reverse=True)[:4]
                    total = sum(weights[k] for k in ranked)
                    j[vertex] = [ranked[k] if k < len(ranked) else 0 for k in range(4)]
                    w[vertex] = [weights[ranked[k]]/total if k < len(ranked) else 0 for k in range(4)]
                cuff = ids[u[ids] >= -.045]
                for vertex in cuff:
                    matching = sum(float(weight) for bone, weight in zip(j[vertex], w[vertex]) if names[int(bone)] in [prefix+'ForeTwist', prefix+'Hand'])
                    assert matching > .999, (path, side, vertex, matching)
                stats.append({'side': side, 'transition_vertices': len(ids), 'cuff_vertices': len(cuff), 'nearest_reference_max_m': float(max(distances))})
            a['JOINTS_0'] = writer.acc(j.astype('<u2'), 5123, 'VEC4', 34962)
            a['WEIGHTS_0'] = writer.acc(w.astype('<f4'), 5126, 'VEC4', 34962)
    doc['asset'].setdefault('extras', {})['wrist_seam'] = VERSION
    doc['asset']['extras']['wrist_seam_stats'] = stats
    write_glb(path, doc, writer.bin)


def main():
    reference_doc, reference_blob = read_glb(ROOT/'assets/models/weapons/v_ak47.glb')
    catalog_path = ROOT/'data/agent_view_arms.json'
    catalog = json.loads(catalog_path.read_text())
    for avatar, definition in catalog['agents'].items():
        path = ROOT/definition['model'].removeprefix('res://')
        repair(path, reference_doc, reference_blob)
        definition['sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
        definition['wrist_seam'] = VERSION
        print('Wrist seam:', avatar)
    catalog_path.write_text(json.dumps(catalog, separators=(',', ':'))+'\n')

if __name__ == '__main__':
    main()
