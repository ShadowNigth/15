#!/usr/bin/env python3
"""CS:GO (Source, Crowbar-decompiled SMD/QC) viewmodel -> skinned, animated glTF 2.0 (.glb).

The output follows the exact conventions of the GoldSrc viewmodels already used by
the game (tools/goldsrc/mdl_converter.py + the cs16-skin-inventory ports):
  * 1 Source unit = 1/32 m
  * left-handed authoring (the game mirrors the viewmodel when right_hand is on)
  * bone-local frames identical to the GoldSrc ports of the same CS:GO rigs, so the
    CS:GO arms/gloves mesh of those ports can be bone-merged onto these models.

Source -> Godot mapping used here (see L / QL below):
    v_gd = A * ( (-y, z, x)_src * SCALE )      (A = 90 deg about +Y on root bones + offset)
"""
import io
import json
import math
import os
import struct
from typing import Dict

import numpy as np
from PIL import Image

from .smd import angle_quat, quat_inv, quat_mul, trs

SCALE = 1.0 / 32.0
_S45 = math.sqrt(0.5)
QA = np.array([0.0, _S45, 0.0, _S45])  # +90 deg about Godot +Y


def L(v):
    """Source position/direction -> Godot (reflection, det -1)."""
    v = np.asarray(v, dtype=np.float64)
    return np.stack([-v[..., 1], v[..., 2], v[..., 0]], axis=-1)


def QL(q):
    """Source quaternion -> Godot quaternion under the reflection L (v' = -L v)."""
    q = np.asarray(q, dtype=np.float64)
    return np.stack([q[..., 1], -q[..., 2], -q[..., 0], q[..., 3]], axis=-1)


def RA(v):
    """+90 deg about Godot +Y: (x, y, z) -> (z, y, -x)."""
    v = np.asarray(v, dtype=np.float64)
    return np.stack([v[..., 2], v[..., 1], -v[..., 0]], axis=-1)


def slerp_identity(q, w):
    """Scale a rotation by weight w (0..1)."""
    if w >= 0.999:
        return q
    ident = np.array([0.0, 0.0, 0.0, 1.0])
    if q[3] < 0:
        q = -q
    d = float(np.clip(q[3], -1.0, 1.0))
    th = math.acos(d)
    if th < 1e-6:
        return ident
    s = math.sin(th)
    return ident * math.sin((1 - w) * th) / s + q * math.sin(w * th) / s


class Rig:
    """Skeleton of the reference SMD (Source space)."""

    def __init__(self, ref):
        self.names = [n for n, _ in ref["nodes"]]
        self.parents = [p for _, p in ref["nodes"]]
        self.index = {n.lower(): i for i, n in enumerate(self.names)}
        f0 = ref["frames"][0]
        self.bind = []
        for i in range(len(self.names)):
            pos, rot = f0.get(i, ([0, 0, 0], [0, 0, 0]))
            self.bind.append((np.array(pos, dtype=np.float64), angle_quat(*rot)))

    def frames_of(self, anim):
        """Animation SMD -> list of per-frame [(pos, quat)] in rig bone order (Source space)."""
        amap = {}
        for ai, (nm, _) in enumerate(anim["nodes"]):
            ri = self.index.get(nm.lower())
            if ri is not None:
                amap[ai] = ri
        out = []
        for fr in anim["frames"]:
            cur = list(self.bind)
            for ai, (pos, rot) in fr.items():
                ri = amap.get(ai)
                if ri is not None:
                    cur[ri] = (np.array(pos, dtype=np.float64), angle_quat(*rot))
            out.append(cur)
        return out


