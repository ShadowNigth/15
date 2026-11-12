"""Restore the omitted native C4 LCD without replacing its body/animations.

Run: python -m tools.source.restore_c4_display /path/c4.cs2.skin /path/c4_visuals.json
Inputs: zh667/ScCsgoKnives @ fd1082b388c0274132181ab2621520819a48a12c,
src/ScCsgoKnives/AnimationData/. The separately imported atlas is
Assets/Textures/ScCsgoKnives/weapon_c4_digits.png, Git blob
51acd2b5e79f5298083c2833adb85aa1e051d150. Original art terms apply.

UV correspondences identify the same C4 body across native/archi bind spaces.
A rigid orthogonal fit includes the existing model's handedness reflection;
it does not reshape the C4 or change any of its skeletal animation tracks.
"""
import json
import sys
from pathlib import Path
import numpy as np
from scipy.spatial import cKDTree
from .add_cs2_knives import read_skin
from .import_modern_agents import read_glb
from .build_sport_gloves import _accessor

ROOT = Path(__file__).resolve().parents[2]
PIN = "fd1082b388c0274132181ab2621520819a48a12c"

def main(skin_path, visuals_path):
    vertices, _, _, parts = read_skin(Path(skin_path))
    document, binary = read_glb(ROOT / "assets/models/weapons/v_c4.glb")
    body = next(p for m in document['meshes'] for p in m['primitives']
                if document['materials'][p['material']]['name'] == 'weapon_c4')
    positions = _accessor(document, binary, body['attributes']['POSITION'])
    uv = _accessor(document, binary, body['attributes']['TEXCOORD_0'])
    source_ids = np.unique(next(i for name, i in parts if name == 'weapon_c4'))
    distance, matches = cKDTree(uv).query(vertices['uv'][source_ids])
    mask = distance < 0.0001
    source = vertices['p'][source_ids][mask] / 32.0
    target = positions[matches[mask]]
    source_center, target_center = source.mean(0), target.mean(0)
    u, _, vt = np.linalg.svd((source-source_center).T @ (target-target_center))
    rotation = vt.T @ u.T
    offset = target_center - source_center @ rotation.T
    error = np.linalg.norm(source @ rotation.T + offset - target, axis=1)
    p95 = float(np.percentile(error, 95))
    if p95 >= 0.00001:
        raise ValueError('C4 bind-space fit no longer matches installed body: ' + str(p95))
    screen = next(i for name, i in parts if name == 'weapon_c4_digits')
    ids, indices = np.unique(screen, return_inverse=True)
    normals = vertices['n'][ids] @ rotation.T
    points = vertices['p'][ids] / 32.0 @ rotation.T + offset + normals * 0.00025
    data = {
        'source': 'https://github.com/zh667/ScCsgoKnives', 'commit': PIN,
        'source_skin': 'src/ScCsgoKnives/AnimationData/c4.cs2.skin',
        'source_visuals': 'src/ScCsgoKnives/AnimationData/c4_visuals.json',
        'fit_p95_m': p95, 'positions': points.round(8).tolist(),
        'normals': normals.round(8).tolist(), 'uv': vertices['uv'][ids].round(8).tolist(),
        'indices': indices.tolist(), 'digits': json.loads(Path(visuals_path).read_text())['Digits'],
        'texture': 'res://assets/textures/archi/c4_digits.png',
    }
    (ROOT / 'data/c4_display.json').write_text(json.dumps(data, indent=2) + '\n')
    print('C4 screen restored:', len(ids), 'vertices;', p95, 'metre p95 fit')

if __name__ == '__main__':
    main(*sys.argv[1:])
