#!/usr/bin/env python3
"""Compare installed archi GLB texture coordinates with their original VVDs.

    PYTHONPATH=<SourceIO parent> python -m tools.source.verify_archi_uvs \
        <archi checkout> [project root]

Unlike a screenshot-only check, this covers every V/P/W model and detects the
incorrect V inversion that mixed neighbouring atlas islands on CS2 weapons.
"""
import json
import os
import struct
import sys

import numpy as np

from .build_archi_weapons import SOURCES, find_package, model_base, model_path
from .mdl_reader import load_model


def read_glb(path):
    with open(path, "rb") as handle:
        raw = handle.read()
    json_length = struct.unpack_from("<I", raw, 12)[0]
    document = json.loads(raw[20:20 + json_length])
    binary = raw[20 + json_length + 8:]
    return document, binary


def accessor(document, binary, index):
    acc = document["accessors"][index]
    view = document["bufferViews"][acc["bufferView"]]
    components = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[acc["type"]]
    dtype = {5126: "<f4", 5125: "<u4", 5123: "<u2", 5121: "u1"}[acc["componentType"]]
    item_size = np.dtype(dtype).itemsize * components
    stride = view.get("byteStride", item_size)
    assert stride == item_size, "interleaved accessor audit is not implemented"
    offset = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    return np.frombuffer(binary, dtype=dtype, count=acc["count"] * components,
                         offset=offset).reshape(-1, components)


def compare_view(weapon, package, project):
    model = load_model(model_path(package, SOURCES[weapon][1]))
    path = os.path.join(project, "assets/models/weapons", "v_%s.glb" % model_base(weapon))
    document, binary = read_glb(path)
    primitives = document["meshes"][0]["primitives"]
    assert len(primitives) >= len(model["meshes"]), weapon
    errors = 0
    vertices = 0
    for index, mesh in enumerate(model["meshes"]):
        actual = np.asarray(accessor(document, binary, primitives[index]["attributes"]["TEXCOORD_0"]))
        expected = np.asarray(mesh["uv"], dtype=np.float32)
        if actual.shape != expected.shape:
            raise AssertionError("%s view primitive %d shape %s != %s" %
                                 (weapon, index, actual.shape, expected.shape))
        errors += int(np.count_nonzero(np.max(np.abs(actual - expected), axis=1) > 0.000002))
        vertices += len(actual)
    if errors:
        raise AssertionError("%s: %d view UVs do not match the VVD" % (weapon, errors))
    return vertices


def compare_world(weapon, package, project):
    stem = "w_" + SOURCES[weapon][1][2:]
    if weapon == "m249":
        stem = "w_mach_m249"
    model = load_model(model_path(package, stem))
    meshes = model["meshes"]
    if weapon == "elite":
        meshes = [mesh for mesh in meshes if "right" in str(mesh.get("model", "")).lower()]
    expected = set()
    for mesh in meshes:
        for uv in np.round(np.asarray(mesh["uv"]), 5):
            expected.add((float(uv[0]), float(uv[1])))
    vertices = 0
    for prefix in ("p", "w"):
        path = os.path.join(project, "assets/models/weapons", "%s_%s.glb" % (prefix, model_base(weapon)))
        document, binary = read_glb(path)
        errors = 0
        for mesh in document["meshes"]:
            for primitive in mesh["primitives"]:
                actual = np.asarray(accessor(document, binary, primitive["attributes"]["TEXCOORD_0"]))
                vertices += len(actual)
                # Round in float64: rounded float32 values have a different
                # binary representation and must not create false mismatches.
                for uv in np.round(np.asarray(actual, dtype=np.float64), 5):
                    if (float(uv[0]), float(uv[1])) not in expected:
                        errors += 1
        if errors:
            raise AssertionError("%s_%s: %d world UVs do not match the VVD" % (prefix, weapon, errors))
    return vertices


def main():
    archi = sys.argv[1]
    project = os.path.abspath(sys.argv[2] if len(sys.argv) > 2 else
                              os.path.join(os.path.dirname(__file__), "../.."))
    view_vertices = 0
    world_vertices = 0
    for weapon in SOURCES:
        package = find_package(archi, weapon)
        view_vertices += compare_view(weapon, package, project)
        world_vertices += compare_world(weapon, package, project)
        print("UV OK", weapon, flush=True)
    print("PASS: 43 V + 86 P/W models match original VVD UVs; %d coordinates checked" %
          (view_vertices + world_vertices))


if __name__ == "__main__":
    main()
