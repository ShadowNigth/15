#!/usr/bin/env python3
"""Build native-bind Sport Gloves for every archi viewmodel.

    python -m tools.source.build_sport_gloves /tmp/archi-review/Sport_gloves
    python -m tools.source.build_sport_gloves --check /tmp/archi-review/Sport_gloves

Source: ShadowNigth/archi/Sport_gloves. Only the Rootns Rig g0...g4 glove
meshes are used. Arm/sleeve SMDs, the duplicate Saseky meshes, and Knife Rig
are deliberately excluded. GoldSrc and the target Source rigs use different
local bone axes. A per-target proper rotation recovered from 32 shared
hand/finger parent-child directions converts each rigid vertex into the target
bone frame; no animation is retargeted and no runtime vertex rebaking occurs.
"""
import copy
import hashlib
import io
import json
import math
import re
import struct
import sys
from pathlib import Path

import numpy as np
from PIL import Image

from .refine_weapon_animations import read_glb
from .smd import parse_smd, trs
from .smd_converter import GlbWriter, Rig, globals_of

ROOT = Path(__file__).resolve().parents[2]
SCALE = 1.0 / 32.0
SOURCE_COMMIT = "43b46172606a31759637c90378782390f374c1ee"
RIG_NAME = "Rootns Rig"
# Each target gets its own row-vector rotation: source_unit @ axis_row = target_unit.
WEAR_NAMES = {"BS": "Battle-Scarred", "FT": "Field-Tested", "MW": "Minimal Wear", "WW": "Well-Worn"}
MODEL_OUT = Path("assets/models/sport_gloves")
TEXTURE_OUT = Path("assets/textures/sport_gloves")
CATALOG_OUT = Path("data/sport_gloves.json")


def _slug(text):
    return re.sub(r"_+", "_", re.sub(r"[^a-z0-9]+", "_", text.lower())).strip("_")


def _material_name(source_name):
    return "sport_glove_" + Path(source_name).stem.lower()


def _accessor(document, binary, index):
    accessor = document["accessors"][index]
    view = document["bufferViews"][accessor["bufferView"]]
    offset = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}[accessor["type"]]
    dtype = np.dtype({5126: "<f4", 5125: "<u4", 5123: "<u2", 5121: "u1"}[accessor["componentType"]])
    count = int(accessor["count"])
    stride = int(view.get("byteStride", width * dtype.itemsize))
    if stride == width * dtype.itemsize:
        result = np.frombuffer(binary, dtype=dtype, count=count * width, offset=offset).reshape(count, width)
    else:
        result = np.ndarray((count, width), dtype=dtype, buffer=binary, offset=offset,
                            strides=(stride, dtype.itemsize))
    return np.array(result)


def _target(document, binary):
    nodes = document["nodes"]
    parents = {child: parent for parent, node in enumerate(nodes) for child in node.get("children", [])}
    cache = {}

    def global_matrix(index):
        if index not in cache:
            node = nodes[index]
            matrix = trs(np.array(node.get("translation", [0, 0, 0]), dtype=np.float64),
                         np.array(node.get("rotation", [0, 0, 0, 1]), dtype=np.float64))
            matrix[:3, :3] *= np.array(node.get("scale", [1, 1, 1]), dtype=np.float64)
            parent = parents.get(index)
            cache[index] = global_matrix(parent) @ matrix if parent is not None else matrix
        return cache[index]

    armature = next(i for i, node in enumerate(nodes) if node.get("name") == "Armature")
    armature_inverse = np.linalg.inv(global_matrix(armature))
    globals_arm = {i: armature_inverse @ global_matrix(i) for i in range(len(nodes))}
    names = {str(node.get("name", "")).lower(): i for i, node in enumerate(nodes)}
    return names, globals_arm, armature


def _source_rig(source):
    references = [parse_smd(source / RIG_NAME / "Ct Arms" / ("g%d.smd" % i)) for i in range(5)]
    rig = Rig(references[0])
    if any(ref["nodes"] != references[0]["nodes"] or ref["frames"] != references[0]["frames"]
           for ref in references[1:]):
        raise AssertionError("Sport glove reference SMDs do not share one rest skeleton")
    if any(len(vertex[4]) != 1 for ref in references for _mat, tri in ref["triangles"] for vertex in tri):
        raise AssertionError("Sport glove conversion requires the authored rigid weights")
    translations = np.array([p for p, _q in rig.bind])
    rotations = np.array([q for _p, q in rig.bind])
    source_globals = globals_of(rig, translations, rotations)
    source_inverse = [np.linalg.inv(matrix) for matrix in source_globals]
    return references, rig, source_inverse


