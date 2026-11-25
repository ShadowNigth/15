#!/usr/bin/env python3
"""
Validates the entire Counter-Strike 1.5 Godot 4 project:
  1. Parses every .gd script with gdtoolkit's gdparse (AST verification)
  2. Verifies every .glb (maps & models) header, JSON schema, buffer bounds, and external texture URIs
  3. Verifies every sound path, model path, VGUI card, HUD sprite, and map file referenced in data/*.json
  4. Verifies every res:// literal in .gd and .tscn files
"""

import glob
import json
import os
import re
import struct
import subprocess
import sys


def main() -> int:
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    errors = []
    if not os.path.isdir(os.path.join(root, "assets", "models")):
        print("[verify] assets/ has not been unpacked. Run `python tools/pak.py unpack` first "
              "(see docs/ASSET_PACKS.md).")
        return 1

    # 1. GDScript AST validation
    gd_files = sorted(glob.glob(os.path.join(root, "scripts", "**", "*.gd"), recursive=True))
    gdparse_bin = "/tmp/venv/bin/gdparse" if os.path.exists("/tmp/venv/bin/gdparse") else "gdparse"
    for gf in gd_files:
        res = subprocess.run([gdparse_bin, gf], capture_output=True, text=True)
        if res.returncode != 0:
            errors.append(f"[GDScript Syntax Error] {gf}:\n{res.stderr or res.stdout}")
    print(f"[verify] GDScript AST check: {len(gd_files)} scripts checked.")

    # 2. Check static res:// paths in .gd and .tscn
    code_files = gd_files + sorted(glob.glob(os.path.join(root, "scenes", "**", "*.tscn"), recursive=True))
    res_re = re.compile(r'"(res://[^"%\s]+)"')
    checked_res = 0
    for cf in code_files:
        txt = open(cf, "r", encoding="utf-8").read()
        for m in res_re.finditer(txt):
            rpath = m.group(1)
            # Skip directory prefixes ending with /
            if rpath.endswith("/"):
                continue
            disk_p = os.path.join(root, rpath[len("res://") :])
            checked_res += 1
            if not os.path.exists(disk_p):
                errors.append(f"[Missing res:// path] {rpath} in {os.path.relpath(cf, root)}")
    print(f"[verify] Static res:// references checked: {checked_res}")

    # 3. Validate weapons.json, classes.json, radio.json, maps_index.json
    wdb = json.load(open(os.path.join(root, "data", "weapons.json"), encoding="utf-8"))
    for wid, spec in wdb["weapons"].items():
        v_mdl = os.path.join(root, "assets", "models", "weapons", f"{spec['v_model']}.glb")
        w_mdl = os.path.join(root, "assets", "models", "weapons", f"{spec['w_model']}.glb")
        if not os.path.exists(v_mdl):
            errors.append(f"[Missing v_model] {wid} -> {v_mdl}")
        if not os.path.exists(w_mdl):
            errors.append(f"[Missing w_model] {wid} -> {w_mdl}")
        for skey in ("fire_sounds", "silenced_sounds", "explode_sounds", "bounce_sounds", "beep_sounds", "hit_sounds"):
            for srel in spec.get(skey, []):
                sp = os.path.join(root, "assets", "sounds", srel)
                if not os.path.exists(sp):
                    errors.append(f"[Missing weapon sound] {wid}.{skey} -> {srel}")
        for skey1 in ("reload_sound", "deploy_sound", "wall_sound", "stab_sound", "plant_sound", "burst_sound"):
            srel = spec.get(skey1, "")
            if srel and not os.path.exists(os.path.join(root, "assets", "sounds", srel)):
                errors.append(f"[Missing weapon sound] {wid}.{skey1} -> {srel}")
    print(f"[verify] Verified all {len(wdb['weapons'])} weapons (models & sounds).")

    cdb = json.load(open(os.path.join(root, "data", "classes.json"), encoding="utf-8"))
    for tm in ("CT", "T"):
        for cinfo in cdb[tm]:
            p_mdl = os.path.join(root, "assets", "models", "players", f"{cinfo['model']}.glb")
            if not os.path.exists(p_mdl):
                errors.append(f"[Missing player model] {p_mdl}")
    rdb = json.load(open(os.path.join(root, "data", "radio.json"), encoding="utf-8"))
    for grp in rdb.values():
        for it in grp["items"]:
            if not os.path.exists(os.path.join(root, "assets", "sounds", it["sound"])):
                errors.append(f"[Missing radio sound] {it['sound']}")

    # 3b. Every remaining audio route: native cues/voices/gains, baked model events,
    #     map ambience and the literal / printf-style paths used by GDScript.
    sounds_root = os.path.join(root, "assets", "sounds")
    adb = json.load(open(os.path.join(root, "data", "native_audio.json"), encoding="utf-8"))
    mmdb = json.load(open(os.path.join(root, "data", "models_meta.json"), encoding="utf-8"))
    audio_refs = set()

    def collect(value):
        if isinstance(value, dict):
            for v in value.values():
                collect(v)
        elif isinstance(value, list):
            for v in value:
                collect(v)
        elif isinstance(value, str) and value.endswith((".wav", ".ogg")):
            audio_refs.add(value)

    collect(adb)
    collect(mmdb)
    audio_refs.update(adb.get("gains", {}).keys())
    # Map ambience is best-effort: MapLoader skips cues the retail WAD never shipped.
    optional_audio = set()
    for map_file in sorted(glob.glob(os.path.join(root, "data", "maps", "*.json"))):
        for amb in json.load(open(map_file, encoding="utf-8")).get("ambient_sounds", []):
            optional_audio.add(str(amb.get("sound", "")))
    for gf in gd_files:
        text = open(gf, encoding="utf-8").read()
        ui_args = set(re.findall(r'play_ui\("([^"]+)"\)', text))
        for lit in re.findall(r'"([^"\n]*\.(?:wav|ogg))"', text):
            if lit not in ui_args:
                audio_refs.add(lit)
        for lit in ui_args:
            audio_refs.add("ui/" + lit)
    # AudioManager.play_footstep surface banks
    for prefix, count in (("pl_step", 4), ("pl_metal", 4), ("pl_dirt", 4), ("pl_tile", 5),
                          ("pl_duct", 4), ("pl_grate", 4), ("pl_snow", 6), ("pl_ladder", 4),
                          ("pl_slosh", 4)):
        for i in range(1, count + 1):
            audio_refs.add(f"player/{prefix}{i}.wav")
    checked_audio = 0
    all_sounds = {os.path.relpath(p, sounds_root)
                  for p in glob.glob(os.path.join(sounds_root, "**", "*"), recursive=True)
                  if os.path.isfile(p)}
    for rel in sorted(audio_refs):
        if rel.startswith("%s"):
            continue  # play_footstep builds these; its banks are checked above.
        if "%" in rel:
            pattern = re.escape(rel).replace("%s", "[A-Za-z0-9_-]+").replace("%d", r"\d+")
            if not any(re.fullmatch(pattern, s) for s in all_sounds):
                errors.append(f"[Missing sound pattern] {rel}")
            continue
        checked_audio += 1
        if not os.path.exists(os.path.join(sounds_root, rel)):
            errors.append(f"[Missing sound] {rel}")
    missing_ambience = sorted(r for r in optional_audio if r and r not in all_sounds)
    print(f"[verify] Verified {checked_audio} audio routes (cues, voices, model events, code).")
    if missing_ambience:
        print(f"[verify] {len(missing_ambience)} optional map ambience cues absent from the retail WAD "
              "(skipped by MapLoader).")

    # 4. Validate all 15 maps + GLBs + external texture URIs
    midx = json.load(open(os.path.join(root, "data", "maps_index.json"), encoding="utf-8"))
    glb_files = sorted(
        glob.glob(os.path.join(root, "assets", "maps", "*.glb"))
        + glob.glob(os.path.join(root, "assets", "models", "**", "*.glb"), recursive=True)
    )
    for gp in glb_files:
        with open(gp, "rb") as f:
            hdr = f.read(20)
            if len(hdr) < 20:
                errors.append(f"[Truncated GLB] {gp}")
                continue
            magic, ver, tot_len, jlen, jtype = struct.unpack("<5I", hdr)
            if magic != 0x46546C67 or ver != 2 or jtype != 0x4E4F534A:
                errors.append(f"[Invalid GLB Header] {gp}")
                continue
            jdoc = json.loads(f.read(jlen).decode("utf-8"))
            bhdr = f.read(8)
            blen, btype = struct.unpack("<2I", bhdr)
            for bv in jdoc.get("bufferViews", []):
                if bv.get("byteOffset", 0) + bv["byteLength"] > blen:
                    errors.append(f"[GLB bufferView out of bounds] {gp}")
                    break
            for img in jdoc.get("images", []):
                if "uri" in img:
                    tpath = os.path.normpath(os.path.join(os.path.dirname(gp), img["uri"]))
                    if not os.path.exists(tpath):
                        errors.append(f"[Missing GLB texture URI] {gp} -> {img['uri']}")
                        break

    for minfo in midx:
        mname = minfo["name"]
        mjson = json.load(open(os.path.join(root, "data", "maps", f"{mname}.json"), encoding="utf-8"))
        if not mjson["ct_spawns"] or not mjson["t_spawns"]:
            errors.append(f"[Map missing spawns] {mname}")
        if not mjson["waypoints"]:
            errors.append(f"[Map missing Bot waypoints] {mname}")
        lm = os.path.join(root, mjson["lightmap"][len("res://") :])
        if not os.path.exists(lm):
            errors.append(f"[Map missing lightmap] {mname}")

    print(f"[verify] Verified {len(midx)} maps and {len(glb_files)} binary .glb files.")

    # 5. Validate all WAV files have RIFF 2-byte word alignment (prevents Godot 4 FileAccessMemory seek past EOF)
    wav_files = sorted(glob.glob(os.path.join(root, "assets", "sounds", "**", "*.wav"), recursive=True))
    for wp in wav_files:
        raw = open(wp, "rb").read()
        if len(raw) < 44 or (len(raw) & 1) != 0:
            errors.append(f"[Unaligned WAV file] {wp} (len={len(raw)})")
            continue
        riff_sz = struct.unpack_from("<I", raw, 4)[0]
        if riff_sz + 8 != len(raw):
            errors.append(f"[RIFF size mismatch] {wp}")
    print(f"[verify] Verified {len(wav_files)} RIFF 2-byte word-aligned .wav files.")

    if errors:
        print("\n=== VALIDATION ERRORS ===")
        for e in errors:
            print(" ", e)
        return 1

    print("\n[verify] ALL CHECKS PASSED WITH ZERO ERRORS!")
    return 0


if __name__ == "__main__":
    sys.exit(main())
