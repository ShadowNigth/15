#!/usr/bin/env python3
"""Build the game's viewmodels from ixof/Classic-Offensive compiled Source assets.

    PYTHONPATH=<SourceIO checkout parent> python -m tools.source.build_csco_viewmodels \
        <CSCO checkout> <M.A.T>/Source <arms_port_glb> <out_dir> <fallback_glb_dir> [weapon ...]

Classic-Offensive (CSCO) ships compiled MDL v49/VVD/VTX/ANI files, not SMD/QC. The
builder uses its meshes, UVs, skeletons, materials and attachment points. Its custom
recompiled clips use incompatible per-bone staging (confirmed with rendered frames),
so the validated stock M.A.T. clips are retargeted by bone name instead; normalized
CSCO include events are used where they describe that same stock clip. Grenades and
C4 use their previous CS:GO-rig clips retargeted through global bone motion.

Elite, G3SG1 and M249 have no CSCO v_ mesh and keep M.A.T. geometry with the CSCO
texture. CSCO's MP5 has a Galil-derived rig, so its rigid mesh pieces are fitted and
rebound to the validated MP7 rig. CSCO contains no weapon WAV files; sound events
resolve only to audio already installed in the game.
"""
import glob
import json
import os
import re
import sys

import numpy as np

from . import qc as qcmod
from .build_csgo_viewmodels import (SILENCER_BONE, WEAPONS,
                                    attachment_points as mat_attachment_points, build as build_mat,
                                    classic_reload_time, game_names, load_arms, resolve_sound)
from .build_csgo_worldmodels import _proper_axis_rotations, fit_to_reference
from .glb_read import acc, load as load_glb
from .mdl_reader import load_model
from .smd import parse_smd, quat_mat, trs
from .smd_converter import SCALE, Rig, build_glb, encode_texture, globals_of, to_godot_local

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SND_ROOT = os.path.join(REPO, "assets", "sounds")
OFFSET = np.array([0.0, 0.0, 2.0 * SCALE])

CSCO_MODELS = {
    "usp": "v_pist_224",
    "glock18": "v_pist_glock",
    "deagle": "v_pist_deagle_csco",
    "p228": "v_pist_p250",
    "fiveseven": "v_pist_fiveseven",
    "m3": "v_shot_m3super90",
    "xm1014": "v_shot_xm1015",
    "mp5": "v_smg_mp5_csco",
    "tmp": "v_smg_tmp",
    "p90": "v_smg_p91",
    "mac10": "v_smg_mac10",
    "ump45": "v_smg_ump46",
    "ak47": "v_rif_ak41",
    "sg552": "v_rif_sg552",
    "m4a1": "v_rif_m4a2_s",
    "aug": "v_rif_aug1",
    "scout": "v_snip_ssg08",
    "awp": "v_snip_awp",
    "sg550": "v_snip_scar20",
    "knife": "v_knife_16",
    "flashbang": "v_eq_flashbang",
    "hegrenade": "v_eq_fraggrenade",
    "smokegrenade": "v_eq_smokegrenade",
    "c4": "v_ied",
}
# No CSCO viewmodel mesh exists for these, but its matching texture does.
MAT_WITH_CSCO_TEXTURE = {
    "elite": "materials/models/weapons/v_models/pist_elite/m9a1.vtf",
    "g3sg1": "materials/models/weapons/v_models/snip_g3sg1/snip_g3sg1.vtf",
    "m249": "materials/models/weapons/v_models/mach_m249para/m249.vtf",
}
GRENADES = ("flashbang", "hegrenade", "smokegrenade")
FALLBACK_COLORS = {"glass": [0.05, 0.07, 0.09, 1.0], "shell": [0.55, 0.08, 0.06, 1.0],
                   "scope": [0.11, 0.11, 0.12, 1.0], "lens": [0.04, 0.05, 0.07, 1.0]}


def mdl_rig(model):
    rig = Rig.__new__(Rig)
    rig.names = [b[0] for b in model["bones"]]
    rig.parents = [int(b[1]) for b in model["bones"]]
    rig.index = {n.lower(): i for i, n in enumerate(rig.names)}
    rig.bind = [(np.array(b[2], dtype=np.float64), np.array(b[3], dtype=np.float64)) for b in model["bones"]]
    return rig


def remap_mat_frames(frames, mat_rig, target_rig):
    out = []
    for fr in frames:
        pose = list(target_rig.bind)
        for j, name in enumerate(mat_rig.names):
            i = target_rig.index.get(name.lower())
            if i is not None:
                pose[i] = (np.array(fr[j][0], dtype=np.float64), np.array(fr[j][1], dtype=np.float64))
        out.append(pose)
    return out