def _axis_calibration(references, rig, target_names, target_nodes):
    errors = []
    source_directions = []
    target_directions = []
    for index, (name, parent) in enumerate(references[0]["nodes"]):
        if parent < 0 or not any(token in name for token in ("_Fore", "_Hand", "_Finger")):
            continue
        parent_name = references[0]["nodes"][parent][0]
        target_index = target_names.get(name.lower())
        target_parent = target_names.get(parent_name.lower())
        if target_index is None or target_parent is None:
            raise AssertionError("Target is missing glove bone/parent: " + name)
        source_offset = np.array(references[0]["frames"][0][index][0], dtype=np.float64)
        target_offset = np.array(target_nodes[target_index].get("translation", [0, 0, 0]), dtype=np.float64)
        if np.linalg.norm(source_offset) < 0.2 or np.linalg.norm(target_offset) < 0.005:
            continue
        source_directions.append(source_offset / np.linalg.norm(source_offset))
        target_directions.append(target_offset / np.linalg.norm(target_offset))
    if len(source_directions) != 32:
        raise AssertionError("Expected 32 shared hand/finger directions, found %d" % len(source_directions))
    source_array = np.asarray(source_directions)
    target_array = np.asarray(target_directions)
    u, _singular, vt = np.linalg.svd(source_array.T @ target_array)
    axis_row = u @ vt
    if np.linalg.det(axis_row) < 0.0:
        u[:, -1] *= -1.0
        axis_row = u @ vt
    for source_unit, target_unit in zip(source_array, target_array):
        dot = float(np.clip(np.dot(source_unit @ axis_row, target_unit), -1.0, 1.0))
        errors.append(math.degrees(math.acos(dot)))
    return axis_row, max(errors)


def _winding_alignment(points, normals, indices):
    """Dot products between geometric front-face normals and authored normals."""
    triangles = np.asarray(indices, dtype=np.int64).reshape(-1, 3)
    geometric = np.cross(points[triangles[:, 1]] - points[triangles[:, 0]],
                         points[triangles[:, 2]] - points[triangles[:, 0]])
    authored = normals[triangles].sum(axis=1)
    denominator = np.linalg.norm(geometric, axis=1) * np.linalg.norm(authored, axis=1)
    valid = denominator > 1e-12
    return (geometric[valid] * authored[valid]).sum(axis=1) / denominator[valid]


def _original_glove_bounds(document, binary):
    points = []
    for mesh in document.get("meshes", []):
        for primitive in mesh["primitives"]:
            material = document["materials"][primitive["material"]]["name"].lower()
            if material == "ct_base_glove.bmp":
                points.append(_accessor(document, binary, primitive["attributes"]["POSITION"]).astype(np.float64))
    if not points:
        raise AssertionError("Target has no original ct_base_glove.bmp surface")
    vertices = np.concatenate(points)
    return vertices.min(axis=0), vertices.max(axis=0)


