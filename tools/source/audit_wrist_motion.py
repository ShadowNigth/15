"""Offline source-mesh diagnostic, NOT a Godot framebuffer or acceptance substitute.
Evaluates shipped GLB inspection channels and the runtime's canonical bind mapping.
Usage: python -m tools.source.audit_wrist_motion --output /tmp/wrist-audit
"""
import argparse, copy, json
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw
from scipy.spatial.transform import Rotation, Slerp
from .import_modern_agents import read_glb
from .build_sport_gloves import _accessor
from .expand_cs2go_cosmetics import ROOT


def matrix(values):
    return np.vstack([np.asarray(values).reshape(3, 4), [0, 0, 0, 1]])


def pose(doc, blob, clip, fraction):
    nodes = copy.deepcopy(doc['nodes'])
    animation = next(a for a in doc['animations'] if a['name'] == clip)
    duration = max(float(_accessor(doc, blob, s['input']).max()) for s in animation['samplers'])
    for channel in animation['channels']:
        sampler = animation['samplers'][channel['sampler']]
        assert sampler.get('interpolation', 'LINEAR') in ['LINEAR', 'STEP']
        times = _accessor(doc, blob, sampler['input']).reshape(-1)
        data = _accessor(doc, blob, sampler['output'])
        t = np.clip(duration * fraction, times[0], times[-1])
        index = min(max(0, int(np.searchsorted(times, t, side='right'))-1), len(times)-1)
        path = channel['target']['path']
        value = data[index]
        if index+1 < len(times) and sampler.get('interpolation') != 'STEP':
            alpha = (t-times[index])/(times[index+1]-times[index])
            if path == 'rotation':
                value = Slerp([0, 1], Rotation.from_quat(data[index:index+2]))([float(alpha)]).as_quat()[0]
            else:
                value = value*(1-alpha)+data[index+1]*alpha
        nodes[channel['target']['node']][path] = value
    parents = {c: i for i, node in enumerate(nodes) for c in node.get('children', [])}
    cache = {}
    def world(index):
        if index not in cache:
            node = nodes[index]
            if 'matrix' in node:
                local = np.asarray(node['matrix']).reshape(4, 4).T
            else:
                local = np.eye(4)
                local[:3, :3] = Rotation.from_quat(node.get('rotation', [0, 0, 0, 1])).as_matrix() @ np.diag(node.get('scale', [1, 1, 1]))
                local[:3, 3] = node.get('translation', [0, 0, 0])
            cache[index] = world(parents[index]) @ local if index in parents else local
        return cache[index]
    return {node['name']: world(i) for i, node in enumerate(nodes) if 'name' in node}


def primitives(path, mapping=None, omit=()):
    doc, blob = read_glb(path)
    for node in doc['nodes']:
        if 'mesh' not in node or 'skin' not in node:
            continue
        skin = doc['skins'][node['skin']]
        names = [doc['nodes'][i]['name'] for i in skin['joints']]
        binds = _accessor(doc, blob, skin['inverseBindMatrices']).reshape(-1, 4, 4).transpose(0, 2, 1)
        for p in doc['meshes'][node['mesh']]['primitives']:
            mat = doc['materials'][p['material']]
            if mat['name'] in omit:
                continue
            attrs = p['attributes']
            v = _accessor(doc, blob, attrs['POSITION']).astype(float)
            j = _accessor(doc, blob, attrs['JOINTS_0']).astype(int)
            w = _accessor(doc, blob, attrs['WEIGHTS_0']).astype(float)
            if mapping is not None:
                converted = np.zeros_like(v)
                for slot in range(j.shape[1]):
                    for bind in np.unique(j[:, slot]):
                        mask = (j[:, slot] == bind) & (w[:, slot] > 0)
                        if not mask.any(): continue
                        entry = mapping[names[bind]]
                        converted[mask] += (np.c_[v[mask], np.ones(mask.sum())] @ matrix(entry['matrix']).T)[:, :3] * w[mask, slot, None]
                v = converted
                binds = np.array([matrix(mapping[n]['bind']) if n in mapping else np.eye(4) for n in names])
                names = [mapping[n]['target'] if n in mapping else n for n in names]
            color = np.array(mat.get('pbrMetallicRoughness', {}).get('baseColorFactor', [0.65, .65, .65, 1])[:3])
            yield {'vertices': v, 'joints': j, 'weights': w, 'binds': binds, 'names': names,
                   'faces': _accessor(doc, blob, p['indices']).reshape(-1, 3), 'color': color, 'material': mat['name']}


