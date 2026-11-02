"""Compiled Source MDL v49 (+ .vvd/.vtx/.ani) reader built on SourceIO's library parsers.

SourceIO (https://github.com/REDxEYE/SourceIO, MIT) is used only as a build-time dependency:
put a checkout on PYTHONPATH as a package named ``SourceIO`` (see tools/source/README.md).

load_model(path) -> dict with
    bones:      [(name, parent, pos3, quat_xyzw)]            (Source units, parent space)
    meshes:     [{material, pos(N,3), nrm(N,3), uv(N,2), bones(N,3), weights(N,3), idx(M,3)}]
                bodygroup default sub-model only, model space, Source winding
    materials:  [name]       cdmaterials: [dir]
    sequences:  [{name, anims:[anim index], events:[(cycle, event, options, name, type)], flags}]
    anims:      {index: {name, fps, frames(F, B) ANIM_DTYPE}}   (pos/rot per bone, parent space)
    attachments:[(name, bone, matrix3x4)]
    includes:   [paths]
"""
import os

import numpy as np

from SourceIO.library.models.mdl.structs.ani_file import AniFile, read_anim_block_table
from SourceIO.library.models.mdl.v49.mdl_file import MdlV49
from SourceIO.library.models.vtx.v7.vtx import Vtx
from SourceIO.library.models.vvd import Vvd
from SourceIO.library.utils import FileBuffer
from SourceIO.library.models.mdl.structs import local_animation as _la
from SourceIO.library.models.mdl.structs.compressed_vectors import Quat48, Quat48S
from SourceIO.library.models.mdl.structs.frame_anim import StudioFrameAnim

_F = _la.AniBoneFlags


def _read_frame_animations(self, buffer, bones, section_frame_count):
    """CS:GO STUDIO_FRAMEANIM decoder handling constants + per-frame data together
    (upstream SourceIO asserts they never co-exist, which CS:GO weapon anims violate)."""
    entry = buffer.tell()
    fa = StudioFrameAnim.from_buffer(buffer)
    flags = [buffer.read_uint8() for _ in bones]
    data = {}
    if fa.constant_offset > 0:
        buffer.seek(entry + fa.constant_offset)
        for bone in bones:
            f = flags[bone.bone_id]
            if not f & (_F.CONST_ROT2 | _F.RAW_ROT | _F.RAW_POS | _F.CONST_POS2):
                continue
            arr = data.setdefault(bone.name, _bind_frames(bone, section_frame_count))
            if f & _F.CONST_ROT2:
                arr["rot"][:] = Quat48S.read(buffer)
            if f & _F.RAW_ROT:
                arr["rot"][:] = Quat48.read(buffer)
            if f & _F.RAW_POS:
                arr["pos"][:] = buffer.read_fmt("3e")
            if f & _F.CONST_POS2:
                arr["pos"][:] = buffer.read_fmt("3f")
    if fa.frame_offset > 0 and fa.frame_length > 0:
        for fi in range(section_frame_count):
            buffer.seek(entry + fa.frame_offset + fi * fa.frame_length)
            for bone in bones:
                f = flags[bone.bone_id]
                if not f & (_F.ANIM_ROT2 | _F.ANIM_ROT | _F.ANIM_POS | _F.FULL_ANIM_POS):
                    continue
                arr = data.setdefault(bone.name, _bind_frames(bone, section_frame_count))
                if f & _F.ANIM_ROT2:
                    arr["rot"][fi] = Quat48S.read(buffer)
                if f & _F.ANIM_ROT:
                    arr["rot"][fi] = Quat48.read(buffer)
                if f & _F.ANIM_POS:
                    arr["pos"][fi] = buffer.read_fmt("3e")
                if f & _F.FULL_ANIM_POS:
                    arr["pos"][fi] = buffer.read_fmt("3f")
    return data


def _bind_frames(bone, n):
    arr = np.zeros((n,), _la.ANIM_DTYPE)
    arr["pos"][:] = bone.position
    arr["rot"][:] = bone.quat
    return arr


_la.StudioAnimDesc._read_frame_animations = _read_frame_animations


def _merge_strip_groups(vtx_mesh):
    idx, verts, off = [], [], 0
    for sg in vtx_mesh.strip_groups:
        idx.append(np.add(sg.indices, off))
        verts.append(sg.vertexes["original_mesh_vertex_index"].reshape(-1).astype(np.uint32))
        off += sum(s.vertex_count for s in sg.strips)
    return np.hstack(idx), np.hstack(verts), off


