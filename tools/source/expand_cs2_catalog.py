#!/usr/bin/env python3
"""Install the complete *shipped* ScCsgoKnives catalog at the pinned revision.

python -m tools.source.expand_cs2_catalog SOURCE_ROOT
Original arms/UVs/animations and the three installed knives are preserved.
Textures are shared externally rather than duplicated in every V/P/W mesh.
The folding-part adapter appends mechanical tracks, never replacing arm tracks.
"""
import copy
import hashlib
import json
from pathlib import Path
import sys

import numpy as np
from PIL import Image

from . import add_cs2_knives as base
from .build_sport_gloves import _accessor
from .refine_weapon_animations import read_glb, write_glb
from .smd import trs

ROOT = base.ROOT
NAMES = dict(bayonet="Bayonet", bowie="Bowie Knife", butterfly="Butterfly Knife", canis="Survival Knife", cord="Paracord Knife", css="Classic Knife", default_ct="Default CT Knife", default_t="Default T Knife", falchion="Falchion Knife", flip="Flip Knife", gut="Gut Knife", karambit="Karambit", kukri="CS2 Kukri", m9="M9 Bayonet", navaja="Navaja Knife", outdoor="Nomad Knife", push="Shadow Daggers", skeleton="Skeleton Knife", stiletto="Stiletto Knife", tactical="Huntsman Knife", talon="Talon Knife", ursus="Ursus Knife")
EXISTING = {"karambit", "m9", "bayonet"}
OUT = Path("assets/textures/cs2_catalog")


