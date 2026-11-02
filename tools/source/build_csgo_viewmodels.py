#!/usr/bin/env python3
"""Build the game's v_*.glb viewmodels from the CSGO-M.A.T. repository
(https://github.com/ilunp/CSGO-M.A.T, Crowbar-decompiled SMD + QC + VTF).

    python -m tools.source.build_csgo_viewmodels <MAT checkout>/Source <arms_port_glb> <out_dir> [weapon ...]

CS:GO viewmodels ship without arms (they are bone-merged at runtime), so the CS:GO
glove/sleeve mesh is taken from a GoldSrc port of the same rig (<arms_port_glb>,
materials ct_base_glove / ct_arms) and re-bound by bone name.

Writes <out_dir>/v_<weapon>.glb and <out_dir>/csgo_meta.json (sequences, durations,
sound events resolved against assets/sounds/weapons, unresolved sound report).
"""
import glob
import json
import os
import re
import sys

import numpy as np

from . import qc as qcmod
from .smd import parse_smd
from .smd_converter import (SCALE, Rig, apply_delta, build_glb, encode_texture, globals_of, mesh_from_smds,
                            to_godot_local)

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SND_ROOT = os.path.join(REPO, "assets", "sounds")

# game weapon -> (M.A.T. folder, qc stem, csgo sound dir)
WEAPONS = {
    "usp": ("Pistol/USP_S", "v_pist_223", "usp"),
    "glock18": ("Pistol/Glock18", "v_pist_glock18", "glock18"),
    "deagle": ("Pistol/Desert_Eagle", "v_pist_deagle", "deagle"),
    "p228": ("Pistol/P250", "v_pist_p250", "p250"),
    "elite": ("Pistol/Dual_Berettas", "v_pist_elite", "elite"),
    "fiveseven": ("Pistol/Five_SeveN", "v_pist_fiveseven", "fiveseven"),
    "m3": ("ShotGun/Nova", "v_shot_nova", "nova"),
    "xm1014": ("ShotGun/XM1014", "v_shot_xm1014", "xm1014"),
    "mp5": ("SubMachineGun/MP7", "v_smg_mp7", "mp7"),
    "tmp": ("SubMachineGun/MP9", "v_smg_mp9", "mp9"),
    "p90": ("SubMachineGun/P90", "v_smg_p90", "p90"),
    "mac10": ("SubMachineGun/MAC_10", "v_smg_mac10", "mac10"),
    "ump45": ("SubMachineGun/UMP_45", "v_smg_ump45", "ump45"),
    "ak47": ("Rifle/AK-47", "v_rif_ak47", "ak47"),
    "sg552": ("Rifle/SG553", "v_rif_sg556", "sg556"),
    "m4a1": ("Rifle/M4A1_S", "v_rif_m4a1_s", "m4a1"),
    "aug": ("Rifle/AUG", "v_rif_aug", "aug"),
    "scout": ("SniperRifle/SSG08", "v_snip_ssg08", "ssg08"),
    "awp": ("SniperRifle/AWP", "v_snip_awp", "awp"),
    "g3sg1": ("SniperRifle/G3SG1", "v_snip_g3sg1", "g3sg1"),
    "sg550": ("SniperRifle/Scar20", "v_snip_scar20", "scar20"),
    "m249": ("MachineGun/M249Para", "v_mach_m249para", "m249"),
    "knife": ("Knife/CSS", "v_knife_css", "knife"),
}
SILENCER_BONE = {"usp": "v_weapon.silencer", "m4a1": "v_weapon.m4a1_silencer"}
DROP = re.compile(r"(lookat0[2-9]|_prepare|_loop|ironsight|reposition|^empty_|left_hand|^idle2$|mac10_inspect)")
KNIFE_MAP = {"idle1": "idle", "draw": "draw", "light_miss1": "slash1", "light_miss2": "slash2",
             "light_hit1": "midslash1", "light_hit2": "midslash2", "heavy_miss1": "stab_miss",
             "heavy_hit1": "stab", "lookat01": "inspect"}