def _read_anims(mdl, buf, path):
    ani = None
    ani_path = os.path.splitext(path)[0] + ".ani"
    if os.path.exists(ani_path):
        ani = AniFile.from_buffer(FileBuffer(ani_path)).buffer
    table = read_anim_block_table(buf, getattr(mdl.header, "anim_block_offset", 0),
                                  getattr(mdl.header, "anim_block_count", 0))
    out = {}
    for i, ad in enumerate(mdl.anim_descs):
        try:
            frames = ad.read_animations(buf, mdl.bones, ani, table)
        except Exception as ex:  # noqa: BLE001
            print("  anim %s failed: %s" % (ad.name, ex))
            continue
        if not frames:  # data lives in a stock CS:GO .ani that is not shipped
            continue
        F = max(int(ad.frame_count), 1)
        arr = np.zeros((F, len(mdl.bones)), dtype=[("pos", np.float32, (3,)), ("rot", np.float32, (4,))])
        names = [b.name for b in mdl.bones]
        for bi, b in enumerate(mdl.bones):
            arr["pos"][:, bi] = b.position
            arr["rot"][:, bi] = b.quat
        for bname, data in dict(frames).items():
            if bname in names:
                bi = names.index(bname)
                n = min(F, len(data))
                arr["pos"][:n, bi] = data["pos"][:n]
                arr["rot"][:n, bi] = data["rot"][:n]
        out[i] = {"name": ad.name, "fps": float(ad.fps), "frames": arr, "flags": int(ad.flags)}
    return out


def load_model(path, want_mesh=True):
    buf = FileBuffer(path)
    mdl = MdlV49.from_buffer(buf)
    res = {"name": mdl.header.name, "bones": [], "meshes": [], "materials": [m.name for m in mdl.materials],
           "cdmaterials": list(mdl.materials_paths), "sequences": [], "attachments": [],
           "includes": list(mdl.include_models), "mdl": mdl}
    for b in mdl.bones:
        res["bones"].append((b.name, b.parent_id, np.array(b.position, float), np.array(b.quat, float)))
    for a in mdl.attachments:
        res["attachments"].append((a.name, a.parent_bone, np.array(a.matrix, float).reshape(3, 4)))
    for s in mdl.sequences:
        # In v49 named client events (silencer, brass, reload-complete) have event=0 and
        # type=1024; their actual identifier is in ``name``. Sound events remain event=5004.
        evs = [(float(e.cycle), int(e.event), str(e.options), str(e.name), int(e.type)) for e in s.events]
        res["sequences"].append({"name": s.name, "label": getattr(s, "label", s.name),
                                 "anims": [int(x) for x in np.array(s.anim_desc_indices).reshape(-1)],
                                 "events": evs, "flags": int(s.flags), "activity": getattr(s, "activity_name", ""),
                                 "seq": s})
    res["anims"] = _read_anims(mdl, buf, path)
    if want_mesh and os.path.exists(os.path.splitext(path)[0] + ".vvd"):
        vvd = Vvd.from_buffer(FileBuffer(os.path.splitext(path)[0] + ".vvd"))
        vtx_path = os.path.splitext(path)[0] + ".dx90.vtx"
        if not os.path.exists(vtx_path):
            vtx_path = os.path.splitext(path)[0] + ".vtx"
        vtx = Vtx.from_buffer(FileBuffer(vtx_path))
        allv = vvd.lod_data[0]
        for vbp, bp in zip(vtx.body_parts, mdl.body_parts):
            for k, (vm, m) in enumerate(zip(vbp.models, bp.models)):
                if k > 0 or m.vertex_count == 0:  # default sub-model of each bodygroup only
                    continue
                mv = allv[m.vertex_offset:m.vertex_offset + m.vertex_count]
                for vmesh, mesh in zip(vm.model_lods[0].meshes, m.meshes):
                    if not vmesh.strip_groups:
                        continue
                    idx, verts, _ = _merge_strip_groups(vmesh)
                    v = mv[verts.astype(np.int64) + mesh.vertex_index_start]
                    res["meshes"].append({
                        "material": res["materials"][mesh.material_index] if mesh.material_index < len(
                            res["materials"]) else "mat%d" % mesh.material_index,
                        "bodypart": bp.name, "model": m.name,
                        "pos": np.array(v["vertex"], float), "nrm": np.array(v["normal"], float),
                        "uv": np.array(v["uv"], float), "bones": np.array(v["bone_id"], int),
                        "weights": np.array(v["weight"], float), "idx": np.array(idx, np.int64).reshape(-1, 3)})
    return res