def to_godot_local(rig, pose, offset):
    """[(pos, quat)] Source local -> Godot local (t, q) arrays, root correction applied."""
    n = len(pose)
    ts = np.zeros((n, 3))
    qs = np.zeros((n, 4))
    for i, (p, q) in enumerate(pose):
        t = L(p) * SCALE
        qq = QL(q)
        if rig.parents[i] < 0:
            t = RA(t) + offset
            qq = quat_mul(QA, qq)
        norm = np.linalg.norm(qq)
        if norm < 1e-8:
            # A few CS2 FRAMEANIM sections contain an all-zero quaternion for an
            # untouched bone.  Fall back to its bind rotation rather than emitting
            # NaNs into the GLB animation track.
            qq = QL(rig.bind[i][1])
            if rig.parents[i] < 0:
                qq = quat_mul(QA, qq)
            norm = np.linalg.norm(qq)
        ts[i] = t
        qs[i] = qq / norm if norm > 1e-8 else np.array([0.0, 0.0, 0.0, 1.0])
    return ts, qs


def globals_of(rig, ts, qs):
    g = [None] * len(ts)

    def calc(i):
        if g[i] is None:
            m = trs(ts[i], qs[i])
            p = rig.parents[i]
            g[i] = calc(p) @ m if p >= 0 else m
        return g[i]
    for i in range(len(ts)):
        calc(i)
    return g


def apply_delta(base_frames, delta_pose, corr_pose, weights, mode="pre"):
    """Source additive layer: delta = corr^-1 * anim (per bone, Source local space)."""
    out = []
    for fr in base_frames:
        cur = []
        for i, (p, q) in enumerate(fr):
            w = weights[i]
            if w <= 0:
                cur.append((p, q))
                continue
            dp = delta_pose[i][0] - corr_pose[i][0]
            if mode == "pre":
                dq = quat_mul(delta_pose[i][1], quat_inv(corr_pose[i][1]))
                nq = quat_mul(slerp_identity(dq, w), q)
            else:
                dq = quat_mul(quat_inv(corr_pose[i][1]), delta_pose[i][1])
                nq = quat_mul(q, slerp_identity(dq, w))
            cur.append((p + dp * w, nq))
        out.append(cur)
    return out


class GlbWriter:
    def __init__(self):
        self.bin = bytearray()
        self.views = []
        self.accessors = []

    def view(self, raw, target=None):
        while len(self.bin) % 4:
            self.bin.append(0)
        bv = {"buffer": 0, "byteOffset": len(self.bin), "byteLength": len(raw)}
        if target:
            bv["target"] = target
        self.bin.extend(raw)
        self.views.append(bv)
        return len(self.views) - 1

    def acc(self, arr, ctype, atype, target=None, minmax=False):
        arr = np.ascontiguousarray(arr)
        a = {"bufferView": self.view(arr.tobytes(), target), "componentType": ctype,
             "count": int(arr.shape[0]), "type": atype}
        if minmax:
            a["min"] = np.min(arr, axis=0).astype(float).reshape(-1).tolist()
            a["max"] = np.max(arr, axis=0).astype(float).reshape(-1).tolist()
        self.accessors.append(a)
        return len(self.accessors) - 1