SND_PREFIX_DIR = {"m4a1s": "m4a1", "glock": "glock18", "glock18": "glock18", "hkp2000": "hkp2000", "usp": "usp",
                  "deagle": "deagle", "elite": "elite", "fiveseven": "fiveseven", "p250": "p250", "nova": "nova",
                  "xm1014": "xm1014", "mp7": "mp7", "mp9": "mp9", "p90": "p90", "mac10": "mac10",
                  "ump45": "ump45", "ak47": "ak47", "sg556": "sg556", "m4a1": "m4a1", "aug": "aug",
                  "ssg08": "ssg08", "awp": "awp", "g3sg1": "g3sg1", "scar20": "scar20", "m249": "m249",
                  "knife": "knife"}
FALLBACK_COLORS = {"glass": [0.05, 0.07, 0.09, 1.0], "shell": [0.55, 0.08, 0.06, 1.0],
                   "scope": [0.11, 0.11, 0.12, 1.0], "lens": [0.04, 0.05, 0.07, 1.0]}


def game_names(weapon, raw):
    s = raw.lower()
    if weapon == "knife":
        return [KNIFE_MAP[s]] if s in KNIFE_MAP else []
    if DROP.search(s):
        return []
    for pfx in ("ak47_", "awp_", "glock_", "mac10_"):
        if s.startswith(pfx):
            s = s[len(pfx):]
    if s == "lookat01":
        s = "inspect"
    if s == "idle1":
        s = "idle"
    if weapon == "glock18":
        if s == "firesingle":
            return ["shoot", "shoot2", "shoot3"]
        if s == "firelast":
            return ["shoot_empty"]
    m = re.fullmatch(r"fire(\d?)", s)
    if m:
        s = "shoot" + (m.group(1) or "1")
    if s == "shoot":
        s = "shoot1"
    if s in ("shoot_empty", "fire_empty", "firelast", "shootlast"):
        s = "shootlast"  # PlayerController plays "shootlast" on the final round
    if weapon in SILENCER_BONE:
        if s == "attach":
            return ["add_silencer"]
        if s == "detach":
            return ["detach_silencer"]
        if s == "draw_silenced":  # CS:GO naming is inverted: this one hides the silencer
            return ["draw_unsil"]
        if s == "draw":
            return ["draw"]
        return [s, s + "_unsil"]
    return [s]


def resolve_sound(name, cache):
    """'Weapon_AK47.Clipout' -> 'weapons/csgo/ak47/ak47_clipout.wav' (or None)."""
    if name in cache:
        return cache[name]
    res = None
    if "." in name:
        pfx, suf = name.split(".", 1)
        pfx = pfx.lower().replace("weapon_", "").replace("weapon", "")
        s = suf.lower()
        m = re.fullmatch(r"(?:silencer)?weaponmove(\d)", s)
        if m:
            n = int(m.group(1))
            if not os.path.exists(os.path.join(SND_ROOT, "weapons", "csgo", "movement%d.wav" % n)):
                n = (n - 1) % 3 + 1  # only movement1-3 ship with the pack
            res = "weapons/csgo/movement%d.wav" % n
        else:
            s = re.sub(r"^lookat(\d+)$", r"speciallookatf\1", s)
            s = re.sub(r"^taunttap\d$", "taunttap", s)
            m2 = re.fullmatch(r"taunt(?:look|twirl)(\d?)", s)
            if m2:  # Dualies inspect flourishes have no dedicated wav: use generic foley
                cache[name] = "weapons/csgo/movement%d.wav" % (int(m2.group(1) or 3) % 3 + 1)
                return cache[name]
            s = {"tauntstarttap": "taunttap", "lclipin": "leftclipin", "rclipin": "rightclipin",
                 "pumpduringshot": "pump", "deploy": "deploy1"}.get(s, s)
            if pfx == "m4a1s":
                s = "silencer" + s
            d = SND_PREFIX_DIR.get(pfx)
            if d:
                folder = os.path.join(SND_ROOT, "weapons", "csgo", d)
                if os.path.isdir(folder):
                    want = s.replace("_", "")
                    for fn in sorted(os.listdir(folder)):
                        stem = fn[:-4].lower()
                        tail = stem.split("_", 1)[1] if "_" in stem else stem
                        if tail.replace("_", "") == want or stem.replace("_", "") == want:
                            res = "weapons/csgo/%s/%s" % (d, fn)
                            break
    cache[name] = res
    return res