def _build_model(model_path, references, rig, source_inverse):
    document, binary = read_glb(str(model_path))
    target_names, target_globals, armature = _target(document, binary)
    axis_row, axis_error = _axis_calibration(references, rig, target_names, document["nodes"])
    axis_column = axis_row.T
    if axis_error > 80.0:
        raise AssertionError("%s hand-axis mismatch is %.3f degrees" % (model_path.name, axis_error))

    skin_source = document["skins"][0]
    joint_position = {node: index for index, node in enumerate(skin_source["joints"])}
    buckets = {}
    for reference in references:
        for source_material, triangle in reference["triangles"]:
            material_name = _material_name(source_material)
            bucket = buckets.setdefault(material_name, {"unique": {}, "p": [], "n": [], "uv": [], "j": [], "w": [], "i": []})
            # This conversion uses proper rotations, not a reflection. Keep the
            # authored winding so glTF front faces agree with the outer normals.
            for vertex in triangle:
                bone, position, normal, uv, _links = vertex
                target_node = target_names.get(rig.names[bone].lower())
                if target_node is None or target_node not in joint_position:
                    raise AssertionError("No native target joint for " + rig.names[bone])
                key = (bone, *(round(float(x), 5) for x in position),
                       *(round(float(x), 4) for x in normal),
                       round(float(uv[0]), 6), round(float(uv[1]), 6))
                vertex_index = bucket["unique"].get(key)
                if vertex_index is None:
                    local = source_inverse[bone] @ np.array([*position, 1.0], dtype=np.float64)
                    local[:3] = axis_column @ (local[:3] * SCALE)
                    target = target_globals[target_node] @ local
                    local_normal = source_inverse[bone][:3, :3] @ np.array(normal, dtype=np.float64)
                    target_normal = target_globals[target_node][:3, :3] @ (axis_column @ local_normal)
                    target_normal /= max(float(np.linalg.norm(target_normal)), 1e-10)
                    vertex_index = len(bucket["p"])
                    bucket["unique"][key] = vertex_index
                    bucket["p"].append(target[:3])
                    bucket["n"].append(target_normal)
                    bucket["uv"].append([uv[0], 1.0 - uv[1]])
                    bucket["j"].append([joint_position[target_node], 0, 0, 0])
                    bucket["w"].append([1.0, 0.0, 0.0, 0.0])
                bucket["i"].append(vertex_index)

    writer = GlbWriter()
    materials = []
    primitives = []
    all_points = []
    winding_samples = []
    for material_index, material_name in enumerate(sorted(buckets)):
        bucket = buckets[material_name]
        points = np.asarray(bucket["p"], dtype=np.float64)
        indices = np.asarray(bucket["i"], dtype=np.int64)
        winding_samples.append(_winding_alignment(points, np.asarray(bucket["n"], dtype=np.float64), indices))
        all_points.append(points)
        materials.append({"name": material_name,
                          "pbrMetallicRoughness": {"baseColorFactor": [1.0, 1.0, 1.0, 1.0],
                                                   "metallicFactor": 0.0, "roughnessFactor": 0.85}})
        attributes = {
            "POSITION": writer.acc(points.astype("<f4"), 5126, "VEC3", 34962, True),
            "NORMAL": writer.acc(np.asarray(bucket["n"], dtype="<f4"), 5126, "VEC3", 34962),
            "TEXCOORD_0": writer.acc(np.asarray(bucket["uv"], dtype="<f4"), 5126, "VEC2", 34962),
            "JOINTS_0": writer.acc(np.asarray(bucket["j"], dtype="<u2"), 5123, "VEC4", 34962),
            "WEIGHTS_0": writer.acc(np.asarray(bucket["w"], dtype="<f4"), 5126, "VEC4", 34962),
        }
        primitives.append({"attributes": attributes,
                           "indices": writer.acc(indices.astype("<u4"), 5125, "SCALAR", 34963),
                           "material": material_index, "mode": 4})

    nodes = copy.deepcopy(document["nodes"])
    for node in nodes:
        node.pop("mesh", None)
        node.pop("skin", None)
    mesh_node = len(nodes)
    nodes.append({"name": "SportGlovesMesh", "mesh": 0, "skin": 0})
    nodes[armature].setdefault("children", []).append(mesh_node)
    inverse_binds = np.array([np.linalg.inv(target_globals[node]).T for node in skin_source["joints"]], dtype="<f4")
    output = {
        "asset": {"version": "2.0", "generator": "ShadowNigth Sport Gloves native-bind converter",
                  "copyright": "Sport_gloves from ShadowNigth/archi; original archi arm surfaces are not included"},
        "scene": 0, "scenes": [{"nodes": [0]}], "nodes": nodes,
        "meshes": [{"name": "SportGloves", "primitives": primitives}], "materials": materials,
        "skins": [{"inverseBindMatrices": writer.acc(inverse_binds.reshape(-1, 16), 5126, "MAT4"),
                   "joints": skin_source["joints"], "skeleton": armature}],
        "buffers": [{"byteLength": len(writer.bin)}], "bufferViews": writer.views, "accessors": writer.accessors,
        "extras": {"source": "ShadowNigth/archi/Sport_gloves", "source_commit": SOURCE_COMMIT,
                   "rig": RIG_NAME, "axis_row": axis_row.tolist(), "rigid_weights": True},
    }
    json_chunk = json.dumps(output, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    json_chunk += b" " * ((-len(json_chunk)) % 4)
    binary_chunk = bytes(writer.bin) + b"\0" * ((-len(writer.bin)) % 4)
    glb = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(json_chunk) + 8 + len(binary_chunk))
    glb += struct.pack("<II", len(json_chunk), 0x4E4F534A) + json_chunk
    glb += struct.pack("<II", len(binary_chunk), 0x004E4942) + binary_chunk

    generated_points = np.concatenate(all_points)
    original_min, original_max = _original_glove_bounds(document, binary)
    bounds_delta = float(max(np.max(np.abs(generated_points.min(axis=0) - original_min)),
                             np.max(np.abs(generated_points.max(axis=0) - original_max))))
    if bounds_delta > 0.035:
        raise AssertionError("%s glove bounds differ from the original by %.4fm" % (model_path.name, bounds_delta))
    winding = np.concatenate(winding_samples)
    winding_mean = float(winding.mean())
    winding_positive = float((winding > 0.0).mean())
    if winding_mean < 0.75 or winding_positive < 0.90:
        raise AssertionError("%s has inward glove faces: mean normal alignment %.4f, positive %.2f%%" %
                             (model_path.name, winding_mean, winding_positive * 100.0))
    return glb, {"vertices": int(len(generated_points)), "triangles": 9900,
                 "axis_error_deg": axis_error, "bounds_delta_m": bounds_delta,
                 "winding_mean": winding_mean, "winding_positive": winding_positive}


