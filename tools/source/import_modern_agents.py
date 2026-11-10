#!/usr/bin/env python3
"""Pinned, offline-runtime SAS/Phoenix compatibility conversion (development tool).
Requires gh authentication, Node 22 and npm ci in tools/source/modern_agents.
Decodes Meshopt and BasisU using bundled WASM, no ktx executable or network CDN.
"""
import copy
import hashlib
import json
import struct
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PIN = 'fb970df0ee8175d9b212d310f6a928f9f61014f2'
BASE = 'packages/assets/public/models/agents/'
CACHE = ROOT / '.cache/modern_agents'
OUT = ROOT / 'assets/models/modern'


def read_glb(path):
    data = path.read_bytes()
    length = struct.unpack_from('<I', data, 12)[0]
    doc = json.loads(data[20:20+length])
    start = 20 + length
    binary_length = struct.unpack_from('<I', data, start)[0]
    return doc, bytearray(data[start+8:start+8+binary_length])


def write_glb(path, doc, binary):
    doc['buffers'] = [{'byteLength': len(binary)}]
    text = json.dumps(doc, separators=(',', ':')).encode()
    text += b' ' * (-len(text) % 4)
    binary += b'\0' * (-len(binary) % 4)
    path.write_bytes(struct.pack('<III', 0x46546c67, 2, 28+len(text)+len(binary)) +
                     struct.pack('<I4s', len(text), b'JSON') + text +
                     struct.pack('<I4s', len(binary), b'BIN\0') + binary)


def fetch(name):
    dest = CACHE / name.replace('/', '_')
    if not dest.exists():
        data = subprocess.check_output(['gh', 'api', '-H', 'Accept: application/vnd.github.raw+json',
            f'repos/3kh0/cs2go/contents/{BASE}{name}?ref={PIN}'])
        dest.write_bytes(data)
    return dest


def attach_clips(body, source, output):
    doc, blob = read_glb(body)
    clips, source_blob = read_glb(source)
    names = {n.get('name'): i for i, n in enumerate(doc['nodes'])}
    offset = len(blob)
    offset += -offset % 4
    blob.extend(b'\0' * (offset-len(blob)))
    view_offset, accessor_offset = len(doc['bufferViews']), len(doc['accessors'])
    for view in clips['bufferViews']:
        view = copy.deepcopy(view)
        view['byteOffset'] = view.get('byteOffset', 0) + offset
        view['buffer'] = 0
        doc['bufferViews'].append(view)
    converted = set()
    animations = []
    for animation in clips['animations']:
        animation = copy.deepcopy(animation)
        kept = []
        for channel in animation['channels']:
            name = clips['nodes'][channel['target']['node']].get('name')
            # Body-only import. Root stays fixed: physics owns displacement.
            if name not in names or name == 'root_motion':
                continue
            channel['target']['node'] = names[name]
            kept.append(channel)
            sampler = animation['samplers'][channel['sampler']]
            index = sampler['output']
            if channel['target']['path'] == 'translation' and index not in converted:
                accessor = clips['accessors'][index]
                view = clips['bufferViews'][accessor['bufferView']]
                assert accessor['componentType'] == 5126 and accessor['type'] == 'VEC3'
                assert 'sparse' not in accessor and view.get('byteStride', 12) == 12
                start = view.get('byteOffset', 0) + accessor.get('byteOffset', 0)
                for at in range(start, start + accessor['count']*12, 4):
                    value = struct.unpack_from('<f', source_blob, at)[0] / 0.0254
                    struct.pack_into('<f', source_blob, at, value)
                accessor.pop('min', None)
                accessor.pop('max', None)
                converted.add(index)
        animation['channels'] = kept
        for sampler in animation['samplers']:
            sampler['input'] += accessor_offset
            sampler['output'] += accessor_offset
        if kept:
            animations.append(animation)
    for accessor in clips['accessors']:
        accessor = copy.deepcopy(accessor)
        if 'bufferView' in accessor:
            accessor['bufferView'] += view_offset
        doc['accessors'].append(accessor)
    doc.setdefault('animations', []).extend(animations)
    blob.extend(source_blob)
    write_glb(output, doc, blob)
    return [a['name'] for a in animations]