def classic_reload_time(weapon):
    path = os.path.join(REPO, "data", "weapons.json")
    try:
        with open(path) as f:
            data = json.load(f)
    except OSError:
        return 0.0
    data = data.get("weapons", data)
    spec = data.get("mp5navy" if weapon == "mp5" else weapon, {})
    return float(spec.get("reload_time", 0.0) or 0.0) if isinstance(spec, dict) else 0.0


def weightlist(cmds, name, rig):
    w = np.zeros(len(rig.names))
    for nm, args in cmds:
        if nm == "$weightlist" and args and args[0] == name:
            blk = args[1] if len(args) > 1 and isinstance(args[1], list) else []
            for k in range(0, len(blk) - 1, 2):
                i = rig.index.get(str(blk[k]).lower())
                if i is not None:
                    w[i] = float(blk[k + 1])
    return w


def load_arms(port_glb):
    from .glb_read import acc, load
    js, b = load(port_glb)
    joints = js["skins"][0]["joints"]
    jn = [js["nodes"][j]["name"] for j in joints]
    ibm = acc(js, b, js["skins"][0]["inverseBindMatrices"]).reshape(-1, 4, 4).transpose(0, 2, 1)
    out = []
    for m in js["meshes"]:
        for pr in m["primitives"]:
            mat = js["materials"][pr["material"]]
            if not mat["name"].lower().startswith(("ct_base_glove", "ct_arms")):
                continue
            a = pr["attributes"]
            pos = acc(js, b, a["POSITION"]).astype(np.float64)
            nrm = acc(js, b, a["NORMAL"]).astype(np.float64)
            uv = acc(js, b, a["TEXCOORD_0"]).astype(np.float64)
            J = acc(js, b, a["JOINTS_0"])[:, 0].astype(int)
            idx = acc(js, b, pr["indices"]).astype(np.int64)
            loc = np.einsum("nij,nj->ni", ibm[J], np.c_[pos, np.ones(len(pos))])[:, :3]
            lnr = np.einsum("nij,nj->ni", ibm[J][:, :3, :3], nrm)
            tex = mat["pbrMetallicRoughness"]["baseColorTexture"]["index"]
            img = js["images"][js["textures"][tex]["source"]]
            bv = js["bufferViews"][img["bufferView"]]
            data = bytes(b[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + bv["byteLength"]])
            out.append({"name": mat["name"], "local": loc, "lnrm": lnr, "uv": uv,
                        "joint_names": [jn[j] for j in J], "idx": idx, "image": (data, img.get("mimeType", "image/png"))})
    return out


