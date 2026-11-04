#!/usr/bin/env python3
"""Build selectable CS2 arm/glove/sleeve meshes for the existing Bip01 rigs.

    python -m tools.source.build_viewmodel_loadouts /tmp/CS2-MultiRig [project]

The source is https://github.com/goribby/CS2-MultiRig (reviewed at
026058b2a70a55257d6b85563f27b3c31e558f26). No licence is declared upstream.
The source's 38-joint names are mapped to the installed weapon skeleton names.
Inverse bind matrices are scaled from Source inches to the project's 1/32 metre
convention. These GLBs are intermediate rigs: at runtime ViewmodelLoadout keeps
the original ct_arms.bmp surfaces, discards MultiRig bare_arm_133 surfaces, bakes
only gloves/sleeves into each weapon's rest space and installs native rigid
target Skin binds, so no weapon mesh or animation needs to be rebuilt.
"""
import io
import json
import os
import struct
import sys

import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
OUT_DIR = os.path.join("assets", "models", "loadouts")
SOURCE_SCALE = 1.0 / 32.0
VARIANTS = {
    "ct_hardknuckle": "Arms/CT/glove_hardknuckle/v_glove_hardknuckle.glb",
    "ct_hardknuckle_black": "Arms/CT/glove_hardknuckle/v_glove_hardknuckle_black.glb",
    "t_fingerless": "Arms/T/glove_fingerless/v_glove_fingerless.gltf",
    "t_fullfinger": "Arms/T/glove_fullfinger/v_glove_fullfinger.gltf",
    "ct_sleeve_sas": "Arms/CT/Sleeves/SAS/sleeve_ctm_sas.gltf",
    "ct_sleeve_fbi": "Arms/CT/Sleeves/FBI/sleeve_ctm_fbi.gltf",
    "t_sleeve_professional": "Arms/T/Sleeves/Professional/sleeve_tm_professional.gltf",
    "t_sleeve_balkan": "Arms/T/Sleeves/Balkan/sleeve_balkan.gltf",
}


def bone_mapping(side):
    target = "v_weapon.Bip01_%s_" % side.upper()
    suffix = "_" + side
    result = {
        "arm_lower" + suffix: target + "Forearm",
        "hand" + suffix: target + "Hand",
        "arm_lower" + suffix + "_twist": target + "ForeTwist",
        "arm_upper" + suffix: target + "UpperArm",
    }
    for modern, number in (("thumb", 0), ("index", 1), ("middle", 2), ("ring", 3), ("pinky", 4)):
        for segment in range(3):
            old = "finger_%s_%d%s" % (modern, segment, suffix)
            new = target + "Finger%d%s" % (number, "" if segment == 0 else str(segment))
            result[old] = new
    return result


BONE_MAP = bone_mapping("l") | bone_mapping("r")


def read_model(path):
    raw = open(path, "rb").read()
    if raw[:4] == b"glTF":
        json_length = struct.unpack_from("<I", raw, 12)[0]
        document = json.loads(raw[20:20 + json_length])
        offset = 20 + json_length
        bin_length = struct.unpack_from("<I", raw, offset)[0]
        binary = raw[offset + 8:offset + 8 + bin_length]
    else:
        document = json.loads(raw.decode("utf-8"))
        uri = document["buffers"][0]["uri"]
        with open(os.path.join(os.path.dirname(path), uri), "rb") as handle:
            binary = handle.read()
    return document, bytearray(binary)


def accessor(document, binary, index):
    desc = document["accessors"][index]
    view = document["bufferViews"][desc["bufferView"]]
    widths = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
    types = {5121: "<u1", 5123: "<u2", 5125: "<u4", 5126: "<f4"}
    width = widths[desc["type"]]
    dtype = np.dtype(types[desc["componentType"]])
    start = view.get("byteOffset", 0) + desc.get("byteOffset", 0)
    stride = view.get("byteStride", width * dtype.itemsize)
    return np.ndarray((desc["count"], width), dtype=dtype, buffer=binary,
                      offset=start, strides=(stride, dtype.itemsize))


