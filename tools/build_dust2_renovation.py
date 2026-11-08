#!/usr/bin/env python3
"""Bake low-cost Dust2 facade dressing and out-of-bounds skyline, no collisions.
Uses only the repository's original textures. The playable BSP is never edited.
"""
import collections
import hashlib
import json
import math
from pathlib import Path
import struct
import subprocess
from polish_dust2 import unpack, accessor, area_squared, BASE, PATH

OUT = 'assets/maps/de_dust2_dressing.glb'


def facades(ceiling=False):
    doc, blob = unpack(subprocess.check_output(['git', 'show', BASE+':'+PATH]))
    found = []
    for p in doc['meshes'][0]['primitives']:
        name = doc['materials'][p['material']]['name']
        if name not in (['sandccrete', 'sandtrim'] if ceiling else ['-0cssandwall', 'sandccrete', 'sandccrete2']):
            continue
        pos = accessor(doc, blob, p['attributes']['POSITION'])
        normals = accessor(doc, blob, p['attributes']['NORMAL'])
        ids = [x[0] for x in accessor(doc, blob, p['indices'])]
        parent = list(range(len(pos)))
        def find(i):
            while i != parent[i]:
                i = parent[i]
            return i
        triangles = []
        for k in range(0, len(ids), 3):
            tri = ids[k:k+3]
            n = normals[tri[0]]
            if area_squared([pos[i] for i in tri]) < 1e-12:
                continue
            if (n[1] > -.99) if ceiling else (abs(n[1]) > .01 or max(abs(n[0]), abs(n[2])) < .99):
                continue
            for v in tri[1:]:
                parent[find(v)] = find(tri[0])
            triangles.append(tri)
        groups = collections.defaultdict(list)
        for tri in triangles:
            groups[find(tri[0])].append(tri)
        for tris in groups.values():
            vertices = [pos[i] for tri in tris for i in tri]
            lo = [min(v[i] for v in vertices) for i in range(3)]
            hi = [max(v[i] for v in vertices) for i in range(3)]
            width, height = max(hi[0]-lo[0], hi[2]-lo[2]), hi[1]-lo[1]
            area = sum(math.sqrt(area_squared([pos[i] for i in tri]))/2 for tri in tris)
            valid = 4 < width < 25 and height > 3.8 and hi[1] >= 6 and area >= width*height*.99
            if ceiling:
                w,d = hi[0]-lo[0], hi[2]-lo[2]
                valid = 2 < w < 22 and 2 < d < 25 and .75 <= lo[1] <= 2.5 and -80 <= lo[0] and hi[0] <= -60 and -18 <= lo[2] and hi[2] <= 8 and area >= w*d*.99
            if valid:
                found.append({'texture': name, 'lo': lo, 'hi': hi, 'normal': normals[tris[0][0]], 'width': width})
    return sorted(found, key=lambda f: (*f['lo'], *f['normal']))


