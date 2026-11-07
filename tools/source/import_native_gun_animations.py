#!/usr/bin/env python3
"""Retarget pinned ScCsgoKnives firearm/utility clips onto the installed meshes.

No replacement geometry, UVs, skin weights, materials or inverse binds. Mechanical
motion is transferred in global space using per-bone idle reference frames, NOT
by copying rotations between incompatible joint axes. Original unmapped helper
bones inherit the nearest mapped parent's motion. See the generated report.
"""
import copy
import hashlib
import json
import re
import sys
from pathlib import Path

import numpy as np
from scipy.spatial.transform import Rotation

from . import add_cs2_knives as base
from . import import_native_knife_animations as native
from .build_sport_gloves import _accessor
from .native_animation_sounds import NativeSounds

SOURCE_IDS = dict(p228='p250', mp5navy='mp5sd', tmp='mp9', sg552='sg556', scout='ssg08',
                  sg550='scar20', m3='nova', m4a1='m4a1s', usp='usp_silencer',
                  cz75='cz75a', galil='galilar', p2000='hkp2000')
for _g in ['decoy', 'flashbang', 'hegrenade', 'incendiary', 'molotov', 'smokegrenade']:
    SOURCE_IDS[_g] = 'grenade_' + _g


def anatomical(name):
    if re.match(r'^v_weapon\.Bip01_[LR]_(Forearm|ForeTwist|Hand|Finger[0-4][12]?)$', name):
        return native.correspondence(name)
    if re.match(r'^v_weapon\.Bip01_[LR]_(UpperArm|Clavicle)$', name):
        side, part = name.removeprefix('v_weapon.Bip01_').split('_')
        return ('arm_upper_' if part == 'UpperArm' else 'armUpperShoulder_') + side
    return None


def mechanical_map(doc, source, wid):
    names = {n['name'] for n in source}
    root = 'weapon_offset' if 'weapon_offset' in names else 'weapon'
    result = {}
    for i, node in enumerate(doc['nodes']):
        name = node['name']
        if anatomical(name) is not None:
            continue
        part = name.lower().replace('v_weapon.', '').replace('v_weapon_', '')
        # Longest suffix first: bolt_action must not become bolt, and magazine2
        # must not become magazine. Legacy model prefixes are deliberately ignored.
        match = next((n for n in sorted(names - {'weapon', 'wpn', 'root_motion'}, key=len, reverse=True)
                      if part == n.lower() or part.endswith('_' + n.lower())), None)
        if match:
            result[i] = match
        for old, new in [('mag', 'magazine'), ('clip', 'magazine'), ('magazine', 'clip'),
                         ('magazine', 'mag'), ('clip', 'mag'), ('bolt', 'chamber')]:
            if new in names and (part == old or part.endswith('_' + old)) and i not in result:
                result[i] = new
        if wid == 'elite':
            hit = re.search(r'_([lr])_(hammer|trigger|slide|magazine)$', part)
            if hit: result[i] = hit[2] + '_' + hit[1]
            if part in ['muzzle', 'muzzle2']: result[i] = 'muzzle_r' if part == 'muzzle' else 'muzzle_l'
        if wid == 'c4' and part == 'c4_switch': result[i] = 'detonator_switch'
        if part in ['weapon_hand_r', 'weapon_hand_l']:
            result[i] = ('weapon_r' if part.endswith('_r') else 'weapon_l') if wid == 'elite' else (
                ('molotov' if part.endswith('_r') else 'lighter') if wid == 'molotov' else root)
        if wid == 'elite':
            for old, new in [('left_elite', 'weapon_l'), ('right_elite', 'weapon_r'),
                             ('left_clip', 'magazine_l'), ('right_clip', 'magazine_r'),
                             ('left_slide', 'slide_l'), ('right_slide', 'slide_r'),
                             ('left_hammer', 'hammer_l'), ('right_hammer', 'hammer_r')]:
                if part.endswith(old): result[i] = new
        # These are body/attachment helpers, not anatomical or animated parts.
        if part in ['v_weapon', 'cam_driver'] or part.endswith('_parent'):
            result.setdefault(i, root)
    return result


