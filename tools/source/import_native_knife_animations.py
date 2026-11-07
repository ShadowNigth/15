#!/usr/bin/env python3
"""Import each shipped CS2 knife's full pose, not Kukri clips or idle-grip fits.

Usage: PYTHONPATH=<numpy,scipy> python -m tools.source.import_native_knife_animations SOURCE_DIRECTORY
SOURCE_DIRECTORY contains the pinned *.cs2.skin and *.cs2.animation.json files.
Original arm/glove geometry, UVs, weights and bind matrices are preserved.
Their anatomical joints follow native hand/finger poses after local-axis conversion.
Knife vertices retain the source skin weights and inverse binds, including both
Shadow Daggers. All available native inspection variants are imported separately.
"""
import copy
import hashlib
import json
import sys
from pathlib import Path

import numpy as np
from scipy.spatial.transform import Rotation, Slerp

from . import add_cs2_knives as base
from .build_sport_gloves import _accessor
from .expand_cs2_catalog import NAMES

ROOT = base.ROOT
C = np.eye(4)
C[:3, :3] = np.array([[0, -1, 0], [0, 0, 1], [-1, 0, 0]]) * 0.0254
CI = np.linalg.inv(C)
AXIS = C[:3, :3] / 0.0254
ALIASES = dict(deploy='draw', deploy2='draw_2', slashHit1='midslash1', slashHit2='midslash2', stab='stab_miss', stabHit='stab', inspect2='inspect_2', inspect3='inspect_3')


def correspondence(name):
    if not name.startswith('v_weapon.Bip01_'):
        return None
    side, suffix = name.removeprefix('v_weapon.Bip01_').split('_', 1)
    if suffix in ['Forearm', 'ForeTwist']:
        return 'arm_lower_' + side
    if suffix == 'Hand':
        return 'hand_' + side
    if suffix.startswith('Finger'):
        digits = suffix.removeprefix('Finger')
        finger = ['thumb', 'index', 'middle', 'ring', 'pinky'][int(digits[0])]
        return 'finger_%s_%d_%s' % (finger, int(digits[1]) if len(digits) > 1 else 0, side)
    raise ValueError(name)


def source_nodes(animation):
    return [dict(name=b['Name'], translation=b['Translation'], rotation=b['Rotation'], scale=b['Scale'], children=b['Children']) for b in animation['Skeleton']]


def axis_calibration(original, source, source_bind, old_bind):
    """Recover per-hand local axes from matching anatomical joint directions.

    The installed ports advance phalanges on local +Z; the native CS2 rig uses
    local +X on the left and -X on the right. Copying quaternion components is
    therefore wrong. Finger bases include the native metacarpal transforms.
    """
    parents = {c:i for i,n in enumerate(original['nodes']) for c in n.get('children', [])}
    idx = {n['name']:i for i,n in enumerate(source)}
    result = {}
    errors = {}
    for side in ['L', 'R']:
        old, new = [], []
        for i, node in enumerate(original['nodes']):
            mapped = correspondence(node['name'])
            parent = parents.get(i)
            if mapped is None or parent is None or ('Bip01_' + side + '_') not in node['name']:
                continue
            mp = correspondence(original['nodes'][parent]['name'])
            if mp is None or node['name'].endswith('ForeTwist'):
                continue
            a = (np.linalg.inv(old_bind[parent]) @ old_bind[i])[:3, 3]
            b = (np.linalg.inv(source_bind[idx[mp]]) @ source_bind[idx[mapped]])[:3, 3]
            if min(np.linalg.norm(a), np.linalg.norm(b)) < 1e-6:
                continue
            old.append(a / np.linalg.norm(a)); new.append(b / np.linalg.norm(b))
        assert len(old) >= 15
        u, _, vt = np.linalg.svd(np.array(old).T @ np.array(new))
        # The original port reflected local mesh coordinates. Recover parity
        # as well as axes; forcing det +1 turns an anatomical hand inside out.
        result[side] = (u @ vt).T
        errors[side] = float(np.degrees(np.arccos(np.clip(np.sum((np.array(old) @ result[side].T) * new, axis=1), -1, 1))).max())
    return result, errors