class MatAnimations:
    """Lazy reader for the stock SMD/QC animation fallback."""

    def __init__(self, weapon, src_root):
        self.weapon = weapon
        folder, stem, _ = WEAPONS[weapon]
        dec = os.path.join(src_root, folder, "Model", "model_source", "V_Models", "Decompile")
        self.qc_path = os.path.join(dec, stem, stem + ".qc")
        self.anim_qc = self.qc_path
        if weapon == "knife":
            self.anim_qc = os.path.join(dec, "v_knife_css_anim", "v_knife_css_anim.qc")
        self.seqs, self.anims, self.cmds = qcmod.sequences(self.anim_qc)
        _, _, model_cmds = qcmod.sequences(self.qc_path)
        ref_files = []
        for nm, args in model_cmds:
            if nm == "$bodygroup":
                blk = args[1] if len(args) > 1 and isinstance(args[1], list) else []
                for k in range(len(blk) - 1):
                    if str(blk[k]).lower() == "studio":
                        ref_files.append(os.path.join(dec, stem, blk[k + 1].replace("\\", "/")))
                        break
        self.rig = Rig(parse_smd(ref_files[0]))
        self._cache = {}

    def frames(self, seq):
        smd = seq["smd"]
        if smd in self.anims:
            smd = self.anims[smd]["smd"]
        if smd in self._cache:
            return self._cache[smd]
        path = os.path.join(os.path.dirname(self.anim_qc), smd.replace("\\", "/"))
        if not path.lower().endswith(".smd"):
            path += ".smd"
        fr = self.rig.frames_of(parse_smd(path, want_triangles=False))
        self._cache[smd] = fr
        return fr

    def fps(self, seq):
        return float(seq["fps"] or self.anims.get(seq["smd"], {}).get("fps") or 30.0)


class MaterialLibrary:
    """Case-insensitive CSCO material/VMT/VTF resolver (the repo mixes path case)."""

    def __init__(self, csco_root, mat_root=None):
        self.root = os.path.join(csco_root, "materials")
        self.mat_root = mat_root
        self.files = {}
        for base, _, files in os.walk(self.root):
            for fn in files:
                p = os.path.join(base, fn)
                self.files[os.path.relpath(p, self.root).replace("\\", "/").lower()] = p
        self.images = {}
        self.missing = []
        self.fallbacks = []

    def path(self, rel):
        return self.files.get(rel.replace("\\", "/").strip("/").lower())

    def _vmt_base(self, path):
        try:
            with open(path, encoding="utf-8", errors="ignore") as f:
                text = f.read()
        except OSError:
            return None
        m = re.search(r"(?im)^\s*[\"']?\$basetexture[\"']?\s+[\"']([^\"']+)[\"']", text)
        if not m:
            m = re.search(r"(?im)^\s*[\"']?\$basetexture[\"']?\s+([^\s/]+(?:[\\/][^\s]+)?)", text)
        return m.group(1) if m else None

    def find_texture(self, model, material):
        for cd in model["cdmaterials"]:
            stem = cd.replace("\\", "/").strip("/") + "/" + material
            vmt = self.path(stem + ".vmt")
            if vmt:
                base = self._vmt_base(vmt)
                if base:
                    vtf = self.path(base + ".vtf")
                    if vtf:
                        return vtf
            vtf = self.path(stem + ".vtf")
            if vtf:
                return vtf
        # A few compiled materials omit their directory in the VMT reference.
        for cd in model["cdmaterials"]:
            vtf = self.path(cd.replace("\\", "/").strip("/") + "/" + material.lower() + ".vtf")
            if vtf:
                return vtf
        return None

    def image(self, path, max_size):
        key = (path, max_size)
        if key not in self.images:
            from srctools.vtf import VTF
            with open(path, "rb") as f:
                self.images[key] = encode_texture(VTF.read(f).get().to_PIL(), max_size, True)
        return self.images[key]

    def entry(self, model, material, max_size=1024, weapon=None):
        path = self.find_texture(model, material)
        if path:
            return {"name": material, "image": self.image(path, max_size)}
        low = material.lower()
        self.missing.append(material)
        for key in ("glass", "lens", "shell", "scope"):
            if key in low:
                return {"name": material, "color": FALLBACK_COLORS[key]}
        if weapon in WEAPONS and self.mat_root:
            folder = WEAPONS[weapon][0]
            candidates = glob.glob(os.path.join(self.mat_root, folder, "Texture", "Default", "*_Texture.vtf"))
            candidates = [p for p in candidates if "exponent" not in p.lower()]
            if candidates:
                self.fallbacks.append("%s:%s" % (weapon, material))
                return {"name": material + " (M.A.T. fallback)", "image": self.image(candidates[0], max_size)}
        return {"name": material, "color": [0.12, 0.13, 0.14, 1.0]}