def clip_name(source_name, clip, used):
    alias = clip.get('Alias')
    aliases = dict(deploy='draw', deploy2='draw_2', deploySilenced='draw',
                   inspect2='inspect_2', inspect3='inspect_3', shootEmpty='shootlast',
                   idleEmpty='idle_empty', reloadEmpty='reload_empty',
                   shootLeft='shoot_left1', shootLeftLast='shoot_leftlast',
                   shootRightLast='shoot_rightlast', idleLeftEmpty='idle_leftempty',
                   idleBothEmpty='idle_bothempty', throwHigh='throw', throwLow='underhand',
                   holdHigh='hold_high', holdLow='hold_low', plant='pressbutton',
                   prepareShoot='prepare', shootAlt='alt1', dryFire='dryfire')
    if alias:
        name = aliases.get(alias, alias)
        if alias == 'deploySilenced': name = 'draw_silenced'
    elif source_name.startswith('lookat0') and re.match(r'^lookat\d+_[a-z0-9]+$', source_name):
        name = 'inspect' if 'inspect' not in used else 'inspect_2'
    elif source_name.startswith('silencer_attach'):
        name = 'attach'
    elif source_name.startswith('silencer_detach'):
        name = 'detach'
    elif source_name.startswith(('draw_', 'idle_', 'shoot1_', 'reload_')):
        name = source_name.split('_')[0]
    else:
        name = 'native_' + source_name
    assert name not in used, (source_name, name)
    return name


def setup(wid, spec, folder):
    path = base.ROOT / ('assets/models/weapons/' + spec['v_model'] + '.glb')
    doc, binary = base.read_glb(str(path))
    srcfile = folder / (SOURCE_IDS.get(wid, wid) + '.cs2.animation.json')
    animation = json.loads(srcfile.read_text())
    source = native.source_nodes(animation)
    idx = {n['name']:i for i,n in enumerate(source)}
    mapping = mechanical_map(doc, source, wid)
    old_idle = base.original_pose(doc, binary, 'idle')
    idle_clip = next(c for n,c in animation['Clips'].items() if c.get('Alias') == 'idle' or n.startswith(('idle_', 'idle1_')))
    idle = native.sample_poses(source, idle_clip, np.array([0.0]))[0]
    # All installed archi ports use 1/32 metre per Source unit and a +2-unit
    # camera-Z root offset. Native JSON is inches (0.0254 m) with the opposite
    # camera-X parity. Undo that port transform before transferring motion.
    placement = np.diag([-0.8128, 0.8128, 0.8128, 1.0])
    placement[2, 3] = -0.0508
    landmarks = {}
    for i,n in mapping.items():
        if n in ['muzzle', 'clip', 'magazine', 'slide', 'bolt', 'trigger', 'pump', 'silencer', 'muzzle_l', 'muzzle_r']:
            landmarks[doc['nodes'][i]['name']] = float(np.linalg.norm((placement @ old_idle[i])[:3,3] - (native.C @ idle[idx[n]])[:3,3]))
    return path, doc, binary, srcfile, animation, source, idx, mapping, old_idle, idle, placement, landmarks


