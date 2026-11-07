#!/usr/bin/env python3
"""Source coverage and byte-exact mesh/skin preservation against pre-conversion."""
import json
import struct
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASELINE = 'e0360c636ab40cb36761dc0ef2189030f922fa33'


def read(raw):
    size = struct.unpack_from('<I', raw, 12)[0]
    doc = json.loads(raw[20:20+size])
    return doc, raw[28+size:]


def array(doc, binary, index):
    a = doc['accessors'][index]
    v = doc['bufferViews'][a['bufferView']]
    width = {'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']]
    size = width * {5121:1,5123:2,5125:4,5126:4}[a['componentType']]
    start = v.get('byteOffset',0)+a.get('byteOffset',0)
    stride = v.get('byteStride',size)
    return a['type'], a['componentType'], a['count'], b''.join(binary[start+i*stride:start+i*stride+size] for i in range(a['count']))


report = json.loads((ROOT/'data/native_gun_animation_report.json').read_text())
meta = json.loads((ROOT/'data/models_meta.json').read_text())
weapons = json.loads((ROOT/'data/weapons.json').read_text())['weapons']
old_meta = json.loads(subprocess.check_output(['git','show',BASELINE+':data/models_meta.json'],cwd=ROOT))
assert set(report) == set(weapons)-{'knife'} and len(report) == 42
assert sum(r['source_clip_count'] for r in report.values()) == 289
for wid,r in report.items():
    rel = 'assets/models/weapons/'+weapons[wid]['v_model']+'.glb'
    d,b = read((ROOT/rel).read_bytes())
    old,ob = read(subprocess.check_output(['git','show',BASELINE+':'+rel],cwd=ROOT))
    assert len(d['meshes']) == len(old['meshes'])
    for before,after in zip(old['meshes'],d['meshes']):
        assert len(before['primitives']) == len(after['primitives'])
        for op,np in zip(before['primitives'],after['primitives']):
            assert op['attributes'].keys() == np['attributes'].keys()
            for field in op['attributes']:
                assert array(old,ob,op['attributes'][field]) == array(d,b,np['attributes'][field]), (wid,field)
            assert array(old,ob,op['indices']) == array(d,b,np['indices']),wid
            assert op['material'] == np['material']
    assert d['materials'] == old['materials'],wid
    assert len(old['skins']) == len(d['skins'])
    for os,ns in zip(old['skins'],d['skins']):
        assert os['joints'] == ns['joints']
        assert array(old,ob,os['inverseBindMatrices']) == array(d,b,ns['inverseBindMatrices']),wid
    assert len(set(r['clips'].values())) == r['source_clip_count'],wid
    animations = {a['name']:a for a in d['animations']}
    assert set(animations) == set(r['clips']),wid
    m = meta['weapons/'+weapons[wid]['v_model']]
    assert m['native_cs2_animation'] and m['native_gun_animations']
    for name,duration in old_meta['weapons/'+weapons[wid]['v_model']]['seq_durations'].items():
        assert m['gameplay_seq_durations'][name] == duration,(wid,name)
    assert d['asset']['native_cs2_animation_sha256'] == r['animation_sha256']
    for name,events in m['seq_events'].items():
        for event in events:
            assert event['t'] <= m['seq_durations'][name]+0.0001
            assert (ROOT/'assets/sounds'/event['wav']).is_file(),event
    assert len(r['pose_checkpoints']) >= r['source_clip_count'],wid
    assert max(r['axis_max_error_deg'].values()) < 14,wid
    for phase in r['shotgun_segments']:
        assert phase in ['start_reload','insert','after_reload'] and phase in animations
for wid,family in [('m4a4','m4a1'),('mag7','mag7')]:
    events = meta['weapons/'+weapons[wid]['v_model']]['seq_events']
    assert all(e['wav'].startswith('weapons/cs2/'+family+'/') for clip in events.values() for e in clip),wid
# Additive R8 prepare must begin on idle, never put the hands at the camera.
r = report['revolver']['pose_checkpoints']
for name,pose in r['prepare'][0]['bones'].items():
    if 'Hand' in name:
        assert pose == r['idle'][0]['bones'][name],name
print('[NATIVE GUN ASSETS] PASS: 42 original meshes/skins/binds, 289 native clips, classic action timings, additive R8')