def mesh_primitives(model, rig, bind_g, mat_index):
    """VVD/VTX model-space skin -> Godot bind-space primitives.

    VTX triangle order is already opposite to Crowbar's SMD triangle order: after the
    reflected Source->Godot transform its face normals agree with the VVD normals, so
    unlike mesh_from_smds() this path must NOT reverse the indices again.
    """
    from .smd_converter import L, RA
    prims = []
    for mesh in model["meshes"]:
        count = len(mesh["pos"])
        joints = np.zeros((count, 4), dtype=int)
        weights = np.zeros((count, 4), dtype=np.float64)
        src_j = np.asarray(mesh["bones"], dtype=int)
        src_w = np.asarray(mesh["weights"], dtype=np.float64)
        n = min(3, src_j.shape[1] if src_j.ndim > 1 else 1)
        if src_j.ndim == 1:
            src_j = src_j[:, None]
            src_w = src_w[:, None]
        joints[:, :n] = np.clip(src_j[:, :n], 0, len(rig.names) - 1)
        weights[:, :n] = src_w[:, :n]
        bad = weights.sum(axis=1) <= 1e-8
        if np.any(bad):
            weights[bad, 0] = 1.0
        weights /= weights.sum(axis=1, keepdims=True)
        pos = RA(L(mesh["pos"]) * SCALE) + OFFSET
        nrm = RA(L(mesh["nrm"]))
        nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-8)
        # VVD texture coordinates and srctools' decoded VTF pixels already use
        # glTF's top-left origin.  Flipping V here scattered neighbouring atlas
        # islands over the weapon (most visibly on the Deagle and AWP).  The
        # separate SMD arm path keeps its own conversion convention.
        uv = np.asarray(mesh["uv"], dtype=np.float64).copy()
        prims.append({"pos": pos, "nrm": nrm, "uv": uv, "joints": joints, "weights": weights,
                      "idx": np.asarray(mesh["idx"], dtype=np.int64).reshape(-1),
                      "material": mat_index(mesh["material"])})
    return prims


def add_arms(prims, materials, rig, bind_g, arms_parts, weapon, report):
    for part in arms_parts:
        ji = [rig.index.get(n.lower(), -1) for n in part["joint_names"]]
        missing = sorted({n for n, j in zip(part["joint_names"], ji) if j < 0})
        if missing:
            report.setdefault("arms_missing_bones", {}).setdefault(weapon, sorted(set(missing)))
        ji = np.array([j if j >= 0 else rig.index.get("v_weapon.bip01_r_hand", 0) for j in ji])
        gs = np.array([bind_g[j] for j in ji])
        pos = np.einsum("nij,nj->ni", gs, np.c_[part["local"], np.ones(len(ji))])[:, :3]
        nrm = np.einsum("nij,nj->ni", gs[:, :3, :3], part["lnrm"])
        nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-8)
        materials.append({"name": part["name"], "image": part["image"]})
        joints = np.zeros((len(ji), 4), dtype=int)
        joints[:, 0] = ji
        weights = np.zeros((len(ji), 4))
        weights[:, 0] = 1.0
        prims.append({"pos": pos, "nrm": nrm, "uv": part["uv"], "joints": joints, "weights": weights,
                      "idx": part["idx"], "material": len(materials) - 1})


def resolve_csco_sound(name, weapon, cache):
    """Resolve CSCO sound-script names to the installed equivalent WAVs.

    CSCO's .gitignore excludes every weapon WAV, so this deliberately only remaps
    existing audio; it never fabricates a missing file.
    """
    key = (weapon, name)
    if key in cache:
        return cache[key]
    low = name.lower()
    direct = {
        "weapon_usp.attachsilencer": "weapons/usp_silencer_on.wav",
        "weapon_usp.detachsilencer": "weapons/usp_silencer_off.wav",
        "weapon_m4a1.silencer_on": "weapons/m4a1_silencer_on.wav",
        "weapon_m4a1.silencer_off": "weapons/m4a1_silencer_off.wav",
        "weapon_m4a1.boltback": "weapons/csgo/m4a1/m4a1_silencer_boltback.wav",
        "weapon_m4a1.boltforward": "weapons/csgo/m4a1/m4a1_silencer_boltforward.wav",
        "c4.draw": "weapons/csgo/c4/c4_draw.wav",
    }
    result = direct.get(low)
    if result is None and low.startswith("incgrenade."):
        suffix = low.split(".", 1)[1]
        fn = {"pullpin_grenade": "pinpull.wav", "pullpin_grenade_start": "pinpull_start.wav"}.get(suffix)
        if fn:
            result = "weapons/csgo/%s/%s" % (weapon, fn)
    if result is None and "." in name:
        pfx, suffix = name.split(".", 1)
        aliases = {"mp5navy": "mp7", "usp": "hkp2000", "p228": "p250", "tmp": "mp9",
                   "sg552": "sg556", "scout": "ssg08", "sg550": "scar20", "m3": "nova"}
        p = pfx.lower().replace("weapon_", "").replace("weapon", "")
        if p in aliases:
            result = resolve_sound("Weapon_%s.%s" % (aliases[p], suffix), cache)
        elif p == "glock" and suffix.lower() == "sliderelease2":
            result = "weapons/csgo/glock18/glock_sliderelease.wav"
        elif p == "aug" and suffix.lower() == "boltslap":
            result = "weapons/csgo/aug/aug_boltrelease.wav"
    if result is None:
        result = resolve_sound(name, cache)
    if result and not os.path.exists(os.path.join(SND_ROOT, result)):
        result = None
    cache[key] = result
    return result


def _event_sound(event_name, weapon, cache, report):
    wav = resolve_csco_sound(event_name, weapon, cache)
    if not wav:
        report.setdefault("unresolved_sounds", {}).setdefault(weapon, set()).add(event_name)
    return wav


