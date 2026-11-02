#!/usr/bin/env python3
"""CS:GO M.A.T. world models -> Godot static GLBs (p_ = held in hand, w_ = dropped).

usage: python -m tools.source.build_csgo_worldmodels <MAT>/Source <ref_dir> <out_dir> [weapon ...]

* p_<id>.glb comes from w_<x>.smd (the third-person model).  CS:GO models are authored in the
  player's "weapon_hand_R" frame; the GoldSrc player rigs used here hold weapons in "Bip01 R Hand"
  with per-weapon-class grips, so each gun is rigidly fitted (ICP, no scale) onto the previous
  p_ model in <ref_dir> (same weapon slot), starting from the common hand-frame rotation.
* w_<id>.glb comes from w_<x>_dropped.smd, laid on its side (thin axis = +Y) for DroppedWeapon.gd,
  which recentres the mesh by its AABB.
"""
import glob
import json
import os
import struct
import sys

import numpy as np

from . import qc as qcmod
from .build_csgo_viewmodels import FALLBACK_COLORS, WEAPONS
from .smd import angle_quat, parse_smd, quat_mat
from .smd_converter import GlbWriter, encode_texture

SC = 1.0 / 32.0
# CS:GO weapon_hand_R axes -> GoldSrc "Bip01 R Hand" (Godot) axes, fitted on the AK-47.
R_HAND = np.array([[0.053, -0.997, 0.053], [-0.188, 0.042, 0.981], [-0.981, -0.062, -0.185]])
# Dropped: barrel +X, gun lying on its side (Source -Y up).
R_DROP = np.array([[1.0, 0.0, 0.0], [0.0, 0.0, 1.0], [0.0, -1.0, 0.0]]) @ np.array(
    [[1.0, 0.0, 0.0], [0.0, 0.0, -1.0], [0.0, 1.0, 0.0]])


def _ortho(R):
    U, _, Vt = np.linalg.svd(R)
    D = np.eye(3)
    D[2, 2] = np.sign(np.linalg.det(U @ Vt))
    return U @ D @ Vt


def globals_src(r):
    fr = r["frames"][0]
    G = {}
    for i, (_, p) in enumerate(r["nodes"]):
        pos, rot = fr[i]
        M = np.eye(4)
        M[:3, :3] = quat_mat(angle_quat(*rot))
        M[:3, 3] = pos
        G[i] = G[p] @ M if p >= 0 else M
    return G


def studio_smds(qc_path, skip=("skeleto", "physics", "holsterstrap")):
    _, _, cmds = qcmod.sequences(qc_path)
    out = []
    for nm, args in cmds:
        if nm.lower() != "$bodygroup" or len(args) < 2 or not isinstance(args[1], list):
            continue
        blk = args[1]
        for k, tok in enumerate(blk):
            low = str(tok).lower()
            if low == "blank":
                break
            if low == "studio" and k + 1 < len(blk):
                if not any(s in str(blk[k + 1]).lower() for s in skip):
                    out.append(os.path.join(os.path.dirname(qc_path), str(blk[k + 1])))
                break
    return out


def load_tris(smd_paths, frame_bone="weapon_hand_R", only_side=None):
    """[(material, [(pos_local_m, nrm_local, uv)]*3)] in <frame_bone> space (metres, Source axes).
    only_side 'L'/'R' keeps triangles whose first vertex is weighted to a left / right bone chain."""
    tris = []
    for p in smd_paths:
        r = parse_smd(p)
        names = [n for n, _ in r["nodes"]]
        parents = [q for _, q in r["nodes"]]
        G = globals_src(r)
        F = G[names.index(frame_bone)] if frame_bone in names else np.eye(4)
        Fi = np.linalg.inv(F)

        def side(bi):
            while bi >= 0:
                if names[bi].endswith("_L"):
                    return "L"
                if names[bi].endswith("_R"):
                    return "R"
                bi = parents[bi]
            return "R"
        for mat, vs in r["triangles"]:
            if only_side and side(vs[0][0]) != only_side:
                continue
            tri = []
            for _b, pos, nrm, uv, _links in vs:
                lp = Fi @ np.array([pos[0], pos[1], pos[2], 1.0])
                tri.append((lp[:3] * SC, Fi[:3, :3] @ np.array(nrm), (uv[0], 1.0 - uv[1])))
            tris.append((mat, tri))
    return tris


