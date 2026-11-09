"""Offline GLB inventory; no downloads, engine changes, or asset redistribution."""
import argparse
import hashlib
import json
from pathlib import Path
import struct


def inspect_glb(path):
    raw = Path(path).read_bytes()
    if len(raw) < 20:
        raise ValueError('Truncated GLB')
    magic, version, length = struct.unpack_from('<4sII', raw)
    if magic != b'glTF' or version != 2 or length != len(raw):
        raise ValueError('Invalid GLB header')
    pos, document = 12, None
    while pos < length:
        if pos + 8 > length:
            raise ValueError('Truncated chunk header')
        size, kind = struct.unpack_from('<II', raw, pos)
        pos += 8
        if size % 4 or pos + size > length:
            raise ValueError('Invalid chunk length')
        if document is None and kind != 0x4E4F534A:
            raise ValueError('First chunk must be JSON')
        if kind == 0x4E4F534A:
            if document is not None:
                raise ValueError('Duplicate JSON chunk')
            document = json.loads(raw[pos:pos + size])
        pos += size
    if document is None:
        raise ValueError('No JSON document')
    nodes = document.get('nodes', [])
    def node_name(i):
        return nodes[i].get('name', '#' + str(i))
    joints = sorted({node_name(i) for s in document.get('skins', []) for i in s['joints']})
    clips = []
    for clip in document.get('animations', []):
        targets = sorted({node_name(c['target']['node']) for c in clip.get('channels', []) if 'node' in c['target']})
        clips.append({'name': clip.get('name', ''), 'targets': targets})
    return {'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest(),
            'mesh_count': len(document.get('meshes', [])), 'joints': joints,
            'animations': clips, 'materials': [m.get('name', '') for m in document.get('materials', [])],
            'external_uris': [x['uri'] for key in ('images', 'buffers') for x in document.get(key, [])
                              if 'uri' in x and not x['uri'].startswith('data:')]}


def audit(folder):
    manifest = json.loads(Path(__file__).with_name('manifest.json').read_text())
    results = {}
    for entry in manifest['files']:
        name = Path(entry['path']).name
        path = Path(folder) / name
        if not path.is_file():
            results[name] = {'status': 'missing'}
            continue
        try:
            result = inspect_glb(path)
            result['status'] = 'verified' if all(result[k] == entry[k] for k in ('bytes', 'sha256')) else 'manifest_mismatch'
            results[name] = result
        except (ValueError, KeyError, IndexError, struct.error) as exc:
            results[name] = {'status': 'invalid', 'error': str(exc)}
    animations = results.get('animations.glb', {}).get('animations', [])
    coverage = {}
    for name in ('ct-sas.glb', 't-phoenix.glb'):
        joints = set(results.get(name, {}).get('joints', []))
        if joints and animations:
            coverage[name] = {a['name']: sorted(set(a['targets']) - joints) for a in animations}
    return {'files': results, 'animation_targets_outside_skin': coverage,
            'note': 'Name coverage is diagnostic, not proof of retargeting or rendered Godot compatibility.'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('folder', help='Folder containing the three GLBs (outside the game assets)')
    args = parser.parse_args()
    report = audit(args.folder)
    print(json.dumps(report, indent=2))
    raise SystemExit(0 if all(x['status'] == 'verified' for x in report['files'].values()) else 1)
