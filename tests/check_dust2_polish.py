"""Verify deterministic geometry repair, area, original UVs and authored gameplay."""
import collections
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import math
spec = importlib.util.spec_from_file_location('dust2', 'tools/polish_dust2.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
source = subprocess.check_output(['git', 'show', m.BASE+':'+m.PATH])
result, report = m.polish(source)
assert result == Path(m.PATH).read_bytes(), 'GLB is not reproducible'
assert report == json.loads(Path('data/dust2_polish_report.json').read_text())
old, old_blob = m.unpack(source)
new, new_blob = m.unpack(result)
for key in ['materials', 'textures', 'images', 'samplers']:
    assert new.get(key) == old.get(key), key+' changed'

def stats(doc, blob):
    areas = collections.Counter()
    bounds = []
    uv_vertices = set()
    for mesh in doc['meshes']:
        for p in mesh['primitives']:
            attrs = {k:m.accessor(doc, blob, a) for k,a in p['attributes'].items()}
            ids = [x[0] for x in m.accessor(doc, blob, p['indices'])]
            for i in range(0, len(ids), 3):
                vertices = [attrs['POSITION'][v] for v in ids[i:i+3]]
                area = math.sqrt(m.area_squared(vertices))/2
                if doc is new:
                    assert area > 0.0000001, 'Degenerate output triangle'
                areas[p['material']] += area
            for i, pos in enumerate(attrs['POSITION']):
                assert all(math.isfinite(x) for k in attrs for x in attrs[k][i])
                bounds.append(pos)
                uv_vertices.add((pos, attrs['TEXCOORD_0'][i], attrs['TEXCOORD_1'][i]))
    return areas, [min(p[i] for p in bounds) for i in range(3)]+[max(p[i] for p in bounds) for i in range(3)], uv_vertices

a, bounds, vertices = stats(old, old_blob)
b, new_bounds, new_vertices = stats(new, new_blob)
assert bounds == new_bounds, 'Map extents changed'
for material in a:
    assert abs(a[material]-b[material]) < max(.005, a[material]*.00001), (material, a[material], b[material])
# All vertices from non-degenerate source triangles must preserve BOTH UV sets.
for mesh in old['meshes']:
    for p in mesh['primitives']:
        attrs = {k:m.accessor(old, old_blob, x) for k,x in p['attributes'].items()}
        ids = [x[0] for x in m.accessor(old, old_blob, p['indices'])]
        for i in range(0, len(ids), 3):
            tri = ids[i:i+3]
            if m.area_squared([attrs['POSITION'][x] for x in tri]) < 1e-12:
                continue
            for v in tri:
                assert (attrs['POSITION'][v], attrs['TEXCOORD_0'][v], attrs['TEXCOORD_1'][v]) in new_vertices
assert [n for n in new['nodes'] if n['name'].startswith('submodel_')]
assert len([n for n in old['nodes'] if n['name'].startswith('submodel_')]) == len([n for n in new['nodes'] if n['name'].startswith('submodel_')]) == 38
assert Path('data/maps/de_dust2.json').read_bytes() == subprocess.check_output(['git','show',m.BASE+':data/maps/de_dust2.json'])
print('[DUST2 STATIC] PASS: deterministic repair; original materials, UV0/UV1, extents, area per material, 38 brush entities and gameplay data preserved')
print(json.dumps(report))