def resolve_image(source_root, model_path, uri):
    decoded = uri.replace("%20", " ")
    candidates = [
        os.path.join(os.path.dirname(model_path), decoded),
        os.path.join(source_root, "Arms", "Shared", decoded),
        os.path.join(source_root, "Arms", "Shared", os.path.basename(decoded)),
    ]
    for candidate in candidates:
        if os.path.isfile(candidate):
            return candidate
    raise FileNotFoundError("cannot resolve %s for %s" % (uri, model_path))


def image_roles(document):
    roles = {}
    for material in document.get("materials", []):
        pbr = material.get("pbrMetallicRoughness", {})
        for key, role in (("baseColorTexture", "base"), ("metallicRoughnessTexture", "orm")):
            if key in pbr:
                roles[pbr[key]["index"]] = role
        for key, role in (("normalTexture", "normal"), ("occlusionTexture", "orm")):
            if key in material:
                roles[material[key]["index"]] = role
    return roles


def process_image(data, role):
    image = Image.open(io.BytesIO(data))
    image.load()
    limit = 1024 if role in ("normal", "orm") else 2048
    if max(image.size) > limit:
        ratio = limit / float(max(image.size))
        size = tuple(max(1, int(round(axis * ratio))) for axis in image.size)
        image = image.resize(size, Image.Resampling.LANCZOS)
    has_alpha = image.mode in ("RGBA", "LA") or "transparency" in image.info
    if has_alpha:
        image = image.convert("RGBA")
        alpha = image.getchannel("A")
        has_alpha = alpha.getextrema()[0] < 250
    output = io.BytesIO()
    if role == "base" and not has_alpha:
        image.convert("RGB").save(output, format="JPEG", quality=94, subsampling=0, optimize=True)
        return output.getvalue(), "image/jpeg"
    if role in ("normal", "orm"):
        image = image.convert("RGB")
    image.save(output, format="PNG", optimize=True)
    return output.getvalue(), "image/png"


def append_bytes(binary, views, data, **extra):
    while len(binary) % 4:
        binary.append(0)
    view = {"buffer": 0, "byteOffset": len(binary), "byteLength": len(data)}
    view.update(extra)
    views.append(view)
    binary.extend(data)
    return len(views) - 1