def sample_native(source, animation, clip, times):
    """CS2 RelativeToFrame/FirstFrame deltas belong over the moving idle pose.

    Matches Cs2Rig.SampleAdditive, including subtraction of frame-zero root/wp n
    rotations: treating the R8 layer as an absolute pose puts hands at the eye.
    """
    if not clip.get('Additive'):
        return native.sample_poses(source, clip, times)
    assert clip['Additive'] == 'RelativeToFrame' and clip['AdditiveBase'] == 'FirstFrame'
    under = next(c for c in animation['Clips'].values() if c.get('Alias') == clip.get('AdditiveOver','idle'))
    base_times = np.mod(times, float(under['Duration'])) if under['Duration'] else np.zeros(len(times))
    bases = native.sample_poses(source, under, base_times)
    layers = native.sample_poses(source, clip, np.r_[0.0,times])
    parents = {c:i for i,n in enumerate(source) for c in n.get('children',[])}
    result = []
    for f,base_pose in enumerate(bases):
        overrides = {}
        for i,node in enumerate(source):
            parent = parents.get(i)
            def local(pose):
                return np.linalg.inv(pose[parent]) @ pose[i] if parent is not None else pose[i]
            b, first, now = local(base_pose),local(layers[0]),local(layers[f+1])
            rotation = b[:3,:3] @ np.linalg.inv(first[:3,:3]) @ now[:3,:3]
            overrides[i] = dict(translation=b[:3,3]+now[:3,3]-first[:3,3],rotation=Rotation.from_matrix(rotation).as_quat(),scale=node['scale'])
        result.append(base.matrices(source,overrides))
    return result


def configure_import(path):
    """Keep native keys accurate: Godot's default lossy optimizer drops small
    hand/part movements. Also retain constant scales for suppressor overrides.
    """
    resource = 'res://' + str(path.relative_to(base.ROOT))
    cache = 'res://.godot/imported/' + path.name + '-' + hashlib.md5(resource.encode()).hexdigest() + '.scn'
    settings = {key:{'optimizer/enabled':False,'compression/enabled':False}
                for key in ['PATH:AnimationPlayer','AnimationPlayer','PATH:Armature/AnimationPlayer']}
    text = '[remap]\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\npath='+json.dumps(cache)+'\n\n[deps]\nsource_file='+json.dumps(resource)+'\ndest_files=['+json.dumps(cache)+']\n\n[params]\n'
    text += 'nodes/root_type=""\nnodes/root_name=""\nnodes/apply_root_scale=true\nnodes/root_scale=1.0\nmeshes/ensure_tangents=true\nmeshes/generate_lods=false\nmeshes/create_shadow_meshes=false\nmeshes/light_baking=0\nskins/use_named_skins=true\nanimation/import=true\nanimation/fps=60\nanimation/trimming=false\nanimation/remove_immutable_tracks=false\nanimation/import_rest_as_RESET=false\nimport_script/path=""\n'
    text += '_subresources=' + json.dumps({'nodes':settings}).replace('false','false')+'\n'
    path.with_suffix(path.suffix+'.import').write_text(text)


