#!/usr/bin/env python3
"""Repair attachment and slide tracks without rebuilding any weapon meshes.

    python -m tools.source.refine_weapon_animations [project root]
    python -m tools.source.refine_weapon_animations --check [project root]

Only these tracks are replaced:
  * M4A1 / USP: gun attachment translation + rotation during both inspections.
  * Glock18: slide translation during shoot, shoot2, shoot3 and shoot_empty.

All mesh primitives, UVs, images, materials, nodes and skins remain untouched.
New animation accessors are appended to the existing binary buffer. This is NOT
the historical UV migration and must never be replaced by that one-way pass.
"""
import copy
import json
import math
import os
import struct
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
MODEL_DIR = os.path.join("assets", "models", "weapons")
INSPECTIONS = {
    "v_m4a1": {
        "node": "v_weapon.M4A1_s_Parent",
        "clips": {"inspect": "idle", "inspect_unsil": "idle_unsil"},
    },
    "v_usp": {
        "node": "weapon_hand_r",
        "clips": {"inspect": "idle", "inspect_unsil": "idle_unsil"},
    },
}
GLOCK_CLIPS = ("shoot", "shoot2", "shoot3", "shoot_empty")
COMPONENTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def read_glb(path):
    raw = open(path, "rb").read()
    if raw[:4] != b"glTF" or struct.unpack_from("<I", raw, 4)[0] != 2:
        raise ValueError("not a glTF 2 GLB: " + path)
    offset = 12
    document = None
    binary = None
    while offset < len(raw):
        length, kind = struct.unpack_from("<II", raw, offset)
        data = raw[offset + 8:offset + 8 + length]
        if kind == 0x4E4F534A:
            document = json.loads(data.decode("utf-8"))
        elif kind == 0x004E4942:
            binary = bytearray(data)
        offset += 8 + length
    if document is None or binary is None:
        raise ValueError("incomplete GLB: " + path)
    return document, binary