def glb_positions(path):
    with open(path, "rb") as f:
        data = f.read()
    jl = struct.unpack_from("<I", data, 12)[0]
    js = json.loads(data[20:20 + jl])
    binb = data[20 + jl + 8:]
    out = []
    for m in js["meshes"]:
        for pr in m["primitives"]:
            a = js["accessors"][pr["attributes"]["POSITION"]]
            bv = js["bufferViews"][a["bufferView"]]
            off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
            out.append(np.frombuffer(binb, np.float32, a["count"] * 3, off).reshape(-1, 3))
    return np.concatenate(out).astype(np.float64)


def _two_clusters(P, iters=20):
    c = np.array([P[np.argmin(P.sum(1))], P[np.argmax(P.sum(1))]])
    lab = np.zeros(len(P), int)
    for _ in range(iters):
        lab = np.argmin(((P[:, None, :] - c[None]) ** 2).sum(-1), axis=1)
        c = np.array([P[lab == k].mean(0) if np.any(lab == k) else c[k] for k in (0, 1)])
    return lab


def _proper_axis_rotations():
    import itertools
    out = []
    for perm in itertools.permutations(range(3)):
        for sg in itertools.product((1.0, -1.0), repeat=3):
            M = np.zeros((3, 3))
            for i in range(3):
                M[i, perm[i]] = sg[i]
            if np.linalg.det(M) > 0:
                out.append(M)
    return out


def fit_to_reference(A, B, R0, iters=60):
    """Rigid ICP of points A onto B starting at rotation R0 (centroids aligned)."""
    from scipy.spatial import cKDTree
    rng = np.random.default_rng(0)
    A = A[rng.choice(len(A), min(4000, len(A)), replace=False)]
    B = B[rng.choice(len(B), min(4000, len(B)), replace=False)]
    tree = cKDTree(B)
    R = R0.copy()
    t = B.mean(0) - (A @ R.T).mean(0)
    for _ in range(iters):
        X = A @ R.T + t
        _, j = tree.query(X)
        Y = B[j]
        mx, my = X.mean(0), Y.mean(0)
        U, _, Vt = np.linalg.svd((X - mx).T @ (Y - my))
        D = np.eye(3)
        D[2, 2] = np.sign(np.linalg.det(Vt.T @ U.T))
        dR = Vt.T @ D @ U.T
        R = dR @ R
        t = dR @ t + (my - dR @ mx)
    X = A @ R.T + t
    res = (tree.query(X)[0].mean() + cKDTree(X).query(B)[0].mean()) / 2
    ang = np.degrees(np.arccos(np.clip((np.trace(R0.T @ R) - 1) / 2, -1, 1)))
    return R, t, float(res), float(ang)


def write_static_glb(out_path, node_name, groups, materials_for):
    """groups: [(tris, R, t)] -> one static mesh (each group rigidly placed)."""
    buckets = {}
    for tris, R, t in groups:
        for mat, tri in tris:
            buckets.setdefault(mat, []).append([(R @ p + t, R @ n, uv) for p, n, uv in tri])
    w = GlbWriter()
    mats, images, textures, prims, img_index = [], [], [], [], {}
    for mat, tlist in sorted(buckets.items()):
        md = {"name": mat, "pbrMetallicRoughness": {"metallicFactor": 0.0, "roughnessFactor": 0.85}}
        img, color = materials_for(mat)
        if img is not None:
            key = id(img)
            if key not in img_index:
                images.append({"bufferView": w.view(img[0]), "mimeType": img[1], "name": mat})
                textures.append({"sampler": 0, "source": len(images) - 1})
                img_index[key] = len(textures) - 1
            md["pbrMetallicRoughness"]["baseColorTexture"] = {"index": img_index[key]}
        else:
            md["pbrMetallicRoughness"]["baseColorFactor"] = color
        mats.append(md)
        uniq, P, N, U, idx = {}, [], [], [], []
        for tri in tlist:
            for pos, nrm, uv in tri:
                k = (round(pos[0], 5), round(pos[1], 5), round(pos[2], 5),
                     round(nrm[0], 3), round(nrm[1], 3), round(nrm[2], 3), round(uv[0], 5), round(uv[1], 5))
                if k not in uniq:
                    uniq[k] = len(P)
                    P.append(pos)
                    N.append(nrm)
                    U.append(uv)
                idx.append(uniq[k])
        P = np.array(P)
        N = np.array(N)
        N /= np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-8)
        prims.append({
            "attributes": {
                "POSITION": w.acc(P.astype(np.float32), 5126, "VEC3", 34962, True),
                "NORMAL": w.acc(N.astype(np.float32), 5126, "VEC3", 34962),
                "TEXCOORD_0": w.acc(np.array(U, np.float32), 5126, "VEC2", 34962),
            },
            "indices": w.acc(np.array(idx, np.uint32), 5125, "SCALAR", 34963),
            "material": len(mats) - 1,
        })
    while len(w.bin) % 4:
        w.bin.append(0)
    js = {"asset": {"version": "2.0", "generator": "CSGO-SMD-Godot-Converter"}, "scene": 0,
          "scenes": [{"nodes": [0]}], "nodes": [{"name": node_name, "mesh": 0}],
          "meshes": [{"name": node_name, "primitives": prims}], "materials": mats,
          "accessors": w.accessors, "bufferViews": w.views, "buffers": [{"byteLength": len(w.bin)}]}
    if images:
        js["images"] = images
        js["textures"] = textures
        js["samplers"] = [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}]
    jb = json.dumps(js, separators=(",", ":")).encode()
    jb += b" " * ((4 - len(jb) % 4) % 4)
    with open(out_path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(jb) + 8 + len(w.bin)))
        f.write(struct.pack("<II", len(jb), 0x4E4F534A))
        f.write(jb)
        f.write(struct.pack("<II", len(w.bin), 0x004E4942))
        f.write(w.bin)