def csco_events(seq, weapon, duration, fps, cache, report):
    """CSCO normalized-cycle events -> game events plus silencer show/hide times."""
    events, show, hide = [], None, None
    keypad = 0
    for cycle, code, options, name, _event_type in seq["events"]:
        t = float(cycle) * duration
        if code == 5004 and options:
            wav = _event_sound(options, weapon, cache, report)
            if wav:
                events.append({"t": round(t, 3), "wav": wav})
        elif code == 7001 and weapon == "c4" and seq["name"].lower() == "pressbutton":
            if options and options[0].isdigit():
                keypad += 1
                events.append({"t": round(t, 3), "wav": "weapons/csgo/c4/key_press%d.wav" % min(keypad, 7)})
            elif not options:
                events.append({"t": round(t, 3), "wav": "weapons/csgo/c4/c4_initiate.wav"})
        if name == "AE_CL_SHOW_SILENCER":
            show = t
        elif name == "AE_CL_HIDE_SILENCER":
            hide = t
    events.sort(key=lambda e: e["t"])
    return events, show, hide


def mat_events(seq, weapon, fps, cache, report):
    events, show, hide = [], None, None
    for event in seq["events"]:
        code = str(event[0])
        if code == "5004" and len(event) >= 3:
            wav = _event_sound(event[2], weapon, cache, report)
            if wav:
                events.append({"t": round(float(event[1]) / fps, 3), "wav": wav})
        elif code == "AE_CL_SHOW_SILENCER":
            show = float(event[1]) / fps
        elif code == "AE_CL_HIDE_SILENCER":
            hide = float(event[1]) / fps
    events.sort(key=lambda e: e["t"])
    return events, show, hide


def mat_to_quat(matrix):
    """Rotation matrix -> xyzw quaternion, robust to either trace branch."""
    r = np.asarray(matrix, dtype=np.float64)[:3, :3]
    # Remove tiny accumulated scaling before extracting a rotation.
    r = r / np.maximum(np.linalg.norm(r, axis=0, keepdims=True), 1e-12)
    tr = float(np.trace(r))
    if tr > 0.0:
        s = np.sqrt(tr + 1.0) * 2.0
        q = np.array([(r[2, 1] - r[1, 2]) / s, (r[0, 2] - r[2, 0]) / s,
                      (r[1, 0] - r[0, 1]) / s, 0.25 * s])
    else:
        i = int(np.argmax(np.diag(r)))
        if i == 0:
            s = np.sqrt(1.0 + r[0, 0] - r[1, 1] - r[2, 2]) * 2.0
            q = np.array([0.25 * s, (r[0, 1] + r[1, 0]) / s,
                          (r[0, 2] + r[2, 0]) / s, (r[2, 1] - r[1, 2]) / s])
        elif i == 1:
            s = np.sqrt(1.0 + r[1, 1] - r[0, 0] - r[2, 2]) * 2.0
            q = np.array([(r[0, 1] + r[1, 0]) / s, 0.25 * s,
                          (r[1, 2] + r[2, 1]) / s, (r[0, 2] - r[2, 0]) / s])
        else:
            s = np.sqrt(1.0 + r[2, 2] - r[0, 0] - r[1, 1]) * 2.0
            q = np.array([(r[0, 2] + r[2, 0]) / s, (r[1, 2] + r[2, 1]) / s,
                          0.25 * s, (r[1, 0] - r[0, 1]) / s])
    return q / max(np.linalg.norm(q), 1e-12)


