#!/usr/bin/env python3
"""Offline surface correspondence for the current Archi weapon UV atlases.

The curated CS:GO Ports/BDS finishes are already-baked legacy albedos. Fifteen
weapon families have a different current HD unwrap. This module samples that
artwork through nearest legacy surface points and barycentric UV interpolation;
it never edits a runtime mesh, UV, rig or animation. It is not Valve's compositor.

Geometry reference: zh667/ScCsgoKnives, pinned by build_weapon_skins.py. Its
NWM1 pairs share an idle world space and their current UVs were compared with
the installed Archi GLBs. Five families without a distinct legacy body keep the
original PNG bytes and do not enter this module.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import struct
import tempfile
from pathlib import Path

import numpy as np
import trimesh
from PIL import Image
from scipy.ndimage import binary_dilation, distance_transform_edt, map_coordinates

from .glb_read import acc, load as load_glb

ALGORITHM = "nwm1-nearest-surface-v5"
MESH_DIRECTORY = Path("src/ScCsgoTactical/Assets/Models/ScCsgoTactical/Weapons")
ASSETS = {
    "ak47": "ak47",
    "aug": "aug",
    "awp": "awp",
    "deagle": "deagle",
    "famas": "famas",
    "fiveseven": "fiveseven",
    "galil": "galilar",
    "glock18": "glock18",
    "m249": "m249",
    "m4a1": "m4a1s",
    "mac10": "mac10",
    "m3": "nova",
    "p90": "p90",
    "sg550": "scar20",
    "usp": "usp_silencer",
}


class _Reader:
    def __init__(self, data: bytes):
        self.data = data
        self.offset = 0

    def take(self, count: int) -> bytes:
        result = self.data[self.offset:self.offset + count]
        if len(result) != count:
            raise ValueError("Truncated NWM1 mesh")
        self.offset += count
        return result

    def values(self, fmt: str):
        return struct.unpack("<" + fmt, self.take(struct.calcsize("<" + fmt)))

    def text(self) -> str:
        length = self.values("i")[0]
        if not 0 <= length <= 256:
            raise ValueError("Invalid NWM1 text length")
        return self.take(length).decode("utf-8")

    def matrix(self) -> np.ndarray:
        return np.asarray(self.values("16f"), dtype=np.float64).reshape(4, 4)


def _read_nwm1(path: Path) -> dict:
    reader = _Reader(path.read_bytes())
    if reader.values("i")[0] != 0x314D574E:
        raise ValueError("Not an NWM1 weapon mesh: " + str(path))
    asset = reader.text()
    legacy = reader.values("?")[0]
    reader.values("?")  # right-grip metadata is irrelevant to the atlas
    reader.matrix()
    groups = []
    for _ in range(reader.values("i")[0]):
        texture = reader.text()
        reader.values("?")  # silencer visibility is preserved by the game rig
        bone = reader.text()
        reader.matrix()
        reader.text()
        reader.matrix()
        vertex_count, index_count = reader.values("ii")
        raw = np.frombuffer(reader.take(vertex_count * 26), dtype=np.uint8).reshape(vertex_count, 26).copy()
        positions = raw[:, :12].copy().view("<f4").reshape(-1, 3).astype(np.float64)
        uvs = raw[:, 12:20].copy().view("<f4").reshape(-1, 2).astype(np.float64)
        indices = np.asarray(reader.values(str(index_count) + "i"), dtype=np.int32).reshape(-1, 3)
        groups.append({"texture": texture, "bone": bone, "positions": positions,
                       "uvs": uvs, "indices": indices})
    if reader.offset != len(reader.data):
        raise ValueError("Trailing NWM1 data: " + str(path))
    return {"asset": asset, "legacy": legacy, "groups": groups}


def _bone_name(name: str) -> str:
    name = name.lstrip("@")
    name = re.sub(r"__[pc]\d+$", "", name)
    return re.sub(r"^(strap[1-6])_hd$", r"\1", name)


def _surface(document: dict, asset: str) -> dict:
    positions, uvs, faces, bones = [], [], [], []
    vertex_offset = 0
    expected = asset + "_hd"
    for group in document["groups"]:
        if group["texture"] != expected:
            continue
        count = len(group["positions"])
        positions.append(group["positions"])
        uvs.append(group["uvs"])
        faces.append(group["indices"] + vertex_offset)
        bones.extend([_bone_name(group["bone"])] * len(group["indices"]))
        vertex_offset += count
    if not faces:
        raise ValueError("No painted weapon surface in " + document["asset"])
    return {"positions": np.concatenate(positions), "uvs": np.concatenate(uvs),
            "faces": np.concatenate(faces), "bones": np.asarray(bones)}


def _tile_shifts(triangle_uv: np.ndarray, axis: int) -> range:
    # Include every repeat that intersects the unit atlas. Several current HD
    # parts deliberately tile beyond 1.0; clipping only the unshifted triangle
    # would leave those islands empty.
    low = int(np.ceil(-triangle_uv[:, axis].max() - 1e-7))
    high = int(np.floor(1.0 - triangle_uv[:, axis].min() + 1e-7))
    return range(low, high + 1)


def _raster_surface(surface: dict, size: int, face_selection: np.ndarray | None = None):
    positions = np.zeros((size, size, 3), dtype=np.float32)
    face_ids = np.full((size, size), -1, dtype=np.int32)
    faces = surface["faces"] if face_selection is None else surface["faces"][face_selection]
    for face_index, triangle in enumerate(faces):
        original_face_index = face_index if face_selection is None else int(face_selection[face_index])
        original_uv = surface["uvs"][triangle]
        for shift_u in _tile_shifts(original_uv, 0):
            for shift_v in _tile_shifts(original_uv, 1):
                uv = (original_uv + (shift_u, shift_v)) * size - 0.5
                lower = np.maximum(np.ceil(uv.min(axis=0)).astype(int), 0)
                upper = np.minimum(np.floor(uv.max(axis=0)).astype(int), size - 1)
                if np.any(lower > upper):
                    continue
                a, b, c = uv
                determinant = ((b[0] - a[0]) * (c[1] - a[1])
                               - (b[1] - a[1]) * (c[0] - a[0]))
                if abs(determinant) < 1e-9:
                    continue
                xx, yy = np.meshgrid(np.arange(lower[0], upper[0] + 1),
                                     np.arange(lower[1], upper[1] + 1))
                weight1 = ((xx - a[0]) * (c[1] - a[1])
                           - (yy - a[1]) * (c[0] - a[0])) / determinant
                weight2 = ((b[0] - a[0]) * (yy - a[1])
                           - (b[1] - a[1]) * (xx - a[0])) / determinant
                weight0 = 1.0 - weight1 - weight2
                inside = (weight0 >= -1e-7) & (weight1 >= -1e-7) & (weight2 >= -1e-7)
                y, x = yy[inside], xx[inside]
                weights = np.stack([weight0[inside], weight1[inside], weight2[inside]], axis=-1)
                positions[y, x] = weights @ surface["positions"][triangle]
                face_ids[y, x] = original_face_index
    return positions, face_ids


def _project_uv(source: dict, face_selection: np.ndarray, points: np.ndarray):
    mesh = trimesh.Trimesh(vertices=source["positions"],
                           faces=source["faces"][face_selection], process=False)
    result_uv = np.zeros((len(points), 2), dtype=np.float32)
    result_distance = np.zeros(len(points), dtype=np.float32)
    for start in range(0, len(points), 4096):
        part = slice(start, min(start + 4096, len(points)))
        closest, distance, face = trimesh.proximity.closest_point(mesh, points[part])
        barycentric = trimesh.triangles.points_to_barycentric(mesh.triangles[face], closest)
        result_uv[part] = np.einsum("ni,nij->nj", barycentric,
                                    source["uvs"][mesh.faces[face]])
        result_distance[part] = distance
    return result_uv, result_distance


def _calculate_correspondence(current_path: Path, legacy_path: Path, asset: str, size: int):
    current_document = _read_nwm1(current_path)
    legacy_document = _read_nwm1(legacy_path)
    if current_document["legacy"] or not legacy_document["legacy"]:
        raise ValueError("Current/legacy NWM1 identities are reversed for " + asset)
    current = _surface(current_document, asset)
    legacy = _surface(legacy_document, asset)
    source_bones = set(legacy["bones"])
    target_face_transfer = np.asarray([
        not ((bone.startswith("bullet") or bone == "shell") and bone not in source_bones)
        for bone in current["bones"]
    ])

    # Hardware-only faces must not overwrite the transferable body islands.
    # Their own GLB mask is applied later; excluding them here keeps Nova's
    # shell UVs from replacing the receiver/pump correspondence.
    positions, face_ids = _raster_surface(current, size, np.flatnonzero(target_face_transfer))
    covered = face_ids >= 0
    safe_ids = np.maximum(face_ids, 0)
    mapped_uv = np.zeros((size, size, 2), dtype=np.float32)
    distances = np.full((size, size), np.nan, dtype=np.float32)
    report = {}
    for bone in sorted(set(current["bones"])):
        target = covered & (current["bones"][safe_ids] == bone) & target_face_transfer[safe_ids]
        yy, xx = np.where(target)
        if not len(xx):
            continue
        selection = np.flatnonzero(legacy["bones"] == bone)
        mode = "same-bone"
        if not len(selection):
            selection = np.arange(len(legacy["faces"]))
            mode = "global-unmatched-bone"
        points = positions[yy, xx]
        # A matched bone is a hard semantic boundary. A globally closer triangle
        # can belong to the magazine or receiver and was measurably worse on the
        # independent AK/Vulcan HD reference, even when its distance was smaller.
        local_uv, local_distance = _project_uv(legacy, selection, points)
        mapped_uv[yy, xx] = local_uv
        distances[yy, xx] = local_distance
        report[bone] = {
            "mode": mode,
            "samples": len(xx),
            "global_replacements": 0,
            "distance_quantiles": [float(v) for v in np.quantile(local_distance, [0, .5, .9, .99, 1])],
        }

    # Fill only unused texels from their nearest covered texel. This prevents
    # black atlas backgrounds from bleeding into filtered island gutters.
    nearest = distance_transform_edt(~covered, return_distances=False, return_indices=True)
    mapped_uv = mapped_uv[tuple(nearest)]
    transfer = target_face_transfer[safe_ids]
    transfer[~covered] = False
    transfer = transfer[tuple(nearest)]
    return {"uv": mapped_uv, "covered": covered, "distance": distances,
            "position": positions, "transfer": transfer, "report": report}


def _cache_directory() -> Path:
    configured = os.environ.get("ARCHI_SKIN_UV_CACHE")
    return Path(configured) if configured else Path(tempfile.gettempdir()) / "archi-weapon-skin-uv-cache"


def correspondence(mesh_source: Path, asset: str, size: int = 512) -> dict:
    current_path = mesh_source / MESH_DIRECTORY / (asset + ".scmesh")
    legacy_path = mesh_source / MESH_DIRECTORY / (asset + "-legacy.scmesh")
    for path in (current_path, legacy_path):
        if not path.is_file():
            raise FileNotFoundError("Missing current/legacy UV reference: " + str(path))
    current_hash = hashlib.sha256(current_path.read_bytes()).hexdigest()
    legacy_hash = hashlib.sha256(legacy_path.read_bytes()).hexdigest()
    key = hashlib.sha256((ALGORITHM + str(size) + current_hash + legacy_hash).encode("ascii")).hexdigest()[:24]
    cache = _cache_directory()
    cache.mkdir(parents=True, exist_ok=True)
    path = cache / (asset + "-" + key + ".npz")
    if path.is_file():
        with np.load(path, allow_pickle=False) as data:
            result = {name: data[name] for name in ("uv", "covered", "distance", "position", "transfer")}
            result["report"] = json.loads(str(data["report_json"].item()))
    else:
        result = _calculate_correspondence(current_path, legacy_path, asset, size)
        temporary = path.with_suffix(".tmp.npz")
        np.savez_compressed(temporary, uv=result["uv"], covered=result["covered"],
                            distance=result["distance"], position=result["position"],
                            transfer=result["transfer"],
                            report_json=np.asarray(json.dumps(result["report"], sort_keys=True)))
        os.replace(temporary, path)
    result["mesh_hashes"] = {"current": current_hash, "legacy": legacy_hash}
    return result


def sample_rgb(image: np.ndarray, uv: np.ndarray) -> np.ndarray:
    height, width = image.shape[:2]
    coordinates = [uv[..., 1] * height - 0.5, uv[..., 0] * width - 0.5]
    return np.stack([map_coordinates(image[..., channel], coordinates, order=1,
                                    mode="grid-wrap") for channel in range(3)], axis=-1)


def hardware_mask(glb_path: Path, material_names: list[str], size: int = 512):
    """Keep separately-authored bullet/shell surfaces on Original HD.

    Most such regions are already identified by the NWM1 material pair. This
    additional mask is measured on the installed Archi GLB, covering Nova's
    distinct shell islands and every M249 belt round, including their mip gutters.
    """
    js, binary = load_glb(glb_path)
    if not js.get("skins"):
        return np.zeros((size, size), dtype=bool), []
    joint_nodes = js["skins"][0]["joints"]
    joint_names = [js["nodes"][node].get("name", "").lower() for node in joint_nodes]
    hardware_joints = {index for index, name in enumerate(joint_names)
                       if "bullet" in name or "shell" in name}
    if not hardware_joints:
        return np.zeros((size, size), dtype=bool), []
    materials = set(material_names)
    mask = np.zeros((size, size), dtype=bool)
    used_names = set()
    for mesh in js.get("meshes", []):
        for primitive in mesh["primitives"]:
            if js["materials"][primitive["material"]].get("name", "") not in materials:
                continue
            attributes = primitive["attributes"]
            required = {"TEXCOORD_0", "JOINTS_0", "WEIGHTS_0"}
            if not required.issubset(attributes):
                continue
            uv = acc(js, binary, attributes["TEXCOORD_0"])
            joints = acc(js, binary, attributes["JOINTS_0"])
            weights = acc(js, binary, attributes["WEIGHTS_0"])
            dominant = joints[np.arange(len(joints)), weights.argmax(axis=1)]
            indices = acc(js, binary, primitive["indices"]).reshape(-1, 3)
            for triangle in indices:
                owners = dominant[triangle]
                if not all(int(owner) in hardware_joints for owner in owners):
                    continue
                used_names.update(joint_names[int(owner)] for owner in owners)
                original_uv = uv[triangle]
                for shift_u in _tile_shifts(original_uv, 0):
                    for shift_v in _tile_shifts(original_uv, 1):
                        coords = (original_uv + (shift_u, shift_v)) * size - 0.5
                        lower = np.maximum(np.ceil(coords.min(axis=0)).astype(int), 0)
                        upper = np.minimum(np.floor(coords.max(axis=0)).astype(int), size - 1)
                        if np.any(lower > upper):
                            continue
                        a, b, c = coords
                        determinant = ((b[0] - a[0]) * (c[1] - a[1])
                                       - (b[1] - a[1]) * (c[0] - a[0]))
                        if abs(determinant) < 1e-9:
                            continue
                        xx, yy = np.meshgrid(np.arange(lower[0], upper[0] + 1),
                                             np.arange(lower[1], upper[1] + 1))
                        w1 = ((xx - a[0]) * (c[1] - a[1])
                              - (yy - a[1]) * (c[0] - a[0])) / determinant
                        w2 = ((b[0] - a[0]) * (yy - a[1])
                              - (b[1] - a[1]) * (xx - a[0])) / determinant
                        w0 = 1.0 - w1 - w2
                        inside = (w0 >= -1e-7) & (w1 >= -1e-7) & (w2 >= -1e-7)
                        mask[yy[inside], xx[inside]] = True
    return binary_dilation(mask, iterations=2), sorted(used_names)


def reproject(source: Image.Image, default: Image.Image, mapping: dict,
              preserve: np.ndarray | None = None) -> Image.Image:
    source_rgb = np.asarray(source.convert("RGB"), dtype=np.float32) / 255.0
    default_rgb = np.asarray(default.convert("RGB").resize(source.size, Image.Resampling.LANCZOS),
                             dtype=np.float32) / 255.0
    artwork = sample_rgb(source_rgb, mapping["uv"])
    transfer = mapping["transfer"].copy()
    if preserve is not None:
        transfer &= ~preserve
    result = artwork * transfer[..., None] + default_rgb * (1.0 - transfer[..., None])
    return Image.fromarray(np.uint8(np.clip(result * 255.0 + 0.5, 0, 255)), "RGB")
