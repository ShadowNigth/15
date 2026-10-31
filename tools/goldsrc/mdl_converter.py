#!/usr/bin/env python3
"""
Converts GoldSrc StudioMDL v10 (.mdl + companion T.mdl textures + IDSQ sequence groups)
into standard glTF 2.0 Binary (.glb) models with:
  - Embedded lossless 8-bit indexed/RGBA PNG textures
  - Full bone hierarchy & vertex skinning (JOINTS_0, WEIGHTS_0)
  - Sampled skeletal animations (idle, shoot, reload, draw, silencer, locomotion, death)
  - GoldSrc -> Godot 4 right-handed coordinate conversion: (x, y, z)_gs -> (-y, z, -x)_gd * SCALE
"""

import glob
import io
import json
import math
import os
import struct
from typing import Dict, List, Optional, Tuple

import numpy as np
from PIL import Image

from . import SCALE


def gs_pos_to_gd(v: np.ndarray) -> np.ndarray:
    """(x, y, z)_goldsrc -> (-y, z, -x)_godot * SCALE (proper rotation det=+1)."""
    out = np.empty_like(v, dtype=np.float32)
    out[..., 0] = -v[..., 1] * SCALE
    out[..., 1] = v[..., 2] * SCALE
    out[..., 2] = -v[..., 0] * SCALE
    return out


def gs_dir_to_gd(v: np.ndarray) -> np.ndarray:
    """(x, y, z)_goldsrc -> (-y, z, -x)_godot (unit vectors / normals)."""
    out = np.empty_like(v, dtype=np.float32)
    out[..., 0] = -v[..., 1]
    out[..., 1] = v[..., 2]
    out[..., 2] = -v[..., 0]
    return out


def gs_quat_to_gd(q: np.ndarray) -> np.ndarray:
    """(qx, qy, qz, qw)_goldsrc -> (-qy, qz, -qx, qw)_godot (similarity under det=+1 C)."""
    out = np.empty_like(q, dtype=np.float32)
    out[..., 0] = -q[..., 1]
    out[..., 1] = q[..., 2]
    out[..., 2] = -q[..., 0]
    out[..., 3] = q[..., 3]
    return out


def angle_quaternion_gs(rx: float, ry: float, rz: float) -> np.ndarray:
    """Matches Half-Life SDK StudioCalcBoneQuaterion (intrinsic ZYX)."""
    sr, cr = math.sin(rx * 0.5), math.cos(rx * 0.5)
    sp, cp = math.sin(ry * 0.5), math.cos(ry * 0.5)
    sy, cy = math.sin(rz * 0.5), math.cos(rz * 0.5)
    qx = sr * cp * cy - cr * sp * sy
    qy = cr * sp * cy + sr * cp * sy
    qz = cr * cp * sy - sr * sp * cy
    qw = cr * cp * cy + sr * sp * sy
    return np.array([qx, qy, qz, qw], dtype=np.float32)


def trs_to_mat4(t: np.ndarray, q: np.ndarray) -> np.ndarray:
    x, y, z, w = float(q[0]), float(q[1]), float(q[2]), float(q[3])
    m = np.eye(4, dtype=np.float32)
    m[0, 0] = 1.0 - 2.0 * (y * y + z * z)
    m[0, 1] = 2.0 * (x * y - z * w)
    m[0, 2] = 2.0 * (x * z + y * w)
    m[1, 0] = 2.0 * (x * y + z * w)
    m[1, 1] = 1.0 - 2.0 * (x * x + z * z)
    m[1, 2] = 2.0 * (y * z - x * w)
    m[2, 0] = 2.0 * (x * z - y * w)
    m[2, 1] = 2.0 * (y * z + x * w)
    m[2, 2] = 1.0 - 2.0 * (x * x + y * y)
    m[:3, 3] = t
    return m


def eval_rle_anim_value(buf: bytes, rle_pos: int, frame: int) -> int:
    """Evaluates Half-Life mstudioanimvalue_t RLE compressed int16 track at `frame`."""
    k = frame
    pos = rle_pos
    n = len(buf)
    while pos + 2 <= n:
        valid = buf[pos]
        total = buf[pos + 1]
        if total == 0:
            return 0
        if k < total:
            idx = (k + 1) if k < valid else valid
            val_pos = pos + idx * 2
            if val_pos + 2 > n:
                return 0
            return struct.unpack_from("<h", buf, val_pos)[0]
        k -= total
        pos += (valid + 1) * 2
    return 0


PLAYER_ANIM_KEYWORDS = (
    "idle",
    "idle1",
    "crouch_idle",
    "walk",
    "run",
    "crouchrun",
    "jump",
    "crouch_aim_carbine",
    "crouch_shoot_carbine",
    "crouch_reload_carbine",
    "ref_aim_carbine",
    "ref_shoot_carbine",
    "ref_reload_carbine",
    "crouch_aim_onehanded",
    "crouch_shoot_onehanded",
    "crouch_reload_onehanded",
    "ref_aim_onehanded",
    "ref_shoot_onehanded",
    "ref_reload_onehanded",
    "crouch_aim_dualpistols",
    "crouch_shoot_dualpistols",
    "crouch_shoot2_dualpistols",
    "crouch_reload_dualpistols",
    "ref_aim_dualpistols",
    "ref_shoot_dualpistols",
    "ref_shoot2_dualpistols",
    "ref_reload_dualpistols",
    "crouch_aim_rifle",
    "crouch_shoot_rifle",
    "crouch_reload_rifle",
    "ref_aim_rifle",
    "ref_shoot_rifle",
    "ref_reload_rifle",
    "crouch_aim_mp5",
    "crouch_shoot_mp5",
    "crouch_reload_mp5",
    "ref_aim_mp5",
    "ref_shoot_mp5",
    "ref_reload_mp5",
    "crouch_aim_shotgun",
    "crouch_shoot_shotgun",
    "crouch_reload_shotgun",
    "ref_aim_shotgun",
    "ref_shoot_shotgun",
    "ref_reload_shotgun",
    "crouch_aim_m249",
    "crouch_shoot_m249",
    "crouch_reload_m249",
    "ref_aim_m249",
    "ref_shoot_m249",
    "ref_reload_m249",
    "ref_aim_grenade",
    "ref_shoot_grenade",
    "crouch_aim_grenade",
    "crouch_shoot_grenade",
    "crouch_aim_c4",
    "crouch_shoot_c4",
    "ref_aim_c4",
    "ref_shoot_c4",
    "ref_reload_c4",
    "crouch_aim_knife",
    "crouch_shoot_knife",
    "ref_aim_knife",
    "ref_shoot_knife",
    "crouch_aim_ak47",
    "crouch_shoot_ak47",
    "crouch_reload_ak47",
    "ref_aim_ak47",
    "ref_shoot_ak47",
    "ref_reload_ak47",
    "gut_flinch",
    "head_flinch",
    "die_simple",
    "die_backwards",
    "die_forwards",
    "death1",
    "death2",
    "death3",
    "crouch_die",
    "head",
    "gutshot",
    "left",
    "back",
    "right",
    "forward",
)