def main(folder, selected=None, analyze=False):
    folder = Path(folder)
    weapons = json.loads((base.ROOT / 'data/weapons.json').read_text())['weapons']
    meta_path = base.ROOT / 'data/models_meta.json'
    metadata = json.loads(meta_path.read_text())
    report_path = base.ROOT / 'data/native_gun_animation_report.json'
    reports = json.loads(report_path.read_text()) if report_path.exists() else {}
    sounds = NativeSounds.__new__(NativeSounds)
    sounds.files = {str(p.relative_to(base.ROOT / 'assets/sounds/weapons/archi')).lower():str(p)
                    for p in (base.ROOT / 'assets/sounds/weapons/archi').rglob('*.wav')}
    sounds.unresolved = {}
    for wid, spec in weapons.items():
        if wid == 'knife' or (selected and wid not in selected): continue
        state = setup(wid, spec, folder)
        path, doc, binary, srcfile, animation, source, idx, mapping, old_idle, idle, placement, landmarks = state
        if analyze:
            print(wid, 'mapping', {doc['nodes'][i]['name']: n for i,n in mapping.items()}, 'errors_m', landmarks, flush=True)
            continue
        m = metadata['weapons/' + spec['v_model']]
        assert not m.get('native_gun_animations'), 'Start from original GLB/metadata, not an already converted rig'
        original, obin = copy.deepcopy(doc), bytes(binary)
        parents = {c:i for i,n in enumerate(doc['nodes']) for c in n.get('children', [])}
        joints = set(j for skin in doc['skins'] for j in skin['joints'])
        calibration = copy.deepcopy(original)
        for node in calibration['nodes']:
            if not re.match(r'^v_weapon\.Bip01_[LR]_(Forearm|ForeTwist|Hand|Finger[0-4][12]?)$', node['name']):
                node['name'] = '_' + node['name']
        axes, errors = native.axis_calibration(calibration, source, base.matrices(source), base.matrices(original['nodes']))
        # A few legacy rigs give individual phalanges a different local axis
        # (notably the R8 right ring finger). Correct those outliers individually
        # instead of rotating the entire hand to accommodate one bent bind bone.
        old_bind, source_bind = base.matrices(original['nodes']),base.matrices(source)
        bone_axes, directional_errors = {},{'L':[],'R':[]}
        for i,node in enumerate(calibration['nodes']):
            mapped = native.correspondence(node['name'])
            parent = parents.get(i)
            if mapped is None or parent is None or node['name'].endswith('ForeTwist'): continue
            mp = native.correspondence(calibration['nodes'][parent]['name'])
            if mp is None: continue
            side = node['name'].removeprefix('v_weapon.Bip01_')[0]
            a = (np.linalg.inv(old_bind[parent]) @ old_bind[i])[:3,3]
            b = (np.linalg.inv(source_bind[idx[mp]]) @ source_bind[idx[mapped]])[:3,3]
            if min(np.linalg.norm(a),np.linalg.norm(b)) < 1e-6: continue
            a,b = a/np.linalg.norm(a),b/np.linalg.norm(b)
            k = axes[side]
            error = float(np.degrees(np.arccos(np.clip(np.dot(k@a,b),-1,1))))
            if error > 15 and 'Finger' in original['nodes'][parent]['name']:
                correction = Rotation.align_vectors([b],[k@a])[0].as_matrix()
                bone_axes[parent] = correction @ k
                error = 0.0
            directional_errors[side].append(error)
        post_axis_errors = {side:max(values) for side,values in directional_errors.items()}
        # Right-side factors preserve each old part's pivot, local axes, scale,
        # and exact geometry at idle. The left factor supplies native motion.
        factors = {i:np.linalg.inv(native.C @ idle[idx[n]] @ native.CI) @ placement @ old_idle[i]
                   for i,n in mapping.items()}
        fallback = {}
        for i in joints - mapping.keys():
            parent = parents.get(i)
            while parent is not None and parent not in mapping:
                parent = parents.get(parent)
            fallback[i] = parent

        def target(pose, clip=None, at=0.0):
            out = [x.copy() for x in old_idle]
            for i,n in mapping.items():
                out[i] = native.C @ pose[idx[n]] @ native.CI @ factors[i]
            for i in joints:
                anatomical_name = anatomical(doc['nodes'][i]['name'])
                if anatomical_name:
                    side = doc['nodes'][i]['name'].removeprefix('v_weapon.Bip01_')[0]
                    out[i] = np.eye(4)
                    out[i][:3,:3] = native.AXIS @ pose[idx[anatomical_name]][:3,:3] @ bone_axes.get(i,axes[side])
                    out[i][:3,3] = (native.C @ pose[idx[anatomical_name]])[:3,3]
                elif i not in mapping:
                    parent = fallback[i]
                    out[i] = out[parent] @ np.linalg.inv(old_idle[parent]) @ old_idle[i] if parent is not None else placement @ old_idle[i]
            # Native graph visibility for reload-only helper props. These rules
            # are not present in absolute bone curves (ScGunPartVisibility.cs).
            for i,n in mapping.items():
                hidden = wid == 'revolver' and n in ['loader_handle','loader_holder'] and (clip is None or not clip['SourceName'].startswith('reload'))
                if wid == 'sawedoff' and n == 'shell':
                    marks = {e['Name']:float(e['At']) for e in (clip or {}).get('Events',[]) if e['Class'] == 'CNmClipDocEvent_ID'}
                    hidden = not (marks.get('WPN_RELOAD_LOOP',float('inf')) <= at < marks.get('WPN_RELOAD_OUTRO',float('-inf')))
                if wid == 'cz75' and n == 'magazine2':
                    detach = next((float(e['At']) for e in (clip or {}).get('Events',[]) if e['Name'] == 'Weapon_CZ.Clipout2'),float('inf'))
                    hidden = at >= detach or (clip is not None and clip.get('Alias','').startswith('reloadFollowup'))
                if hidden: out[i][:3,:3] *= 0.0001
            return out

        idle_target = target(idle)
        for i in joints:
            parent = parents.get(i)
            local = np.linalg.inv(idle_target[parent]) @ idle_target[i] if parent is not None else idle_target[i]
            t,r,scale = native.decompose([local])
            doc['nodes'][i] = {k:v for k,v in doc['nodes'][i].items() if k not in ['matrix','translation','rotation','scale']}
            doc['nodes'][i].update(translation=t[0].tolist(), rotation=r[0].tolist(), scale=scale[0].tolist())
        doc['animations'] = []
        durations, sources, events, raw_events, segments, checkpoints = {}, {}, {}, {}, {}, {}
        all_clips = []
        for source_name, clip in animation['Clips'].items():
            name = clip_name(source_name, clip, durations)
            duration = float(clip['Duration']) or 1.0
            all_clips.append((name, source_name, clip, 0.0, duration))
            durations[name] = duration
            if bool(spec.get('shotgun_reload')) and name == 'reload':
                marks = {e['Name']:e for e in clip.get('Events', []) if e.get('Class') == 'CNmClipDocEvent_ID'}
                for alias, marker in [('start_reload','WPN_RELOAD_INTRO'),('insert','WPN_RELOAD_LOOP'),('after_reload','WPN_RELOAD_OUTRO')]:
                    e = marks[marker]
                    start, end = float(e['At']), min(float(clip['Duration']),float(e['At'])+float(e['Duration']))
                    if alias == 'start_reload':
                        # Classic controller credits the first shell when its
                        # start timer ends. Include that first native insertion,
                        # then repeat only the native loop for subsequent shells.
                        loop = marks['WPN_RELOAD_LOOP']
                        end = float(loop['At'])+float(loop['Duration'])
                    all_clips.append((alias,source_name,clip,start,end))
                    durations[alias] = end-start
                    segments[alias] = [start,end]
        for name, source_name, clip, start, end in all_clips:
            duration = end-start
            samples = np.array(sorted({start,end} | {float(t) for tracks in clip['Bones'].values()
                for field,tr in tracks.items() if field in ['Translation','Rotation','Scale'] for t in tr['Times'] if start < float(t) < end}))
            extra = {float(e['At']) for e in clip.get('Events',[]) if start < float(e.get('At',0)) < end}
            if clip.get('Additive'):
                under = next(c for c in animation['Clips'].values() if c.get('Alias') == clip.get('AdditiveOver','idle'))
                extra |= {float(t) for curves in under['Bones'].values() for field,tr in curves.items() if field in ['Translation','Rotation','Scale'] for t in tr['Times'] if start < float(t) < end}
            samples = np.array(sorted(set(samples) | extra | {max(start,t-0.00001) for t in extra}))
            poses = sample_native(source, animation, clip, samples)
            targets = np.array([target(pose,clip,float(at)) for pose,at in zip(poses,samples)])
            times = samples-start
            if True:  # Every source clip, including helpers and secondary variants.
                chosen = sorted({0,len(times)//3,2*len(times)//3,len(times)-1})
                tracked = [i for i in sorted(joints) if anatomical(doc['nodes'][i]['name']) in ['hand_L','hand_R'] or i in mapping and mapping[i] in ['clip','magazine','slide','bolt','pump','silencer','weapon_l','weapon_r','lighter','molotov','detonator_switch','loader_handle','loader_holder','shell','magazine2']]
                checkpoints[name] = [dict(t=float(times[f]), bones={doc['nodes'][i]['name']:targets[f,i].round(7).tolist() for i in tracked}) for f in chosen]
            track = dict(name=name, samplers=[], channels=[], extras=dict(source_clip=source_name,source_interval=[start,end]))
            # Drop numerically constant channels to two keys; all changing source
            # samples and endpoints remain. This saves space without decimation.
            time_accessors = {}
            for i in sorted(joints):
                parent = parents.get(i)
                local = np.linalg.inv(targets[:,parent]) @ targets[:,i] if parent is not None else targets[:,i]
                t,r,scale = native.decompose(local)
                for field,kind,values in [('translation','VEC3',t),('rotation','VEC4',r),('scale','VEC3',scale)]:
                    if field == 'rotation':
                        for f in range(1,len(values)):
                            if np.dot(values[f-1],values[f]) < 0: values[f] *= -1
                    constant = np.max(np.abs(values-values[0])) < 1e-7
                    used_times, used_values = (times[[0,-1]], values[[0,-1]]) if constant else (times, values)
                    key = 'constant' if constant else 'full'
                    if key not in time_accessors:
                        inp = base.append_array(doc,binary,used_times,'SCALAR')
                        doc['accessors'][inp].update(min=[0.0], max=[duration])
                        time_accessors[key] = inp
                    out = base.append_array(doc,binary,used_values,kind)
                    track['channels'].append(dict(sampler=len(track['samplers']),target=dict(node=i,path=field)))
                    visibility_scale = field == 'scale' and i in mapping and ((wid == 'revolver' and mapping[i] in ['loader_handle','loader_holder']) or (wid == 'sawedoff' and mapping[i] == 'shell') or (wid == 'cz75' and mapping[i] == 'magazine2'))
                    track['samplers'].append(dict(input=time_accessors[key],output=out,interpolation='STEP' if visibility_scale else 'LINEAR'))
            doc['animations'].append(track)
            sources[name] = source_name
            raw_events[name] = [e for e in clip.get('Events',[]) if start <= float(e.get('At',0)) < end]
            for e in raw_events[name]:
                if e.get('Class') != 'CNmClipDocEvent_Sound': continue
                sound = sounds.find(e['Name'],wid)
                wav = 'weapons/archi/'+sound if sound else None
                if wid in ['m4a4','mag7']:
                    # Keep the dedicated recordings introduced before this
                    # animation conversion; only their native event times change.
                    family = 'm4a1' if wid == 'm4a4' else 'mag7'
                    suffix = e['Name'].split('.',1)[-1].lower().removesuffix('_q')
                    suffix = {'pumpback':'pump_back','pumpforward':'pump_forward'}.get(suffix,suffix) if wid=='mag7' else suffix
                    candidate = 'weapons/cs2/'+family+'/'+family+'_'+suffix+'.wav'
                    wav = candidate if (base.ROOT/'assets/sounds'/candidate).is_file() else None
                if wav:
                    events.setdefault(name,[]).append(dict(t=float(e['At'])-start,wav=wav))
        # Compatibility routes are aliases to native tracks, never old animation
        # data. Glock burst retriggers the same native slide cycle per shot.
        aliases = dict(shoot='shoot1',shoot2='shoot1',shoot3='shoot1',shoot_empty='shootlast',
                       fire='shoot1',alt2='alt1',alt3='alt1',add_silencer='attach',detach_silencer='detach',
                       draw_unsil='draw',idle_unsil='idle',reload_unsil='reload',inspect_unsil='inspect',
                       shoot1_unsil='shoot1',shoot2_unsil='shoot1',shoot3_unsil='shoot1',shootlast_unsil='shootlast')
        if wid == 'elite': aliases['shoot_right1'] = 'shoot1'
        if wid == 'usp': aliases['draw'], aliases['draw_unsil'] = 'draw_silenced', 'draw'
        by_name = {a['name']:a for a in doc['animations']}
        for alias,source_alias in aliases.items():
            if source_alias not in by_name or (alias in by_name and alias != 'draw'): continue
            track = copy.deepcopy(by_name[source_alias]); track['name'] = alias
            if alias == 'draw' and alias in by_name:
                doc['animations'] = [a for a in doc['animations'] if a['name'] != alias]
            doc['animations'].append(track)
            durations[alias] = durations[source_alias]; sources[alias] = sources[source_alias]
            events[alias] = copy.deepcopy(events.get(source_alias,[]))
        binary = native.compact(doc,binary)
        # Hard byte-equivalence checks for ALL original primitives and binds.
        for om,nm in zip(original['meshes'],doc['meshes']):
            for op,np_ in zip(om['primitives'],nm['primitives']):
                for field in op['attributes']:
                    assert np.array_equal(_accessor(original,obin,op['attributes'][field]),_accessor(doc,binary,np_['attributes'][field]))
                assert np.array_equal(_accessor(original,obin,op['indices']),_accessor(doc,binary,np_['indices']))
        for os,ns in zip(original['skins'],doc['skins']):
            assert np.array_equal(_accessor(original,obin,os['inverseBindMatrices']),_accessor(doc,binary,ns['inverseBindMatrices']))
        sha = hashlib.sha256(srcfile.read_bytes()).hexdigest()
        doc['asset']['native_cs2_animation_sha256'] = sha
        base.write_glb(str(path),doc,binary)
        configure_import(path)
        gameplay = copy.deepcopy(m['seq_durations'])
        # Source durations stay intact. Runtime retimes only gameplay actions
        # to their pre-conversion durations and retimes sound events identically.
        if 'reload_empty' in durations: gameplay.setdefault('reload_empty',gameplay.get('reload',float(spec.get('reload_time',2.5))))
        m.update(cz_spare_detach_times={n:next((float(e['At']) for e in animation['Clips'][sn].get('Events',[]) if e['Name']=='Weapon_CZ.Clipout2'),None) for n,sn in sources.items()} if wid=='cz75' else {},gameplay_seq_durations=gameplay, sequences=list(durations),seq_durations=durations,seq_events=events,
                 native_cs2_animation=True,native_gun_animations=True,authored_right_hand=True,
                 inspect_clips=[n for n in sources if n.startswith('inspect') and n != 'inspect_unsil'],
                 animation_source='ScCsgoKnives native per-weapon clips, original geometry and anatomical arm retarget')
        for field in ['muzzle','muzzle_unsil','muzzle_alt','eject']:
            if isinstance(m.get(field),list): m[field] = ((placement @ np.array(m[field]+[1.0]))[:3] + np.array([0.0635,-0.0381,0])).round(7).tolist()
        reports[wid] = dict(source_commit=base.SOURCE_COMMIT,source_weapon=SOURCE_IDS.get(wid,wid),animation_sha256=sha,
             source_clip_count=len(animation['Clips']),pose_checkpoints=checkpoints,clips=sources,durations=durations,shotgun_segments=segments,
             mechanical_bones={original['nodes'][i]['name']:n for i,n in mapping.items()},
             idle_pivot_residual_m=landmarks,axis_max_error_deg=post_axis_errors,axis_global_fit_error_deg=errors,
             per_bone_axis_overrides={original['nodes'][i]['name']:k.tolist() for i,k in bone_axes.items()},source_events=raw_events,
             original_geometry_uv_weights_indices_and_inverse_binds_preserved=True,
             mechanical_transfer='C N(t) N(idle)^-1 C^-1 D O(idle); per-bone frame calibration',
             placement_matrix=placement.tolist())
        print('NATIVE GUN',wid,'source clips',len(animation['Clips']),'runtime clips',len(durations),'axis errors',errors,flush=True)
        meta_path.write_text(json.dumps(metadata,indent=2,ensure_ascii=False)+'\n')
        report_path.write_text(json.dumps(reports,indent=2)+'\n')


if __name__ == '__main__':
    args = sys.argv[1:]
    analyze = '--analyze' in args
    if analyze: args.remove('--analyze')
    main(args[0], args[1:] or None, analyze)
