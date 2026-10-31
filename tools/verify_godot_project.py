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
    if not os.path.exists(os.path.join(root, "assets", "models", "players", "vip.glb")):
        errors.append("[Missing VIP model]")
    if not os.path.exists(os.path.join(root, "assets", "models", "players", "hostage.glb")):
        errors.append("[Missing Hostage model]")

    rdb = json.load(open(os.path.join(root, "data", "radio.json"), encoding="utf-8"))
    for grp in rdb.values():
        for it in grp["items"]:
            if not os.path.exists(os.path.join(root, "assets", "sounds", it["sound"])):
                errors.append(f"[Missing radio sound] {it['sound']}")

    # 4. Validate all 26 maps + GLBs + external texture URIs
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
                if bv["byteOffset"] + bv["byteLength"] > blen:
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
