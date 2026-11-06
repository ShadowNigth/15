#!/usr/bin/env python3
"""Complete pinned inventories and preservation of the original 120 finishes."""
import json
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
catalog = json.loads((root / 'data/weapon_skins.json').read_text())
knives = json.loads((root / 'data/knife_models.json').read_text())
assert len(knives['options']) == 23
assert len(catalog['weapons']) == 57
assert sum(len(v['options']) for k, v in catalog['weapons'].items() if k.startswith('knife_')) == 42
painted = [o for k, v in catalog['weapons'].items() if k.startswith('knife_') for o in v['options'] if o['id'] != 'factory']
assert len(painted) == 20
new_guns = [o for k, v in catalog['weapons'].items() if not k.startswith('knife_') for o in v['options'] if o['id'].startswith('sc_')]
assert len(new_guns) == 44
original = json.loads(subprocess.check_output(['git', 'show', '432c1f46f3dfd93b7b6ce6c6e09be1cfe842bfee:data/weapon_skins.json'], cwd=root))
for wid, entry in original['weapons'].items():
    assert catalog['weapons'][wid]['materials'] == entry['materials']
    assert catalog['weapons'][wid]['options'][:len(entry['options'])] == entry['options']
for family in catalog['weapons'].values():
    assert len({o['id'] for o in family['options']}) == len(family['options'])
    for option in family['options']:
        for field in ('texture', 'normal', 'orm'):
            if field in option:
                path = root / option[field].removeprefix('res://')
                assert path.is_file(), path
        assert len(option.get('source_sha256', '')) == 64
report = json.loads((root / 'data/shipped_cs2_uv_report.json').read_text())
assert len(report['finishes']) == 44
assert report['algorithm'] == 'nwm1-nearest-surface-v5'
print('[COMPLETE CATALOG] PASS: 22 knives + original, 42 knife appearances, 44 new + 120 preserved gun finishes')
