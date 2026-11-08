"""Deterministic dressing, original textures, safe wall anchors and skyline bounds."""
import sys
sys.path.insert(0,'tools')
import build_aztec_renovation as build
from polish_dust2 import unpack,accessor,area_squared
from pathlib import Path
import json,math,subprocess,itertools
output,report=build.build()
assert output==Path(build.OUT).read_bytes(), 'Dressing must be reproducible'
assert json.loads(json.dumps(report))==json.loads(Path('data/aztec_renovation.json').read_text())
assert report['triangles']<=18000 and report['mesh_cells']<=50 and report['materials']==5
for path in ['assets/maps/de_aztec.glb','data/maps/de_aztec.json','assets/maps/de_dust2.glb','assets/maps/de_dust2_dressing.glb']:
    assert Path(path).read_bytes()==subprocess.check_output(['git','show',build.BASE+':'+path]), path
j,b=unpack(output)
for image in j['images']:
    assert (Path(build.OUT).parent/image['uri']).is_file()
for mesh in j['meshes']:
    for p in mesh['primitives']:
        v=accessor(j,b,p['attributes']['POSITION'])
        assert all(math.isfinite(x) for point in v for x in point)
        for i in range(0,len(v),3):
            assert area_squared(v[i:i+3])>1e-16
for f in report['features']:
    if f['kind'].startswith('backdrop'):
        x,y,z=f['center'];w,h,d=f['size']
        assert x+w/2 < -47.5 or x-w/2>56 or z+d/2 < -115.5 or z-d/2>70.5, f
    else:
        lo,hi,n=f['lo'],f['hi'],f['normal'];a,b=f['bounds']
        assert a[1]>=lo[1]+2.65 and b[1]<=hi[1],f
        axis=0 if abs(n[0])>.9 else 2
        for value in [a[axis],b[axis]]:
            depth=(value-lo[axis])*n[axis]
            assert -.5<=depth<=f['max_depth'],(f,depth)
assert b'Collision' not in output and b'physics' not in output
print('[AZTEC RENOVATION STATIC] PASS:',report['triangles'],'triangles;',report['mesh_cells'],'cells;',len(report['features']),'features; original BSP, gameplay and Dust2 unchanged')
