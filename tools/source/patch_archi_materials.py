#!/usr/bin/env python3
"""Patch only corrected archi material images in an existing calibrated GLB set.

    python -m tools.source.patch_archi_materials /tmp/archi_build/weapons

The full archi builder is authoritative for source conversion.  This texture-only
installer is intentionally narrower: it matches materials by index/name, replaces
changed embedded image bufferViews, and preserves every geometry, skin and
animation bufferView byte-for-byte.  Use it when a material fix must not alter the
already inspected weapon poses or optional animation clips.
"""
import json
import os
import struct
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]


def read_glb(path):
    raw = path.read_bytes()
    if len(raw) < 28:
        raise ValueError("truncated GLB: " + str(path))
    magic, version, total = struct.unpack_from("<III", raw, 0)
    if magic != 0x46546C67 or version != 2 or total != len(raw):
        raise ValueError("invalid GLB header: " + str(path))
    json_length, json_type = struct.unpack_from("<II", raw, 12)
    if json_type != 0x4E4F534A:
        raise ValueError("missing GLB JSON chunk: " + str(path))
    json_start = 20
    bin_header = json_start + json_length
    bin_length, bin_type = struct.unpack_from("<II", raw, bin_header)
    if bin_type != 0x004E4942:
        raise ValueError("missing GLB BIN chunk: " + str(path))
    document = json.loads(raw[json_start:bin_header].decode("utf-8"))
    binary = raw[bin_header + 8:bin_header + 8 + bin_length]
    return document, binary


def view_bytes(document, binary, index):
    view = document["bufferViews"][index]
    start = view.get("byteOffset", 0)
    return binary[start:start + view["byteLength"]]


def material_image(document, binary, material):
    pbr = material["pbrMetallicRoughness"]
    texture = document["textures"][pbr["baseColorTexture"]["index"]]
    image_index = texture["source"]
    image = document["images"][image_index]
    view_index = image["bufferView"]
    return image_index, view_index, image["mimeType"], view_bytes(document, binary, view_index)


def patch_model(destination, reference, dry_run=False):
    old_js, old_bin = read_glb(destination)
    new_js, new_bin = read_glb(reference)
    old_materials = old_js.get("materials", [])
    new_materials = new_js.get("materials", [])
    if len(old_materials) != len(new_materials):
        raise ValueError("material count differs: " + destination.name)
    replacements = {}
    changed = 0
    for index, (old_mat, new_mat) in enumerate(zip(old_materials, new_materials)):
        if old_mat.get("name") != new_mat.get("name"):
            raise ValueError("material slot %d differs: %s" % (index, destination.name))
        old_pbr = old_mat.get("pbrMetallicRoughness", {})
        new_pbr = new_mat.get("pbrMetallicRoughness", {})
        if old_pbr.get("baseColorFactor") != new_pbr.get("baseColorFactor"):
            raise ValueError("unexpected colour-factor change: %s/%s" % (destination.name, old_mat.get("name")))
        if "baseColorTexture" not in old_pbr and "baseColorTexture" not in new_pbr:
            continue
        old_image, old_view, old_mime, old_data = material_image(old_js, old_bin, old_mat)
        new_image, new_view, new_mime, new_data = material_image(new_js, new_bin, new_mat)
        if old_mime != new_mime:
            raise ValueError("image MIME changed: %s/%s" % (destination.name, old_mat.get("name")))
        if old_data == new_data:
            continue
        if old_view in replacements and replacements[old_view] != new_data:
            raise ValueError("shared image view has conflicting replacements: " + destination.name)
        replacements[old_view] = new_data
        old_js["images"][old_image]["mimeType"] = new_mime
        changed += 1

    if not changed or dry_run:
        return changed

    output = bytearray()
    for index, old_view in enumerate(old_js.get("bufferViews", [])):
        while len(output) % 4:
            output.append(0)
        data = replacements.get(index, view_bytes(old_js, old_bin, index))
        old_view["byteOffset"] = len(output)
        old_view["byteLength"] = len(data)
        output.extend(data)
    while len(output) % 4:
        output.append(0)
    if old_js.get("buffers"):
        old_js["buffers"][0]["byteLength"] = len(output)

    json_data = json.dumps(old_js, separators=(",", ":")).encode("utf-8")
    json_data += b" " * ((-len(json_data)) % 4)
    total = 12 + 8 + len(json_data) + 8 + len(output)
    result = bytearray(struct.pack("<III", 0x46546C67, 2, total))
    result.extend(struct.pack("<II", len(json_data), 0x4E4F534A))
    result.extend(json_data)
    result.extend(struct.pack("<II", len(output), 0x004E4942))
    result.extend(output)
    temporary = destination.with_suffix(".glb.tmp")
    temporary.write_bytes(result)
    os.replace(temporary, destination)
    return changed


def main():
    if len(sys.argv) not in (2, 3, 4):
        raise SystemExit("usage: python -m tools.source.patch_archi_materials REFERENCE_DIR [DESTINATION_DIR] [--dry-run]")
    reference_dir = Path(sys.argv[1])
    destination_dir = Path(sys.argv[2]) if len(sys.argv) >= 3 and sys.argv[2] != "--dry-run" else REPO / "assets" / "models" / "weapons"
    dry_run = "--dry-run" in sys.argv[3:] or (len(sys.argv) == 3 and sys.argv[2] == "--dry-run")
    models = 0
    images = 0
    for reference in sorted(reference_dir.glob("*.glb")):
        destination = destination_dir / reference.name
        if not destination.exists():
            raise FileNotFoundError(destination)
        changed = patch_model(destination, reference, dry_run)
        if changed:
            models += 1
            images += changed
    print(("%s: %d corrected images across %d calibrated GLBs; all non-image bufferViews preserved" %
           ("Would patch" if dry_run else "Patched", images, models)))


if __name__ == "__main__":
    main()
