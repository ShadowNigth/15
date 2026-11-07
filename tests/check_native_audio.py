#!/usr/bin/env python3
"""Verify complete audio inventory/provenance and source-event synchronization."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
manifest = json.loads((ROOT/'data/native_audio_manifest.json').read_text())
catalog = json.loads((ROOT/'data/native_audio.json').read_text())
assert manifest['commit'] == catalog['commit'] == '1eb8067fd0b7214df5bccf3ac3807fbaa3aee70d'
assert len(manifest['files']) == 649
paths = set()
for entry in manifest['files']:
    path = entry['path']
    assert path not in paths and path.startswith('native/') and '..' not in path
    paths.add(path)
    raw = (ROOT/'assets/sounds'/path).read_bytes()
    assert len(raw) == entry['bytes']
    assert hashlib.sha256(raw).hexdigest() == entry['sha256'], path
    assert hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest() == entry['git_blob'], path
    assert raw.startswith(b'OggS') if path.endswith('.ogg') else raw.startswith(b'RIFF'), path
assert paths == {str(p.relative_to(ROOT/'assets/sounds')) for p in (ROOT/'assets/sounds/native').rglob('*') if p.suffix in ('.ogg','.wav')}

def check_paths(value):
    if isinstance(value, dict):
        for v in value.values(): check_paths(v)
    elif isinstance(value, list):
        for v in value: check_paths(v)
    elif isinstance(value, str) and value.startswith(('native/', 'weapons/')):
        assert (ROOT/'assets/sounds'/value).is_file(), value
check_paths(catalog)
assert len(catalog['weapons']) == 43 and len(catalog['model_events']) == 64
assert catalog['weapons']['m4a4']['fire_sounds'] != catalog['weapons']['m4a1']['fire_sounds']
for lang in ('en','zh'):
    for team in ('ct','t'):
        assert len(catalog['voices'][lang][team]) == 17
reports = json.loads((ROOT/'data/native_gun_animation_report.json').read_text())
weapons = json.loads((ROOT/'data/weapons.json').read_text())['weapons']
count = 0
for wid, report in reports.items():
    model = 'weapons/'+weapons[wid]['v_model']
    for clip, events in catalog['model_events'][model].items():
        assert events == sorted(events, key=lambda e:e['t'])
        start = report['shotgun_segments'].get(clip, [0])[0]
        raw = report['source_events'].get('draw' if wid == 'usp' and clip == 'draw_unsil' else clip)
        if raw is None:
            original = next(n for n,s in report['clips'].items() if s == report['clips'][clip] and n in report['source_events'])
            raw = report['source_events'][original]
        for event in events:
            source = event.get('source_event')
            if source and not source.startswith('action:'):
                assert any(e['Class'] == 'CNmClipDocEvent_Sound' and e['Name'] == source and abs(float(e['At'])-start-event['t']) < 0.00002 for e in raw), (wid, clip, event)
                assert '_fire_' not in event['wav'], 'Gunshots must not play twice from animation and controller'
                count += 1
print(f'[NATIVE AUDIO ASSETS] PASS: 649 byte-exact recordings, 43 slots, 64 rigs, {count} verified native event times, EN/ZH CT/T voices')