def build(weapon, src_root, ref_dir, out_dir, report):
    folder = WEAPONS[weapon][0]
    wroot = os.path.join(src_root, folder, "Model", "model_source", "W_Models", "Decompile")
    dirs = sorted(d for d in glob.glob(os.path.join(wroot, "w_*")) if os.path.isdir(d))
    held = next(d for d in dirs if not d.endswith(("_dropped", "_mag")))
    dropped = next((d for d in dirs if d.endswith("_dropped")), None)
    tex_dir = os.path.join(src_root, folder, "Texture", "Default")
    vtf = [p for p in glob.glob(os.path.join(tex_dir, "*_Texture.vtf")) if "exponent" not in p.lower()]
    from srctools.vtf import VTF
    with open(vtf[0], "rb") as f:
        img = encode_texture(VTF.read(f).get().to_PIL(), 512, True)

    def materials_for(name):
        low = name.lower()
        for k in ("glass", "lens", "shell"):
            if k in low:
                return None, FALLBACK_COLORS[k]
        return img, None
    game = "mp5" if weapon == "mp5" else weapon
    info = {}
    # held (p_)
    held_smds = studio_smds(glob.glob(os.path.join(held, "*.qc"))[0])
    ref = os.path.join(ref_dir, "p_%s.glb" % game)
    B = glb_positions(ref) if os.path.exists(ref) else None
    if weapon == "elite" and B is not None:
        # Dualies: each pistol lives on its own hand bone; the GoldSrc reference holds them apart,
        # so fit the right gun to the reference pistol nearest the hand and the left one to the other.
        lab = _two_clusters(B)
        near = int(np.argmin([np.linalg.norm(B[lab == k].mean(0)) for k in (0, 1)]))
        groups = []
        for sd, bone, cl in (("R", "weapon_hand_R", near), ("L", "weapon_hand_L", 1 - near)):
            tris = load_tris(held_smds, bone, sd)
            A = np.array([v[0] for _, tri in tris for v in tri])
            best = None
            for R0 in _proper_axis_rotations():
                fit = fit_to_reference(A, B[lab == cl], R0, iters=30)
                if best is None or fit[2] < best[2]:
                    best = fit
            R, t = best[0], best[1]
            info["p_fit_" + sd] = {"residual_m": round(best[2], 4)}
            groups.append((tris, _ortho(R), t))
    else:
        tris = load_tris(held_smds)
        A = np.array([v[0] for _, tri in tris for v in tri])
        R, t = R_HAND, np.zeros(3)
        if B is not None:
            R, t, res, ang = fit_to_reference(A, B, R_HAND)
            info["p_fit"] = {"residual_m": round(res, 4), "deg_from_hand_frame": round(ang, 1)}
        groups = [(tris, _ortho(R), t)]
    write_static_glb(os.path.join(out_dir, "p_%s.glb" % game), "p_" + game, groups, materials_for)
    # dropped (w_)
    if dropped:
        tris = load_tris(studio_smds(glob.glob(os.path.join(dropped, "*.qc"))[0]))
        write_static_glb(os.path.join(out_dir, "w_%s.glb" % game), "w_" + game, [(tris, R_DROP, np.zeros(3))],
                         materials_for)
    report[weapon] = info
    return info


def main():
    src_root, ref_dir, out_dir = sys.argv[1:4]
    only = sys.argv[4:] or list(WEAPONS)
    os.makedirs(out_dir, exist_ok=True)
    report = {}
    for wpn in only:
        print(wpn, build(wpn, src_root, ref_dir, out_dir, report))
    with open(os.path.join(out_dir, "world_report.json"), "w") as f:
        json.dump(report, f, indent=1)


if __name__ == "__main__":
    main()