def decompose(matrices):
    matrices = np.asarray(matrices)
    basis = matrices[:, :3, :3]
    scales = np.linalg.norm(basis, axis=1)
    scales[np.linalg.det(basis) < 0, 0] *= -1
    rotations = basis / scales[:, None, :]
    assert np.allclose(np.transpose(rotations, (0,2,1)) @ rotations, np.eye(3), atol=1e-5)
    return matrices[:, :3, 3], Rotation.from_matrix(rotations).as_quat(), scales



def sample_poses(nodes, clip, times):
    overrides = [{} for _ in times]
    for i, node in enumerate(nodes):
        for path, track in clip['Bones'].get(node['name'], {}).items():
            if path not in ['Translation', 'Rotation', 'Scale']:
                continue
            tt, vv = np.array(track['Times']), np.array(track['Values'])
            at = np.clip(times, tt[0], tt[-1])
            if len(tt) == 1:
                values = np.repeat(vv, len(times), axis=0)
            elif path == 'Rotation':
                values = Slerp(tt, Rotation.from_quat(vv))(at).as_quat()
            else:
                values = np.column_stack([np.interp(at, tt, vv[:, k]) for k in range(3)])
            for frame, value in enumerate(values):
                overrides[frame].setdefault(i, {})[path.lower()] = value
    return [base.matrices(nodes, over) for over in overrides]


def target_globals(original, native, source_index, axes):
    output = []
    for node in original['nodes']:
        mapped = correspondence(node['name'])
        m = np.eye(4)
        if mapped is not None:
            pose = native[source_index[mapped]]
            side = node['name'].removeprefix('v_weapon.Bip01_')[0]
            m[:3, :3] = AXIS @ pose[:3, :3] @ axes[side]
            m[:3, 3] = (C @ pose)[:3, 3]
        output.append(m)
    return output


def compact(doc, binary):
    """Discard superseded Kukri and earlier adapter buffers; keep live bytes exact."""
    refs = []
    for mesh in doc['meshes']:
        for p in mesh['primitives']:
            refs += [(p, 'indices')] if 'indices' in p else []
            refs += [(p['attributes'], k) for k in p['attributes']]
            for target in p.get('targets', []): refs += [(target,k) for k in target]
    refs += [(skin,'inverseBindMatrices') for skin in doc['skins']]
    for anim in doc['animations']:
        for sampler in anim['samplers']: refs += [(sampler,'input'),(sampler,'output')]
    live = sorted({obj[key] for obj,key in refs})
    remap = {old:new for new,old in enumerate(live)}
    accessors = [copy.deepcopy(doc['accessors'][i]) for i in live]
    for obj,key in refs: obj[key] = remap[obj[key]]
    images = [image for image in doc.get('images',[]) if 'bufferView' in image]
    used_views = sorted({a['bufferView'] for a in accessors} | {image['bufferView'] for image in images})
    views, output, vm = [], bytearray(), {}
    for i in used_views:
        view = copy.deepcopy(doc['bufferViews'][i]); offset = view.get('byteOffset',0)
        output.extend(b'\0' * (-len(output)%4)); data = binary[offset:offset+view['byteLength']]
        view.update(buffer=0, byteOffset=len(output)); vm[i] = len(views)
        views.append(view); output.extend(data)
    for obj in accessors + images: obj['bufferView'] = vm[obj['bufferView']]
    doc['accessors'], doc['bufferViews'] = accessors, views
    return output