class Builder:
    def __init__(self):
        self.buckets = collections.defaultdict(list)
        self.features = []
        self.anchor = (0, 0, False)

    def quad(self, points, mat, tint=(1, 1, 1), repeat=(1, 1)):
        a, b, c = points[:3]
        u, v = [b[i]-a[i] for i in range(3)], [c[i]-a[i] for i in range(3)]
        n = (u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0])
        length = math.sqrt(sum(x*x for x in n))
        if length < 1e-8:
            return
        n = tuple(x/length for x in n)
        shade = .69 + .27*max(0, sum(n[i]*(-.38, .82, .42)[i] for i in range(3)))
        color = tuple(min(1, x*shade) for x in tint)+(1,)
        uv = [(0, 0), (repeat[0], 0), (repeat[0], repeat[1]), (0, repeat[1])]
        for i in [0, 1, 2, 0, 2, 3]:
            self.buckets[(*self.anchor, mat)].append((tuple(points[i]), n, uv[i], color))

    def box(self, center, size, mat, tint=(1, 1, 1)):
        x, y, z = center
        a, b, c = [s/2 for s in size]
        points = [(x-a,y-b,z-c),(x+a,y-b,z-c),(x+a,y+b,z-c),(x-a,y+b,z-c),
                  (x-a,y-b,z+c),(x+a,y-b,z+c),(x+a,y+b,z+c),(x-a,y+b,z+c)]
        for face in [(0,3,2,1),(4,5,6,7),(0,4,7,3),(1,2,6,5),(3,7,6,2),(0,1,5,4)]:
            self.quad([points[i] for i in face], mat, tint)

    def pipe(self, a, b, radius, mat='iron', sides=6):
        direction = [b[i]-a[i] for i in range(3)]
        length = math.sqrt(sum(x*x for x in direction))
        d = [x/length for x in direction]
        aux = (0,1,0) if abs(d[1]) < .9 else (1,0,0)
        u = [d[1]*aux[2]-d[2]*aux[1], d[2]*aux[0]-d[0]*aux[2], d[0]*aux[1]-d[1]*aux[0]]
        length_u = math.sqrt(sum(x*x for x in u))
        u = [x/length_u for x in u]
        v = [d[1]*u[2]-d[2]*u[1],d[2]*u[0]-d[0]*u[2],d[0]*u[1]-d[1]*u[0]]
        for k in range(sides):
            rings=[]
            for t in [k/sides*math.tau,(k+1)/sides*math.tau]:
                rings.append([radius*(u[i]*math.cos(t)+v[i]*math.sin(t)) for i in range(3)])
            self.quad([tuple(a[i]+rings[0][i] for i in range(3)),tuple(a[i]+rings[1][i] for i in range(3)),tuple(b[i]+rings[1][i] for i in range(3)),tuple(b[i]+rings[0][i] for i in range(3))],mat)

    def dress(self, face, index):
        lo, hi, n, width = face['lo'], face['hi'], face['normal'], face['width']
        mid = [(lo[i]+hi[i])/2 for i in range(3)]
        tangent = (1,0,0) if abs(n[2]) > .9 else (0,0,1)
        self.anchor = (math.floor(mid[0]/32), math.floor(mid[2]/32), False)
        start = sum(len(v) for v in self.buckets.values())
        def point(x,y,depth):
            return tuple(mid[i]+tangent[i]*x+n[i]*depth+(y-mid[1] if i==1 else 0) for i in range(3))
        def box(x,y,depth,w,h,d,mat,tint=(1,1,1)):
            self.box(point(x,y,depth), (w,h,d) if abs(n[2])>.9 else (d,h,w),mat,tint)
        # All detail is backed by a solid rectangular wall, above player head height.
        box(0,hi[1]-.22,.028,width-.14,.16,.075,'stone')
        box(0,hi[1]-.39,.016,width-.18,.045,.05,'stone',(.73,.69,.60))
        window = index % 3 == 0 and hi[1]-lo[1] >= 5.0
        if window:
            y = hi[1]-1.35
            box(0,y,.025,1.13,1.38,.065,'iron',(.48,.51,.46))
            for x in [-.58,.58]:
                box(x,y,.055,.09,1.56,.10,'stone')
            for sy in [-.73,.73]:
                box(0,y+sy,.055,1.25,.09,.10,'stone')
            box(0,y-.81,.06,1.38,.10,.12,'stone')
            # Two closed louvered shutters: no fake opening or traversable window.
            for side in [-1,1]:
                for k in range(6):
                    box(side*.265,y-.55+k*.21,.075,.49,.16,.075,'shutter',(.80,.88,.83))
            box(0,y,.08,.045,1.29,.09,'iron')
        if index % 7 == 1:
            # Short upper-facade drain, deliberately never reaching the walkway.
            x = width*.5-.20
            self.pipe(point(x,lo[1]+2.8,.095), point(x,hi[1]-.45,.095), .036)
            for y in [lo[1]+3.0,hi[1]-.65]:
                box(x,y,.062,.12,.055,.12,'iron')
        if index % 6 == 2:
            # Wall-hugging electrical cable, not a line across a combat corridor.
            top = hi[1]-.62
            for k in range(6):
                x0, x1 = -width*.44+width*.88*k/6, -width*.44+width*.88*(k+1)/6
                y0, y1 = top-.16*math.sin(math.pi*k/6), top-.16*math.sin(math.pi*(k+1)/6)
                self.pipe(point(x0,y0,.045), point(x1,y1,.045),.013,sides=4)
        if index % 8 == 0:
            # A small, unlit brass wall lantern, no new realtime light/shadow.
            x,y=width*.5-.43,lo[1]+2.9
            box(x,y,.10,.18,.32,.16,'iron')
            box(x,y,.19,.11,.22,.08,'lamp')
            for dx in [-.065,.065]:
                box(x+dx,y,.235,.018,.28,.025,'iron')
            box(x,y+.18,.15,.25,.055,.24,'iron')
        self.features.append({'kind':'facade','normal':n,'lo':lo,'hi':hi,'closed_shutter':window,'vertices':sum(len(v)for v in self.buckets.values())-start})

    def interiors(self):
        for face in facades(ceiling=True):
            lo,hi=face['lo'],face['hi']
            x,y,z=[(lo[i]+hi[i])/2 for i in range(3)]
            w,d=hi[0]-lo[0],hi[2]-lo[2]
            self.anchor=(math.floor(x/32),math.floor(z/32),False)
            self.box((x,y-.035,z),(w-.08,.07,.14),'stone',(.72,.68,.58))
            self.box((x,y-.035,z),(.14,.07,d-.08),'stone',(.72,.68,.58))
            self.box((x,y-.10,z),(.32,.12,.38),'iron')
            self.box((x,y-.167,z),(.24,.02,.28),'lamp')
            self.features.append({'kind':'vault_trim','lo':lo,'hi':hi})

    def skyline(self):
        # Entire buildings lie beyond the original [-118,48] x [-60,80] BSP bounds.
        for i,(x,z,w,d,h) in enumerate([(68,-48,10,9,16),(85,-19,12,12,18),(68,17,9,12,13),(80,56,14,10,17),(-100,103,12,10,14),(-68,108,15,11,17),(-26,102,10,12,12),(-45,-85,13,10,16)]):
            self.anchor=(math.floor(x/32),math.floor(z/32),True)
            tint=[(.85,.80,.69),(.77,.72,.63),(.90,.85,.75)][i%3]
            floor=-3
            self.box((x,floor+h/2,z),(w,h,d),'wall',tint)
            for offset in [-1,1]:
                self.box((x+offset*(w/2-.13),floor+h+.15,z),(.26,.40,d+.15),'stone',tint)
                self.box((x,floor+h+.15,z+offset*(d/2-.13)),(w,.40,.26),'stone',tint)
            # Small roof cistern and closed windows enrich the distant silhouette.
            self.box((x+1,floor+h+.65,z),(1.1,1.0,1.1),'stone',(.74,.75,.66))
            for sy in range(2):
                for sx in [-1,1]:
                    self.box((x+sx*w*.23,floor+h*.45+sy*2.5,z-d/2-.018),(.8,1.05,.035),'shutter',(.63,.69,.65))
            self.features.append({'kind':'backdrop','center':[x,floor+h/2,z],'size':[w,h,d]})

    def bake(self):
        mats=[('stone','sandtrim'),('wall','-0cssandwall'),('shutter','sandcrtsmsd'),('iron','generic011'),('lamp','white')]
        doc={'asset':{'version':'2.0','generator':'Dust2 visual renovation v1'},'scene':0,'scenes':[{'nodes':[]}],'nodes':[],'meshes':[],'materials':[],'textures':[],'images':[],'samplers':[{'magFilter':9729,'minFilter':9987,'wrapS':10497,'wrapT':10497}],'buffers':[],'bufferViews':[],'accessors':[]}
        for i,(name,texture) in enumerate(mats):
            doc['images'].append({'uri':'../textures/world/'+texture+'.png'})
            doc['textures'].append({'source':i,'sampler':0})
            doc['materials'].append({'name':'Dust2_'+name,'pbrMetallicRoughness':{'baseColorTexture':{'index':i},'baseColorFactor':([.20,.40,.35,1] if name=='shutter' else ([.95,.65,.27,1] if name=='lamp' else [1,1,1,1])),'metallicFactor':0,'roughnessFactor':1}})
        indices={name:i for i,(name,_) in enumerate(mats)}
        blob=bytearray()
        def acc(values,kind):
            while len(blob)%4:blob.append(0)
            data=b''.join(struct.pack('<'+'f'*len(v),*v)for v in values)
            vi=len(doc['bufferViews']);doc['bufferViews'].append({'buffer':0,'byteOffset':len(blob),'byteLength':len(data),'target':34962});blob.extend(data)
            entry={'bufferView':vi,'componentType':5126,'count':len(values),'type':kind}
            if kind=='VEC3':
                entry.update(min=[min(v[i]for v in values)for i in range(3)],max=[max(v[i]for v in values)for i in range(3)])
            doc['accessors'].append(entry);return len(doc['accessors'])-1
        cells=sorted(set(k[:3]for k in self.buckets))
        for cell in cells:
            prims=[]
            for key,values in sorted(self.buckets.items()):
                if key[:3]!=cell:continue
                prims.append({'mode':4,'material':indices[key[3]],'attributes':{'POSITION':acc([v[0]for v in values],'VEC3'),'NORMAL':acc([v[1]for v in values],'VEC3'),'TEXCOORD_0':acc([v[2]for v in values],'VEC2'),'COLOR_0':acc([v[3]for v in values],'VEC4')}})
            idx=len(doc['nodes']);doc['scenes'][0]['nodes'].append(idx)
            doc['nodes'].append({'name':('Backdrop' if cell[2] else 'Facade')+'_%d_%d'%cell[:2],'mesh':idx})
            doc['meshes'].append({'primitives':prims})
        while len(blob)%4:blob.append(0)
        doc['buffers']=[{'byteLength':len(blob)}]
        raw=json.dumps(doc,separators=(',',':')).encode();raw+=b' '*(-len(raw)%4)
        output=struct.pack('<III',0x46546c67,2,28+len(raw)+len(blob))+struct.pack('<II',len(raw),0x4e4f534a)+raw+struct.pack('<II',len(blob),0x004e4942)+blob
        report={'triangles':sum(len(v)//3 for v in self.buckets.values()),'mesh_cells':len(cells),'materials':len(mats),'source_commit':BASE,'asset_sha256':hashlib.sha256(output).hexdigest(),'features':self.features}
        return output,report


def build():
    builder=Builder()
    for index,face in enumerate(facades()):
        builder.dress(face,index)
    builder.interiors()
    builder.skyline()
    return builder.bake()


if __name__=='__main__':
    output,report=build()
    Path(OUT).write_bytes(output)
    Path('data/dust2_renovation.json').write_text(json.dumps(report,indent=2)+'\n')
    print({k:v for k,v in report.items()if k!='features'})