def main():
    import sys
    sys.path.insert(0, str(ROOT))
    import numpy as np
    from tools.source.add_cs2_knives import original_pose
    CACHE.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = json.loads(fetch('inspects/animations.json').read_text())
    weapons = json.loads((ROOT/'data/weapons.json').read_text())['weapons']
    aliases = {'ak47':'ak', 'm4a1':'m4a1_silencer', 'sg552':'sg556', 'scout':'ssg08',
        'sg550':'scar', 'm3':'nova', 'mp5navy':'mp5sd', 'tmp':'mp9', 'galil':'galilar',
        'usp':'usp', 'glock18':'glock', 'p228':'p250', 'elite':'elite',
        'p2000':'hkp2000', 'cz75':'cz75a', 'taser':'taser', 'hegrenade':'hegrenade',
        'smokegrenade':'smokegrenade', 'flashbang':'flashbang', 'incendiary':'incgrenade'}
    selected = ['world/rifle/_default_rifle','world/pistol/_default_pistol',
                'world/knife/_default_knife', 'world/grenade/_default_grenade', 'world/equipment/c4']
    mapping = {}
    for wid, spec in weapons.items():
        token = aliases.get(wid,wid)
        candidates = [k for k in manifest['packs'] if k.startswith('world/') and
                      k.split('/')[-1] in [token, 'rifle_'+token, 'pistol_'+token, 'grenade_'+token]]
        pack = candidates[0] if candidates else ('world/knife/_default_knife' if wid == 'knife' else
               'world/pistol/_default_pistol' if spec.get('slot') == 2 else
               'world/grenade/_default_grenade' if spec.get('grenade') else
               'world/equipment/c4' if wid == 'c4' else 'world/rifle/_default_rifle')
        mapping[wid] = pack
        if pack not in selected:
            selected.append(pack)
    sources = {}
    for pack in selected:
        if pack not in manifest['packs']:
            continue
        sources[pack] = fetch(manifest['packs'][pack]['url'].split('/models/agents/')[1])
    report = {'repository': 'https://github.com/3kh0/cs2go', 'commit': PIN,
              'status': 'active SAS/Phoenix appearances; original physics retained', 'models': [],
              'sources': {k:hashlib.sha256(v.read_bytes()).hexdigest() for k,v in sources.items()}}
    sockets = {}
    for name, upstream, classic in [('sas','roster/ctm-sas.glb','urban'), ('phoenix','roster/tm-phoenix.glb','terror')]:
        original = fetch(upstream)
        decoded = CACHE / (name + '-decoded.glb')
        subprocess.run(['node', str(Path(__file__).with_name('modern_agents')/'decode.mjs'),
                        str(original), str(decoded)], check=True)
        final = OUT / (name + '.glb')
        body = decoded
        for source in sources.values():
            attach_clips(body, source, final)
            body = final
        doc, binary = read_glb(final)
        by_name = {a['name']:a for a in doc['animations']}
        weapon_clips = {}
        # Private aliases refer only to absolute body clips, never weapon-only or additive tracks.
        for wid, pack in mapping.items():
            candidates = [a['name'] for a in read_glb(sources[pack])[0]['animations'] if '@weapon' not in a['name']]
            table = {}
            for action in ['idle','idle_crouch','shoot','reload','reload_crouch','draw','draw_crouch']:
                names = [n for n in candidates if n.startswith(action+'_') and
                         (not n.startswith(action+'_crouch_') or 'crouch' in action)]
                if action in ['idle','shoot']:
                    names = [n for n in names if '.vnmclip+non_additive' in n] or [n for n in names if '.vnmclip' not in n]
                if action == 'shoot' and wid == 'knife':
                    names = ['frontswing_knife']
                if not names:
                    continue
                chosen = names[0]
                alias = 'modern_'+action+'_'+wid
                clip = copy.deepcopy(by_name[chosen]); clip['name'] = alias
                doc['animations'].append(clip)
                table[action] = alias
            weapon_clips[wid] = table
        # Old preview code can select familiar names while playing genuinely native clips.
        for alias, native in {'idle1':'idle_rifle','ref_aim_carbine':'idle_rifle','ref_aim_ak47':'idle_rifle',
                'ref_aim_onehanded':'idle_pistol','walk':'walk_n_rifle','run':'run_n_rifle',
                'crouch_idle':'idle_crouch_rifle','crouchrun':'crouch_n_rifle'}.items():
            clip = copy.deepcopy(by_name[native]);clip['name']=alias;doc['animations'].append(clip)
        write_glb(final, doc, binary)
        # Hand-relative calibration preserves the unchanged p_ mesh orientation and metric scale.
        old, old_binary = read_glb(ROOT/f'assets/models/players/{classic}.glb')
        old_hand = next(i for i,n in enumerate(old['nodes']) if n.get('name') == 'Bip01 R Hand')
        modern_hand = next(i for i,n in enumerate(doc['nodes']) if n.get('name') == 'hand_R')
        turn = np.diag([-1.,1.,-1.,1.])
        sockets[name] = {}
        for wid,spec in weapons.items():
            hold = weapon_clips[wid].get('idle', 'idle_rifle')
            pose = original_pose(doc,binary,hold)[modern_hand]
            ext = 'onehanded' if spec.get('slot')==2 else 'knife' if wid=='knife' else 'carbine'
            old_pose = original_pose(old,old_binary,'ref_aim_'+ext)[old_hand]
            local = np.linalg.inv((turn@pose)[:3,:3]) @ old_pose[:3,:3]
            sockets[name][wid] = {'basis':local.tolist(), 'clips':weapon_clips[wid]}
        roots = doc['scenes'][doc.get('scene',0)]['nodes']
        doc['nodes'].append({'name':'GodotForward', 'rotation':[0,1,0,0], 'children':roots})
        doc['scenes'][doc.get('scene',0)]['nodes']=[len(doc['nodes'])-1]
        write_glb(final,doc,binary)
        report['models'].append({'name':name,'source':BASE+upstream,
            'source_sha256':hashlib.sha256(original.read_bytes()).hexdigest(),
            'output_sha256':hashlib.sha256(final.read_bytes()).hexdigest(),
            'path':str(final.relative_to(ROOT)), 'clips':len(doc['animations'])})
    (ROOT/'data/modern_agent_sockets.json').write_text(json.dumps(sockets,indent=2)+'\n')
    (ROOT/'data/modern_agents_import.json').write_text(json.dumps(report,indent=2)+'\n')


if __name__ == '__main__':
    main()