def encode_texture(img: Image.Image, max_size=1024, jpeg=True):
    img = img.convert("RGB") if jpeg else img.convert("RGBA")
    if max(img.size) > max_size:
        img = img.resize((max_size, max_size * img.size[1] // img.size[0]), Image.LANCZOS)
    buf = io.BytesIO()
    if jpeg:
        img.save(buf, "JPEG", quality=88, optimize=True)
        return buf.getvalue(), "image/jpeg"
    img.save(buf, "PNG", optimize=True)
    return buf.getvalue(), "image/png"


def build_glb(out_path, rig, bind_t, bind_q, prims, materials, animations, extra_scale_tracks=None):
    """prims: list of dict(pos, nrm, uv, joints(Nx4), weights(Nx4), idx, material)
    materials: list of dict(name, image=(bytes, mime) | None, color=[r,g,b,a])
    animations: list of (name, times, ts[F,B,3], qs[F,B,4], scale_tracks{bone: s[F,3]})
    """
    w = GlbWriter()
    images, textures, mats = [], [], []
    for m in materials:
        md = {"name": m["name"], "pbrMetallicRoughness": {"metallicFactor": 0.0, "roughnessFactor": 0.85}}
        if m.get("alpha_mode"):
            md["alphaMode"] = m["alpha_mode"]
        if m.get("alpha_cutoff") is not None:
            md["alphaCutoff"] = float(m["alpha_cutoff"])
        if m.get("double_sided"):
            md["doubleSided"] = True
        if m.get("emissive") is not None:
            md["emissiveFactor"] = m["emissive"]
        if m.get("image"):
            data, mime = m["image"]
            images.append({"bufferView": w.view(data), "mimeType": mime, "name": m["name"]})
            textures.append({"sampler": 0, "source": len(images) - 1})
            md["pbrMetallicRoughness"]["baseColorTexture"] = {"index": len(textures) - 1}
            if m.get("color") is not None:
                md["pbrMetallicRoughness"]["baseColorFactor"] = m["color"]
        else:
            md["pbrMetallicRoughness"]["baseColorFactor"] = m.get("color", [0.5, 0.5, 0.5, 1.0])
        mats.append(md)

    gl_prims = []
    for p in prims:
        n = len(p["pos"])
        attrs = {
            "POSITION": w.acc(p["pos"].astype("<f4"), 5126, "VEC3", 34962, True),
            "NORMAL": w.acc(p["nrm"].astype("<f4"), 5126, "VEC3", 34962),
            "TEXCOORD_0": w.acc(p["uv"].astype("<f4"), 5126, "VEC2", 34962),
            "JOINTS_0": w.acc(p["joints"].astype("<u2"), 5123, "VEC4", 34962),
            "WEIGHTS_0": w.acc(p["weights"].astype("<f4"), 5126, "VEC4", 34962),
        }
        idx = p["idx"].astype("<u2" if n <= 65535 else "<u4")
        gl_prims.append({"attributes": attrs,
                         "indices": w.acc(idx, 5123 if n <= 65535 else 5125, "SCALAR", 34963),
                         "material": p["material"], "mode": 4})

    nb = len(rig.names)
    nodes = [{"name": "Armature", "children": []}]
    kids = {i: [] for i in range(nb)}
    for i in range(nb):
        p = rig.parents[i]
        if p >= 0:
            kids[p].append(1 + i)
        else:
            nodes[0]["children"].append(1 + i)
    for i in range(nb):
        nd = {"name": rig.names[i], "translation": bind_t[i].tolist(), "rotation": bind_q[i].tolist()}
        if kids[i]:
            nd["children"] = kids[i]
        nodes.append(nd)
    mesh_node = len(nodes)
    nodes.append({"name": "Mesh", "mesh": 0, "skin": 0})
    nodes[0]["children"].append(mesh_node)

    G = globals_of(rig, bind_t, bind_q)
    ibm = np.array([np.linalg.inv(g).T for g in G], dtype="<f4")
    skin = {"inverseBindMatrices": w.acc(ibm.reshape(nb, 16), 5126, "MAT4"),
            "joints": [1 + i for i in range(nb)], "skeleton": 0}

    gl_anims = []
    cache = {}
    for name, times, ts, qs, sc in animations:
        key = id(ts)
        if key in cache:  # alias: same clip under another name
            gl_anims.append({"name": name, "samplers": cache[key]["samplers"], "channels": cache[key]["channels"]})
            continue
        t_full = w.acc(times.astype("<f4").reshape(-1, 1), 5126, "SCALAR", None, True)
        t_const = t_full
        if len(times) > 2:
            t_const = w.acc(np.array([times[0], times[-1]], dtype="<f4").reshape(-1, 1), 5126, "SCALAR", None, True)
        samplers, channels = [], []

        def add(node, path, vals, atype, tol):
            if len(times) > 2 and float(np.max(np.abs(vals - vals[0]))) < tol:
                a = w.acc(np.array([vals[0], vals[-1]], dtype="<f4"), 5126, atype)
                inp = t_const
            else:
                a = w.acc(vals.astype("<f4"), 5126, atype)
                inp = t_full
            samplers.append({"input": inp, "interpolation": "LINEAR", "output": a})
            channels.append({"sampler": len(samplers) - 1, "target": {"node": node, "path": path}})

        for b in range(nb):
            add(1 + b, "translation", ts[:, b, :], "VEC3", 1e-5)
            add(1 + b, "rotation", qs[:, b, :], "VEC4", 1e-5)
        for b, s in (sc or {}).items():
            add(1 + b, "scale", s, "VEC3", 1e-6)
        entry = {"name": name, "samplers": samplers, "channels": channels}
        cache[key] = entry
        gl_anims.append(entry)

    while len(w.bin) % 4:
        w.bin.append(0)
    js = {
        "asset": {"version": "2.0", "generator": "CSGO-SMD-Godot-Converter"},
        "scene": 0, "scenes": [{"nodes": [0]}],
        "nodes": nodes,
        "meshes": [{"name": os.path.splitext(os.path.basename(out_path))[0], "primitives": gl_prims}],
        "skins": [skin],
        "materials": mats,
        "accessors": w.accessors, "bufferViews": w.views, "buffers": [{"byteLength": len(w.bin)}],
    }
    if images:
        js["images"] = images
        js["textures"] = textures
        js["samplers"] = [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}]
    if gl_anims:
        js["animations"] = gl_anims
    jb = json.dumps(js, separators=(",", ":")).encode()
    jb += b" " * ((4 - len(jb) % 4) % 4)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(jb) + 8 + len(w.bin)))
        f.write(struct.pack("<II", len(jb), 0x4E4F534A))
        f.write(jb)
        f.write(struct.pack("<II", len(w.bin), 0x004E4942))
        f.write(w.bin)