class GlbClipSource:
    """Sample the previous GLB and retarget global bone motion onto another CS:GO rig."""

    def __init__(self, path):
        self.js, self.bin = load_glb(path)
        self.nodes = self.js["nodes"]
        self.parent = {}
        self.name_to_node = {}
        for i, nd in enumerate(self.nodes):
            self.name_to_node[str(nd.get("name", "")).lower()] = i
            for child in nd.get("children", []):
                self.parent[child] = i
        self.default_local = [trs(nd.get("translation", [0, 0, 0]), nd.get("rotation", [0, 0, 0, 1]),
                                  nd.get("scale", [1, 1, 1])) for nd in self.nodes]
        self.bind_global = self._globals({})
        self.anim_by_name = {a["name"]: a for a in self.js.get("animations", [])}

    def _globals(self, locals_override):
        cache = {}

        def calc(i):
            if i not in cache:
                cache[i] = (calc(self.parent[i]) @ locals_override.get(i, self.default_local[i])
                            if i in self.parent else locals_override.get(i, self.default_local[i]))
            return cache[i]
        return [calc(i) for i in range(len(self.nodes))]

    def _channel_values(self, anim, t):
        locals_override = {}
        for channel in anim["channels"]:
            sampler = anim["samplers"][channel["sampler"]]
            times = acc(self.js, self.bin, sampler["input"]).reshape(-1)
            values = acc(self.js, self.bin, sampler["output"])
            if t <= times[0]:
                value = values[0]
            elif t >= times[-1]:
                value = values[-1]
            else:
                k = int(np.searchsorted(times, t) - 1)
                a = (t - times[k]) / max(times[k + 1] - times[k], 1e-9)
                value = values[k] * (1.0 - a) + values[k + 1] * a
            node = channel["target"]["node"]
            local = locals_override.get(node, self.default_local[node].copy())
            path = channel["target"]["path"]
            if path == "translation":
                local[:3, 3] = value
            elif path == "rotation":
                m = np.eye(4)
                m[:3, :3] = quat_mat(value / np.linalg.norm(value))
                local[:3, :3] = m[:3, :3]
            elif path == "scale":
                local[:3, :3] = local[:3, :3] @ np.diag(value)
            locals_override[node] = local
        return locals_override

    def clip(self, name, target_rig, target_bind_t, target_bind_q):
        anim = self.anim_by_name[name]
        inputs = [acc(self.js, self.bin, s["input"]).reshape(-1) for s in anim["samplers"]]
        times = max(inputs, key=len).astype(np.float64)
        if len(times) < 2:
            times = np.array([0.0, 1.0 / 30.0])
        target_bind_g = globals_of(target_rig, target_bind_t, target_bind_q)
        common = {i: self.name_to_node[n.lower()] for i, n in enumerate(target_rig.names)
                  if n.lower() in self.name_to_node}
        ref_name = "v_weapon.parent" if "v_weapon.parent" in self.name_to_node else "v_weapon.c4"
        ref_old = self.name_to_node.get(ref_name)
        root = next((i for i, p in enumerate(target_rig.parents) if p < 0), 0)
        root_delta = np.eye(4)
        if ref_old is not None and ref_name in target_rig.index:
            ref_new = target_rig.index[ref_name]
            root_delta = np.linalg.inv(self.bind_global[ref_old]) @ target_bind_g[ref_new]
        ts = np.zeros((len(times), len(target_rig.names), 3))
        qs = np.zeros((len(times), len(target_rig.names), 4))
        for fi, t in enumerate(times):
            old_global = self._globals(self._channel_values(anim, float(t)))
            desired = [None] * len(target_rig.names)
            for i, old_i in common.items():
                desired[i] = old_global[old_i]
            if ref_old is not None:
                desired[root] = old_global[ref_old] @ root_delta

            def fill(i):
                if desired[i] is None:
                    p = target_rig.parents[i]
                    local = trs(target_bind_t[i], target_bind_q[i])
                    desired[i] = fill(p) @ local if p >= 0 else local
                return desired[i]

            for i in range(len(desired)):
                fill(i)
            for i in range(len(desired)):
                p = target_rig.parents[i]
                local = np.linalg.inv(desired[p]) @ desired[i] if p >= 0 else desired[i]
                ts[fi, i] = local[:3, 3]
                qs[fi, i] = mat_to_quat(local)
        for fi in range(1, len(times)):
            flip = np.sum(qs[fi] * qs[fi - 1], axis=1) < 0
            qs[fi][flip] *= -1
        return times, ts, qs


def _candidates(weapon, main_model, include_models):
    """Game sequence name -> (model, sequence, origin), main model taking precedence."""
    out = {}
    for model, origin in [(main_model, "csco")] + [(m, "csco_include") for m in include_models]:
        for seq in model["sequences"]:
            for name in game_names(weapon, seq["name"]):
                out.setdefault(name, (model, seq, origin))
    return out


def _finish_animation(weapon, names, poses, fps, events, show, hide, rig, out_anims,
                      meta_seqs, durations, event_map, source_name, source_map):
    if len(poses) == 1:
        poses = poses * 2
    count = len(poses)
    ts = np.zeros((count, len(rig.names), 3))
    qs = np.zeros((count, len(rig.names), 4))
    for fi, pose in enumerate(poses):
        ts[fi], qs[fi] = to_godot_local(rig, pose, OFFSET)
    for fi in range(1, count):
        flip = np.sum(qs[fi] * qs[fi - 1], axis=1) < 0
        qs[fi][flip] *= -1
    times = np.arange(count, dtype=np.float64) / fps
    duration = round(max(count - 1, 1) / fps, 3)
    want = classic_reload_time(weapon) if names[0] == "reload" else 0.0
    if want > 0.0 and abs(want / duration - 1.0) > 0.05:
        factor = float(np.clip(want / duration, 0.5, 2.0))
        times *= factor
        duration = round(duration * factor, 3)
        events = [{**e, "t": round(e["t"] * factor, 3)} for e in events]
        if show is not None:
            show *= factor
        if hide is not None:
            hide *= factor
    sil_bone = rig.index.get(SILENCER_BONE.get(weapon, "-"), None)
    for gi, game_name in enumerate(names):
        scales = None
        if sil_bone is not None:
            visibility = np.ones(count)
            if game_name.endswith("_unsil"):
                visibility[:] = 0.0
            elif game_name == "add_silencer":
                visibility[:] = 0.0
                if show is not None:
                    visibility[times >= show - 1e-5] = 1.0
            elif game_name == "detach_silencer" and hide is not None:
                visibility[times >= hide - 1e-5] = 0.0
            scales = {sil_bone: np.repeat(np.maximum(visibility, 1e-4)[:, None], 3, axis=1)}
            out_anims.append((game_name, times, ts.copy() if gi else ts, qs, scales))
        else:
            out_anims.append((game_name, times, ts, qs, None))
        meta_seqs.append(game_name)
        durations[game_name] = duration
        if events:
            event_map[game_name] = events
        source_map[game_name] = source_name
    return times, ts, qs