def texture(source, stem):
    path = source / (stem + ".png")
    target = OUT / (stem + ".jpg")
    (ROOT / target).parent.mkdir(parents=True, exist_ok=True)
    Image.open(path).convert("RGB").save(ROOT / target, quality=95, subsampling=0)
    from .build_weapon_skins import _import_sidecar
    (ROOT / (target.as_posix() + ".import")).write_text(_import_sidecar(target))
    result = {"texture": "res://" + target.as_posix(), "source_sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
    for suffix, field in [("_normal", "normal"), ("_orm", "orm")]:
        p = source / (stem + suffix + ".png")
        if not p.exists():
            continue
        digest = hashlib.sha256(p.read_bytes()).hexdigest()
        out = OUT / (field + "_" + digest[:20] + ".png")
        (ROOT / out).write_bytes(p.read_bytes())
        (ROOT / (out.as_posix() + ".import")).write_text(_import_sidecar(out))
        result[field] = "res://" + out.as_posix()
    return result


def material(document, data, key):
    indices = {}
    for field in ["texture", "normal", "orm"]:
        if field not in data:
            continue
        image = len(document.setdefault("images", []))
        # Files are siblings of models only through this relative URI.
        uri = "../../textures/cs2_catalog/" + Path(data[field]).name
        document["images"].append({"uri": uri})
        indices[field] = len(document.setdefault("textures", []))
        document["textures"].append({"source": image, "sampler": 0})
    document.setdefault("samplers", [{"magFilter": 9729, "minFilter": 9987}])
    pbr = {"baseColorTexture": {"index": indices["texture"]}, "metallicFactor": 0.55, "roughnessFactor": 0.72}
    mat = {"name": "sc_cs2_" + key, "pbrMetallicRoughness": pbr}
    if "orm" in indices:
        pbr["metallicRoughnessTexture"] = {"index": indices["orm"]}
        mat["occlusionTexture"] = {"index": indices["orm"]}
    if "normal" in indices:
        mat["normalTexture"] = {"index": indices["normal"]}
    document["materials"].append(mat)
    return len(document["materials"]) - 1


def grip(pose, side, idle, names):
    hand = pose["hand_" + side][:3, 3]
    target_hand = idle[names["v_weapon.Bip01_" + side + "_Hand"]][:3, 3]
    src, dst = [], []
    for finger, number in [("index", 1), ("middle", 2), ("ring", 3), ("pinky", 4)]:
        a = pose["finger_" + finger + "_0_" + side][:3, 3] - hand
        b = idle[names["v_weapon.Bip01_" + side + "_Finger" + str(number)]][:3, 3] - target_hand
        src.append(a / np.linalg.norm(a)); dst.append(b / np.linalg.norm(b))
    u, _, vt = np.linalg.svd(np.array(src).T @ np.array(dst))
    if np.linalg.det(u @ vt) < 0:
        u[:, -1] *= -1
    rotation = (u @ vt).T
    result = np.eye(4); result[:3, :3] = rotation / 32.0
    result[:3, 3] = target_hand - rotation @ hand / 32.0
    return result


def skinned_idle(vertices, joints, inverse, pose):
    points, normals = np.zeros((len(vertices), 3)), np.zeros((len(vertices), 3))
    homogeneous = np.column_stack((vertices["p"], np.ones(len(vertices))))
    for joint, name in enumerate(joints):
        assert name in pose or vertices["w"][vertices["j"] == joint].sum() == 0
    for influence in range(4):
        for joint in np.unique(vertices["j"][:, influence]):
            mask = vertices["j"][:, influence] == joint
            weights = vertices["w"][mask, influence, None]
            transform = pose.get(joints[joint], np.eye(4)) @ inverse[joint]
            points[mask] += (homogeneous[mask] @ transform.T)[:, :3] * weights
            normals[mask] += vertices["n"][mask] @ transform[:3, :3].T * weights
    return points, normals


def main(source_root):
    source_root = Path(source_root)
    assets = source_root / "src/ScCsgoKnives"
    textures = assets / "Assets/Textures/ScCsgoKnives"
    finishes = {row["asset"]: row for row in json.loads((assets / "Assets/ScKnifeFinishes.json").read_text())["rows"]}
    catalog_path = ROOT / "data/knife_models.json"
    catalog = json.loads(catalog_path.read_text())
    original, binary_original = read_glb(str(ROOT / "assets/models/weapons/v_knife.glb"))
    names = {node["name"]: i for i, node in enumerate(original["nodes"])}
    idle = base.original_pose(original, binary_original, "idle")
    bind = base.original_pose(original, binary_original)
    weapon = names["weapon_hand_r"]
    left = names["v_weapon.Bip01_L_Hand"]
    old_positions = _accessor(original, binary_original, original["meshes"][0]["primitives"][0]["attributes"]["POSITION"])
    world_affines = {}
    for prefix in ["p", "w"]:
        d, b = read_glb(str(ROOT / ("assets/models/weapons/" + prefix + "_knife.glb")))
        points = _accessor(d, b, d["meshes"][0]["primitives"][0]["attributes"]["POSITION"])
        world_affines[prefix] = np.linalg.lstsq(np.column_stack((old_positions, np.ones(len(old_positions)))), points, rcond=None)[0]
        assert np.linalg.det(world_affines[prefix][:3]) > 0
    skins = json.loads((ROOT / "data/weapon_skins.json").read_text())
    metadata = json.loads((ROOT / "data/models_meta.json").read_text())
    existing_options = {option["id"]: option for option in catalog["options"]}
    for key, name in NAMES.items():
        factory = texture(textures, key + "_cs2")
        options = [{"id": "factory", "name": name + " | Factory", "finish": "Factory", **factory}]
        if key in finishes:
            row = finishes[key]; paint = row["finish"]
            finish = "Fade" if paint == "aa_fade" else "Ruby" if "ruby" in paint else "Gamma Doppler Phase " + paint[-1]
            options.append({"id": paint, "name": name + " | " + finish, "finish": finish, "paint_kit": paint, "paint_id": row["paintId"], **texture(textures, key + "_finish__" + paint)})
        skins["weapons"]["knife_" + key] = {"display_name": name, "materials": ["sc_cs2_" + key], "options": options}
        if key in EXISTING:
            existing_options[key]["model_name"] = name
            existing_options[key]["name"] = name
            existing_options[key]["default_finish"] = options[-1]["finish"]
            continue
        vertices, joints, inverse, primitives = base.read_skin(assets / "AnimationData" / (key + ".cs2.skin"))
        animation = json.loads((assets / "AnimationData" / (key + ".cs2.animation.json")).read_text())
        pose = base.source_pose(animation)
        points, normals = skinned_idle(vertices, joints, inverse, pose)
        to_bind = bind[weapon] @ np.linalg.inv(idle[weapon]) @ grip(pose, "R", idle, names)
        positions = (np.column_stack((points, np.ones(len(points)))) @ to_bind.T)[:, :3]
        normal_bind = normals @ to_bind[:3, :3].T
        bones = np.zeros((len(vertices), 4), dtype=np.uint16)
        bones[:, 0] = original["skins"][0]["joints"].index(weapon)
        weights = np.zeros((len(vertices), 4)); weights[:, 0] = 1
        if key == "push":
            # Both Shadow Daggers are real geometry, each bound to its own hand.
            dominant = vertices["j"][np.arange(len(vertices)), vertices["w"].argmax(axis=1)]
            mask = np.array([joints[i] == "weapon_l" for i in dominant])
            transform = bind[left] @ np.linalg.inv(idle[left]) @ grip(pose, "L", idle, names)
            positions[mask] = (np.column_stack((points[mask], np.ones(mask.sum()))) @ transform.T)[:, :3]
            normal_bind[mask] = normals[mask] @ transform[:3, :3].T
            bones[mask, 0] = original["skins"][0]["joints"].index(left)
            assert mask.any() and (~mask).any()
        normal_bind /= np.maximum(np.linalg.norm(normal_bind, axis=1, keepdims=True), 1e-10)
        indices = np.concatenate([p[1] for p in primitives])
        for prefix in ["v", "p", "w"]:
            if prefix == "v":
                document, binary = copy.deepcopy(original), bytearray(binary_original)
                p, n = positions.copy(), normal_bind.copy()
            else:
                document = {"asset": {"version": "2.0"}, "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"name": prefix + "_knife_" + key, "mesh": 0}], "meshes": [{"primitives": [{}]}], "materials": [], "accessors": [], "bufferViews": [], "buffers": [{"byteLength": 0}]}
                binary = bytearray()
                # A third-person hand holds one of the paired daggers.
                affine = world_affines[prefix]
                p = np.column_stack((positions, np.ones(len(positions)))) @ affine
                n = normal_bind @ np.linalg.inv(affine[:3]).T
                n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-10)
            mat = material(document, factory, key)
            attributes = {"POSITION": base.append_array(document, binary, p, "VEC3"), "NORMAL": base.append_array(document, binary, n, "VEC3"), "TEXCOORD_0": base.append_array(document, binary, vertices["uv"], "VEC2")}
            if prefix == "v":
                attributes["JOINTS_0"] = base.append_array(document, binary, bones, "VEC4", 5123)
                attributes["WEIGHTS_0"] = base.append_array(document, binary, weights, "VEC4")
            document["meshes"][0]["primitives"][0] = {"attributes": attributes, "indices": base.append_array(document, binary, indices if key != "push" or prefix == "v" else indices.reshape(-1, 3)[np.all(~mask[indices.reshape(-1, 3)], axis=1)].reshape(-1), "SCALAR", 5125), "material": mat}
            if prefix == "v":
                append_folding(document, binary, animation, pose, joints, vertices, to_bind, bind[weapon], weapon, attributes)
            document["asset"]["cs2_catalog_commit"] = base.SOURCE_COMMIT
            base.write_glb(str(ROOT / ("assets/models/weapons/" + prefix + "_knife_" + key + ".glb")), document, binary)
        option = {"id": key, "name": name, "model_name": name, "default_finish": "Factory", **{p + "_model": p + "_knife_" + key for p in ["v", "p", "w"]}}
        existing_options[key] = option
        meta = copy.deepcopy(metadata["weapons/v_knife"])
        meta.update(source="zh667/ScCsgoKnives", source_commit=base.SOURCE_COMMIT, source_model=key, materials=["sc_cs2_" + key, "ct_base_glove.bmp", "ct_arms.bmp"], vertices=len(vertices) + int(meta["vertices"]) - len(old_positions), animation_source="original archi arms; source mechanical folding tracks appended")
        part_names = [joint for i, joint in enumerate(joints) if joint in ["blade", "rear", "lock"] and vertices["w"][vertices["j"] == i].sum() > 0]
        meta["bones"] = 40 + len(part_names)
        meta["mechanical_bones"] = part_names
        if not part_names:
            meta["animation_source"] = "original archi arm and knife clips retained without modification"
        metadata["weapons/v_knife_" + key] = meta
        print("KNIFE", key, len(vertices), flush=True)
    catalog["options"] = [existing_options["original"]] + [existing_options[key] for key in NAMES]
    catalog["complete_catalog"] = {"models": 22, "painted_finishes": 20, "factory_finishes": 22, "source_commit": base.SOURCE_COMMIT}
    catalog_path.write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + "\n")
    (ROOT / "data/models_meta.json").write_text(json.dumps(metadata, indent=2, ensure_ascii=False) + "\n")
    (ROOT / "data/weapon_skins.json").write_text(json.dumps(skins, indent=2, ensure_ascii=False) + "\n")


