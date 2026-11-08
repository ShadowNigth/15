"""Reproducible dressing, safe upper facade anchors, finite geometry and asset budget."""
import sys
from pathlib import Path
import json
import math
import subprocess
sys.path.insert(0, 'tools')
import build_dust2_renovation as build
from polish_dust2 import unpack, accessor, area_squared
output, report = build.build()
assert output == Path(build.OUT).read_bytes(), 'Dressing not reproducible'
assert json.loads(json.dumps(report)) == json.loads(Path('data/dust2_renovation.json').read_text())
assert report['triangles'] <= 7200 and report['mesh_cells'] <= 30 and report['materials'] == 5
assert Path('assets/maps/de_dust2.glb').read_bytes() == subprocess.check_output(['git','show','a02d7f5d:assets/maps/de_dust2.glb'])
assert Path('data/maps/de_dust2.json').read_bytes() == subprocess.check_output(['git','show','a02d7f5d:data/maps/de_dust2.json'])
doc, blob = unpack(output)
for image in doc['images']:
    assert (Path(build.OUT).parent/image['uri']).is_file(), image
for mesh in doc['meshes']:
    for p in mesh['primitives']:
        vertices = accessor(doc, blob, p['attributes']['POSITION'])
        normals = accessor(doc, blob, p['attributes']['NORMAL'])
        for v in vertices:
            assert all(math.isfinite(x) for x in v)
        for i in range(0,len(vertices),3):
            assert area_squared(vertices[i:i+3]) > 1e-16
            a,b,c = vertices[i:i+3]
            u,v = [b[k]-a[k]for k in range(3)],[c[k]-a[k]for k in range(3)]
            cross = [u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]]
            assert sum(cross[k]*normals[i][k]for k in range(3)) > 0, 'Winding/normal mismatch'
for feature in report['features']:
    if feature['kind'] == 'backdrop':
        x,y,z = feature['center'];w,h,d = feature['size']
        assert x-w/2 > 60 or z-d/2 > 90 or z+d/2 < -72
    elif feature['kind'] == 'vault_trim':
        assert feature['lo'][1] == feature['hi'][1] and .75 <= feature['lo'][1] <= 2.5
    else:
        assert feature['hi'][1]-feature['lo'][1] > 3.8
        if feature['closed_shutter']:
            assert feature['hi'][1]-2.2 > feature['lo'][1]+2.7
assert b'Collision' not in output and b'physics' not in output
print('[DUST2 RENOVATION] PASS:',report['triangles'],'triangles;',report['mesh_cells'],'cells;',len(report['features']),'features; original BSP/gameplay unchanged')