def mesh_from_smds(rig, smd_list, bind_G, offset, mat_index):
    """Reference triangles -> primitives (deduplicated), in Godot bind space."""
    buckets: Dict[int, list] = {}
    for smd in smd_list:
        local_index = {}
        for ai, (nm, _) in enumerate(smd["nodes"]):
            ri = rig.index.get(nm.lower())
            local_index[ai] = ri if ri is not None else 0
        for mat, vs in smd["triangles"]:
            mi = mat_index(mat)
            for v in reversed(vs):  # reflection -> flip winding
                b, pos, nrm, uv, links = v
                lk = sorted(links, key=lambda x: -x[1])[:4]
                tot = sum(x[1] for x in lk) or 1.0
                j = [local_index.get(x[0], 0) for x in lk] + [0] * (4 - len(lk))
                wt = [x[1] / tot for x in lk] + [0.0] * (4 - len(lk))
                buckets.setdefault(mi, []).append((pos, nrm, uv, tuple(j), tuple(wt)))
    prims = []
    for mi, verts in sorted(buckets.items()):
        uniq = {}
        P, N, U, J, W, I = [], [], [], [], [], []
        for pos, nrm, uv, j, wt in verts:
            key = (round(pos[0], 4), round(pos[1], 4), round(pos[2], 4), round(nrm[0], 3), round(nrm[1], 3),
                   round(nrm[2], 3), round(uv[0], 5), round(uv[1], 5), j, wt)
            k = uniq.get(key)
            if k is None:
                k = len(P)
                uniq[key] = k
                P.append(pos)
                N.append(nrm)
                U.append([uv[0], 1.0 - uv[1]])
                J.append(j)
                W.append(wt)
            I.append(k)
        P = RA(L(np.array(P)) * SCALE) + offset
        N = RA(L(np.array(N)))
        N /= np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-8)
        prims.append({"pos": P, "nrm": N, "uv": np.array(U), "joints": np.array(J), "weights": np.array(W),
                      "idx": np.array(I), "material": mi})
    return prims