def attachment_points(model, rig, out_anims):
    idle = next((a for a in out_anims if a[0] == "idle"), out_anims[0] if out_anims else None)
    if idle is None:
        return {}
    global_g = globals_of(rig, idle[2][0], idle[3][0])
    muzzles, ejects, tip = [], [], None
    for name, bone, matrix in model["attachments"]:
        if bone < 0 or bone >= len(rig.names):
            continue
        x, y, z = matrix[:, 3]
        point = (global_g[bone] @ np.array([-y * SCALE, z * SCALE, x * SCALE, 1.0]))[:3]
        low = name.lower()
        bone_low = rig.names[bone].lower()
        if low == "muzzle_flash2":
            tip = point
        elif "shell" in bone_low or "eject" in bone_low or low == "2":
            ejects.append(point)
        elif "flash" in bone_low or "muzzle" in bone_low or low == "1":
            muzzles.append(point)
    rnd = lambda v: [round(float(c), 4) for c in v]  # noqa: E731
    muzzles.sort(key=lambda v: v[0])
    ejects.sort(key=lambda v: v[0])
    result = {}
    if muzzles:
        result["muzzle"] = rnd(muzzles[0])
        if tip is not None:
            result["muzzle"], result["muzzle_unsil"] = rnd(tip), rnd(muzzles[0])
        if len(muzzles) > 1 and muzzles[-1][0] > 0:
            result["muzzle_alt"] = rnd(muzzles[-1])
    if ejects:
        result["eject"] = rnd(ejects[0])
    return result


def skinned_gun_points(path, animation="idle"):
    """Gun-only vertices of a viewmodel GLB, skinned at frame zero (arm materials excluded)."""
    source = GlbClipSource(path)
    anim = source.anim_by_name[animation]
    global_g = source._globals(source._channel_values(anim, 0.0))
    skin = source.js["skins"][0]
    ibm = acc(source.js, source.bin, skin["inverseBindMatrices"]).reshape(-1, 4, 4).transpose(0, 2, 1)
    joint_matrices = np.array([global_g[j] @ ibm[k] for k, j in enumerate(skin["joints"])])
    points = []
    for mesh in source.js["meshes"]:
        for primitive in mesh["primitives"]:
            material = source.js["materials"][primitive["material"]]["name"].lower()
            if material.startswith(("ct_base_glove", "ct_arms")):
                continue
            attrs = primitive["attributes"]
            pos = acc(source.js, source.bin, attrs["POSITION"]).astype(np.float64)
            joints = acc(source.js, source.bin, attrs["JOINTS_0"]).astype(int)
            weights = acc(source.js, source.bin, attrs["WEIGHTS_0"]).astype(np.float64)
            p4 = np.c_[pos, np.ones(len(pos))]
            skinned = np.zeros((len(pos), 3))
            for k in range(4):
                skinned += weights[:, k:k + 1] * np.einsum(
                    "nij,nj->ni", joint_matrices[joints[:, k]], p4)[:, :3]
            points.append(skinned)
    return np.concatenate(points)


