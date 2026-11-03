#!/usr/bin/env python3
"""Structural and rendered-pose validation for an archi weapon build.

    PYTHONPATH=<SourceIO parent> python -m tools.source.validate_archi_build \
        /tmp/archi_build /tmp/archi_preview

Uses a small Pillow painter renderer so it can run without a Godot/X11 install.
It is intentionally a geometry/animation inspection aid, not a replacement for a
final in-engine play test.
"""
import io
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

from .build_archi_weapons import SOURCES, model_base
from .build_csco_viewmodels import GlbClipSource
from .glb_read import acc


def material_colours(js, binary):
    colours = []
    for material in js.get("materials", []):
        colour = np.array([105, 110, 118], dtype=np.float64)
        pbr = material.get("pbrMetallicRoughness", {})
        factor = pbr.get("baseColorFactor", [1, 1, 1, 1])
        if "baseColorTexture" in pbr:
            tex = js["textures"][pbr["baseColorTexture"]["index"]]
            image = js["images"][tex["source"]]
            view = js["bufferViews"][image["bufferView"]]
            raw = binary[view.get("byteOffset", 0):view.get("byteOffset", 0) + view["byteLength"]]
            try:
                pil = Image.open(io.BytesIO(raw)).convert("RGB").resize((1, 1), Image.LANCZOS)
                colour = np.array(pil.getpixel((0, 0)), dtype=np.float64)
            except Exception:
                pass
        colour *= np.array(factor[:3])
        colours.append(tuple(int(x) for x in np.clip(colour, 18, 235)))
    return colours


def skin_primitive(source, primitive, global_g, ibm, joints):
    attrs = primitive["attributes"]
    pos = acc(source.js, source.bin, attrs["POSITION"]).astype(np.float64)
    joint = acc(source.js, source.bin, attrs["JOINTS_0"]).astype(int)
    weight = acc(source.js, source.bin, attrs["WEIGHTS_0"]).astype(np.float64)
    joint_matrices = np.array([global_g[node] @ ibm[k] for k, node in enumerate(joints)])
    p4 = np.c_[pos, np.ones(len(pos))]
    skinned = np.zeros((len(pos), 3))
    for k in range(4):
        skinned += weight[:, k:k + 1] * np.einsum("nij,nj->ni", joint_matrices[joint[:, k]], p4)[:, :3]
    indices = acc(source.js, source.bin, primitive["indices"]).astype(np.int64).reshape(-1, 3)
    return skinned, indices


def pose(path, animation="idle", fraction=0.0):
    source = GlbClipSource(path)
    if animation not in source.anim_by_name:
        animation = next(iter(source.anim_by_name))
    anim = source.anim_by_name[animation]
    times = [float(acc(source.js, source.bin, sampler["input"]).reshape(-1)[-1]) for sampler in anim["samplers"]]
    target = max(times) * fraction
    global_g = source._globals(source._channel_values(anim, target))
    skin = source.js["skins"][0]
    joints = skin["joints"]
    ibm = acc(source.js, source.bin, skin["inverseBindMatrices"]).reshape(-1, 4, 4).transpose(0, 2, 1)
    parts = []
    for mesh in source.js["meshes"]:
        for primitive in mesh["primitives"]:
            pos, idx = skin_primitive(source, primitive, global_g, ibm, joints)
            parts.append((pos, idx, int(primitive["material"])))
    return source, parts


def render(path, animation="idle", fraction=0.0, size=(360, 270), right_hand=True):
    source, parts = pose(path, animation, fraction)
    width, height = size
    image = Image.new("RGB", size, (20, 24, 30))
    draw = ImageDraw.Draw(image)
    colours = material_colours(source.js, source.bin)
    triangles = []
    focal = width * 0.88
    for pos, idx, mat in parts:
        for tri in idx:
            p = pos[tri]
            if np.any(p[:, 2] > -0.035):
                continue
            depth = float(p[:, 2].mean())
            triangles.append((depth, p, mat))
    triangles.sort(key=lambda item: item[0])
    light = np.array([0.35, 0.75, 0.56])
    light /= np.linalg.norm(light)
    for _depth, p, mat in triangles:
        normal = np.cross(p[1] - p[0], p[2] - p[0])
        length = np.linalg.norm(normal)
        shade = 0.60 if length < 1e-10 else 0.48 + 0.52 * abs(float(np.dot(normal / length, light)))
        base = colours[mat] if mat < len(colours) else (110, 115, 120)
        colour = tuple(int(np.clip(c * shade, 0, 255)) for c in base)
        xy = []
        for x, y, z in p:
            if right_hand:
                x = -x
            xy.append((width * 0.50 + float(x) / -float(z) * focal,
                       height * 0.56 - float(y) / -float(z) * focal))
        draw.polygon(xy, fill=colour)
    label = os.path.basename(path) + "  " + animation
    if fraction:
        label += " @ %.2f" % fraction
    draw.rectangle((0, 0, width, 21), fill=(10, 13, 18))
    draw.text((7, 5), label, fill=(235, 238, 242))
    return image