def build(weapon, src_root, arms_port, out_dir, report, texture_override=None):
    folder, stem, _snd = WEAPONS[weapon]
    dec = os.path.join(src_root, folder, "Model", "model_source", "V_Models", "Decompile")
    qc_path = os.path.join(dec, stem, stem + ".qc")
    anim_qc = qc_path
    if weapon == "knife":
        anim_qc = os.path.join(dec, "v_knife_css_anim", "v_knife_css_anim.qc")
    seqs, anims, cmds = qcmod.sequences(anim_qc)
    _, _, model_cmds = qcmod.sequences(qc_path)

    # reference meshes = first studio of every bodygroup (scope-lens masks skipped)
    ref_files = []
    for nm, args in model_cmds:
        if nm == "$bodygroup":
            blk = args[1] if len(args) > 1 and isinstance(args[1], list) else []
            for k in range(len(blk) - 1):
                if str(blk[k]).lower() == "studio":
                    ref_files.append(os.path.join(dec, stem, blk[k + 1].replace("\\", "/")))
                    break
    refs = [parse_smd(p) for p in ref_files]
    rig = Rig(refs[0])
    for extra in refs[1:]:
        for nm, par in extra["nodes"]:
            if nm.lower() not in rig.index:
                raise SystemExit(f"{weapon}: bodygroup bone {nm} missing from main reference")

    def frames(smd_rel):
        base = os.path.dirname(anim_qc)
        p = os.path.join(base, smd_rel.replace("\\", "/"))
        if not p.lower().endswith(".smd"):
            p += ".smd"
        return rig.frames_of(parse_smd(p, want_triangles=False))

    bind_pose = rig.bind

    def bind_local(offset):
        return to_godot_local(rig, bind_pose, offset)

    port_name = "v_mp5" if weapon == "mp5" else "v_" + weapon
    # The GoldSrc ports sit exactly 2 units (1/16 m) further back than raw CS:GO data;
    # keep that framing for every weapon (verified on the ports' idle hand bones).
    offset = np.array([0.0, 0.0, 2.0 * SCALE])

    bind_t, bind_q = bind_local(offset)
    bind_G = globals_of(rig, bind_t, bind_q)

    # textures
    tex_dir = os.path.join(src_root, folder, "Texture", "Default")
    vtf = [p for p in glob.glob(os.path.join(tex_dir, "*_Texture.vtf")) if "exponent" not in p.lower()]
    if texture_override:
        vtf = [texture_override]
    from srctools.vtf import VTF
    with open(vtf[0], "rb") as f:
        main_img = encode_texture(VTF.read(f).get().to_PIL(), 1024, True)
    materials, mat_ids = [], {}
    main_mats = set()
    for r in refs:
        for mat, _ in r["triangles"]:
            main_mats.add(mat)
    primary = max(main_mats, key=lambda m: sum(1 for r in refs for t in r["triangles"] if t[0] == m))

    def mat_index(name):
        if name in mat_ids:
            return mat_ids[name]
        low = name.lower()
        entry = {"name": name}
        if name == primary or not any(k in low for k in ("scope", "glass", "lens", "shell")):
            entry["image"] = main_img
        else:
            key = next(k for k in ("glass", "lens", "shell", "scope") if k in low)
            entry["color"] = FALLBACK_COLORS[key]
            if key == "scope" and low.endswith("_scope") and weapon == "aug":
                entry["image"] = main_img  # AUG scope body shares the main sheet layout
                entry.pop("color")
        materials.append(entry)
        mat_ids[name] = len(materials) - 1
        return mat_ids[name]

    prims = mesh_from_smds(rig, refs, bind_G, offset, mat_index)

    # arms (bone-merged from the port)
    if arms_port:
        for part in load_arms(arms_port):
            ji = [rig.index.get(n.lower(), -1) for n in part["joint_names"]]
            missing = sorted({n for n, j in zip(part["joint_names"], ji) if j < 0})
            if missing:
                report.setdefault("arms_missing_bones", {})[weapon] = missing
            ji = np.array([j if j >= 0 else rig.index.get("v_weapon.bip01_r_hand", 0) for j in ji])
            Gs = np.array([bind_G[j] for j in ji])
            pos = np.einsum("nij,nj->ni", Gs, np.c_[part["local"], np.ones(len(ji))])[:, :3]
            nrm = np.einsum("nij,nj->ni", Gs[:, :3, :3], part["lnrm"])
            nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-8)
            materials.append({"name": part["name"], "image": part["image"]})
            J = np.zeros((len(ji), 4), dtype=int)
            J[:, 0] = ji
            W = np.zeros((len(ji), 4))
            W[:, 0] = 1.0
            prims.append({"pos": pos, "nrm": nrm, "uv": part["uv"], "joints": J, "weights": W,
                          "idx": part["idx"], "material": len(materials) - 1})

    # additive "idle_reposition_difference" layer (M4A1-S)
    delta = None
    for s in seqs:
        if "delta" in s["flags"]:
            a = anims.get(s["smd"], {"smd": s["smd"], "raw": []})
            d_frames = frames(a["smd"])
            corr = None
            wl = None
            raw = []

            def _flat(x):
                for t in x:
                    if isinstance(t, list):
                        _flat(t)
                    else:
                        raw.append(t)
            _flat(a.get("raw") or [])
            for k, tok in enumerate(raw):
                if str(tok).lower() == "subtract":
                    corr = frames(anims[raw[k + 1]]["smd"])[0]
                if str(tok).lower() == "weightlist":
                    wl = weightlist(cmds, raw[k + 1], rig)
            delta = (s["name"], d_frames[0], corr if corr is not None else list(rig.bind),
                     wl if wl is not None else np.ones(len(rig.names)))

    sil_bone = rig.index.get(SILENCER_BONE.get(weapon, "-"), None)
    out_anims, meta_seqs, durations, events = [], [], {}, {}
    snd_cache = report.setdefault("_snd_cache", {})
    for s in seqs:
        names = game_names(weapon, s["name"])
        if not names or "delta" in s["flags"]:
            continue
        smd = s["smd"]
        if smd in anims:
            smd = anims[smd]["smd"]
        fr = frames(smd)
        layered = "addlayer" in s["flags"] or "blendlayer" in s["flags"]
        # Crowbar writes the M4A1-S "idle_reposition_difference" layer as an already-subtracted
        # delta; the plain clips match the CS:GO pose (checked against the port's idle hands), so
        # the layer is only applied on request.
        if delta is not None and layered and os.environ.get("APPLY_DELTA"):
            fr = apply_delta(fr, delta[1], delta[2], delta[3], report.get("delta_mode", "pre"))
        fps = s["fps"] or (anims.get(s["smd"], {}).get("fps") if s["smd"] in anims else None) or 30.0
        F = len(fr)
        if F == 1:
            fr = fr * 2
            F = 2
        ts = np.zeros((F, len(rig.names), 3))
        qs = np.zeros((F, len(rig.names), 4))
        for fi, pose in enumerate(fr):
            ts[fi], qs[fi] = to_godot_local(rig, pose, offset)
        for fi in range(1, F):  # quaternion hemisphere continuity
            flip = np.sum(qs[fi] * qs[fi - 1], axis=1) < 0
            qs[fi][flip] *= -1
        times = np.arange(F) / fps
        dur = round(max(len(fr) - 1, 1) / fps, 3)
        evs = []
        show_f, hide_f = None, None
        for e in s["events"]:
            code = str(e[0])
            if code == "5004" and len(e) >= 3:
                wav = resolve_sound(e[2], snd_cache)
                if wav:
                    evs.append({"t": round(float(e[1]) / fps, 3), "wav": wav})
                else:
                    report.setdefault("unresolved_sounds", {}).setdefault(weapon, set()).add(e[2])
            elif code == "AE_CL_SHOW_SILENCER":
                show_f = int(float(e[1]))
            elif code == "AE_CL_HIDE_SILENCER":
                hide_f = int(float(e[1]))
        evs.sort(key=lambda x: x["t"])
        want = classic_reload_time(weapon) if names[0] == "reload" else 0.0
        if want > 0.0 and abs(want / dur - 1.0) > 0.05:
            # Keep CS 1.5 reload timing (WeaponController uses the clip length as the reload
            # time): retime the clip AND its sound events together so they stay in sync.
            k = float(np.clip(want / dur, 0.5, 2.0))
            times = times * k
            dur = round(dur * k, 3)
            evs = [{"t": round(e["t"] * k, 3), "wav": e["wav"]} for e in evs]
            report.setdefault("retimed_reloads", {})[weapon] = round(k, 3)
        for gi, gname in enumerate(names):
            sc = None
            if sil_bone is not None:
                vis = np.ones(F)
                if gname.endswith("_unsil"):
                    vis[:] = 0.0
                elif gname == "add_silencer":
                    vis[:] = 0.0
                    if show_f is not None:
                        vis[min(show_f, F - 1):] = 1.0
                elif gname == "detach_silencer":
                    if hide_f is not None:
                        vis[min(hide_f, F - 1):] = 0.0
                sc = {sil_bone: np.repeat(np.maximum(vis, 1e-4)[:, None], 3, axis=1)}
                # each silencer variant needs its own sampler set
                out_anims.append((gname, times, ts.copy() if gi else ts, qs, sc))
            else:
                out_anims.append((gname, times, ts, qs, None))
            meta_seqs.append(gname)
            durations[gname] = dur
            if evs:
                events[gname] = evs
    out = os.path.join(out_dir, port_name + ".glb")
    build_glb(out, rig, bind_t, bind_q, prims, materials, out_anims)
    info = {"sequences": meta_seqs, "seq_durations": durations, "seq_events": events,
            "bones": len(rig.names), "offset": [round(float(x), 4) for x in offset]}
    info.update(attachment_points(weapon, rig, out_anims, cmds))
    return info


