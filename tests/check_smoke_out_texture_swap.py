"""Offline checks for the requested Smoke Out texture-only surface exchange."""
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]

def main():
    catalog = json.loads((ROOT/'data/sport_gloves.json').read_text())
    option = next(o for o in catalog['options'] if o['id'] == '5033_10078')
    assert option['texture_layout'] == 'opposite-hand-palm-back-v1'
    manifest = json.loads((ROOT/'assets/textures/moto_smoke_out_swapped/mapping.json').read_text())
    assert manifest['mesh_edited'] is False
    rig = json.loads((ROOT/'data/native_view_rigs.json').read_text())['gloves']['moto_smoke_out']
    assert hashlib.sha256((ROOT/rig['model'][6:]).read_bytes()).hexdigest() == rig['sha256']
    for side, other in [('left','right'), ('right','left')]:
        row = manifest['hands'][side]
        assert row['source_texture_hand'] == other and row['palm_back_reversed']
        assert row['distance_p50_m'] < .006 and row['distance_p99_m'] < .025
        material = 'glove_motorcycle_' + side
        for path in [option['native_textures'][material], *option['native_maps'][material].values()]:
            assert Image.open(ROOT/path[6:]).size == (1024,1024)
        old = np.asarray(Image.open(ROOT/f'assets/textures/moto_smoke_out/{material}.webp')).astype(float)
        new = np.asarray(Image.open(ROOT/option['native_textures'][material][6:])).astype(float)
        # This reference island was the large pale dorsal pad. It must now
        # carry the darker palm artwork, not just reversed lettering.
        assert new[390:460,140:310].mean() < old[390:460,140:310].mean() - 20
    assert len(catalog['options']) == 27
    assert sum(o.get('native_model') == 'sport_native' for o in catalog['options']) == 26
    print('PASS: Smoke Out sides and palm/back exchanged; native mesh unchanged; 26 other finishes retained')

if __name__ == '__main__':
    main()