def write_glb(path, document, binary):
    while len(binary) % 4:
        binary.append(0)
    document["buffers"][0]["byteLength"] = len(binary)
    json_data = json.dumps(document, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    json_data += b" " * ((-len(json_data)) % 4)
    total = 12 + 8 + len(json_data) + 8 + len(binary)
    with open(path, "wb") as handle:
        handle.write(struct.pack("<4sII", b"glTF", 2, total))
        handle.write(struct.pack("<II", len(json_data), 0x4E4F534A))
        handle.write(json_data)
        handle.write(struct.pack("<II", len(binary), 0x004E4942))
        handle.write(binary)


def animation(document, name):
    matches = [item for item in document.get("animations", []) if item.get("name") == name]
    if len(matches) != 1:
        raise AssertionError("expected one animation %s, got %d" % (name, len(matches)))
    return matches[0]


def node_index(document, name):
    matches = [index for index, node in enumerate(document.get("nodes", []))
               if node.get("name") == name]
    if len(matches) != 1:
        raise AssertionError("expected one node %s, got %d" % (name, len(matches)))
    return matches[0]


def channel_for(document, clip, node_name, path):
    target_node = node_index(document, node_name)
    matches = [(channel, clip["samplers"][channel["sampler"]])
               for channel in clip["channels"]
               if channel["target"].get("node") == target_node
               and channel["target"].get("path") == path]
    if len(matches) != 1:
        raise AssertionError("expected %s/%s/%s channel" % (clip["name"], node_name, path))
    return matches[0]


def accessor_values(document, binary, index):
    accessor = document["accessors"][index]
    if accessor.get("componentType") != 5126:
        raise AssertionError("animation accessor must be float32")
    view = document["bufferViews"][accessor["bufferView"]]
    count = accessor["count"]
    width = COMPONENTS[accessor["type"]]
    stride = view.get("byteStride", width * 4)
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    values = []
    for item in range(count):
        values.append(struct.unpack_from("<%df" % width, binary, start + item * stride))
    return values


def append_accessor(document, binary, values, value_type):
    width = COMPONENTS[value_type]
    if value_type == "SCALAR":
        values = [(float(value),) for value in values]
    if not values or any(len(value) != width for value in values):
        raise AssertionError("invalid accessor values")
    while len(binary) % 4:
        binary.append(0)
    payload = b"".join(struct.pack("<%df" % width, *value) for value in values)
    view_index = len(document["bufferViews"])
    document["bufferViews"].append({
        "buffer": 0,
        "byteOffset": len(binary),
        "byteLength": len(payload),
    })
    binary.extend(payload)
    minima = [min(value[axis] for value in values) for axis in range(width)]
    maxima = [max(value[axis] for value in values) for axis in range(width)]
    accessor_index = len(document["accessors"])
    document["accessors"].append({
        "bufferView": view_index,
        "componentType": 5126,
        "count": len(values),
        "type": value_type,
        "min": minima,
        "max": maxima,
    })
    return accessor_index


def refine_inspection_model(document, binary, model):
    config = INSPECTIONS[model]
    report = []
    for clip_name, idle_name in config["clips"].items():
        idle = animation(document, idle_name)
        clip = animation(document, clip_name)
        for path in ("translation", "rotation"):
            _, idle_sampler = channel_for(document, idle, config["node"], path)
            reference = accessor_values(document, binary, idle_sampler["output"])[0]
            channel, sampler = channel_for(document, clip, config["node"], path)
            old = accessor_values(document, binary, sampler["output"])
            deviation = max(math.sqrt(sum((value[axis] - reference[axis]) ** 2
                                          for axis in range(len(reference)))) for value in old)
            sampler["output"] = append_accessor(
                document, binary, [reference] * len(old), "VEC4" if path == "rotation" else "VEC3")
            report.append("%s/%s/%s: removed %.6f attachment deviation" %
                          (model, clip_name, path, deviation))
    return report


def refine_glock(document, binary):
    _, idle_sampler = channel_for(document, animation(document, "idle"),
                                  "v_weapon_glock_slide", "translation")
    base = accessor_values(document, binary, idle_sampler["output"])[0]
    _, reload_sampler = channel_for(document, animation(document, "reload"),
                                    "v_weapon_glock_slide", "translation")
    reload_values = accessor_values(document, binary, reload_sampler["output"])
    recoil = max((tuple(value[axis] - base[axis] for axis in range(3))
                  for value in reload_values), key=lambda value: sum(axis * axis for axis in value))
    travel = math.sqrt(sum(axis * axis for axis in recoil))
    if not 0.035 <= travel <= 0.065:
        raise AssertionError("unexpected Glock slide travel: %.6f" % travel)

    report = ["Glock slide travel reused from reload: %.6f m" % travel]
    for clip_name in GLOCK_CLIPS:
        clip = animation(document, clip_name)
        channel, sampler = channel_for(document, clip, "v_weapon_glock_slide", "translation")
        times = [value[0] for value in accessor_values(document, binary, sampler["input"])]
        duration = max(times)
        frame = 1.0 / 30.0  # Godot's GLTF importer bakes these bone tracks at 30 Hz.
        if duration <= 4.0 * frame:
            raise AssertionError("Glock firing clip is too short for its authored cycle")
        locked = clip_name == "shoot_empty"
        # Frame-aligned peaks survive GLTF resampling without losing travel.
        profile = ([(0.0, 0.0), (frame, 0.0), (2.0 * frame, 1.0), (duration, 1.0)] if locked else
                   [(0.0, 0.0), (frame, 0.0), (2.0 * frame, 1.0),
                    (3.0 * frame, 0.12), (4.0 * frame, 0.0), (duration, 0.0)])
        values = [tuple(base[axis] + recoil[axis] * amount for axis in range(3))
                  for _, amount in profile]
        new_sampler = {
            "input": append_accessor(document, binary, [time for time, _ in profile], "SCALAR"),
            "output": append_accessor(document, binary, values, "VEC3"),
            "interpolation": "LINEAR",
        }
        clip["samplers"].append(new_sampler)
        channel["sampler"] = len(clip["samplers"]) - 1
        report.append("v_glock18/%s: %s" %
                      (clip_name, "locked open" if locked else "full slide cycle"))
    return report


def verify(document, binary, model):
    if model in INSPECTIONS:
        config = INSPECTIONS[model]
        for clip_name, idle_name in config["clips"].items():
            idle = animation(document, idle_name)
            clip = animation(document, clip_name)
            for path in ("translation", "rotation"):
                _, idle_sampler = channel_for(document, idle, config["node"], path)
                reference = accessor_values(document, binary, idle_sampler["output"])[0]
                _, sampler = channel_for(document, clip, config["node"], path)
                values = accessor_values(document, binary, sampler["output"])
                for value in values:
                    error = max(abs(value[axis] - reference[axis]) for axis in range(len(reference)))
                    if error > 0.000002:
                        raise AssertionError("%s/%s attachment is not stable" % (model, clip_name))
    if model == "v_glock18":
        _, idle_sampler = channel_for(document, animation(document, "idle"),
                                      "v_weapon_glock_slide", "translation")
        base = accessor_values(document, binary, idle_sampler["output"])[0]
        for clip_name in GLOCK_CLIPS:
            clip = animation(document, clip_name)
            _, sampler = channel_for(document, clip, "v_weapon_glock_slide", "translation")
            values = accessor_values(document, binary, sampler["output"])
            travel = max(math.sqrt(sum((value[axis] - base[axis]) ** 2 for axis in range(3)))
                         for value in values)
            if travel < 0.035:
                raise AssertionError("Glock %s has no slide travel" % clip_name)
            final_error = math.sqrt(sum((values[-1][axis] -
                                         (base[axis] if clip_name != "shoot_empty" else
                                          values[2][axis])) ** 2 for axis in range(3)))
            if final_error > 0.000002:
                raise AssertionError("Glock %s has wrong final slide pose" % clip_name)


def refine_model(project, model, check_only):
    path = os.path.join(project, MODEL_DIR, model + ".glb")
    document, binary = read_glb(path)
    verify_before = copy.deepcopy({key: document.get(key) for key in
                                   ("nodes", "meshes", "materials", "textures", "images", "skins")})
    accessor_count = len(document["accessors"])
    view_count = len(document["bufferViews"])
    original_binary = bytes(binary)
    if check_only:
        verify(document, binary, model)
        print("PASS", model)
        return
    try:
        verify(document, binary, model)
        print("PASS", model, "already refined; no bytes appended")
        return
    except AssertionError:
        pass
    if model in INSPECTIONS:
        report = refine_inspection_model(document, binary, model)
    else:
        report = refine_glock(document, binary)
    if {key: document.get(key) for key in verify_before} != verify_before:
        raise AssertionError("mesh/material/skeleton data changed in " + model)
    if bytes(binary[:len(original_binary)]) != original_binary:
        raise AssertionError("existing binary data changed in " + model)
    if document["accessors"][:accessor_count] != read_glb(path)[0]["accessors"]:
        raise AssertionError("existing accessors changed in " + model)
    if document["bufferViews"][:view_count] != read_glb(path)[0]["bufferViews"]:
        raise AssertionError("existing buffer views changed in " + model)
    verify(document, binary, model)
    write_glb(path, document, binary)
    verified_document, verified_binary = read_glb(path)
    verify(verified_document, verified_binary, model)
    for line in report:
        print(line)


def main():
    check_only = "--check" in sys.argv[1:]
    arguments = [arg for arg in sys.argv[1:] if arg != "--check"]
    if len(arguments) > 1 or any(arg.startswith("--") for arg in arguments):
        raise SystemExit(__doc__)
    project = os.path.abspath(arguments[0] if arguments else ROOT)
    for model in ("v_m4a1", "v_usp", "v_glock18"):
        refine_model(project, model, check_only)


if __name__ == "__main__":
    main()