def attachment_points(weapon, rig, out_anims, cmds):
    """muzzle / eject (+ muzzle_unsil, muzzle_alt) from the QC $attachments, in model space at
    idle frame 0 (the convention data/models_meta.json uses)."""
    idle = next((a for a in out_anims if a[0] == "idle"), out_anims[0] if out_anims else None)
    if idle is None:
        return {}
    G = globals_of(rig, idle[2][0], idle[3][0])
    muzzles, ejects, tip = [], [], None
    for nm, args in cmds:
        if nm.lower() != "$attachment" or len(args) < 5:
            continue
        name, bone = str(args[0]).lower(), str(args[1]).lower()
        bi = rig.index.get(bone)
        if bi is None:
            continue
        x, y, z = (float(v) for v in args[2:5])
        # bone-local Source vector -> Godot bone-local (smd_converter.L), metres
        p = (G[bi] @ np.array([-y * SCALE, z * SCALE, x * SCALE, 1.0]))[:3]
        if name == "muzzle_flash2":
            tip = p
        elif "shell" in bone or "eject" in bone:
            ejects.append(p)
        elif "flash" in bone or "muzzle" in bone or name == "1":
            muzzles.append(p)
        elif name == "2":
            ejects.append(p)
    rnd = lambda v: [round(float(c), 4) for c in v]  # noqa: E731
    # gun-hand side is x < 0 in model space (mirrored to the right in game)
    muzzles.sort(key=lambda v: v[0])
    ejects.sort(key=lambda v: v[0])
    res = {}
    if muzzles:
        res["muzzle"] = rnd(muzzles[0])
        if tip is not None:
            res["muzzle"], res["muzzle_unsil"] = rnd(tip), rnd(muzzles[0])
        if len(muzzles) > 1 and muzzles[-1][0] > 0:
            res["muzzle_alt"] = rnd(muzzles[-1])
    if ejects:
        res["eject"] = rnd(ejects[0])
    return res


def main():
    src_root, arms_port, out_dir = sys.argv[1:4]
    only = sys.argv[4:] or list(WEAPONS)
    report = {"delta_mode": os.environ.get("DELTA_MODE", "pre")}
    meta = {}
    for wpn in only:
        info = build(wpn, src_root, arms_port, out_dir, report)
        meta["weapons/" + ("v_mp5" if wpn == "mp5" else "v_" + wpn)] = info
        print(f"{wpn}: {len(info['sequences'])} seqs, offset {info['offset']}, "
              f"{os.path.getsize(os.path.join(out_dir, ('v_mp5' if wpn == 'mp5' else 'v_' + wpn) + '.glb')) // 1024} KB")
    report.pop("_snd_cache", None)
    rep = {k: ({kk: (sorted(vv) if isinstance(vv, (set, list)) else vv) for kk, vv in v.items()} if isinstance(v, dict) else v) for k, v in report.items()}
    meta["_report"] = rep
    with open(os.path.join(out_dir, "csgo_meta.json"), "w") as f:
        json.dump(meta, f, indent=1)
    print(json.dumps(rep, indent=1))


if __name__ == "__main__":
    main()
