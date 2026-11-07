#!/usr/bin/env python3
"""Check native knife clips while preserving original arm/glove mesh data."""
import hashlib
import json
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1]


def glb(path):
    raw = path.read_bytes()
    size = struct.unpack_from('<I', raw, 12)[0]
    document = json.loads(raw[20:20 + size])
    start = 20 + size
    count = struct.unpack_from('<I', raw, start)[0]
    return document, raw[start + 8:start + 8 + count]


def accessor(document, binary, index):
    a = document['accessors'][index]
    view = document['bufferViews'][a['bufferView']]
    width = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}[a['type']]
    fmt = {5126: 'f', 5125: 'I', 5123: 'H', 5121: 'B'}[a['componentType']]
    stride = view.get('byteStride', width * struct.calcsize(fmt))
    offset = view.get('byteOffset', 0) + a.get('byteOffset', 0)
    return [struct.unpack_from('<' + fmt * width, binary, offset + i * stride) for i in range(a['count'])]


def main():
    folder = ROOT / 'assets/models/weapons'
    original, original_binary = glb(folder / 'v_knife.glb')
    catalog = json.loads((ROOT / 'data/knife_models.json').read_text())
    assert len(catalog['options']) == 23
    geometry_hashes = set()
    for option in catalog['options'][1:]:
        document, binary = glb(folder / (option['v_model'] + '.glb'))
        report = json.loads((ROOT / 'data/native_knife_animation_report.json').read_text())[option['id']]
        assert document['asset']['native_cs2_animation_sha256'] == report['animation_sha256']
        assert [n['name'] for n in document['nodes'][:len(original['nodes'])]] == [n['name'] for n in original['nodes']]
        assert document['skins'][0]['joints'][:len(original['skins'][0]['joints'])] == original['skins'][0]['joints']
        assert accessor(document, binary, document['skins'][0]['inverseBindMatrices'])[:len(original['skins'][0]['joints'])] == accessor(original, original_binary, original['skins'][0]['inverseBindMatrices'])
        for old, new in zip(original['meshes'][0]['primitives'][1:], document['meshes'][0]['primitives'][1:]):
            assert old['material'] == new['material']
            assert accessor(original, original_binary, old['indices']) == accessor(document, binary, new['indices'])
            for field in old['attributes']:
                assert accessor(original, original_binary, old['attributes'][field]) == accessor(document, binary, new['attributes'][field]), (option['id'], field)
        animations = {a['name']:a for a in document['animations']}
        assert set(animations) == set(report['clips'])
        for name, animation in animations.items():
            assert animation['extras']['source_clip'] == report['clips'][name]
            animated = {c['target']['node'] for c in animation['channels']}
            assert {3, 8, 28, 12} <= animated, 'Both hands and fingers must use native motion'
            assert max(accessor(document, binary, animation['samplers'][0]['input']))[0] >= report['durations'][name] - 0.0001
        assert document['materials'][:len(original['materials'])] == original['materials']
        primitive = document['meshes'][0]['primitives'][0]
        attributes = primitive['attributes']
        pos = accessor(document, binary, attributes['POSITION'])
        uv = accessor(document, binary, attributes['TEXCOORD_0'])
        joints = accessor(document, binary, attributes['JOINTS_0'])
        weights = accessor(document, binary, attributes['WEIGHTS_0'])
        assert len(pos) == len(uv) == len(joints) == len(weights) > 1000
        assert all(abs(sum(w) - 1) < 1e-5 for w in weights)
        assert all(0 <= j < len(document['skins'][0]['joints']) for item in joints for j in item)
        assert all(0 <= i[0] < len(pos) for i in accessor(document, binary, primitive['indices']))
        geometry_hashes.add(hashlib.sha256(repr(pos).encode()).hexdigest())
        material = document['materials'][primitive['material']]
        assert material['pbrMetallicRoughness']['metallicRoughnessTexture'] == material['occlusionTexture']
        assert 'normalTexture' in material
        for prefix in ('p_model', 'w_model'):
            world, world_binary = glb(folder / (option[prefix] + '.glb'))
            assert len(world['meshes'][0]['primitives']) == 1
            world_prim = world['meshes'][0]['primitives'][0]
            assert len(accessor(world, world_binary, world_prim['attributes']['POSITION'])) == len(pos)
            assert accessor(world, world_binary, world_prim['attributes']['TEXCOORD_0']) == uv
        print('[KNIFE ASSETS]', option['name'], 'geometry/UV/material/world/arms/animation integrity PASS')
    assert len(geometry_hashes) == 22, 'All 22 models have distinct geometry'


if __name__ == '__main__':
    main()
