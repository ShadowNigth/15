#!/usr/bin/env python3
"""Build explicit sound-only overrides; never re-export animation/model geometry.
Run fetch_native_audio first. JSON event names come from the pinned native pose
report, not guessed animation fractions. Legacy audio stays as a narrow fallback.
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = 'native/sccsgoknives/'


def build():
    manifest = json.loads((ROOT/'data/native_audio_manifest.json').read_text())
    paths = {f['path'] for f in manifest['files']}
    def cue(stem):
        direct = [BASE+stem+ext for ext in ('.ogg', '.wav') if BASE+stem+ext in paths]
        return direct or sorted(p for p in paths if re.fullmatch(re.escape(BASE+stem)+r'_\d+\.(ogg|wav)', p))
    def first(stem):
        return next(iter(cue(stem)), '')
    sounds = json.loads((Path.home()/'.cache/scsounds-code/cs2_sounds.json').read_text())['Clips']
    event_assets = {}
    for key, clip in sounds.items():
        weapon = key.split(':')[0]
        for e in clip['Cues']:
            if e.get('Asset'):
                event_assets[(weapon, e['Event'].lower())] = e['Asset']
    reports = json.loads((ROOT/'data/native_gun_animation_report.json').read_text())
    weapons = json.loads((ROOT/'data/weapons.json').read_text())['weapons']
    models = json.loads((ROOT/'data/models_meta.json').read_text())
    specs, events, unresolved = {}, {}, {}
    for wid, report in reports.items():
        family = report['source_weapon']
        patch = {}
        for field, stem in [('fire_sounds', family+'_fire'), ('silenced_sounds', family+'_fire_silenced'),
                            ('deploy_sound', family+'_draw'), ('reload_sound', family+'_clipout'),
                            ('insert_sound', family+'_insertshell'), ('prepare_sound', family+'_prepare'),
                            ('zoom_sound', family+'_zoom'), ('silencer_on_sound', family+'_silencer_on'),
                            ('silencer_off_sound', family+'_silencer_off')]:
            found = cue(stem)
            if found:
                patch[field] = found if field.endswith('_sounds') else found[0]
        if family.startswith('grenade_'):
            for field, suffix in [('deploy_sound','draw'),('pinpull_sound','pin'),('throw_sound','throw'),('bounce_sound','bounce')]:
                if cue(family+'_'+suffix): patch[field] = first(family+'_'+suffix)
            if cue(family+'_explode'): patch['explode_sounds'] = cue(family+'_explode')
        specs[wid] = patch
        target = {}
        for name, source_clip in report['clips'].items():
            raw = report['source_events'].get('draw' if wid == 'usp' and name == 'draw_unsil' else name)
            if raw is None:
                original = next((n for n,s in report['clips'].items() if s == source_clip and n in report['source_events']), None)
                raw = report['source_events'].get(original, [])
            start = report['shotgun_segments'].get(name, [0])[0]
            sequence = []
            for e in raw:
                if e.get('Class') != 'CNmClipDocEvent_Sound': continue
                event = e['Name']; lower = event.lower(); suffix = lower.split('.')[-1].removesuffix('_q')
                # Shot audio is owned by WeaponController for human AND AI. Do
                # not replay it from animation events, including auto/burst fire.
                if any(x in suffix for x in ('single', 'shoot', 'fire')): continue
                asset = event_assets.get((family, lower))
                found = cue(asset) if asset else []
                if not found:
                    candidates = [family+'_'+suffix]
                    if 'weaponmove' in suffix: candidates += ['movement'+suffix[-1]]
                    if 'pullpin' in suffix: candidates += [family+'_pin']
                    if suffix in ('throw','throwunder') and family.startswith('grenade_'): candidates += [family+'_throw']
                    if family == 'c4' and suffix == 'keypressquiet': candidates += ['c4_key_press1']
                    if lower == 'c4.draw.beep': candidates += ['c4_draw_01']
                    if lower == 'c4.draw.grab': candidates += ['c4_draw_grab_01']
                    if lower.endswith('.gear') or lower.startswith('inspect.gear.'): candidates += ['movement1']
                    if 'insertshell' in suffix: candidates += [family+'_insertshell']
                    if family == 'm4a4': candidates += ['m4a1s_'+suffix]
                    for candidate in candidates:
                        found = cue(candidate)
                        if found: break
                t = round(float(e['At'])-start, 6)
                if not found:
                    unresolved.setdefault(wid, set()).add(event)
                    continue
                if t < -0.00001 or t > float(models['weapons/'+weapons[wid]['v_model']]['seq_durations'][name])+0.00001: continue
                sequence.append(dict(t=max(0,t), wav=found[0], variants=found, source_event=event))
            # Preserve truly missing recordings only, not generic recordings from
            # the wrong firearm. Matched native events replace the old schedule.
            if not sequence:
                sequence = models['weapons/'+weapons[wid]['v_model']]['seq_events'].get(name, [])
            target[name] = sorted(sequence, key=lambda e:e['t'])
        if family.startswith('grenade_') and 'pinpull_sound' in patch:
            pin = patch['pinpull_sound']
            if not any(e.get('wav') == pin for e in target.get('pullpin', [])):
                target.setdefault('pullpin', []).insert(0, dict(t=0.0, wav=pin, source_event='action:pullpin'))
        events['weapons/'+weapons[wid]['v_model']] = target
    specs['knife'] = dict(fire_sounds=cue('knife_slash'), deploy_sound=first('knife_deploy'))
    knife_reports = json.loads((ROOT/'data/native_knife_animation_report.json').read_text())
    for knife, report in knife_reports.items():
        target = {}
        for clip in report['clips']:
            if clip.startswith('draw'):
                target[clip] = [dict(t=0.0, wav=first('butterfly_draw' if knife == 'butterfly' else 'knife_deploy'))]
            elif knife == 'butterfly' and clip.startswith('inspect'):
                target[clip] = [dict(t=0.0, wav=first('butterfly_inspect'))]
        # Compatibility aliases must carry the exact same sound schedule.
        for alias, native in [('deploy','draw'),('deploy2','draw_2'),('inspect2','inspect_2'),('inspect3','inspect_3')]:
            if native in target: target[alias] = target[native]
        events['weapons/v_knife_'+knife] = target
    replacements = {}
    for old, stem in [('player/bhit_helmet-1.wav','hits/helmet_dink'),('player/bhit_kevlar-1.wav','hits/kevlar')]:
        replacements[old] = cue(stem)
    for i in range(1,4):
        replacements[f'player/headshot{i}.wav'] = cue('hits/headshot_noarmor')
        replacements[f'player/pl_shell{i}.wav'] = cue('casing_metal')
    cues = {name:cue(stem) for name,stem in dict(
        he_explode='grenade_hegrenade_explode', flash_explode='grenade_flashbang_explode',
        smoke_emit='grenade_smokegrenade_emit', smoke_clear='grenade_smokegrenade_clear',
        molotov_explode='grenade_molotov_explode', incendiary_explode='grenade_incendiary_explode',
        fire_loop='grenade_fire_loop', fire_extinguish='grenade_fire_extinguish', fire_airburst='grenade_fire_airburst',
        c4_start='c4_initiate', c4_beep='c4_beep2', c4_beep_fast='c4_beep2_10sec',
        c4_defuse_start='c4_disarmstart', c4_defuse_end='c4_disarmfinish', c4_explode='c4_explode_close_01',
        headshot_armor='hits/headshot_armor', casing_shotgun='casing_shotgun',
        kill_confirm='bf1_kill_ding').items()}
    cues['respawn'] = ['native/sccsgodeathmatch/respawn.ogg']
    cues['match_end'] = ['native/sccsgodeathmatch/match_end.ogg']
    voices = {}
    for p in sorted(paths):
        if p.startswith('native/sccsgovoice/'):
            language,team,name = p.removeprefix('native/sccsgovoice/').split('/')
            command = name.rsplit('-',1)[0]
            voices.setdefault(language,{}).setdefault(team,{}).setdefault(command,[]).append(p)
    catalog = dict(commit=manifest['commit'], weapons=specs, model_events=events,
                   replacements=replacements, cues=cues, voices=voices,
                   unresolved_events={k:sorted(v) for k,v in unresolved.items()})
    (ROOT/'data/native_audio.json').write_text(json.dumps(catalog, indent=2)+'\n')
    print('Audio routes:', len(specs), 'slots;',len(events),'rigs;',sum(len(v) for clips in events.values() for v in clips.values()),'timed cues')
    print('Missing source event names retained in report:', sum(len(s) for s in unresolved.values()))


if __name__ == '__main__': build()
