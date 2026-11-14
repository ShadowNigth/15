#!/usr/bin/env python3
"""No optional deps: prove provenance, event routing and GLB animation availability."""
import hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
manifest=json.loads((ROOT/'data/native_world_manifest.json').read_text());checks=0
for entry in manifest['files']:
 if 'path' in entry:
  p=ROOT/entry['path'].removeprefix('res://');assert p.is_file(),p
  assert hashlib.sha256(p.read_bytes()).hexdigest()==entry['sha256'],p
  if entry.get('operation')=='unchanged bytes':assert entry['source_sha256']==entry['sha256']
  checks+=1
r=json.loads((ROOT/'data/native_casings.json').read_text());assert len(r['models'])==8 and len(r['weapons'])==33
report=json.loads((ROOT/'data/native_gun_animation_report.json').read_text())
for wid,route in r['weapons'].items():
 for clip,cues in route['clips'].items():
  expected=r['source_cues'][route['source_weapon']+':'+report[wid]['clips'][clip]]
  assert len(cues)==len(expected)
  for cue,original in zip(cues,expected):
   assert cue['at']==original['At'] and cue['model']==original['Model']
   assert cue['speed_min']==original['SpeedMin'] and cue['speed_max']==original['SpeedMax']
   assert cue['bone'] in report[wid]['mechanical_bones']
   assert len(cue['frame'])==4 and all(len(row)==4 for row in cue['frame'])
   checks+=1
assert 'taser' not in r['weapons'] and 'revolver' not in r['weapons']
assert r['weapons']['awp']['clips']['shoot1'][0]['at']==0.74
# The unused ct/t/hostage/chicken review models were removed from the project (never loaded by the game).
for name in ('ct','t','hostage','chicken'):
 assert not (ROOT/f'assets/models/native/{name}.glb').exists(),name
print(f'[NATIVE WORLD ASSETS] PASS: {checks} provenance/routes; 8 shells, 33 guns, 8 icons')
