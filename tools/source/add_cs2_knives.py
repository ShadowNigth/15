#!/usr/bin/env python3
"""Add three fixed-blade CS2 knives without changing the installed arms/animations.

Usage: PYTHONPATH=<numpy+pillow> python -m tools.source.add_cs2_knives SOURCE_ROOT
SOURCE_ROOT is a checkout/cache of zh667/ScCsgoKnives at SOURCE_COMMIT.
Only the named .skin/.animation.json and finish PNGs are required. The JSON idle
pose is used to recover the source grip, NOT imported as a replacement animation.
The original nine archi knife clips, skin binds, arms, glove surfaces and Sport
Gloves remain byte-identical. No Survivalcraft C# runtime is incorporated.
"""
import copy
import hashlib
import json
import struct
import sys
from pathlib import Path

import numpy as np

from .build_sport_gloves import _accessor
from .refine_weapon_animations import read_glb, write_glb
from .smd import trs

ROOT = Path(__file__).resolve().parents[2]
SOURCE_COMMIT = "1eb8067fd0b7214df5bccf3ac3807fbaa3aee70d"
CHOICES = [
    ("karambit", "Karambit | Gamma Doppler Phase 4", "am_gamma_doppler_phase4"),
    ("m9", "M9 Bayonet | Gamma Doppler Phase 1", "am_gamma_doppler_phase1"),
    ("bayonet", "Bayonet | Ruby", "am_ruby_marbleized"),
]


def read_skin(path):
    raw = path.read_bytes()
    offset = 0

    def take(fmt):
        nonlocal offset
        result = struct.unpack_from("<" + fmt, raw, offset)
        offset += struct.calcsize("<" + fmt)
        return result

    def text():
        nonlocal offset
        length = take("H")[0]
        result = raw[offset:offset + length].decode("utf-8")
        offset += length
        return result

    assert raw[:8] == b"SCK2SKIN", "Unsupported mesh signature"
    offset = 8
    assert take("I")[0] == 2, "Unsupported mesh version"
    joints, inverse = [], []
    for _ in range(take("H")[0]):
        joints.append(text())
        # Survivalcraft stores row-vector matrices; use column vectors here.
        inverse.append(np.array(take("16f")).reshape(4, 4).T)
    count = take("I")[0]
    dtype = np.dtype([("p", "<f4", 3), ("n", "<f4", 3), ("uv", "<f4", 2),
                      ("j", "u1", 4), ("w", "<f4", 4)])
    vertices = np.frombuffer(raw, dtype=dtype, count=count, offset=offset).copy()
    offset += count * 52
    primitives = []
    for _ in range(take("H")[0]):
        material = text()
        indices = np.array(take(str(take("I")[0]) + "I"), dtype=np.uint32)
        assert len(indices) % 3 == 0 and indices.max() < count
        primitives.append((material, indices))
    assert offset == len(raw)
    assert np.allclose(vertices["w"].sum(axis=1), 1.0, atol=1e-5)
    return vertices, joints, inverse, primitives


def matrices(nodes, overrides=None):
    parents = {child: parent for parent, node in enumerate(nodes)
               for child in node.get("children", [])}
    result = {}

    def get(index):
        if index not in result:
            node = dict(nodes[index])
            node.update((overrides or {}).get(index, {}))
            if "matrix" in node:
                local = np.array(node["matrix"]).reshape(4, 4).T
            else:
                local = trs(np.array(node.get("translation", [0, 0, 0])),
                            np.array(node.get("rotation", [0, 0, 0, 1])))
                local[:3, :3] *= np.array(node.get("scale", [1, 1, 1]))
            result[index] = get(parents[index]) @ local if index in parents else local
        return result[index]
    return [get(i) for i in range(len(nodes))]


def original_pose(document, binary, clip_name=None):
    overrides = {}
    if clip_name:
        clip = next(a for a in document["animations"] if a["name"] == clip_name)
        for channel in clip["channels"]:
            sampler = clip["samplers"][channel["sampler"]]
            value = _accessor(document, binary, sampler["output"])[0].tolist()
            overrides.setdefault(channel["target"]["node"], {})[channel["target"]["path"]] = value
    return matrices(document["nodes"], overrides)


def source_pose(animation):
    nodes = [{"name": b["Name"], "translation": b["Translation"],
              "rotation": b["Rotation"], "scale": b["Scale"],
              "children": b["Children"]} for b in animation["Skeleton"]]
    clip = next(c for c in animation["Clips"].values() if c["Alias"] == "idle")
    overrides = {}
    for i, node in enumerate(nodes):
        for path, track in clip["Bones"].get(node["name"], {}).items():
            if path in ("Rotation", "Translation", "Scale"):
                overrides.setdefault(i, {})[path.lower()] = track["Values"][0]
    return {node["name"]: matrix for node, matrix in zip(nodes, matrices(nodes, overrides))}