def deform(p, globals):
    result = np.zeros_like(p['vertices'])
    for slot in range(p['joints'].shape[1]):
        for bind in np.unique(p['joints'][:, slot]):
            mask = (p['joints'][:, slot] == bind) & (p['weights'][:, slot] > 0)
            if not mask.any(): continue
            transform = globals[p['names'][bind]] @ p['binds'][bind]
            result[mask] += (np.c_[p['vertices'][mask], np.ones(mask.sum())] @ transform.T)[:, :3] * p['weights'][mask, slot, None]
    assert np.isfinite(result).all()
    return result


def render(parts, globals, label, fov):
    # Flat material diagnostic deliberately avoids pretending to be game lighting.
    image = Image.new('RGB', (960, 540), '#343b45')
    draw = ImageDraw.Draw(image)
    polygons = []
    for p in parts:
        v = deform(p, globals) + [0.0635, -0.0381, 0]
        z = -v[:, 2]
        scale = 270/np.tan(np.radians(fov/2))
        xy = np.c_[480+v[:, 0]*scale/np.maximum(z, .001), 270-v[:, 1]*scale/np.maximum(z, .001)]
        for face in p['faces']:
            if z[face].min() < .02: continue
            points = xy[face]
            if points.max(0)[0] < 0 or points.min(0)[0] > 960 or points.max(0)[1] < 0 or points.min(0)[1] > 540: continue
            normal = np.cross(v[face[1]]-v[face[0]], v[face[2]]-v[face[0]])
            normal /= max(np.linalg.norm(normal), 1e-8)
            light = .5+.5*abs(float(normal @ np.array([.3,.5,.8124])))
            base = p['color']
            if p['material'].startswith('glove'): base = np.array([.85, .62, .22])
            if p['material'].startswith('bare_arm'): base = np.array([.88, .65, .48])
            color = tuple(np.clip(base*light*255, 0, 255).astype(int))
            polygons.append((z[face].mean(), list(map(tuple, points)), color))
    for _, points, color in sorted(polygons, key=lambda row: -row[0]): draw.polygon(points, fill=color)
    draw.rectangle((0,0,960,42), fill='#10151c')
    draw.text((12,8), 'SOURCE MESH DIAGNOSTIC - NOT A GODOT CAPTURE', fill='white')
    draw.text((12,26), label, fill='white')
    return image


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--render', action='store_true', help='Render flat source diagnostics, not game framebuffers')
    args = parser.parse_args(); args.output.mkdir(parents=True, exist_ok=True)
    config = json.loads((ROOT/'data/agent_view_arms.json').read_text())
    report = {'kind': 'offline source evaluation; not Godot framebuffer', 'cases': []}
    for model in ['v_knife_karambit', 'v_ak47', 'v_m4a1', 'v_awp']:
        path = ROOT/f'assets/models/weapons/{model}.glb'
        doc, blob = read_glb(path)
        mapping = config['targets']['v_knife' if model.startswith('v_knife_') else model]
        gloves = [p for p in primitives(path) if p['material'] == 'ct_base_glove.bmp']
        weapon = list(primitives(path, omit=('ct_arms.bmp', 'ct_base_glove.bmp')))
        for avatar in ['sas', 'leet', 'phoenix_a', 'fbi']:
            sleeves = list(primitives(ROOT/f'assets/models/agent_arms/{avatar}.glb', mapping))
            for clip in [a['name'] for a in doc['animations'] if a['name'].startswith('inspect')]:
                frames=[]; bounds=[]
                for fraction in np.linspace(0, .999, 31):
                    globals = pose(doc, blob, clip, fraction)
                    points = np.concatenate([deform(p, globals) for p in gloves+sleeves])
                    bounds.append(float(np.ptp(points, axis=0).max()))
                    if args.render and model == 'v_knife_karambit':
                        frames.append(render(weapon+gloves+sleeves, globals, f'{model} / {avatar} / {clip} / {fraction:.3f}', 53.668))
                assert max(bounds)<3, (model, avatar, clip, max(bounds))
                report['cases'].append({'model':model,'agent':avatar,'clip':clip,'samples':31,'maximum_extent_m':max(bounds)})
                if frames:
                    stem=f'{model}_{avatar}_{clip}'
                    frames[15].save(args.output/(stem+'.png'))
                    frames[0].save(args.output/(stem+'.gif'),save_all=True,append_images=frames[1:],duration=90,loop=0)
    (args.output/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    print('Source evaluation PASS:', len(report['cases']), 'animation/agent cases, 31 samples each')

if __name__=='__main__':main()