def structural(build_dir):
    report = {"valid": True, "models": {}, "errors": []}
    for weapon in SOURCES:
        base = model_base(weapon)
        for prefix in ("v", "p", "w"):
            name = "%s_%s" % (prefix, base)
            path = os.path.join(build_dir, "weapons", name + ".glb")
            source = GlbClipSource(path)
            bad = []
            for index, accessor in enumerate(source.js.get("accessors", [])):
                if accessor["componentType"] != 5126:
                    continue
                values = acc(source.js, source.bin, index)
                if not np.isfinite(values).all():
                    bad.append(index)
            if bad:
                report["errors"].append({"model": name, "nonfinite_accessors": bad})
                report["valid"] = False
            animations = [a["name"] for a in source.js.get("animations", [])]
            if prefix == "v":
                required = ["idle"]
                if weapon not in ("knife", "flashbang", "hegrenade", "smokegrenade", "decoy", "molotov", "incendiary", "c4"):
                    if weapon == "glock18":
                        required.append("shoot")
                    elif weapon == "elite":
                        required.extend(("shoot_left1", "shoot_right1"))
                    else:
                        required.append("shoot1")
                for req in required:
                    if req not in animations:
                        report["errors"].append({"model": name, "missing_animation": req})
                        report["valid"] = False
            report["models"][name] = {"animations": animations, "materials": len(source.js.get("materials", []))}
    return report


def main():
    build_dir, out_dir = sys.argv[1:3]
    os.makedirs(out_dir, exist_ok=True)
    report = structural(build_dir)
    with open(os.path.join(out_dir, "validation.json"), "w") as handle:
        json.dump(report, handle, indent=2)
    print("structural valid:", report["valid"], "errors:", len(report["errors"]))
    thumbs = []
    for weapon in SOURCES:
        path = os.path.join(build_dir, "weapons", "v_" + model_base(weapon) + ".glb")
        print("render", weapon, flush=True)
        thumbs.append((weapon, render(path, size=(320, 240))))
    cols = 5
    rows = math.ceil(len(thumbs) / cols)
    sheet = Image.new("RGB", (cols * 320, rows * 240), (12, 15, 20))
    draw = ImageDraw.Draw(sheet)
    for index, (weapon, image) in enumerate(thumbs):
        x, y = (index % cols) * 320, (index // cols) * 240
        sheet.paste(image, (x, y))
        draw.text((x + 8, y + 224), weapon, fill=(240, 190, 80))
    sheet.save(os.path.join(out_dir, "contact.png"))

    checks = {
        "ak47": ["idle", "draw", "shoot1", "reload"],
        "usp": ["idle_unsil", "add_silencer", "shoot1", "reload"],
        "revolver": ["idle", "prepare", "fire", "alt1", "reload"],
        "m3": ["idle", "shoot1", "start_reload", "insert", "after_reload"],
        "knife": ["idle", "slash1", "midslash1", "stab"],
        "molotov": ["idle", "pullpin", "throw", "underhand"],
    }
    for weapon, animations in checks.items():
        path = os.path.join(build_dir, "weapons", "v_" + model_base(weapon) + ".glb")
        strip = Image.new("RGB", (360 * len(animations), 270), (12, 15, 20))
        for index, animation in enumerate(animations):
            strip.paste(render(path, animation, 0.45 if animation != "idle" else 0.0), (360 * index, 0))
        strip.save(os.path.join(out_dir, weapon + "_poses.png"))


if __name__ == "__main__":
    main()