def append_view(document, binary, payload):
    binary.extend(b"\0" * (-len(binary) % 4))
    index = len(document["bufferViews"])
    document["bufferViews"].append({"buffer": 0, "byteOffset": len(binary), "byteLength": len(payload)})
    binary.extend(payload)
    return index


def append_array(document, binary, values, kind, component=5126):
    dtype = {5126: "<f4", 5125: "<u4", 5123: "<u2"}[component]
    array = np.asarray(values, dtype=dtype)
    accessor = {"bufferView": append_view(document, binary, array.tobytes()),
                "componentType": component, "count": len(array), "type": kind}
    if kind == "VEC3":
        accessor.update(min=array.min(0).astype(float).tolist(), max=array.max(0).astype(float).tolist())
    document["accessors"].append(accessor)
    return len(document["accessors"]) - 1


def install_material(document, binary, source, stem, key):
    textures = []
    for suffix in ("", "_normal", "_orm"):
        path = source / (stem + suffix + ".png")
        index = len(document.setdefault("images", []))
        document["images"].append({"bufferView": append_view(document, binary, path.read_bytes()), "mimeType": "image/png"})
        textures.append(len(document.setdefault("textures", [])))
        document["textures"].append({"source": index, "sampler": 0})
    document.setdefault("samplers", [{"magFilter": 9729, "minFilter": 9987}])
    index = len(document["materials"])
    document["materials"].append({"name": "sc_cs2_" + key,
        "pbrMetallicRoughness": {"baseColorTexture": {"index": textures[0]},
                                "metallicRoughnessTexture": {"index": textures[2]},
                                "metallicFactor": 0.68, "roughnessFactor": 0.65},
        "normalTexture": {"index": textures[1]}, "occlusionTexture": {"index": textures[2]}})
    return index


