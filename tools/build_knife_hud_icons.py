"""Reproducible, texture-independent silhouettes of the shipped knife geometry.
Requires numpy and Pillow. No downloads or model/skin edits. Supersampled alpha.
"""
import sys
from pathlib import Path
import json
import numpy as np
from PIL import Image, ImageDraw
sys.path.insert(0, str(Path(__file__).parent / 'source'))
from glb_read import load, acc
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/ui/knives'
OUT.mkdir(parents=True, exist_ok=True)
for option in json.loads((ROOT / 'data/knife_models.json').read_text())['options']:
    source = ROOT / 'assets/models/weapons' / (option['p_model'] + '.glb')
    document, binary = load(source)
    surfaces = []
    for mesh in document['meshes']:
        for primitive in mesh['primitives']:
            vertices = acc(document, binary, primitive['attributes']['POSITION']).astype(float)
            indices = acc(document, binary, primitive['indices']).reshape(-1, 3)
            surfaces.append((vertices, indices))
    points = np.vstack([v for v, _ in surfaces])
    centre = (points.min(axis=0) + points.max(axis=0)) / 2
    # Area-independent unique vertices avoid dense handle topology dominating PCA.
    unique = np.unique(np.round(points, 5), axis=0)
    _, axes = np.linalg.eigh(np.cov((unique - centre).T))
    basis = axes[:, [-1, -2]]
    projected = (points - centre) @ basis
    low, high = projected.min(axis=0), projected.max(axis=0)
    scale = min(292 / max(high[0] - low[0], .001), 108 / max(high[1] - low[1], .001))
    offset = (np.array([320, 128]) - (high-low) * scale) / 2
    image = Image.new('RGBA', (1280, 512))
    draw = ImageDraw.Draw(image)
    for vertices, triangles in surfaces:
        xy = (((vertices - centre) @ basis - low) * scale + offset) * 4
        for triangle in triangles:
            draw.polygon([tuple(p) for p in xy[triangle]], fill=(255, 255, 255, 255))
    image.resize((320, 128), Image.Resampling.LANCZOS).save(OUT / (option['id'] + '.png'))
    print(option['id'], source.name)