def build_mp5_transplant(csco_root, mat_root, out_dir, fallback_dir, arms_parts, report):
    """CSCO's MP5 uses a Galil-derived rig, not the stock MP7 rig used by the fallback.

    Fit its rigid gun pieces onto the validated MP7 idle pose, then rebind those pieces
    to the equivalent MP7 bones. This keeps the CSCO mesh/texture without the broken
    proportions produced by copying parent-local MP7 channels onto the Galil skeleton.
    """
    weapon = "mp5"
    model = load_model(os.path.join(csco_root, "models", "weapons", CSCO_MODELS[weapon] + ".mdl"))
    mat = MatAnimations(weapon, mat_root)
    rig = mat.rig
    bind_t, bind_q = to_godot_local(rig, rig.bind, OFFSET)
    bind_g = globals_of(rig, bind_t, bind_q)
    idle_seq = next(s for s in mat.seqs if game_names(weapon, s["name"]) == ["idle"])
    idle_t, idle_q = to_godot_local(rig, mat.frames(idle_seq)[0], OFFSET)
    idle_g = globals_of(rig, idle_t, idle_q)
    reference = skinned_gun_points(os.path.join(fallback_dir, "v_mp5.glb"))
    from .smd_converter import L, RA
    raw_parts = []
    for mesh in model["meshes"]:
        pos = RA(L(mesh["pos"]) * SCALE) + OFFSET
        nrm = RA(L(mesh["nrm"]))
        raw_parts.append((pos, nrm))
    source_points = np.concatenate([p for p, _ in raw_parts])
    best = None
    for initial in _proper_axis_rotations():
        fit = fit_to_reference(source_points, reference, initial, iters=30)
        if best is None or fit[2] < best[2]:
            best = fit
    rotation, translation = best[0], best[1]
    report.setdefault("mp5_mesh_fit", {})["residual_m"] = round(best[2], 5)
    report["mp5_mesh_fit"]["deg_from_initial"] = round(best[3], 2)
    library = report["_materials"]
    materials, prims = [], []
    source_bones = [b[0].lower() for b in model["bones"]]
    parent_joint = rig.index["v_weapon.mp7_parent"]
    bone_aliases = {"v_weapon.magazine": "v_weapon.clip", "v_weapon.galilar_parent": "v_weapon.mp7_parent"}
    for mesh, (pos, nrm) in zip(model["meshes"], raw_parts):
        idle_pos = pos @ rotation.T + translation
        idle_nrm = nrm @ rotation.T
        target_joints = []
        for source_joint in mesh["bones"][:, 0]:
            name = source_bones[int(source_joint)]
            name = bone_aliases.get(name, name)
            target_joints.append(rig.index.get(name, parent_joint))
        target_joints = np.array(target_joints, dtype=int)
        bind_pos = np.zeros_like(idle_pos)
        bind_nrm = np.zeros_like(idle_nrm)
        for joint in np.unique(target_joints):
            mask = target_joints == joint
            inverse_motion = bind_g[joint] @ np.linalg.inv(idle_g[joint])
            bind_pos[mask] = np.einsum("ij,nj->ni", inverse_motion,
                                       np.c_[idle_pos[mask], np.ones(mask.sum())])[:, :3]
            bind_nrm[mask] = idle_nrm[mask] @ inverse_motion[:3, :3].T
        bind_nrm /= np.maximum(np.linalg.norm(bind_nrm, axis=1, keepdims=True), 1e-8)
        joints = np.zeros((len(bind_pos), 4), dtype=int)
        joints[:, 0] = target_joints
        weights = np.zeros((len(bind_pos), 4))
        weights[:, 0] = 1.0
        # Direct VVD/VTF sampling uses the same top-left origin as glTF.
        uv = np.asarray(mesh["uv"], dtype=np.float64).copy()
        materials.append(library.entry(model, mesh["material"], 1024, weapon))
        prims.append({"pos": bind_pos, "nrm": bind_nrm, "uv": uv, "joints": joints, "weights": weights,
                      "idx": np.asarray(mesh["idx"]).reshape(-1), "material": len(materials) - 1})
    add_arms(prims, materials, rig, bind_g, arms_parts, weapon, report)
    candidates = _candidates(weapon, model, [])
    cache = report.setdefault("_snd_cache", {})
    out_anims, meta_seqs, durations, event_map, source_map = [], [], {}, {}, {}
    for seq in mat.seqs:
        names = game_names(weapon, seq["name"])
        if not names or "delta" in seq["flags"]:
            continue
        poses = mat.frames(seq)
        fps = mat.fps(seq)
        candidate = candidates.get(names[0])
        if candidate and candidate[2] == "csco_include":
            source_name = "mat_stock+csco_include_events"
            events, show, hide = csco_events(candidate[1], weapon, max(len(poses) - 1, 1) / fps,
                                             fps, cache, report)
        else:
            source_name = "mat_stock"
            events, show, hide = mat_events(seq, weapon, fps, cache, report)
        _finish_animation(weapon, names, poses, fps, events, show, hide, rig, out_anims,
                          meta_seqs, durations, event_map, source_name, source_map)
    output = os.path.join(out_dir, "v_mp5.glb")
    build_glb(output, rig, bind_t, bind_q, prims, materials, out_anims)
    info = {"sequences": meta_seqs, "seq_durations": durations, "seq_events": event_map,
            "bones": len(rig.names), "offset": [round(float(x), 4) for x in OFFSET],
            "source": "ixof/Classic-Offensive mesh + M.A.T. MP7 rig"}
    info.update(mat_attachment_points(weapon, rig, out_anims, mat.cmds))
    report.setdefault("animation_sources", {})[weapon] = source_map
    return info