def build_variant(source_root, project, variant, relative):
    model_path = os.path.join(source_root, relative)
    document, original = read_model(model_path)
    document.pop("animations", None)
    document.pop("cameras", None)
    for node in document.get("nodes", []):
        name = node.get("name", "")
        if name in BONE_MAP:
            node["name"] = BONE_MAP[name]
    for skin in document.get("skins", []):
        for joint in skin["joints"]:
            name = document["nodes"][joint].get("name", "")
            if not name.startswith("v_weapon.Bip01_"):
                raise AssertionError("unmapped joint %s in %s" % (name, variant))

    used_accessors = set()
    for mesh in document.get("meshes", []):
        for primitive in mesh["primitives"]:
            used_accessors.update(primitive.get("attributes", {}).values())
            if "indices" in primitive:
                used_accessors.add(primitive["indices"])
            for target in primitive.get("targets", []):
                used_accessors.update(target.values())
    for skin in document.get("skins", []):
        used_accessors.add(skin["inverseBindMatrices"])
    accessor_map = {old: new for new, old in enumerate(sorted(used_accessors))}
    document["accessors"] = [document["accessors"][old] for old in sorted(used_accessors)]
    for mesh in document.get("meshes", []):
        for primitive in mesh["primitives"]:
            primitive["attributes"] = {key: accessor_map[value]
                                       for key, value in primitive["attributes"].items()}
            if "indices" in primitive:
                primitive["indices"] = accessor_map[primitive["indices"]]
            for target in primitive.get("targets", []):
                for key, value in list(target.items()):
                    target[key] = accessor_map[value]
    for skin in document.get("skins", []):
        skin["inverseBindMatrices"] = accessor_map[skin["inverseBindMatrices"]]

    roles = image_roles(document)
    images = []
    for index, image in enumerate(document.get("images", [])):
        if "uri" in image:
            path = resolve_image(source_root, model_path, image["uri"])
            data = open(path, "rb").read()
        else:
            view = document["bufferViews"][image["bufferView"]]
            start = view.get("byteOffset", 0)
            data = bytes(original[start:start + view["byteLength"]])
        payload, mime = process_image(data, roles.get(index, "base"))
        images.append((payload, mime))

    # Keep only accessor buffer views. Image data is re-encoded and appended below.
    used_views = set()
    for desc in document.get("accessors", []):
        if "bufferView" in desc:
            used_views.add(desc["bufferView"])
        if "sparse" in desc:
            sparse = desc["sparse"]
            used_views.add(sparse["indices"]["bufferView"])
            used_views.add(sparse["values"]["bufferView"])
    binary = bytearray()
    views = []
    view_map = {}
    for old_index in sorted(used_views):
        old = document["bufferViews"][old_index]
        start = old.get("byteOffset", 0)
        data = bytes(original[start:start + old["byteLength"]])
        extra = {}
        for key in ("byteStride", "target"):
            if key in old:
                extra[key] = old[key]
        view_map[old_index] = append_bytes(binary, views, data, **extra)
    for desc in document.get("accessors", []):
        if "bufferView" in desc:
            desc["bufferView"] = view_map[desc["bufferView"]]
        if "sparse" in desc:
            desc["sparse"]["indices"]["bufferView"] = view_map[desc["sparse"]["indices"]["bufferView"]]
            desc["sparse"]["values"]["bufferView"] = view_map[desc["sparse"]["values"]["bufferView"]]
    for index, (payload, mime) in enumerate(images):
        view_index = append_bytes(binary, views, payload)
        document["images"][index] = {
            "name": document["images"][index].get("name", variant + "_%d" % index),
            "bufferView": view_index,
            "mimeType": mime,
        }
    document["bufferViews"] = views
    document["buffers"] = [{"byteLength": len(binary)}]

    # Scale only inverse bind matrices, not mesh coordinates. Each target skeleton
    # supplies its own current joint globals when the named binds are resolved.
    for skin in document.get("skins", []):
        desc = document["accessors"][skin["inverseBindMatrices"]]
        view = document["bufferViews"][desc["bufferView"]]
        if desc.get("componentType") != 5126 or desc.get("type") != "MAT4":
            raise AssertionError("inverse binds must be float MAT4")
        matrices = accessor(document, binary, skin["inverseBindMatrices"])
        for index in range(desc["count"]):
            matrix = matrices[index].reshape(4, 4).T.copy()
            matrix[:3, :] *= SOURCE_SCALE
            matrices[index] = matrix.T.reshape(16)
    document.setdefault("asset", {})["extras"] = {
        "loadoutVariant": variant,
        "source": "goribby/CS2-MultiRig@026058b2a70a55257d6b85563f27b3c31e558f26",
        "sourceLicense": "not declared upstream",
    }

    while len(binary) % 4:
        binary.append(0)
    document["buffers"][0]["byteLength"] = len(binary)
    json_data = json.dumps(document, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    json_data += b" " * ((-len(json_data)) % 4)
    total = 12 + 8 + len(json_data) + 8 + len(binary)
    output = os.path.join(project, OUT_DIR, variant + ".glb")
    os.makedirs(os.path.dirname(output), exist_ok=True)
    with open(output, "wb") as handle:
        handle.write(struct.pack("<4sII", b"glTF", 2, total))
        handle.write(struct.pack("<II", len(json_data), 0x4E4F534A))
        handle.write(json_data)
        handle.write(struct.pack("<II", len(binary), 0x004E4942))
        handle.write(binary)
    print("%-24s %8.2f MiB" % (variant, os.path.getsize(output) / 1048576.0))


def main():
    if len(sys.argv) not in (2, 3):
        raise SystemExit(__doc__)
    source_root = os.path.abspath(sys.argv[1])
    project = os.path.abspath(sys.argv[2] if len(sys.argv) == 3 else ROOT)
    for variant, relative in VARIANTS.items():
        build_variant(source_root, project, variant, relative)


if __name__ == "__main__":
    main()
