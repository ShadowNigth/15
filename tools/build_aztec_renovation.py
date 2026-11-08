#!/usr/bin/env python3
"""Original-texture temple relief, hanging ferns and out-of-play jungle skyline.
Deterministic offline mesh baking. No edits to the playable BSP or gameplay data.
"""
import collections
import json
import math
from pathlib import Path
import random
import subprocess
from build_dust2_renovation import Builder
from polish_dust2 import unpack, accessor, area_squared

BASE = '57034ba0d31fd12335f7c3a50979377a4934c1c3'
OUT = 'assets/maps/de_aztec_dressing.glb'


def walls():
    doc, blob = unpack(subprocess.check_output(['git', 'show', 'babfb0ad:assets/maps/de_aztec.glb']))
    found = []
    for p in doc['meshes'][0]['primitives']:
        name = doc['materials'][p['material']]['name']
        if name not in ['-0azwll', '-1azmoss', '-0azmoss', 'aztrim', 'tnnl_flr1a', 'azstata', 'azstatb', 'azstatc']:
            continue
        pos = accessor(doc, blob, p['attributes']['POSITION'])
        normals = accessor(doc, blob, p['attributes']['NORMAL'])
        ids = [v[0] for v in accessor(doc, blob, p['indices'])]
        parent = list(range(len(pos)))
        def find(i):
            while i != parent[i]:
                i = parent[i]
            return i
        tris = []
        for k in range(0, len(ids), 3):
            tri = ids[k:k+3]; n = normals[tri[0]]
            if abs(n[1]) > .01 or max(abs(n[0]), abs(n[2])) < .99 or area_squared([pos[v] for v in tri]) < 1e-12:
                continue
            for v in tri[1:]:
                parent[find(v)] = find(tri[0])
            tris.append(tri)
        groups = collections.defaultdict(list)
        for tri in tris:
            groups[find(tri[0])].append(tri)
        for group in groups.values():
            points = [pos[v] for tri in group for v in tri]
            lo = [min(v[i] for v in points) for i in range(3)]
            hi = [max(v[i] for v in points) for i in range(3)]
            width = max(hi[0]-lo[0], hi[2]-lo[2]); height = hi[1]-lo[1]
            area = sum(math.sqrt(area_squared([pos[v] for v in tri]))/2 for tri in group)
            if 3 < width < 30 and height > 3.4 and area >= width*height*.995:
                found.append(dict(lo=lo, hi=hi, normal=normals[group[0][0]], width=width))
    return sorted(found, key=lambda f: (*f['lo'], *f['normal']))


