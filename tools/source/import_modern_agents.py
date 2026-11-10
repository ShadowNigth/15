#!/usr/bin/env python3
"""Pinned, offline-runtime SAS/Phoenix compatibility conversion (development tool).
Requires gh authentication, Node 22 and npm ci in tools/source/modern_agents.
Decodes Meshopt and BasisU using bundled WASM, no ktx executable or network CDN.
"""
import copy
import hashlib
import json
import struct
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PIN = 'fb970df0ee8175d9b212d310f6a928f9f61014f2'
BASE = 'packages/assets/public/models/agents/'
CACHE = ROOT / '.cache/modern_agents'
OUT = ROOT / 'assets/models/modern'


def read_glb(path):
    data = path.read_bytes()
    length = struct.unpack_from('<I', data, 12)[0]
    doc = json.loads(data[20:20+length])
    start = 20 + length
    binary_length = struct.unpack_from('<I', data, start)[0]
    return doc, bytearray(data[start+8:start+8+binary_length])


def write_glb(path, doc, binary):
    doc['buffers'] = [{'byteLength': len(binary)}]
    text = json.dumps(doc, separators=(',', ':')).encode()
    text += b' ' * (-len(text) % 4)
    binary += b'\0' * (-len(binary) % 4)
    path.write_bytes(struct.pack('<III', 0x46546c67, 2, 28+len(text)+len(binary)) +
                     struct.pack('<I4s', len(text), b'JSON') + text +
                     struct.pack('<I4s', len(binary), b'BIN\0') + binary)


def fetch(name):
    dest = CACHE / name.replace('/', '_')
    if not dest.exists():
        data = subprocess.check_output(['gh', 'api', '-H', 'Accept: application/vnd.github.raw+json',
            f'repos/3kh0/cs2go/contents/{BASE}{name}?ref={PIN}'])
        dest.write_bytes(data)
    return dest


def attach_clips(body, source, output):
    doc, blob = read_glb(body)
    clips, source_blob = read_glb(source)
    names = {n.get('name'): i for i, n in enumerate(doc['nodes'])}
    offset = len(blob)
    offset += -offset % 4
    blob.extend(b'\0' * (offset-len(blob)))
    view_offset, accessor_offset = len(doc['bufferViews']), len(doc['accessors'])
    for view in clips['bufferViews']:
        view = copy.deepcopy(view)
        view['byteOffset'] = view.get('byteOffset', 0) + offset
        view['buffer'] = 0
        doc['bufferViews'].append(view)
    converted = set()
    animations = []
    for animation in clips['animations']:
        animation = copy.deepcopy(animation)
        kept = []
        for channel in animation['channels']:
            name = clips['nodes'][channel['target']['node']].get('name')
            # Body-only import. Root stays fixed: physics owns displacement.
            if name not in names or name == 'root_motion':
                continue
            channel['target']['node'] = names[name]
            kept.append(channel)
            sampler = animation['samplers'][channel['sampler']]
            index = sampler['output']
            if channel['target']['path'] == 'translation' and index not in converted:
                accessor = clips['accessors'][index]
                view = clips['bufferViews'][accessor['bufferView']]
                assert accessor['componentType'] == 5126 and accessor['type'] == 'VEC3'
                assert 'sparse' not in accessor and view.get('byteStride', 12) == 12
                start = view.get('byteOffset', 0) + accessor.get('byteOffset', 0)
                for at in range(start, start + accessor['count']*12, 4):
                    value = struct.unpack_from('<f', source_blob, at)[0] / 0.0254
                    struct.pack_into('<f', source_blob, at, value)
                accessor.pop('min', None)
                accessor.pop('max', None)
                converted.add(index)
        animation['channels'] = kept
        for sampler in animation['samplers']:
            sampler['input'] += accessor_offset
            sampler['output'] += accessor_offset
        if kept:
            animations.append(animation)
    for accessor in clips['accessors']:
        accessor = copy.deepcopy(accessor)
        if 'bufferView' in accessor:
            accessor['bufferView'] += view_offset
        doc['accessors'].append(accessor)
    doc['animations'] = animations
    blob.extend(source_blob)
    write_glb(output, doc, blob)
    return [a['name'] for a in animations]


def main():
    CACHE.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    source = fetch('inspects/animations/world/rifle/_default_rifle.glb')
    report = {'repository': 'https://github.com/3kh0/cs2go', 'commit': PIN,
              'status': 'isolated validation; not active gameplay replacement', 'models': []}
    for name, upstream in [('sas', 'roster/ctm-sas.glb'), ('phoenix', 'roster/tm-phoenix.glb')]:
        original = fetch(upstream)
        decoded = CACHE / (name + '-decoded.glb')
        subprocess.run(['node', str(Path(__file__).with_name('modern_agents')/'decode.mjs'),
                        str(original), str(decoded)], check=True)
        final = OUT / (name + '.glb')
        clips = attach_clips(decoded, source, final)
        doc, _ = read_glb(final)
        assert not doc.get('extensionsRequired')
        assert all(i.get('mimeType') == 'image/png' for i in doc['images'])
        report['models'].append({'name': name, 'source': BASE+upstream,
            'source_sha256': hashlib.sha256(original.read_bytes()).hexdigest(),
            'output_sha256': hashlib.sha256(final.read_bytes()).hexdigest(),
            'path': str(final.relative_to(ROOT)), 'clips': clips})
    report['animation_source'] = BASE+'inspects/animations/world/rifle/_default_rifle.glb'
    report['animation_sha256'] = hashlib.sha256(source.read_bytes()).hexdigest()
    (ROOT/'data/modern_agents_import.json').write_text(json.dumps(report, indent=2)+'\n')


if __name__ == '__main__':
    main()