def main(source_root):
    source_root = Path(source_root)
    assets = source_root / "src/ScCsgoKnives"
    texture_root = assets / "Assets/Textures/ScCsgoKnives"
    original, original_binary = read_glb(str(ROOT / "assets/models/weapons/v_knife.glb"))
    names = {n["name"]: i for i, n in enumerate(original["nodes"])}
    bind = original_pose(original, original_binary)
    idle = original_pose(original, original_binary, "idle")
    hand_index, weapon_index = names["v_weapon.Bip01_R_Hand"], names["weapon_hand_r"]
    weapon_joint = original["skins"][0]["joints"].index(weapon_index)
    old_primitive = original["meshes"][0]["primitives"][0]
    old_positions = _accessor(original, original_binary, old_primitive["attributes"]["POSITION"])
    options = [{"id": "original", "name": "Original Kukri", "v_model": "v_knife", "p_model": "p_knife", "w_model": "w_knife"}]
    report = {"source_commit": SOURCE_COMMIT, "animation_policy": "preserve installed archi clips; source idle only calibrates grip", "knives": {}}
    for key, label, finish in CHOICES:
        path = assets / "AnimationData" / (key + ".cs2.skin")
        vertices, joints, inverse, primitives = read_skin(path)
        animation = json.loads((assets / "AnimationData" / (key + ".cs2.animation.json")).read_text())
        pose = source_pose(animation)
        for joint, name in enumerate(joints):
            assert name in pose or vertices["w"][vertices["j"] == joint].sum() == 0, "Unresolved weighted joint: " + name
        transforms = [pose.get(name, np.eye(4)) @ ib for name, ib in zip(joints, inverse)]
        points, normals = np.zeros((len(vertices), 3)), np.zeros((len(vertices), 3))
        homogeneous = np.column_stack((vertices["p"], np.ones(len(vertices))))
        for influence in range(4):
            for joint in np.unique(vertices["j"][:, influence]):
                mask = vertices["j"][:, influence] == joint
                weights = vertices["w"][mask, influence, None]
                points[mask] += (homogeneous[mask] @ transforms[joint].T)[:, :3] * weights
                normals[mask] += vertices["n"][mask] @ transforms[joint][:3, :3].T * weights
        # Recover a proper hand-axis rotation from anatomical landmarks. Matching
        # palm axes rather than weapon bounding boxes preserves the Karambit grip.
        source_hand = pose["hand_R"][:3, 3]
        target_hand = idle[hand_index][:3, 3]
        src, dst = [], []
        for finger, number in [("index", 1), ("middle", 2), ("ring", 3), ("pinky", 4)]:
            a = pose["finger_" + finger + "_0_R"][:3, 3] - source_hand
            b = idle[names["v_weapon.Bip01_R_Finger" + str(number)]][:3, 3] - target_hand
            src.append(a / np.linalg.norm(a))
            dst.append(b / np.linalg.norm(b))
        u, _, vt = np.linalg.svd(np.array(src).T @ np.array(dst))
        if np.linalg.det(u @ vt) < 0:
            u[:, -1] *= -1
        rotation = (u @ vt).T
        posed = (points - source_hand) @ rotation.T / 32.0 + target_hand
        posed_normals = normals @ rotation.T
        back_to_bind = bind[weapon_index] @ np.linalg.inv(idle[weapon_index])
        positions = (np.column_stack((posed, np.ones(len(posed)))) @ back_to_bind.T)[:, :3]
        normal_bind = posed_normals @ back_to_bind[:3, :3].T
        normal_bind /= np.maximum(np.linalg.norm(normal_bind, axis=1, keepdims=True), 1e-10)
        joint_array = np.zeros((len(positions), 4), dtype=np.uint16)
        joint_array[:, 0] = weapon_joint
        weights = np.zeros((len(positions), 4)); weights[:, 0] = 1.0
        # Proper rotations preserve glTF winding; .skin indices retain glTF CCW.
        indices = np.concatenate([p[1] for p in primitives])
        for prefix in ("v", "p", "w"):
            document, binary = copy.deepcopy(original), bytearray(original_binary)
            p, n = positions.copy(), normal_bind.copy()
            if prefix != "v":
                world, world_binary = read_glb(str(ROOT / ("assets/models/weapons/" + prefix + "_knife.glb")))
                reference = _accessor(world, world_binary, world["meshes"][0]["primitives"][0]["attributes"]["POSITION"])
                # Original p_/w_ knife meshes retain vertex correspondence.
                affine, _, _, _ = np.linalg.lstsq(np.column_stack((old_positions, np.ones(len(old_positions)))), reference, rcond=None)
                assert np.max(np.linalg.norm(np.column_stack((old_positions, np.ones(len(old_positions)))) @ affine - reference, axis=1)) < 0.001
                p = np.column_stack((p, np.ones(len(p)))) @ affine
                n = n @ np.linalg.inv(affine[:3]).T
                n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-10)
                document, binary = copy.deepcopy(world), bytearray(world_binary)
            material = install_material(document, binary, texture_root, key + "_finish__" + finish, key)
            attributes = {"POSITION": append_array(document, binary, p, "VEC3"),
                          "NORMAL": append_array(document, binary, n, "VEC3"),
                          "TEXCOORD_0": append_array(document, binary, vertices["uv"], "VEC2")}
            if prefix == "v":
                attributes["JOINTS_0"] = append_array(document, binary, joint_array, "VEC4", 5123)
                attributes["WEIGHTS_0"] = append_array(document, binary, weights, "VEC4")
            primitive = {"attributes": attributes, "indices": append_array(document, binary, indices, "SCALAR", 5125), "material": material}
            document["meshes"][0]["primitives"][0] = primitive
            document["asset"]["cs2_knife_source"] = SOURCE_COMMIT
            out = ROOT / ("assets/models/weapons/" + prefix + "_knife_" + key + ".glb")
            write_glb(str(out), document, binary)
        options.append({"id": key, "name": label, **{p + "_model": p + "_knife_" + key for p in ("v", "p", "w")}})
        report["knives"][key] = {"vertices": len(vertices), "triangles": len(indices) // 3,
            "mesh_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "bind_bounds": [positions.min(0).tolist(), positions.max(0).tolist()],
            "grip_distance_m": float(np.linalg.norm(posed.mean(0) - target_hand))}
        print(key, report["knives"][key])
    (ROOT / "data/knife_models.json").write_text(json.dumps({"default": "original", "options": options, "provenance": report}, indent=2) + "\n")
    meta_path = ROOT / "data/models_meta.json"
    metadata = json.loads(meta_path.read_text())
    for key, _, _ in CHOICES:
        meta = copy.deepcopy(metadata["weapons/v_knife"])
        meta.update(source="zh667/ScCsgoKnives", source_commit=SOURCE_COMMIT, source_model=key,
                    animation_source="existing ShadowNigth/archi v_knife_kukri; retained without modification",
                    materials=["sc_cs2_" + key, "ct_base_glove.bmp", "ct_arms.bmp"],
                    vertices=int(meta["vertices"]) - len(old_positions) + report["knives"][key]["vertices"])
        meta.pop("world", None)
        metadata["weapons/v_knife_" + key] = meta
    meta_path.write_text(json.dumps(metadata, indent=2, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main(sys.argv[1])