def main(directory, selected=None):
    folder = Path(directory)
    original, obin = base.read_glb(str(ROOT / 'assets/models/weapons/v_knife.glb'))
    old_bind = base.original_pose(original, obin)
    old_skin = original['skins'][0]
    old_ibm = _accessor(original, obin, old_skin['inverseBindMatrices'])
    old_parents = {c:i for i,n in enumerate(original['nodes']) for c in n.get('children', [])}
    metadata_path = ROOT / 'data/models_meta.json'
    metadata = json.loads(metadata_path.read_text())
    report_path = ROOT / 'data/native_knife_animation_report.json'
    reports = json.loads(report_path.read_text()) if selected and report_path.exists() else {}
    for key in (selected or NAMES):
        animfile = folder / (key + '.cs2.animation.json')
        animation = json.loads(animfile.read_text())
        vertices, joints, inverse, primitives = base.read_skin(folder / (key + '.cs2.skin'))
        nodes = source_nodes(animation)
        source_index = {n['name']:i for i,n in enumerate(nodes)}
        source_bind = base.matrices(nodes)
        assert all(n in source_index or vertices['w'][vertices['j'] == i].sum() == 0 for i,n in enumerate(joints))
        axes, error = axis_calibration(original, nodes, source_bind, old_bind)
        path = ROOT / ('assets/models/weapons/v_knife_' + key + '.glb')
        doc, binary = base.read_glb(str(path))
        # Preserve all previously embedded images and exact original arm accessors.
        doc['nodes'] = copy.deepcopy(original['nodes'])
        doc['skins'] = [copy.deepcopy(old_skin)]
        doc['skins'][0]['skeleton'] = 0
        doc['animations'] = []
        knife_nodes = []
        for name in joints:
            index = len(doc['nodes'])
            knife_nodes.append(index)
            doc['nodes'].append({'name': 'cs2_mechanical_' + name, 'matrix': (C @ (source_bind[source_index[name]] if name in source_index else np.eye(4)) @ CI).T.reshape(-1).tolist()})
            doc['nodes'][0].setdefault('children', []).append(index)
        doc['skins'][0]['joints'] += knife_nodes
        converted_inverse = [(C @ m @ CI).T.reshape(-1) for m in inverse]
        doc['skins'][0]['inverseBindMatrices'] = base.append_array(doc, binary, np.vstack([old_ibm, converted_inverse]), 'MAT4')
        prim = doc['meshes'][0]['primitives'][0]
        p = (np.column_stack([vertices['p'], np.ones(len(vertices))]) @ C.T)[:, :3]
        n = vertices['n'] @ AXIS.T
        prim['attributes'] = {
            'POSITION': base.append_array(doc, binary, p, 'VEC3'),
            'NORMAL': base.append_array(doc, binary, n, 'VEC3'),
            'TEXCOORD_0': base.append_array(doc, binary, vertices['uv'], 'VEC2'),
            'JOINTS_0': base.append_array(doc, binary, vertices['j'].astype(np.uint16) + len(old_skin['joints']), 'VEC4', 5123),
            'WEIGHTS_0': base.append_array(doc, binary, vertices['w'], 'VEC4'),
        }
        prim['indices'] = base.append_array(doc, binary, np.concatenate([x[1] for x in primitives]), 'SCALAR', 5125)
        durations, clip_sources = {}, {}
        idle_clip = next(c for c in animation['Clips'].values() if c['Alias'] == 'idle')
        idle_native = sample_poses(nodes, idle_clip, np.array([0.0]))[0]
        idle_target = target_globals(original, idle_native, source_index, axes)
        for i in old_skin['joints']:
            parent = old_parents.get(i)
            local = np.linalg.inv(idle_target[parent]) @ idle_target[i] if parent is not None else idle_target[i]
            doc['nodes'][i] = {k:v for k,v in doc['nodes'][i].items() if k not in ['translation','rotation','scale','matrix']}
            t, r, scale = decompose([local])
            doc['nodes'][i]['translation'] = t[0].tolist()
            doc['nodes'][i]['rotation'] = r[0].tolist()
            doc['nodes'][i]['scale'] = scale[0].tolist()
        for source_name, clip in animation['Clips'].items():
            alias = clip['Alias']
            name = ALIASES.get(alias, alias)
            assert name not in durations, (key, name)
            times = np.array(sorted({0.0, float(clip['Duration'])} | {float(t) for tracks in clip['Bones'].values() for field,tr in tracks.items() if field in ['Translation','Rotation','Scale'] for t in tr['Times']}))
            poses = sample_poses(nodes, clip, times)
            target = [target_globals(original, pose, source_index, axes) for pose in poses]
            track = {'name': name, 'samplers': [], 'channels': [], 'extras': {'source_clip': source_name, 'source_alias': alias}}
            inp = base.append_array(doc, binary, times, 'SCALAR')
            doc['accessors'][inp].update(min=[float(times[0])], max=[float(times[-1])])
            for i in old_skin['joints'] + knife_nodes:
                if i in knife_nodes:
                    src = source_index.get(joints[knife_nodes.index(i)])
                    matrices = [C @ pose[src] @ CI if src is not None else np.eye(4) for pose in poses]
                else:
                    parent = old_parents.get(i)
                    matrices = [np.linalg.inv(t[parent]) @ t[i] if parent is not None else t[i] for t in target]
                t, r, scale = decompose(matrices)
                for field, kind, values in [('translation','VEC3',t),('rotation','VEC4',r),('scale','VEC3',scale)]:
                    # Quaternion hemispheres must be continuous across 180 degrees.
                    if field == 'rotation':
                        for f in range(1, len(values)):
                            if np.dot(values[f-1], values[f]) < 0: values[f] *= -1
                    out = base.append_array(doc, binary, values, kind)
                    track['channels'].append({'sampler':len(track['samplers']), 'target':{'node':i,'path':field}})
                    track['samplers'].append({'input':inp,'output':out,'interpolation':'LINEAR'})
            doc['animations'].append(track)
            durations[name] = float(clip['Duration'])
            clip_sources[name] = source_name
        doc['asset']['native_cs2_animation_sha256'] = hashlib.sha256(animfile.read_bytes()).hexdigest()
        binary = compact(doc, binary)
        for old, new in zip(original['meshes'][0]['primitives'][1:], doc['meshes'][0]['primitives'][1:]):
            for field in old['attributes']:
                assert np.array_equal(_accessor(original, obin, old['attributes'][field]), _accessor(doc, binary, new['attributes'][field]))
            assert np.array_equal(_accessor(original, obin, old['indices']), _accessor(doc, binary, new['indices']))
        base.write_glb(str(path), doc, binary)
        m = metadata['weapons/v_knife_' + key]
        m.update(sequences=list(durations), seq_durations=durations, seq_events={}, inspect_clips=[n for n in durations if n.startswith('inspect')],
                 animation_source='native model-specific CS2 clips; original arm/glove geometry retargeted anatomically',
                 native_cs2_animation=True, authored_right_hand=True, bones=len(old_skin['joints']) + len(joints))
        reports[key] = dict(source_commit=base.SOURCE_COMMIT, animation_sha256=doc['asset']['native_cs2_animation_sha256'],
                            clips=clip_sources, durations=durations, axis_max_error_deg=error,
                            axis_matrices={s:axes[s].tolist() for s in axes}, knife_joints=joints,
                            camera_axes='x forward / y left / z up -> -z / -x / +y; 0.0254 m per inch',
                            original_arm_primitives_preserved=True)
        print('NATIVE',key,'clips',len(durations),'axis errors',error,flush=True)
    metadata_path.write_text(json.dumps(metadata,indent=2,ensure_ascii=False)+'\n')
    (ROOT / 'data/native_knife_animation_report.json').write_text(json.dumps(reports,indent=2)+'\n')

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2:] or None)
