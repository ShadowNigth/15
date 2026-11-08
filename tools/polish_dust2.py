#!/usr/bin/env python3
"""Deterministic, texture-preserving Dust2 repair. Reads the pinned pre-polish GLB.
No BSP source or third-party Python packages required. UVs and lightmap coordinates
are interpolated, never rescaled/reprojected. Interactive submodels stay intact.
"""
import bisect
import collections
import copy
import hashlib
import json
import math
from pathlib import Path
import struct
import subprocess

BASE = '511be65e61447fd5801e00898a76a369b8d043ff'
PATH = 'assets/maps/de_dust2.glb'
CELL = 32.0
EPS = 0.00016  # Below 0.006 original GoldSrc units; not a gameplay geometry weld.


def unpack(data):
    n = struct.unpack_from('<I', data, 12)[0]
    return json.loads(data[20:20+n]), data[28+n:]


def accessor(doc, binary, index):
    a = doc['accessors'][index]
    view = doc['bufferViews'][a['bufferView']]
    components = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[a['type']]
    fmt = '<' + {5126: 'f', 5123: 'H', 5125: 'I'}[a['componentType']] * components
    stride = struct.calcsize(fmt)
    start = view.get('byteOffset', 0) + a.get('byteOffset', 0)
    return [struct.unpack_from(fmt, binary, start + i*view.get('byteStride', stride)) for i in range(a['count'])]


def area_squared(points):
    a, b, c = points
    u = [b[i]-a[i] for i in range(3)]
    v = [c[i]-a[i] for i in range(3)]
    return sum(x*x for x in (u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0]))