class AztecBuilder(Builder):
    def fern(self, origin, length, angle, droop, rng):
        x,y,z = origin
        dx,dz = math.cos(angle),math.sin(angle)
        tip = (x+dx*length, y+droop, z+dz*length)
        self.pipe(origin, tip, max(.009, length*.009), 'bark', 4)
        for k in range(1, 7):
            t = k/7
            cx,cy,cz = x+dx*length*t, y+droop*t, z+dz*length*t
            span = length*.24*math.sin(math.pi*t)
            for sign in [-1,1]:
                side = (-dz*span*sign, -.04*length, dx*span*sign)
                a = (cx-dx*length*.075,cy,cz-dz*length*.075)
                b = (cx+side[0]*.55-dx*.03,cy+side[1],cz+side[2]*.55-dz*.03)
                c = (cx+side[0]+dx*length*.07,cy+side[1]*1.8,cz+side[2]+dz*length*.07)
                d = (cx+dx*length*.075,cy,cz+dz*length*.075)
                shade = rng.uniform(.72,1.0)
                self.quad([a,b,c,d], 'leaf', (.32*shade,.60*shade,.30*shade))

    def dress_wall(self, face, index, rng):
        lo,hi,n,w = face['lo'],face['hi'],face['normal'],face['width']
        mid = [(lo[i]+hi[i])/2 for i in range(3)]
        tangent = (1,0,0) if abs(n[2])>.9 else (0,0,1)
        self.anchor = (math.floor(mid[0]/32),math.floor(mid[2]/32),False)
        starts = {key: len(values) for key,values in self.buckets.items()}
        def point(x,y,d):
            return tuple(mid[i]+tangent[i]*x+n[i]*d+(y-mid[1] if i==1 else 0) for i in range(3))
        def box(x,y,d,width,height,depth,mat='stone',tint=(.90,.94,.85)):
            self.box(point(x,y,d),(width,height,depth) if abs(n[2])>.9 else (depth,height,width),mat,tint)
        # Shallow detail wholly backed by a solid rectangle, above standing heads.
        box(0,hi[1]-.16,.055,w-.12,.16,.11)
        box(0,hi[1]-.32,.035,w-.18,.07,.07,tint=(.64,.72,.57))
        count = max(1, int(w/3.8))
        for k in range(count):
            x = (k+.5)*w/count-w/2
            box(x,hi[1]-.59,.045,min(.72,w/count-.18),.28,.09,'glyph')
        has_fern = hi[1]-lo[1] > 4.4 and index % 4 == 0
        if has_fern:
            # Hang on the wall plane; not across doors, paths or the bridge deck.
            for k in range(2):
                x = w*(.10+k*.15)-w*.33
                start=point(x,hi[1]-.28,.13)
                self.fern(start,.48, math.atan2(tangent[2],tangent[0])+k*.9, -.68, rng)
        vertices = [v[0] for key,values in self.buckets.items() for v in values[starts.get(key,0):]]
        bounds = [[min(v[i] for v in vertices) for i in range(3)], [max(v[i] for v in vertices) for i in range(3)]]
        self.features.append(dict(kind='upper_wall',lo=lo,hi=hi,normal=n,bounds=bounds,max_depth=.65,fern=has_fern))

    def jungle(self, rng):
        temples = [(-75,-80,18,16), (81,-55,20,18), (-20,-141,22,20), (25,99,20,18)]
        for x,z,w,d in temples:
            self.anchor=(math.floor(x/32),math.floor(z/32),True)
            for tier in range(5):
                self.box((x,1+tier*1.35,z),(w-tier*2.6,1.35,d-tier*2.3),'wall',(.57,.66,.58))
                self.box((x,1.7+tier*1.35,z),(w-tier*2.6+.25,.16,d-tier*2.3+.25),'stone',(.66,.72,.61))
            self.box((x,8.5,z),(3,2.5,3),'glyph',(.65,.73,.63))
            self.features.append(dict(kind='backdrop_temple',center=[x,4,z],size=[w+.3,12,d+.3]))
        places=[(-67,z) for z in [-104,-65,-25,20,60]]+[(76,z) for z in [-95,-65,-30,5,42,68]]+[(x,-132)for x in [-37,-5,27,51]]+[(x,90)for x in [-39,-8,24,51]]
        for index,(x,z) in enumerate(places):
            self.anchor=(math.floor(x/32),math.floor(z/32),True)
            h=rng.uniform(13,19)
            bottom=(x,-4,z); crown=(x+rng.uniform(-1,1),h,z+rng.uniform(-1,1))
            self.pipe(bottom,crown,.30,'bark',7)
            for branch in range(7):
                self.fern(crown,rng.uniform(3.8,5.5),branch*math.tau/7+rng.uniform(-.12,.12),rng.uniform(-2.2,-.6),rng)
            self.features.append(dict(kind='backdrop_tree',center=[x,h/2,z],size=[14,h+10,14]))


def build():
    b=AztecBuilder(); rng=random.Random(42067)
    for i,face in enumerate(walls()):
        b.dress_wall(face,i,rng)
    b.jungle(rng)
    return b.bake([('stone','aztrim'),('wall','-0azwll'),('glyph','azstata'),('leaf','azgrass'),('bark','rope')], 'Aztec', BASE)

if __name__=='__main__':
    data,report=build();Path(OUT).write_bytes(data)
    Path('data/aztec_renovation.json').write_text(json.dumps(report,indent=2)+'\n')
    print({k:v for k,v in report.items()if k!='features'})