def build_csco(weapon, csco_root, mat_root, out_dir, fallback_dir, arms_parts, report, old_meta):
    model = load_model(os.path.join(csco_root, "models", "weapons", CSCO_MODELS[weapon] + ".mdl"))
    include_models = []
    for include in model["includes"]:
        path = os.path.join(csco_root, include.replace("\\", "/"))
        if os.path.exists(path):
            include_models.append(load_model(path, want_mesh=False))
    rig = mdl_rig(model)
    bind_t, bind_q = to_godot_local(rig, rig.bind, OFFSET)
    bind_g = globals_of(rig, bind_t, bind_q)
    library = report["_materials"]
    materials, mat_ids = [], {}

    def mat_index(name):
        if name not in mat_ids:
            materials.append(library.entry(model, name, 1024, weapon))
            mat_ids[name] = len(materials) - 1
        return mat_ids[name]

    prims = mesh_primitives(model, rig, bind_g, mat_index)
    add_arms(prims, materials, rig, bind_g, arms_parts, weapon, report)
    candidates = _candidates(weapon, model, include_models)
    cache = report.setdefault("_snd_cache", {})
    out_anims, meta_seqs, durations, event_map, source_map = [], [], {}, {}, {}

    if weapon in GRENADES or weapon == "c4":
        # The previous clips and the CSCO meshes share the CS:GO bone names. Retargeting
        # their global motion keeps both hands and the weapon visible; the recompiled
        # CSCO clips use incompatible per-bone staging (verified with rendered frames).
        previous = GlbClipSource(os.path.join(fallback_dir, "v_%s.glb" % weapon))
        previous_events = old_meta.get("weapons/v_" + weapon, {}).get("seq_events", {})
        names_to_build = (("idle", "pullpin", "throw", "deploy", "underhand") if weapon in GRENADES
                          else ("idle", "draw", "drop", "pressbutton"))
        for name in names_to_build:
            times, ts, qs = previous.clip(name, rig, bind_t, bind_q)
            out_anims.append((name, times, ts, qs, None))
            meta_seqs.append(name)
            durations[name] = round(float(times[-1]), 3)
            if name in previous_events:
                event_map[name] = previous_events[name]
            source_map[name] = "retargeted_previous_csgo"
    else:
        mat = MatAnimations(weapon, mat_root)
        for seq in mat.seqs:
            names = game_names(weapon, seq["name"])
            if not names or "delta" in seq["flags"]:
                continue
            candidate = candidates.get(names[0])
            if candidate is None and len(names) > 1:
                candidate = candidates.get(names[1])
            fps = mat.fps(seq)
            poses = remap_mat_frames(mat.frames(seq), mat.rig, rig)
            # Stock include sequences describe the same SMD animation and their normalized
            # events can be used directly. For CSCO's custom main-model clips, retain the
            # M.A.T. event times because those are the frames actually being rendered.
            if candidate and candidate[2] == "csco_include":
                source_name = "mat_stock+csco_include_events"
                duration = max(len(poses) - 1, 1) / fps
                events, show, hide = csco_events(candidate[1], weapon, duration, fps, cache, report)
                # Visibility belongs to the rendered (M.A.T.) clip, not the custom CSCO one.
                _, show, hide = mat_events(seq, weapon, fps, cache, report)
            else:
                source_name = "mat_stock"
                events, show, hide = mat_events(seq, weapon, fps, cache, report)
            _finish_animation(weapon, names, poses, fps, events, show, hide, rig, out_anims,
                              meta_seqs, durations, event_map, source_name, source_map)

    port_name = "v_mp5" if weapon == "mp5" else "v_" + weapon
    output = os.path.join(out_dir, port_name + ".glb")
    build_glb(output, rig, bind_t, bind_q, prims, materials, out_anims)
    info = {"sequences": meta_seqs, "seq_durations": durations, "seq_events": event_map,
            "bones": len(rig.names), "offset": [round(float(x), 4) for x in OFFSET],
            "source": "ixof/Classic-Offensive"}
    info.update(attachment_points(model, rig, out_anims))
    report.setdefault("animation_sources", {})[weapon] = source_map
    report.setdefault("include_status", {})[weapon] = {
        "main": CSCO_MODELS[weapon], "includes_loaded": [m["name"] for m in include_models],
        "includes_missing": [i for i in model["includes"]
                             if not os.path.exists(os.path.join(csco_root, i.replace("\\", "/")))]}
    return info


def main():
    csco_root, mat_root, arms_port, out_dir, fallback_dir = sys.argv[1:6]
    only = sys.argv[6:] or list(WEAPONS) + list(GRENADES) + ["c4"]
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(REPO, "data", "models_meta.json")) as f:
        old_meta = json.load(f)
    arms_parts = load_arms(arms_port) if arms_port else []
    report = {"_materials": MaterialLibrary(csco_root, mat_root)}
    meta = {}
    for weapon in only:
        if weapon in MAT_WITH_CSCO_TEXTURE:
            info = build_mat(weapon, mat_root, arms_port, out_dir, report,
                             texture_override=os.path.join(csco_root, MAT_WITH_CSCO_TEXTURE[weapon]))
            info["source"] = "ilunp/CSGO-M.A.T geometry + ixof/Classic-Offensive texture"
        elif weapon == "mp5":
            info = build_mp5_transplant(csco_root, mat_root, out_dir, fallback_dir, arms_parts, report)
        else:
            info = build_csco(weapon, csco_root, mat_root, out_dir, fallback_dir, arms_parts, report, old_meta)
        port_name = "v_mp5" if weapon == "mp5" else "v_" + weapon
        meta["weapons/" + port_name] = info
        print("%-13s %2d seqs %6d KB" % (weapon, len(info["sequences"]),
                                         os.path.getsize(os.path.join(out_dir, port_name + ".glb")) // 1024))
    missing = sorted(set(report["_materials"].missing))
    if missing:
        report["missing_csco_materials"] = missing
    fallbacks = sorted(set(report["_materials"].fallbacks))
    if fallbacks:
        report["mat_texture_fallbacks"] = fallbacks
    report.pop("_materials", None)
    report.pop("_snd_cache", None)
    cleaned = {}
    for key, value in report.items():
        if isinstance(value, dict):
            cleaned[key] = {k: sorted(v) if isinstance(v, set) else v for k, v in value.items()}
        else:
            cleaned[key] = value
    meta["_report"] = cleaned
    with open(os.path.join(out_dir, "csgo_meta.json"), "w") as f:
        json.dump(meta, f, indent=1)
    print(json.dumps({k: v for k, v in cleaned.items() if k != "animation_sources"}, indent=1))


if __name__ == "__main__":
    main()