def append_folding(document, binary, animation, idle_pose, joints, vertices, to_bind, weapon_bind, weapon_node, attributes):
    """Added below: source mechanical joints animate independently of arm clips."""
    active = [name for i, name in enumerate(joints) if vertices["w"][vertices["j"] == i].sum() > 0]
    parts = [name for name in active if name in ["blade", "rear", "lock"]]
    if not parts:
        return
    import bisect
    from scipy.spatial.transform import Rotation, Slerp
    skeleton = animation["Skeleton"]
    nodes = [{"name": b["Name"], "translation": b["Translation"], "rotation": b["Rotation"], "scale": b["Scale"], "children": b["Children"]} for b in skeleton]
    source_names = {n["name"]: i for i, n in enumerate(nodes)}
    source_clips = {c["Alias"]: c for c in animation["Clips"].values()}
    skin = document["skins"][0]
    inverse = _accessor(document, binary, skin["inverseBindMatrices"]).copy()
    conversion = np.linalg.inv(weapon_bind) @ to_bind
    back = np.linalg.inv(conversion)
    root_name = "weapon_offset"
    extra_nodes = {}
    for part in parts:
        index = len(document["nodes"])
        document["nodes"].append({"name": "cs2_mechanical_" + part})
        document["nodes"][weapon_node].setdefault("children", []).append(index)
        extra_nodes[part] = (index, len(skin["joints"]))
        skin["joints"].append(index)
        inverse = np.vstack((inverse, np.linalg.inv(weapon_bind).T.reshape(1, 16)))
    skin["inverseBindMatrices"] = base.append_array(document, binary, inverse, "MAT4")
    target_joints = np.zeros((len(vertices), 4), dtype=np.uint16)
    for influence in range(4):
        for source_index, name in enumerate(joints):
            target = extra_nodes[name][1] if name in extra_nodes else skin["joints"].index(weapon_node)
            target_joints[vertices["j"][:, influence] == source_index, influence] = target
    attributes["JOINTS_0"] = base.append_array(document, binary, target_joints, "VEC4", 5123)
    attributes["WEIGHTS_0"] = base.append_array(document, binary, vertices["w"], "VEC4")
    aliases = dict(draw="deploy", idle="idle", slash1="slash1", slash2="slash2", midslash1="slashHit1", midslash2="slashHit2", stab_miss="stab", stab="stabHit", inspect="inspect")
    for clip in document["animations"]:
        source = source_clips[aliases[clip["name"]]]
        duration = max(float(_accessor(document, binary, s["input"])[-1, 0]) for s in clip["samplers"])
        times = np.linspace(0, duration, max(2, int(duration * 30) + 1))
        poses = []
        for t in times:
            sample = float(t / duration * source["Duration"])
            overrides = {}
            for name, tracks in source["Bones"].items():
                values = {}
                for path, track in tracks.items():
                    if path not in ["Rotation", "Translation", "Scale"]:
                        continue
                    tt, vv = track["Times"], track["Values"]
                    if len(tt) == 1 or sample <= tt[0]:
                        value = vv[0]
                    elif sample >= tt[-1]:
                        value = vv[-1]
                    else:
                        i = bisect.bisect_right(tt, sample) - 1
                        weight = (sample - tt[i]) / (tt[i + 1] - tt[i])
                        if path == "Rotation":
                            value = Slerp([0, 1], Rotation.from_quat([vv[i], vv[i + 1]]))([weight]).as_quat()[0]
                        else:
                            value = (1 - weight) * np.array(vv[i]) + weight * np.array(vv[i + 1])
                    values[path.lower()] = value
                overrides[source_names[name]] = values
            poses.append(base.matrices(nodes, overrides))
        input_accessor = base.append_array(document, binary, times, "SCALAR")
        for part in parts:
            transforms = []
            for pose in poses:
                delta = idle_pose[root_name] @ np.linalg.inv(pose[source_names[root_name]]) @ pose[source_names[part]] @ np.linalg.inv(idle_pose[part])
                transforms.append(conversion @ delta @ back)
            for path, kind, values in [("translation", "VEC3", [m[:3, 3] for m in transforms]), ("rotation", "VEC4", Rotation.from_matrix(np.array([m[:3, :3] for m in transforms])).as_quat())]:
                output = base.append_array(document, binary, values, kind)
                clip["samplers"].append({"input": input_accessor, "output": output, "interpolation": "LINEAR"})
                clip["channels"].append({"sampler": len(clip["samplers"]) - 1, "target": {"node": extra_nodes[part][0], "path": path}})


if __name__ == "__main__":
    main(sys.argv[1])
