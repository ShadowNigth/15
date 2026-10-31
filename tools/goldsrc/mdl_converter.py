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
    "crouch_idle",
    "walk",
    "run",
    "crouchrun",
    "jump",
    "ref_aim_ak47",
    "ref_shoot_ak47",
    "ref_reload_ak47",
    "ref_aim_carbine",
    "ref_shoot_carbine",
    "ref_aim_onehanded",
    "ref_shoot_onehanded",
    "ref_aim_knife",
    "ref_shoot_knife",
    "ref_aim_c4",
    "crouch_aim_ak47",
    "crouch_shoot_ak47",
    "crouch_aim_carbine",
    "crouch_shoot_carbine",
    "die_simple",
    "die_backwards",
    "die_forwards",
    "head",
    "gutshot",
)


def should_include_seq(model_kind: str, seq_name: str, seq_idx: int) -> bool:
    lname = seq_name.lower()
    if model_kind == "viewmodel":
        return True
    if model_kind == "prop":
        return seq_idx == 0
    # Player / hostage: keep essential gameplay animations compact
    if seq_idx <= 8:
        return True
    return lname in PLAYER_ANIM_KEYWORDS


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
    animations_data = []
    exported_seq_names = []
    seen_names = set()
    for si in range(numseq):
        sofs = seqindex + si * 176
        sname = d[sofs : sofs + 32].split(b"\x00")[0].decode("latin1", errors="ignore").strip() or f"seq_{si}"
        if not should_include_seq(model_kind, sname, si):
            continue
        if sname in seen_names:
            sname = f"{sname}_{si}"
        seen_names.add(sname)

        fps = struct.unpack_from("<f", d, sofs + 32)[0]
        if fps <= 0.1:
            fps = 24.0
        numframes = max(1, struct.unpack_from("<i", d, sofs + 56)[0])
        animindex = struct.unpack_from("<i", d, sofs + 124)[0]
        seqgroup = struct.unpack_from("<i", d, sofs + 168)[0]
        if seqgroup not in seqgroup_buffers:
            continue
        abuf, abase = seqgroup_buffers[seqgroup]
        anim_table_ofs = abase + animindex
        if anim_table_ofs + numbones * 12 > len(abuf):
            continue

        # Subsample long sequences gently to keep GLBs lightweight
        step = 1
        if model_kind == "viewmodel" and numframes > 28:
            step = 2
        elif model_kind != "viewmodel" and numframes > 20:
            step = max(2, numframes // 16)
        sample_frames = list(range(0, numframes, step))
        if sample_frames[-1] != numframes - 1:
            sample_frames.append(numframes - 1)
        times = np.array([f / fps for f in sample_frames], dtype=np.float32)

        bone_tracks = []
        for bi, b in enumerate(bones):
            b_anim_ofs = anim_table_ofs + bi * 12
            offsets = struct.unpack_from("<6H", abuf, b_anim_ofs)
            # Only emit tracks for bones that move or root bone
            is_animated = any(o != 0 for o in offsets)
            if not is_animated and bi > 0 and len(sample_frames) > 1:
                continue

            ts = np.zeros((len(sample_frames), 3), dtype=np.float32)
            qs = np.zeros((len(sample_frames), 4), dtype=np.float32)
            prev_q = None
            for idx_f, f in enumerate(sample_frames):
                dof = list(b["vals"])
                for j in range(6):
                    if offsets[j] != 0:
                        raw_v = eval_rle_anim_value(abuf, b_anim_ofs + offsets[j], f)
                        dof[j] += raw_v * b["scls"][j]
                t_gd = gs_pos_to_gd(np.array(dof[:3], dtype=np.float32))
                q_gd = gs_quat_to_gd(angle_quaternion_gs(dof[3], dof[4], dof[5]))
                norm_q = float(np.linalg.norm(q_gd))
                if norm_q > 1e-6:
                    q_gd = q_gd / norm_q
                # Hemisphere continuity so slerp never flips 360 deg
                if prev_q is not None and float(np.dot(prev_q, q_gd)) < 0.0:
                    q_gd = -q_gd
                prev_q = q_gd
                ts[idx_f] = t_gd
                qs[idx_f] = q_gd

            bone_tracks.append((bi, ts, qs))

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

    # Animations
    gltf_animations = []
    for sname, times, bone_tracks in animations_data:
        acc_time = add_accessor(append_bytes(times.astype("<f4").tobytes()), 5126, len(times), "SCALAR", times[:, None])
        # Fix SCALAR min/max to 1D list per glTF 2.0 spec
        accessors[acc_time]["min"] = [float(times[0])]
        accessors[acc_time]["max"] = [float(times[-1])]

        samplers = []
        channels = []
        for bi, ts, qs in bone_tracks:
            node_idx = 1 + bi
            acc_t = add_accessor(append_bytes(ts.astype("<f4").tobytes()), 5126, len(times), "VEC3")
            s_t = len(samplers)
            samplers.append({"input": acc_time, "interpolation": "LINEAR", "output": acc_t})
            channels.append({"sampler": s_t, "target": {"node": node_idx, "path": "translation"}})

            acc_q = add_accessor(append_bytes(qs.astype("<f4").tobytes()), 5126, len(times), "VEC4")
            s_q = len(samplers)
            samplers.append({"input": acc_time, "interpolation": "LINEAR", "output": acc_q})
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

    return {"sequences": exported_seq_names, "hitboxes": hitboxes, "bones": len(bones)}


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
        if stem.startswith("hostage0") or stem.startswith("p_"):
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