def polish(source, cell_size=CELL, source_commit=BASE, generator='Dust2 faithful polish v1'):
    old, binary = unpack(source)
    doc = copy.deepcopy(old)
    doc['accessors'], doc['bufferViews'], doc['meshes'], doc['nodes'] = [], [], [], []
    blob = bytearray()
    report = collections.Counter()
    point_set = set()
    for p in old['meshes'][0]['primitives']:
        point_set.update(accessor(old, binary, p['attributes']['POSITION']))
    axis_sorted = [sorted((p[axis], p) for p in point_set) for axis in range(3)]
    axis_keys = [[pair[0] for pair in items] for items in axis_sorted]
    edge_cache = {}

    def edge_points(a, b):
        key = tuple(sorted((a, b)))
        if key not in edge_cache:
            start, end = key
            d = tuple(end[i]-start[i] for i in range(3))
            length2 = sum(x*x for x in d)
            axis = max(range(3), key=lambda i: abs(d[i]))
            low, high = sorted((start[axis], end[axis]))
            candidates = axis_sorted[axis][bisect.bisect_left(axis_keys[axis], low-EPS):bisect.bisect_right(axis_keys[axis], high+EPS)]
            cuts = []
            if length2 > EPS*EPS:
                for _, p in candidates:
                    t = sum((p[i]-start[i])*d[i] for i in range(3))/length2
                    if 0.00001 < t < 0.99999 and sum((p[i]-start[i]-t*d[i])**2 for i in range(3)) < EPS*EPS:
                        cuts.append((t, p))
            unique_cuts = []
            for t, p in sorted(cuts):
                if not unique_cuts or sum((p[i]-unique_cuts[-1][1][i])**2 for i in range(3)) > EPS*EPS:
                    unique_cuts.append((t, p))
            edge_cache[key] = unique_cuts
        cuts = edge_cache[key]
        return cuts if a == key[0] else [(1-t, p) for t, p in reversed(cuts)]

    def add_acc(values, kind, integer=False):
        while len(blob) % 4:
            blob.append(0)
        fmt = '<' + ('I' if integer else 'f')*len(values[0])
        content = b''.join(struct.pack(fmt, *v) for v in values)
        view = len(doc['bufferViews'])
        doc['bufferViews'].append({'buffer': 0, 'byteOffset': len(blob), 'byteLength': len(content), 'target': 34963 if integer else 34962})
        blob.extend(content)
        entry = {'bufferView': view, 'componentType': 5125 if integer else 5126, 'count': len(values), 'type': kind}
        if kind == 'VEC3':
            entry['min'] = [min(v[i] for v in values) for i in range(3)]
            entry['max'] = [max(v[i] for v in values) for i in range(3)]
        doc['accessors'].append(entry)
        return len(doc['accessors'])-1

    for node in old['nodes']:
        mesh = old['meshes'][node['mesh']]
        world = node.get('name') == 'worldspawn'
        buckets = collections.defaultdict(list)
        for prim in mesh['primitives']:
            attributes = {k: accessor(old, binary, v) for k, v in prim['attributes'].items()}
            indices = [x[0] for x in accessor(old, binary, prim['indices'])]
            for offset in range(0, len(indices), 3):
                tri = [{k: values[i] for k, values in attributes.items()} for i in indices[offset:offset+3]]
                report['input_triangles'] += 1
                if area_squared([v['POSITION'] for v in tri]) < 1e-12:
                    report['degenerate_triangles_removed'] += 1
                    continue
                polygon = []
                for i, a in enumerate(tri):
                    b = tri[(i+1)%3]
                    polygon.append(a)
                    if world:
                        for t, p in edge_points(a['POSITION'], b['POSITION']):
                            split = {k: tuple(x+(y-x)*t for x, y in zip(a[k], b[k])) for k in a}
                            split['POSITION'] = p
                            polygon.append(split)
                triangles = [tri]
                # Split only boundary edges: n cuts need n+1 triangles, not a
                # centroid fan's n+3. Preserve winding and authored UV seams.
                for split in polygon:
                    if split in tri:
                        continue
                    inserted = False
                    for index, current in enumerate(triangles):
                        for edge in range(3):
                            a, b, c = current[edge], current[(edge+1)%3], current[(edge+2)%3]
                            d = tuple(b['POSITION'][i]-a['POSITION'][i] for i in range(3))
                            length2 = sum(x*x for x in d)
                            if length2 < EPS*EPS:
                                continue
                            offset = tuple(split['POSITION'][i]-a['POSITION'][i] for i in range(3))
                            t = sum(offset[i]*d[i] for i in range(3))/length2
                            if .00001 < t < .99999 and sum((offset[i]-t*d[i])**2 for i in range(3)) < EPS*EPS:
                                triangles[index:index+1] = [[a, split, c], [split, b, c]]
                                inserted = True
                                break
                        if inserted:
                            break
                if len(triangles) > 1:
                    report['t_junction_triangles_repaired'] += 1
                centroid = [sum(v['POSITION'][i] for v in tri)/3 for i in range(3)]
                cell = (math.floor(centroid[0]/cell_size), math.floor(centroid[2]/cell_size)) if world else (0, 0)
                valid_triangles = []
                for repaired in triangles:
                    for vertex in repaired:
                        for key in vertex:
                            vertex[key] = struct.unpack('<'+'f'*len(vertex[key]), struct.pack('<'+'f'*len(vertex[key]), *vertex[key]))
                    if area_squared([v['POSITION'] for v in repaired]) >= 1e-12:
                        valid_triangles.append(repaired)
                if any(not any(v == original for t in valid_triangles for v in t) for original in tri):
                    valid_triangles = [tri]  # Do not lose an authored corner on an extremely thin face.
                    if len(triangles) > 1:
                        report['t_junction_triangles_repaired'] -= 1
                buckets[(cell, prim['material'])].extend(valid_triangles)
        cells = sorted(set(cell for cell, _ in buckets))
        for cell in cells:
            primitives = []
            for (bucket_cell, mat), triangles in sorted(buckets.items()):
                if cell != bucket_cell:
                    continue
                vertices, indices, unique = [], [], {}
                for tri in triangles:
                    for vertex in tri:
                        key = tuple((k, vertex[k]) for k in sorted(vertex))
                        if key not in unique:
                            unique[key] = len(vertices)
                            vertices.append(vertex)
                        indices.append((unique[key],))
                attrs = {k: add_acc([v[k] for v in vertices], 'VEC'+str(len(vertices[0][k]))) for k in vertices[0]}
                primitives.append({'attributes': attrs, 'indices': add_acc(indices, 'SCALAR', True), 'material': mat})
                report['output_triangles'] += len(indices)//3
            name = 'worldchunk_%d_%d' % cell if world else node['name']
            mi = len(doc['meshes'])
            doc['meshes'].append({'name': name, 'primitives': primitives})
            new_node = copy.deepcopy(node)
            new_node.update(name=name, mesh=mi)
            doc['nodes'].append(new_node)
        if world:
            report['world_chunks'] = len(cells)
    doc['scenes'] = [{'nodes': list(range(len(doc['nodes'])))}]
    doc['scene'] = 0
    while len(blob) % 4:
        blob.append(0)
    doc['buffers'] = [{'byteLength': len(blob)}]
    doc.setdefault('asset', {})['generator'] = generator
    encoded = json.dumps(doc, separators=(',', ':')).encode()
    encoded += b' ' * (-len(encoded) % 4)
    result = struct.pack('<III', 0x46546C67, 2, 28+len(encoded)+len(blob))+struct.pack('<II', len(encoded), 0x4E4F534A)+encoded+struct.pack('<II', len(blob), 0x004E4942)+blob
    report = dict(report)
    report.update(source_sha256=hashlib.sha256(source).hexdigest(), output_sha256=hashlib.sha256(result).hexdigest(), source_commit=source_commit, chunk_size_m=cell_size)
    return result, dict(report)


if __name__ == '__main__':
    source = subprocess.check_output(['git', 'show', BASE+':'+PATH])
    output, report = polish(source)
    Path(PATH).write_bytes(output)
    Path('data/dust2_polish_report.json').write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report, indent=2))