def _resource_uid(relative):
    # Godot's stable base-34 ResourceUID text encoding (resource_uid.cpp).
    value = int.from_bytes(hashlib.sha256(("sport_gloves:" + relative.as_posix()).encode("utf-8")).digest()[:8], "big")
    value &= 0x7FFFFFFFFFFFFFFF
    alphabet = "abcdefghijklmnopqrstuvwxy012345678"
    encoded = ""
    while True:
        encoded = alphabet[value % len(alphabet)] + encoded
        value //= len(alphabet)
        if not value:
            return "uid://" + encoded


def _import_sidecar(relative):
    source = "res://" + relative.as_posix()
    imported = "res://.godot/imported/%s-%s.ctex" % (relative.name, hashlib.md5(source.encode("utf-8")).hexdigest())
    return """[remap]\n\nimporter=\"texture\"\ntype=\"CompressedTexture2D\"\nuid=\"%s\"\npath=\"%s\"\nmetadata={\n\"vram_texture\": false\n}\n\n[deps]\n\nsource_file=\"%s\"\ndest_files=[\"%s\"]\n\n[params]\n\ncompress/mode=0\ncompress/high_quality=false\ncompress/lossy_quality=0.7\ncompress/uastc_level=0\ncompress/rdo_quality_loss=0.0\ncompress/hdr_compression=1\ncompress/normal_map=0\ncompress/channel_pack=0\nmipmaps/generate=true\nmipmaps/limit=-1\nroughness/mode=0\nroughness/src_normal=\"\"\nprocess/channel_remap/red=0\nprocess/channel_remap/green=1\nprocess/channel_remap/blue=2\nprocess/channel_remap/alpha=3\nprocess/fix_alpha_border=true\nprocess/premult_alpha=false\nprocess/normal_map_invert_y=false\nprocess/hdr_as_srgb=false\nprocess/hdr_clamp_exposure=false\nprocess/size_limit=0\ndetect_3d/compress_to=0\n""" % (_resource_uid(relative), imported, source, imported)