def should_include_seq(model_kind: str, seq_name: str, seq_idx: int) -> bool:
    lname = seq_name.lower()
    if model_kind == "viewmodel":
        return True
    if model_kind == "prop":
        return seq_idx == 0
    if lname == "dummy":
        return False
    if lname in PLAYER_ANIM_KEYWORDS:
        return True
    return seq_idx <= 6


def find_companion_texture_mdl(mdl_path: str) -> Optional[bytes]:
    base, ext = os.path.splitext(mdl_path)
    parent = os.path.dirname(mdl_path)
    stem = os.path.basename(base).lower()
    for p in glob.glob(os.path.join(parent, "*.[mM][dD][lL]")):
        cand = os.path.splitext(os.path.basename(p))[0].lower()
        if cand == stem + "t":
            return open(p, "rb").read()
    return None


def convert_mdl_to_glb(mdl_path: str, out_glb_path: str, model_kind: str = "prop") -> Optional[dict]:
    with open(mdl_path, "rb") as f:
        d = f.read()
    if len(d) < 244 or d[:4] != b"IDST":
        return None
    ver = struct.unpack_from("<i", d, 4)[0]
    if ver != 10:
        return None

    numbones, boneindex = struct.unpack_from("<ii", d, 140)
    numhitboxes, hitboxindex = struct.unpack_from("<ii", d, 156)
    numseq, seqindex = struct.unpack_from("<ii", d, 164)
    numseqgroups, seqgroupindex = struct.unpack_from("<ii", d, 172)
    numtextures, textureindex, _ = struct.unpack_from("<iii", d, 180)
    numskinref, numskinfamilies, skinindex = struct.unpack_from("<iii", d, 192)
    numbodyparts, bodypartindex = struct.unpack_from("<ii", d, 204)

    # Load texture source (self or companion *T.mdl)
    tex_buf = d
    if numtextures == 0:
        comp = find_companion_texture_mdl(mdl_path)
        if comp and len(comp) >= 204 and comp[:4] == b"IDST":
            tex_buf = comp
            numtextures, textureindex, _ = struct.unpack_from("<iii", tex_buf, 180)
            numskinref, numskinfamilies, skinindex = struct.unpack_from("<iii", tex_buf, 192)

    # Parse textures -> PNG bytes
    textures_info = []
    for ti in range(numtextures):
        tofs = textureindex + ti * 80
        tname = tex_buf[tofs : tofs + 64].split(b"\x00")[0].decode("latin1", errors="ignore")
        tflags, tw, th, tdata_ofs = struct.unpack_from("<iiii", tex_buf, tofs + 64)
        pix = tex_buf[tdata_ofs : tdata_ofs + tw * th]
        pal = tex_buf[tdata_ofs + tw * th : tdata_ofs + tw * th + 768]
        is_masked = bool(tflags & 0x0040)  # STUDIO_NF_MASKED
        arr = np.frombuffer(pix, dtype=np.uint8).reshape((th, tw))
        pal_padded = pal + b"\x00" * max(0, 768 - len(pal))
        pal_arr = np.frombuffer(pal_padded[:768], dtype=np.uint8).reshape((256, 3))
        rgb = pal_arr[arr]
        bio = io.BytesIO()
        if is_masked:
            alpha = np.where(arr == 255, np.uint8(0), np.uint8(255))
            opaque_mask = arr != 255
            fill_rgb = rgb[opaque_mask].mean(axis=0).astype(np.uint8) if np.any(opaque_mask) else np.array([64, 64, 64], dtype=np.uint8)
            rgb = np.where(opaque_mask[..., None], rgb, fill_rgb)
            Image.fromarray(np.dstack([rgb, alpha]), mode="RGBA").save(bio, format="PNG", optimize=True)
        else:
            img_p = Image.fromarray(arr, mode="P")
            img_p.putpalette(list(pal_padded[:768]))
            img_p.save(bio, format="PNG", optimize=True)
        textures_info.append({
            "name": tname or f"tex_{ti}",
            "width": max(1, tw),
            "height": max(1, th),
            "masked": is_masked,
            "png": bio.getvalue(),
        })

    if not textures_info:
        # Fallback 8x8 grey texture
        bio = io.BytesIO()
        Image.new("RGB", (8, 8), (140, 140, 140)).save(bio, format="PNG")
        textures_info.append({"name": "fallback", "width": 8, "height": 8, "masked": False, "png": bio.getvalue()})

    skin_table = []
    if numskinref > 0 and skinindex + numskinref * 2 <= len(tex_buf):
        skin_table = list(struct.unpack_from(f"<{numskinref}H", tex_buf, skinindex))

    # Parse bones
    bones = []
    for bi in range(numbones):
        bofs = boneindex + bi * 112
        bname = d[bofs : bofs + 32].split(b"\x00")[0].decode("latin1", errors="ignore") or f"bone_{bi}"
        parent = struct.unpack_from("<i", d, bofs + 32)[0]
        vals = struct.unpack_from("<6f", d, bofs + 64)
        scls = struct.unpack_from("<6f", d, bofs + 88)
        t_gs = np.array(vals[:3], dtype=np.float32)
        q_gs = angle_quaternion_gs(vals[3], vals[4], vals[5])
        t_gd = gs_pos_to_gd(t_gs)
        q_gd = gs_quat_to_gd(q_gs)
        bones.append({
            "name": bname,
            "parent": parent,
            "vals": vals,
            "scls": scls,
            "t_gs": t_gs,
            "q_gs": q_gs,
            "t_gd": t_gd,
            "q_gd": q_gd,
        })

    if not bones:
        bones.append({
            "name": "root",
            "parent": -1,
            "vals": (0.0,) * 6,
            "scls": (0.0,) * 6,
            "t_gs": np.zeros(3, dtype=np.float32),
            "q_gs": np.array([0, 0, 0, 1], dtype=np.float32),
            "t_gd": np.zeros(3, dtype=np.float32),
            "q_gd": np.array([0, 0, 0, 1], dtype=np.float32),
        })

    # Global rest matrices in GoldSrc and Godot spaces
    rest_gs = []
    rest_gd = []
    for bi, b in enumerate(bones):
        m_gs = trs_to_mat4(b["t_gs"], b["q_gs"])
        m_gd = trs_to_mat4(b["t_gd"], b["q_gd"])
        p = b["parent"]
        if 0 <= p < bi:
            m_gs = rest_gs[p] @ m_gs
            m_gd = rest_gd[p] @ m_gd
        rest_gs.append(m_gs)
        rest_gd.append(m_gd)

    inv_bind_gd = [np.linalg.inv(m).astype(np.float32) for m in rest_gd]

    # Parse hitboxes (for accurate head/chest/stomach/limb multipliers)
    hitboxes = []
    for hi in range(numhitboxes):
        hofs = hitboxindex + hi * 32
        hbone, hgroup = struct.unpack_from("<ii", d, hofs)
        bbmin = gs_pos_to_gd(np.array(struct.unpack_from("<3f", d, hofs + 8), dtype=np.float32))
        bbmax = gs_pos_to_gd(np.array(struct.unpack_from("<3f", d, hofs + 20), dtype=np.float32))
        lo = np.minimum(bbmin, bbmax).tolist()
        hi_v = np.maximum(bbmin, bbmax).tolist()
        hitboxes.append({"bone": hbone, "group": hgroup, "min": [round(x, 4) for x in lo], "max": [round(x, 4) for x in hi_v]})

    # Collect geometry across all bodyparts (using submodel 0 of each bodypart, except skip empty/shield extras)
    # Group triangles by texture index -> glTF primitives
    prim_buckets: Dict[int, List[Tuple[np.ndarray, np.ndarray, Tuple[float, float], int]]] = {}

    for bpi in range(numbodyparts):
        bp_ofs = bodypartindex + bpi * 76
        bp_nummodels, bp_base, bp_modelindex = struct.unpack_from("<iii", d, bp_ofs + 64)
        if bp_nummodels <= 0:
            continue
        # Submodel 0 is default active part (e.g. player body / head / backpack off)
        m_ofs = bp_modelindex
        _, _, nummesh, meshindex, numverts, vertinfoindex, vertindex, numnorms, norminfoindex, normindex, _, _ = (
            struct.unpack_from("<ifiiiiiiiiii", d, m_ofs + 64)
        )
        if numverts <= 0 or nummesh <= 0:
            continue

        v_bones = np.frombuffer(d[vertinfoindex : vertinfoindex + numverts], dtype=np.uint8)
        n_bones = np.frombuffer(d[norminfoindex : norminfoindex + numnorms], dtype=np.uint8)
        verts_local = np.frombuffer(d[vertindex : vertindex + numverts * 12], dtype="<f4").reshape((-1, 3))
        norms_local = np.frombuffer(d[normindex : normindex + numnorms * 12], dtype="<f4").reshape((-1, 3))

        # Transform bone-local GoldSrc vertices -> GoldSrc model space -> Godot model space
        verts_gd = np.zeros((numverts, 3), dtype=np.float32)
        for vi in range(numverts):
            bi = min(int(v_bones[vi]), len(rest_gs) - 1)
            p_gs = rest_gs[bi][:3, :3] @ verts_local[vi] + rest_gs[bi][:3, 3]
            verts_gd[vi] = gs_pos_to_gd(p_gs)

        norms_gd = np.zeros((numnorms, 3), dtype=np.float32)
        for ni in range(numnorms):
            bi = min(int(n_bones[ni]), len(rest_gs) - 1)
            n_gs = rest_gs[bi][:3, :3] @ norms_local[ni]
            ln = float(np.linalg.norm(n_gs))
            if ln > 1e-6:
                n_gs = n_gs / ln
            norms_gd[ni] = gs_dir_to_gd(n_gs)

        for mi in range(nummesh):
            numtris, triindex, skinref, _, _ = struct.unpack_from("<5i", d, meshindex + mi * 20)
            tex_idx = skin_table[skinref] if skinref < len(skin_table) else skinref
            tex_idx = max(0, min(tex_idx, len(textures_info) - 1))
            tw = float(textures_info[tex_idx]["width"])
            th = float(textures_info[tex_idx]["height"])

            bucket = prim_buckets.setdefault(tex_idx, [])
            pos = triindex
            while pos + 2 <= len(d):
                cmd = struct.unpack_from("<h", d, pos)[0]
                pos += 2
                if cmd == 0:
                    break
                cnt = abs(cmd)
                if pos + cnt * 8 > len(d):
                    break
                pts = [struct.unpack_from("<4h", d, pos + k * 8) for k in range(cnt)]
                pos += cnt * 8
                for k in range(cnt - 2):
                    if cmd > 0:  # strip (CW in GoldSrc -> reverse last two for CCW glTF)
                        if k % 2 == 0:
                            tri = (pts[k], pts[k + 2], pts[k + 1])
                        else:
                            tri = (pts[k + 1], pts[k + 2], pts[k])
                    else:  # fan (CW in GoldSrc -> reverse last two for CCW glTF)
                        tri = (pts[0], pts[k + 2], pts[k + 1])

                    for vi, ni, s_px, t_px in tri:
                        vi_c = max(0, min(int(vi), numverts - 1))
                        ni_c = max(0, min(int(ni), numnorms - 1))
                        bi_c = min(int(v_bones[vi_c]), len(bones) - 1)
                        uv = (float(s_px) / tw, float(t_px) / th)
                        bucket.append((verts_gd[vi_c], norms_gd[ni_c], uv, bi_c))

    if not prim_buckets:
        return None

    # Load external seqgroups (IDSQ) if present (e.g. hostage01..08.mdl)
    seqgroup_buffers: Dict[int, Tuple[bytes, int]] = {0: (d, 0)}
    for sgi in range(1, numseqgroups):
        sg_ofs = seqgroupindex + sgi * 104
        sg_name = d[sg_ofs + 32 : sg_ofs + 96].split(b"\x00")[0].decode("latin1", errors="ignore").replace("\\", "/")
        cand = os.path.join(os.path.dirname(mdl_path), os.path.basename(sg_name))
        if os.path.exists(cand):
            sgd = open(cand, "rb").read()
            if sgd[:4] == b"IDSQ":
                seqgroup_buffers[sgi] = (sgd, 0)

    # Parse & sample animations
    # For GoldSrc player models, gait sequences (idle1, walk, run, crouch_idle, crouchrun, jump)
    # leave upper-body spine/arm bones in horizontal 'dummy' T-pose because GoldSrc blends
    # ref_aim_* / crouch_aim_* onto Bip01 Spine and its descendants at runtime.
    upper_bone_set = set()
    aim_tables: Dict[str, Tuple[bytes, int]] = {}
    if model_kind == "player":
        spine_idx = next((i for i, b in enumerate(bones) if b["name"].lower() == "bip01 spine"), -1)
        if spine_idx >= 0:
            upper_bone_set.add(spine_idx)
            for bi, b in enumerate(bones):
                cur = b["parent"]
                guard = 0
                while 0 <= cur < numbones and guard < 128:
                    guard += 1
                    if cur in upper_bone_set:
                        upper_bone_set.add(bi)
                        break
                    cur = bones[cur]["parent"]

            for si in range(numseq):
                sofs = seqindex + si * 176
                sn = d[sofs : sofs + 32].split(b"\x00")[0].decode("latin1", errors="ignore").strip().lower()
                if sn in ("ref_aim_ak47", "crouch_aim_ak47", "ref_aim_onehanded", "crouch_aim_onehanded"):
                    sgrp = struct.unpack_from("<i", d, sofs + 168)[0]
                    if sgrp in seqgroup_buffers:
                        ab, abase = seqgroup_buffers[sgrp]
                        nblends = max(1, struct.unpack_from("<i", d, sofs + 120)[0])
                        aidx = struct.unpack_from("<i", d, sofs + 124)[0]
                        center_ofs = abase + aidx + (nblends // 2) * numbones * 12
                        if center_ofs + numbones * 12 <= len(ab):
                            aim_tables[sn] = (ab, center_ofs)

    def sample_sequence_tracks(
        abuf: bytes,
        anim_table_ofs: int,
        sample_frames: List[int],
        upper_override: Optional[Tuple[bytes, int]] = None,
        force_upper_tracks: bool = False,
        lower_only: bool = False,
    ) -> List[Tuple[int, np.ndarray, np.ndarray]]:
        tracks = []
        for bi, b in enumerate(bones):
            if force_upper_tracks and upper_bone_set and (bi not in upper_bone_set):
                continue
            if lower_only and upper_bone_set and (bi in upper_bone_set):
                continue
            use_upper = (upper_override is not None) and (bi in upper_bone_set)
            emit_upper = use_upper or (force_upper_tracks and (bi in upper_bone_set))
            src_buf = upper_override[0] if use_upper else abuf
            b_anim_ofs = (upper_override[1] if use_upper else anim_table_ofs) + bi * 12
            offsets = struct.unpack_from("<6H", src_buf, b_anim_ofs)
            is_animated = any(o != 0 for o in offsets)
            if not is_animated and not emit_upper and bi > 0 and len(sample_frames) > 1:
                continue

            ts = np.zeros((len(sample_frames), 3), dtype=np.float32)
            qs = np.zeros((len(sample_frames), 4), dtype=np.float32)
            prev_q = None
            for idx_f, f in enumerate(sample_frames):
                dof = list(b["vals"])
                eval_f = 0 if use_upper else f
                for j in range(6):
                    if offsets[j] != 0:
                        raw_v = eval_rle_anim_value(src_buf, b_anim_ofs + offsets[j], eval_f)
                        dof[j] += raw_v * b["scls"][j]
                t_gd = gs_pos_to_gd(np.array(dof[:3], dtype=np.float32))
                q_gd = gs_quat_to_gd(angle_quaternion_gs(dof[3], dof[4], dof[5]))
                norm_q = float(np.linalg.norm(q_gd))
                if norm_q > 1e-6:
                    q_gd = q_gd / norm_q
                if prev_q is not None and float(np.dot(prev_q, q_gd)) < 0.0:
                    q_gd = -q_gd
                prev_q = q_gd
                ts[idx_f] = t_gd
                qs[idx_f] = q_gd
            tracks.append((bi, ts, qs))
        return tracks

    animations_data = []
    exported_seq_names = []
    seq_events_meta: Dict[str, List[dict]] = {}
    seq_durations_meta: Dict[str, float] = {}
    seen_names = set()
    gait_names = {"idle1", "walk", "run", "jump", "crouch_idle", "crouchrun"}

    for si in range(numseq):
        sofs = seqindex + si * 176
        raw_sname = d[sofs : sofs + 32].split(b"\x00")[0].decode("latin1", errors="ignore").strip() or f"seq_{si}"
        if not should_include_seq(model_kind, raw_sname, si):
            continue
        # Skip duplicate dualpistols block in player MDLs (seqs 65..72 duplicate 22..29)
        if model_kind == "player" and raw_sname in seen_names:
            continue
        sname = f"{raw_sname}_{si}" if raw_sname in seen_names else raw_sname
        seen_names.add(sname)

        fps = struct.unpack_from("<f", d, sofs + 32)[0]
        if fps <= 0.1:
            fps = 24.0
        nevents, eventindex, numframes = struct.unpack_from("<iii", d, sofs + 48)
        numframes = max(1, numframes)
        nblends = max(1, struct.unpack_from("<i", d, sofs + 120)[0])
        animindex = struct.unpack_from("<i", d, sofs + 124)[0]
        seqgroup = struct.unpack_from("<i", d, sofs + 168)[0]
        if seqgroup not in seqgroup_buffers:
            continue
        abuf, abase = seqgroup_buffers[seqgroup]
        # Use center blend (nblends // 2) so 9-way aim/shoot blends point straight ahead (0 deg pitch/yaw)!
        blend_idx = (nblends // 2) if nblends > 1 else 0
        anim_table_ofs = abase + animindex + blend_idx * numbones * 12
        if anim_table_ofs + numbones * 12 > len(abuf):
            continue

        # Extract StudioMDL QC events (5004 = frame-exact weapon foley .wav!)
        if model_kind == "viewmodel" and nevents > 0 and 0 <= eventindex and eventindex + nevents * 76 <= len(d):
            ev_list = []
            for ei in range(nevents):
                eofs = eventindex + ei * 76
                eframe, ecode, _ = struct.unpack_from("<iii", d, eofs)
                eparam = d[eofs + 12 : eofs + 76].split(b"\x00")[0].decode("latin1", errors="ignore").strip().replace("\\", "/").lower()
                if ecode == 5004 and eparam:
                    if eparam == "items/cliprelease1.wav":
                        eparam = "weapons/p90_cliprelease.wav"
                    ev_list.append({"t": round(float(eframe) / fps, 3), "wav": eparam})
            if ev_list:
                seq_events_meta[sname] = ev_list

        # Full native framerate (step=1) for ALL first-person viewmodels for crisp animations & sound sync!
        step = 1
        if model_kind != "viewmodel" and numframes > 22:
            step = max(2, numframes // 14)
        sample_frames = list(range(0, numframes, step))
        if sample_frames[-1] != numframes - 1:
            sample_frames.append(numframes - 1)
        times = np.array([f / fps for f in sample_frames], dtype=np.float32)
        seq_durations_meta[sname] = round(float(times[-1]), 3)

        lname = sname.lower()
        is_upper_clip = lname.startswith("ref_") or lname.startswith("crouch_aim_") or lname.startswith("crouch_shoot") or lname.startswith("crouch_reload_") or lname.endswith("_flinch")
        is_lower_gait = (model_kind == "player") and bool(aim_tables) and (lname in gait_names) and bool(upper_bone_set)

        bone_tracks = sample_sequence_tracks(
            abuf,
            anim_table_ofs,
            sample_frames,
            None,
            force_upper_tracks=is_upper_clip,
            lower_only=is_lower_gait,
        )
        if bone_tracks:
            animations_data.append((sname, times, bone_tracks))
            exported_seq_names.append(sname)

    # Assemble binary glTF 2.0 (.glb)
    bin_chunks = bytearray()
    buffer_views = []
    accessors = []

    def append_bytes(raw_b: bytes, target: Optional[int] = None) -> int:
        while len(bin_chunks) % 4 != 0:
            bin_chunks.append(0)
        offset = len(bin_chunks)
        bin_chunks.extend(raw_b)
        bv = {"buffer": 0, "byteOffset": offset, "byteLength": len(raw_b)}
        if target is not None:
            bv["target"] = target
        idx = len(buffer_views)
        buffer_views.append(bv)
        return idx

    def add_accessor(bv_idx: int, comp_type: int, count: int, acc_type: str, arr: Optional[np.ndarray] = None) -> int:
        acc = {
            "bufferView": bv_idx,
            "byteOffset": 0,
            "componentType": comp_type,
            "count": count,
            "type": acc_type,
        }
        if arr is not None and count > 0:
            acc["min"] = np.min(arr, axis=0).astype(float).tolist()
            acc["max"] = np.max(arr, axis=0).astype(float).tolist()
        idx = len(accessors)
        accessors.append(acc)
        return idx

    # Images & materials
    gltf_images = []
    gltf_textures = []
    gltf_materials = []
    gltf_samplers = [{"magFilter": 9728, "minFilter": 9986, "wrapS": 10497, "wrapT": 10497}]  # NEAREST mag, mipmap min

    for ti, tinfo in enumerate(textures_info):
        bv_img = append_bytes(tinfo["png"])
        gltf_images.append({"bufferView": bv_img, "mimeType": "image/png", "name": tinfo["name"]})
        gltf_textures.append({"sampler": 0, "source": ti})
        mat = {
            "name": tinfo["name"],
            "pbrMetallicRoughness": {
                "baseColorTexture": {"index": ti},
                "metallicFactor": 0.0,
                "roughnessFactor": 0.95,
            },
        }
        if tinfo["masked"]:
            mat["alphaMode"] = "MASK"
            mat["alphaCutoff"] = 0.5
            mat["doubleSided"] = True
        gltf_materials.append(mat)

    # Mesh primitives (vertex-deduplicated with uint16 indices)
    gltf_primitives = []
    for tex_idx, verts_list in sorted(prim_buckets.items()):
        if not verts_list:
            continue
        uniq_map: Dict[Tuple, int] = {}
        uniq_verts = []
        indices = []
        for pos_v, nrm_v, uv_v, bi_c in verts_list:
            key = (
                round(float(pos_v[0]), 5), round(float(pos_v[1]), 5), round(float(pos_v[2]), 5),
                round(float(nrm_v[0]), 4), round(float(nrm_v[1]), 4), round(float(nrm_v[2]), 4),
                round(float(uv_v[0]), 5), round(float(uv_v[1]), 5), int(bi_c),
            )
            idx = uniq_map.get(key)
            if idx is None:
                idx = len(uniq_verts)
                uniq_map[key] = idx
                uniq_verts.append((pos_v, nrm_v, uv_v, bi_c))
            indices.append(idx)

        n_v = len(uniq_verts)
        pos_arr = np.array([x[0] for x in uniq_verts], dtype="<f4")
        nrm_arr = np.array([x[1] for x in uniq_verts], dtype="<f4")
        uv_arr = np.array([x[2] for x in uniq_verts], dtype="<f4")
        jnt_arr = np.zeros((n_v, 4), dtype="<u2")
        jnt_arr[:, 0] = [x[3] for x in uniq_verts]
        wgt_arr = np.zeros((n_v, 4), dtype="<f4")
        wgt_arr[:, 0] = 1.0
        idx_arr = np.array(indices, dtype="<u2" if n_v <= 65535 else "<u4")
        idx_comp = 5123 if n_v <= 65535 else 5125

        acc_pos = add_accessor(append_bytes(pos_arr.tobytes(), 34962), 5126, n_v, "VEC3", pos_arr)
        acc_nrm = add_accessor(append_bytes(nrm_arr.tobytes(), 34962), 5126, n_v, "VEC3")
        acc_uv = add_accessor(append_bytes(uv_arr.tobytes(), 34962), 5126, n_v, "VEC2")
        acc_jnt = add_accessor(append_bytes(jnt_arr.tobytes(), 34962), 5123, n_v, "VEC4")
        acc_wgt = add_accessor(append_bytes(wgt_arr.tobytes(), 34962), 5126, n_v, "VEC4")
        acc_idx = add_accessor(append_bytes(idx_arr.tobytes(), 34963), idx_comp, len(indices), "SCALAR")

        gltf_primitives.append({
            "attributes": {
                "POSITION": acc_pos,
                "NORMAL": acc_nrm,
                "TEXCOORD_0": acc_uv,
                "JOINTS_0": acc_jnt,
                "WEIGHTS_0": acc_wgt,
            },
            "indices": acc_idx,
            "material": tex_idx,
            "mode": 4,
        })

    # Nodes: Node 0 = Armature root, Nodes 1..numbones = bone joints, Node (numbones+1) = Skinned Mesh
    gltf_nodes = []
    root_children = []
    bone_children: Dict[int, List[int]] = {i: [] for i in range(len(bones))}
    for bi, b in enumerate(bones):
        node_id = 1 + bi
        p = b["parent"]
        if 0 <= p < len(bones) and p != bi:
            bone_children[p].append(node_id)
        else:
            root_children.append(node_id)

    mesh_node_id = 1 + len(bones)
    gltf_nodes.append({"name": "Armature", "children": root_children + [mesh_node_id]})

    for bi, b in enumerate(bones):
        nd = {
            "name": b["name"],
            "translation": b["t_gd"].astype(float).tolist(),
            "rotation": b["q_gd"].astype(float).tolist(),
        }
        if bone_children[bi]:
            nd["children"] = bone_children[bi]
        gltf_nodes.append(nd)

    gltf_nodes.append({"name": "Mesh", "mesh": 0, "skin": 0})

    # Skin inverseBindMatrices (column-major in glTF 2.0!)
    ibm_col_major = np.array([m.T for m in inv_bind_gd], dtype="<f4")
    acc_ibm = add_accessor(append_bytes(ibm_col_major.tobytes()), 5126, len(bones), "MAT4")
    gltf_skins = [{"inverseBindMatrices": acc_ibm, "joints": [1 + i for i in range(len(bones))], "skeleton": 0}]

    # Animations (with lossless 2-keyframe compression for constant tracks!)
    gltf_animations = []
    for sname, times, bone_tracks in animations_data:
        acc_time_full = add_accessor(append_bytes(times.astype("<f4").tobytes()), 5126, len(times), "SCALAR", times[:, None])
        accessors[acc_time_full]["min"] = [float(times[0])]
        accessors[acc_time_full]["max"] = [float(times[-1])]

        acc_time_const = acc_time_full
        if len(times) > 2:
            t2 = np.array([times[0], times[-1]], dtype="<f4")
            acc_time_const = add_accessor(append_bytes(t2.tobytes()), 5126, 2, "SCALAR", t2[:, None])
            accessors[acc_time_const]["min"] = [float(t2[0])]
            accessors[acc_time_const]["max"] = [float(t2[-1])]

        samplers = []
        channels = []
        for bi, ts, qs in bone_tracks:
            node_idx = 1 + bi
            if len(times) > 2 and float(np.max(np.abs(ts - ts[0]))) < 1e-5:
                ts_c = np.array([ts[0], ts[-1]], dtype="<f4")
                acc_t = add_accessor(append_bytes(ts_c.tobytes()), 5126, 2, "VEC3")
                in_t = acc_time_const
            else:
                acc_t = add_accessor(append_bytes(ts.astype("<f4").tobytes()), 5126, len(times), "VEC3")
                in_t = acc_time_full
            s_t = len(samplers)
            samplers.append({"input": in_t, "interpolation": "LINEAR", "output": acc_t})
            channels.append({"sampler": s_t, "target": {"node": node_idx, "path": "translation"}})

            if len(times) > 2 and float(np.max(np.abs(qs - qs[0]))) < 1e-4:
                qs_c = np.array([qs[0], qs[-1]], dtype="<f4")
                acc_q = add_accessor(append_bytes(qs_c.tobytes()), 5126, 2, "VEC4")
                in_q = acc_time_const
            else:
                acc_q = add_accessor(append_bytes(qs.astype("<f4").tobytes()), 5126, len(times), "VEC4")
                in_q = acc_time_full
            s_q = len(samplers)
            samplers.append({"input": in_q, "interpolation": "LINEAR", "output": acc_q})
            channels.append({"sampler": s_q, "target": {"node": node_idx, "path": "rotation"}})

        gltf_animations.append({"name": sname, "samplers": samplers, "channels": channels})

    while len(bin_chunks) % 4 != 0:
        bin_chunks.append(0)

    gltf_json = {
        "asset": {"version": "2.0", "generator": "CS15-Godot-Extractor"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": gltf_nodes,
        "meshes": [{"name": os.path.splitext(os.path.basename(mdl_path))[0], "primitives": gltf_primitives}],
        "skins": gltf_skins,
        "materials": gltf_materials,
        "textures": gltf_textures,
        "images": gltf_images,
        "samplers": gltf_samplers,
        "accessors": accessors,
        "bufferViews": buffer_views,
        "buffers": [{"byteLength": len(bin_chunks)}],
    }
    if gltf_animations:
        gltf_json["animations"] = gltf_animations

    json_bytes = json.dumps(gltf_json, separators=(",", ":")).encode("utf-8")
    while len(json_bytes) % 4 != 0:
        json_bytes += b" "

    total_len = 12 + 8 + len(json_bytes) + 8 + len(bin_chunks)
    os.makedirs(os.path.dirname(out_glb_path), exist_ok=True)
    with open(out_glb_path, "wb") as out:
        out.write(struct.pack("<III", 0x46546C67, 2, total_len))
        out.write(struct.pack("<II", len(json_bytes), 0x4E4F534A))
        out.write(json_bytes)
        out.write(struct.pack("<II", len(bin_chunks), 0x004E4942))
        out.write(bin_chunks)

    res_meta = {"sequences": exported_seq_names, "hitboxes": hitboxes, "bones": len(bones)}
    if seq_events_meta:
        res_meta["seq_events"] = seq_events_meta
    if seq_durations_meta and model_kind == "viewmodel":
        res_meta["seq_durations"] = seq_durations_meta
    return res_meta


def convert_p_weapon_to_hand_glb(mdl_path: str, out_glb_path: str) -> Optional[dict]:
    """
    Converts a GoldSrc third-person weapon model (p_*.mdl) into a compact static glTF 2.0
    mesh expressed directly in Bip01 R Hand's Godot-local coordinate space so attaching it
    under BoneAttachment3D('Bip01 R Hand') aligns the rifle/pistol/knife/grenade into the
    character's hands with sub-millimeter precision.
    """
    with open(mdl_path, "rb") as f:
        d = f.read()
    if len(d) < 244 or d[:4] != b"IDST" or struct.unpack_from("<i", d, 4)[0] != 10:
        return None

    numbones, boneindex = struct.unpack_from("<ii", d, 140)
    numtextures, textureindex, _ = struct.unpack_from("<iii", d, 180)
    numskinref, _, skinindex = struct.unpack_from("<iii", d, 192)
    numbodyparts, bodypartindex = struct.unpack_from("<ii", d, 204)

    tex_buf = d
    if numtextures == 0:
        comp = find_companion_texture_mdl(mdl_path)
        if comp and len(comp) >= 204 and comp[:4] == b"IDST":
            tex_buf = comp
            numtextures, textureindex, _ = struct.unpack_from("<iii", tex_buf, 180)
            numskinref, _, skinindex = struct.unpack_from("<iii", tex_buf, 192)

    textures_info = []
    for ti in range(numtextures):
        tofs = textureindex + ti * 80
        tname = tex_buf[tofs : tofs + 64].split(b"\x00")[0].decode("latin1", errors="ignore")
        tflags, tw, th, tdata_ofs = struct.unpack_from("<iiii", tex_buf, tofs + 64)
        pix = tex_buf[tdata_ofs : tdata_ofs + tw * th]
        pal = tex_buf[tdata_ofs + tw * th : tdata_ofs + tw * th + 768]
        is_masked = bool(tflags & 0x0040)
        arr = np.frombuffer(pix, dtype=np.uint8).reshape((th, tw))
        pal_padded = pal + b"\x00" * max(0, 768 - len(pal))
        pal_arr = np.frombuffer(pal_padded[:768], dtype=np.uint8).reshape((256, 3))
        rgb = pal_arr[arr]
        bio = io.BytesIO()
        if is_masked:
            alpha = np.where(arr == 255, np.uint8(0), np.uint8(255))
            opaque_mask = arr != 255
            fill_rgb = rgb[opaque_mask].mean(axis=0).astype(np.uint8) if np.any(opaque_mask) else np.array([64, 64, 64], dtype=np.uint8)
            rgb = np.where(opaque_mask[..., None], rgb, fill_rgb)
            Image.fromarray(np.dstack([rgb, alpha]), mode="RGBA").save(bio, format="PNG", optimize=True)
        else:
            img_p = Image.fromarray(arr, mode="P")
            img_p.putpalette(list(pal_padded[:768]))
            img_p.save(bio, format="PNG", optimize=True)
        textures_info.append({"name": tname or f"tex_{ti}", "width": max(1, tw), "height": max(1, th), "masked": is_masked, "png": bio.getvalue()})

    if not textures_info:
        bio = io.BytesIO()
        Image.new("RGB", (8, 8), (120, 120, 120)).save(bio, format="PNG")
        textures_info.append({"name": "fallback", "width": 8, "height": 8, "masked": False, "png": bio.getvalue()})

    skin_table = list(struct.unpack_from(f"<{numskinref}H", tex_buf, skinindex)) if numskinref > 0 else []

    rest_gs = []
    rest_gd = []
    rhand_idx = -1
    for bi in range(numbones):
        bofs = boneindex + bi * 112
        bname = d[bofs : bofs + 32].split(b"\x00")[0].decode("latin1", errors="ignore").strip()
        if bname.lower() == "bip01 r hand":
            rhand_idx = bi
        parent = struct.unpack_from("<i", d, bofs + 32)[0]
        vals = struct.unpack_from("<6f", d, bofs + 64)
        q_gs = angle_quaternion_gs(vals[3], vals[4], vals[5])
        t_gs = np.array(vals[:3], dtype=np.float32)
        m_gs = trs_to_mat4(t_gs, q_gs)
        m_gd = trs_to_mat4(gs_pos_to_gd(t_gs), gs_quat_to_gd(q_gs))
        if 0 <= parent < bi:
            m_gs = rest_gs[parent] @ m_gs
            m_gd = rest_gd[parent] @ m_gd
        rest_gs.append(m_gs)
        rest_gd.append(m_gd)

    if rhand_idx < 0 or not rest_gd:
        return None
    inv_rhand_gd = np.linalg.inv(rest_gd[rhand_idx]).astype(np.float32)

    prim_buckets: Dict[int, List[Tuple[np.ndarray, np.ndarray, Tuple[float, float]]]] = {}
    for bpi in range(numbodyparts):
        bp_ofs = bodypartindex + bpi * 76
        bp_num, _, m_ofs = struct.unpack_from("<iii", d, bp_ofs + 64)
        if bp_num <= 0:
            continue
        _, _, nummesh, meshidx, numverts, vinfo, vidx, numnorms, ninfo, nidx, _, _ = struct.unpack_from("<ifiiiiiiiiii", d, m_ofs + 64)
        if numverts <= 0 or nummesh <= 0:
            continue
        v_bones = np.frombuffer(d[vinfo : vinfo + numverts], dtype=np.uint8)
        n_bones = np.frombuffer(d[ninfo : ninfo + numnorms], dtype=np.uint8)
        verts_local = np.frombuffer(d[vidx : vidx + numverts * 12], dtype="<f4").reshape((-1, 3))
        norms_local = np.frombuffer(d[nidx : nidx + numnorms * 12], dtype="<f4").reshape((-1, 3))

        verts_hand = np.zeros((numverts, 3), dtype=np.float32)
        for vi in range(numverts):
            bi = min(int(v_bones[vi]), len(rest_gs) - 1)
            p_gd = gs_pos_to_gd(rest_gs[bi][:3, :3] @ verts_local[vi] + rest_gs[bi][:3, 3])
            verts_hand[vi] = inv_rhand_gd[:3, :3] @ p_gd + inv_rhand_gd[:3, 3]

        norms_hand = np.zeros((numnorms, 3), dtype=np.float32)
        for ni in range(numnorms):
            bi = min(int(n_bones[ni]), len(rest_gs) - 1)
            n_gd = gs_dir_to_gd(rest_gs[bi][:3, :3] @ norms_local[ni])
            n_h = inv_rhand_gd[:3, :3] @ n_gd
            ln = float(np.linalg.norm(n_h))
            norms_hand[ni] = (n_h / ln) if ln > 1e-6 else np.array([0.0, 1.0, 0.0], dtype=np.float32)

        for mi in range(nummesh):
            _, triindex, skinref, _, _ = struct.unpack_from("<5i", d, meshidx + mi * 20)
            tex_idx = max(0, min(skin_table[skinref] if skinref < len(skin_table) else skinref, len(textures_info) - 1))
            tw = float(textures_info[tex_idx]["width"])
            th = float(textures_info[tex_idx]["height"])
            bucket = prim_buckets.setdefault(tex_idx, [])
            pos = triindex
            while pos + 2 <= len(d):
                cmd = struct.unpack_from("<h", d, pos)[0]
                pos += 2
                if cmd == 0:
                    break
                cnt = abs(cmd)
                if pos + cnt * 8 > len(d):
                    break
                pts = [struct.unpack_from("<4h", d, pos + k * 8) for k in range(cnt)]
                pos += cnt * 8
                for k in range(cnt - 2):
                    tri = ((pts[k], pts[k + 2], pts[k + 1]) if k % 2 == 0 else (pts[k + 1], pts[k + 2], pts[k])) if cmd > 0 else (pts[0], pts[k + 2], pts[k + 1])
                    for vi, ni, s_px, t_px in tri:
                        vi_c = max(0, min(int(vi), numverts - 1))
                        ni_c = max(0, min(int(ni), numnorms - 1))
                        bucket.append((verts_hand[vi_c], norms_hand[ni_c], (float(s_px) / tw, float(t_px) / th)))

    if not prim_buckets:
        return None

    bin_chunks = bytearray()
    buffer_views = []
    accessors = []

    def append_bytes(raw_b: bytes, target: Optional[int] = None) -> int:
        while len(bin_chunks) % 4 != 0:
            bin_chunks.append(0)
        offset = len(bin_chunks)
        bin_chunks.extend(raw_b)
        bv = {"buffer": 0, "byteOffset": offset, "byteLength": len(raw_b)}
        if target is not None:
            bv["target"] = target
        buffer_views.append(bv)
        return len(buffer_views) - 1

    def add_accessor(bv_idx: int, comp_type: int, count: int, acc_type: str, arr: Optional[np.ndarray] = None) -> int:
        acc = {"bufferView": bv_idx, "byteOffset": 0, "componentType": comp_type, "count": count, "type": acc_type}
        if arr is not None and count > 0:
            acc["min"] = np.min(arr, axis=0).astype(float).tolist()
            acc["max"] = np.max(arr, axis=0).astype(float).tolist()
        accessors.append(acc)
        return len(accessors) - 1

    gltf_images = []
    gltf_textures = []
    gltf_materials = []
    gltf_samplers = [{"magFilter": 9728, "minFilter": 9986, "wrapS": 10497, "wrapT": 10497}]
    for ti, tinfo in enumerate(textures_info):
        bv_img = append_bytes(tinfo["png"])
        gltf_images.append({"bufferView": bv_img, "mimeType": "image/png", "name": tinfo["name"]})
        gltf_textures.append({"sampler": 0, "source": ti})
        mat = {"name": tinfo["name"], "pbrMetallicRoughness": {"baseColorTexture": {"index": ti}, "metallicFactor": 0.0, "roughnessFactor": 0.95}}
        if tinfo["masked"]:
            mat["alphaMode"] = "MASK"
            mat["alphaCutoff"] = 0.5
            mat["doubleSided"] = True
        gltf_materials.append(mat)

    gltf_primitives = []
    for tex_idx, verts_list in sorted(prim_buckets.items()):
        uniq_map: Dict[Tuple, int] = {}
        uniq_verts = []
        indices = []
        for pos_v, nrm_v, uv_v in verts_list:
            key = (round(float(pos_v[0]), 5), round(float(pos_v[1]), 5), round(float(pos_v[2]), 5), round(float(nrm_v[0]), 4), round(float(nrm_v[1]), 4), round(float(nrm_v[2]), 4), round(float(uv_v[0]), 5), round(float(uv_v[1]), 5))
            idx = uniq_map.get(key)
            if idx is None:
                idx = len(uniq_verts)
                uniq_map[key] = idx
                uniq_verts.append((pos_v, nrm_v, uv_v))
            indices.append(idx)
        n_v = len(uniq_verts)
        pos_arr = np.array([x[0] for x in uniq_verts], dtype="<f4")
        nrm_arr = np.array([x[1] for x in uniq_verts], dtype="<f4")
        uv_arr = np.array([x[2] for x in uniq_verts], dtype="<f4")
        idx_arr = np.array(indices, dtype="<u2")
        acc_pos = add_accessor(append_bytes(pos_arr.tobytes(), 34962), 5126, n_v, "VEC3", pos_arr)
        acc_nrm = add_accessor(append_bytes(nrm_arr.tobytes(), 34962), 5126, n_v, "VEC3")
        acc_uv = add_accessor(append_bytes(uv_arr.tobytes(), 34962), 5126, n_v, "VEC2")
        acc_idx = add_accessor(append_bytes(idx_arr.tobytes(), 34963), 5123, len(indices), "SCALAR")
        gltf_primitives.append({"attributes": {"POSITION": acc_pos, "NORMAL": acc_nrm, "TEXCOORD_0": acc_uv}, "indices": acc_idx, "material": tex_idx, "mode": 4})

    while len(bin_chunks) % 4 != 0:
        bin_chunks.append(0)
    stem_name = os.path.splitext(os.path.basename(mdl_path))[0]
    gltf_json = {
        "asset": {"version": "2.0", "generator": "CS15-Godot-Extractor"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": stem_name, "mesh": 0}],
        "meshes": [{"name": stem_name, "primitives": gltf_primitives}],
        "materials": gltf_materials,
        "textures": gltf_textures,
        "images": gltf_images,
        "samplers": gltf_samplers,
        "accessors": accessors,
        "bufferViews": buffer_views,
        "buffers": [{"byteLength": len(bin_chunks)}],
    }
    json_bytes = json.dumps(gltf_json, separators=(",", ":")).encode("utf-8")
    while len(json_bytes) % 4 != 0:
        json_bytes += b" "
    total_len = 12 + 8 + len(json_bytes) + 8 + len(bin_chunks)
    os.makedirs(os.path.dirname(out_glb_path), exist_ok=True)
    with open(out_glb_path, "wb") as out:
        out.write(struct.pack("<III", 0x46546C67, 2, total_len))
        out.write(struct.pack("<II", len(json_bytes), 0x4E4F534A))
        out.write(json_bytes)
        out.write(struct.pack("<II", len(bin_chunks), 0x004E4942))
        out.write(bin_chunks)
    return {"sequences": [], "hitboxes": [], "bones": 0}


def run_models_extraction(cstrike_dir: str, out_models_dir: str, out_data_dir: str) -> None:
    models_src = os.path.join(cstrike_dir, "models")
    models_meta = {}
    converted = 0

    # 1. Weapon viewmodels (v_*), worldmodels (w_*), third-person weapon models (p_*) & shells
    for mp in sorted(glob.glob(os.path.join(models_src, "*.[mM][dD][lL]"))):
        stem = os.path.splitext(os.path.basename(mp))[0].lower()
        # Skip external companion T.mdl and IDSQ hostage01..08.mdl
        if stem.endswith("t") and stem in ("oranget", "arcticoranget"):
            continue
        if stem.startswith("hostage0") or stem == "p_shield":
            continue

        if stem.startswith("p_"):
            out_glb = os.path.join(out_models_dir, "weapons", f"{stem}.glb")
            info = convert_p_weapon_to_hand_glb(mp, out_glb)
            if info:
                models_meta[f"weapons/{stem}"] = info
                converted += 1
            continue

        if stem.startswith("v_"):
            kind = "viewmodel"
            sub = "weapons"
        elif stem.startswith("w_") or stem in ("pshell", "rshell", "rshell_big"):
            kind = "prop"
            sub = "weapons"
        elif stem in ("hostage", "scientist"):
            kind = "player"
            sub = "players"
        else:
            kind = "prop"
            sub = "props"

        out_glb = os.path.join(out_models_dir, sub, f"{stem}.glb")
        info = convert_mdl_to_glb(mp, out_glb, model_kind=kind)
        if info:
            models_meta[f"{sub}/{stem}"] = info
            converted += 1

    # 2. All 9 Player character models (models/player/<cls>/<cls>.mdl)
    for cls_dir in sorted(glob.glob(os.path.join(models_src, "player", "*"))):
        if not os.path.isdir(cls_dir):
            continue
        cls_name = os.path.basename(cls_dir).lower()
        mp_cands = glob.glob(os.path.join(cls_dir, "*.[mM][dD][lL]"))
        mp = next((c for c in mp_cands if os.path.splitext(os.path.basename(c))[0].lower() == cls_name), None)
        if not mp and mp_cands:
            mp = mp_cands[0]
        if not mp:
            continue
        out_glb = os.path.join(out_models_dir, "players", f"{cls_name}.glb")
        info = convert_mdl_to_glb(mp, out_glb, model_kind="player")
        if info:
            models_meta[f"players/{cls_name}"] = info
            converted += 1

    with open(os.path.join(out_data_dir, "models_meta.json"), "w", encoding="utf-8") as f:
        json.dump(models_meta, f, indent=2)

    print(f"[mdl_converter] Converted {converted} StudioMDL v10 models (.mdl -> skinned animated .glb)")