def _build_outputs(source, project):
    references, rig, source_inverse = _source_rig(source)
    weapons = json.loads((project / "data/weapons.json").read_text(encoding="utf-8"))["weapons"]
    model_names = sorted({str(spec["v_model"]) for spec in weapons.values()})
    if len(model_names) != 43:
        raise AssertionError("Expected 43 distinct archi viewmodels")
    outputs = {}
    reports = {}
    for model_name in model_names:
        data, report = _build_model(project / "assets/models/weapons" / (model_name + ".glb"),
                                    references, rig, source_inverse)
        outputs[MODEL_OUT / (model_name + ".glb")] = data
        reports[model_name] = report

    options = []
    texture_hashes = {}
    texture_sizes = {}
    for family_dir in sorted(path for path in source.iterdir() if path.is_dir() and path.name.startswith("Sport Gloves ")):
        for variant_dir in sorted(path for path in family_dir.iterdir() if path.is_dir()):
            wear_code = variant_dir.name.rsplit(" ", 1)[-1]
            if wear_code not in WEAR_NAMES:
                raise AssertionError("Unknown Sport Gloves wear: " + variant_dir.name)
            family = family_dir.name.removeprefix("Sport Gloves ")
            option_id = _slug(family) + "_" + wear_code.lower()
            display_family = "Pandora's Box" if family == "Pandora'S'Box" else family
            textures = {}
            for path in sorted(variant_dir.glob("*.bmp")):
                with Image.open(path) as image:
                    rgb = image.convert("RGB")
                    buffer = io.BytesIO()
                    rgb.save(buffer, "JPEG", quality=93, subsampling=0, optimize=True)
                    encoded = buffer.getvalue()
                    dimensions = list(rgb.size)
                digest = hashlib.sha256(encoded).hexdigest()
                if digest not in texture_hashes:
                    relative = TEXTURE_OUT / option_id / (_slug(path.stem) + ".jpg")
                    texture_hashes[digest] = relative
                    outputs[relative] = encoded
                    outputs[Path(str(relative) + ".import")] = _import_sidecar(relative).encode("utf-8")
                    texture_sizes[digest] = dimensions
                relative = texture_hashes[digest]
                textures[_material_name(path.name)] = "res://" + relative.as_posix()
                if texture_sizes[digest] != dimensions:
                    raise AssertionError("Hash collision or inconsistent image dimensions: " + str(path))
            if len(textures) != 10:
                raise AssertionError("Each Sport variant needs ten hand materials: " + str(variant_dir))
            options.append({"id": option_id, "name": "Sport Gloves | %s — %s" % (display_family, WEAR_NAMES[wear_code]),
                            "family": display_family, "wear": WEAR_NAMES[wear_code], "wear_code": wear_code,
                            "textures": textures})
    if len(options) != 26:
        raise AssertionError("Expected 26 Sport Gloves finishes, found %d" % len(options))
    if not any(option["id"] == "arid_mw" for option in options):
        raise AssertionError("Default arid_mw finish is missing")
    catalog = {
        "source": "ShadowNigth/archi/Sport_gloves", "source_commit": SOURCE_COMMIT,
        "rig": RIG_NAME, "default": "arid_mw", "classic_id": "classic", "models": model_names,
        "conversion": "Offline rigid native binds; per-target GoldSrc-to-Source hand axes; original arms and animations unchanged",
        "options": options,
    }
    outputs[CATALOG_OUT] = (json.dumps(catalog, indent=2, ensure_ascii=False, sort_keys=True) + "\n").encode("utf-8")
    return outputs, reports, len(texture_hashes)


def main():
    check_only = "--check" in sys.argv[1:]
    args = [arg for arg in sys.argv[1:] if arg != "--check"]
    if len(args) not in (1, 2):
        raise SystemExit(__doc__)
    source = Path(args[0]).resolve()
    project = Path(args[1]).resolve() if len(args) == 2 else ROOT
    outputs, reports, texture_count = _build_outputs(source, project)
    changed = 0
    for relative, data in sorted(outputs.items(), key=lambda item: item[0].as_posix()):
        destination = project / relative
        if check_only:
            if not destination.is_file() or destination.read_bytes() != data:
                raise AssertionError("Out-of-date or missing output: " + str(relative))
        elif not destination.is_file() or destination.read_bytes() != data:
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)
            changed += 1
    maximum_axis = max(report["axis_error_deg"] for report in reports.values())
    maximum_bounds = max(report["bounds_delta_m"] for report in reports.values())
    minimum_winding = min(report["winding_mean"] for report in reports.values())
    minimum_front = min(report["winding_positive"] for report in reports.values())
    print("%s: 43 native-bind models, 26 finishes, %d shared textures; max axis %.4f deg, max bounds %.5fm; "
          "min normal alignment %.4f, min front faces %.2f%%; %d changed" %
          ("CHECK PASS" if check_only else "BUILD", texture_count, maximum_axis, maximum_bounds,
           minimum_winding, minimum_front * 100.0, changed))


if __name__ == "__main__":
    main()
