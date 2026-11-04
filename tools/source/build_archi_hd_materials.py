#!/usr/bin/env python3
"""Build shared 2K archi colour/normal/phong-roughness textures and a runtime catalog.

    python -m tools.source.build_archi_hd_materials /tmp/archi /home/user/15
    python -m tools.source.build_archi_hd_materials --check /home/user/15

The GLBs keep their calibrated embedded fallback images. GameData replaces only
weapon-material textures at runtime, so v_/p_/w_ models share one decoded copy.
Original arms/gloves, geometry, UVs, tint factors and special Molotov shaders are
not rebuilt. Source normal maps need their green channel inverted for Godot.
The _m red channel is a Phong exponent, NOT metalness: it becomes a subtle
roughness multiplier (1 - 0.30 * red) while the accepted metallic finish stays.
"""
import hashlib
import io
import json
import os
import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

import numpy as np
from PIL import Image
from srctools.vtf import VTF

from .refine_weapon_animations import read_glb

ROOT = Path(__file__).resolve().parents[2]
OUT_REL = Path("assets/textures/archi")
CATALOG_REL = Path("data/archi_materials.json")
MAX_SIZE = 2048
KINDS = ("color", "normal", "roughness")


def _value(text, key):
    pattern = r"(?im)^\s*[\"']?\\?" + re.escape(key) + r"[\"']?\s+([^\r\n]+)"
    match = re.search(pattern, text)
    if not match:
        return None
    value = match.group(1).strip()
    quoted = re.match(r"[\"']([^\"']+)[\"']", value)
    return quoted.group(1) if quoted else value.split()[0]


def _bool_value(text, key):
    return (_value(text, key) or "0").strip("\"'") not in ("0", "0.0", "")


def _tint(text):
    match = re.search(r"(?im)^\s*[\"']?\$color2[\"']?\s+[\"']?\[([^]]+)\]", text)
    if not match:
        return None
    try:
        values = [float(value) for value in match.group(1).replace(",", " ").split()[:3]]
        return [max(0.0, min(1.0, value)) for value in values] if len(values) == 3 else None
    except ValueError:
        return None


def _material_names(project):
    names = set()
    folder = project / "assets/models/weapons"
    for path in sorted(folder.glob("*.glb")):
        if not path.stem.startswith(("v_", "p_", "w_")):
            continue
        document, _binary = read_glb(str(path))
        for material in document.get("materials", []):
            names.add(str(material.get("name", "")).lower())
    return names


def _choose_vmt(candidates):
    def score(path):
        text = path.as_posix()
        return (0 if "/Vanilla (Default)/" in text else 1,
                0 if "/m_cs2_knife_kukri/" in text else 1,
                0 if "/m_cs2_fiveseven/" in text else 1,
                len(text), text)
    return sorted(candidates, key=score)[0]


def _vmt_index(source):
    result = defaultdict(list)
    for path in source.glob("CS2GO*/**/*.vmt"):
        result[path.stem.lower()].append(path)
    return result


def _materials_root(vmt_path):
    for parent in vmt_path.parents:
        if parent.name == "materials":
            return parent
    raise ValueError("VMT is outside a materials directory: " + str(vmt_path))


def _texture(materials_root, reference):
    if not reference:
        return None
    normalized = reference.replace("\\", "/").strip("/")
    if normalized.startswith("dev/"):
        return None  # engine-provided flat normals are not shipped by archi
    path = materials_root / (normalized + ".vtf")
    return path if path.is_file() else None


def _resize(image):
    image = image.copy()
    if max(image.size) > MAX_SIZE:
        width, height = image.size
        if width >= height:
            size = (MAX_SIZE, max(1, round(height * MAX_SIZE / width)))
        else:
            size = (max(1, round(width * MAX_SIZE / height)), MAX_SIZE)
        image = image.resize(size, Image.Resampling.LANCZOS)
    return image


def _decode(path, keep_alpha=True):
    with path.open("rb") as handle:
        image = VTF.read(handle).get().to_PIL()
        # Pillow premultiplies RGB while resizing RGBA. Keep the established
        # colour/tint-mask pipeline, but never let a data map's unrelated alpha
        # channel attenuate normal XYZ or the red Phong exponent channel.
        if not keep_alpha:
            image = image.convert("RGB")
        return _resize(image)


def _encode_color(image, jpeg, masked_tint):
    image = image.convert("RGBA" if masked_tint is not None or not jpeg else "RGB")
    if masked_tint is not None:
        # Same linear-space Source tint operation as the calibrated GLB builder.
        pixels = np.asarray(image, dtype=np.float32) / 255.0
        srgb = pixels[..., :3]
        linear = np.where(srgb <= 0.04045, srgb / 12.92,
                          ((srgb + 0.055) / 1.055) ** 2.4)
        tint = np.asarray(masked_tint, dtype=np.float32).reshape(1, 1, 3)
        linear *= 1.0 + (tint - 1.0) * pixels[..., 3:4]
        srgb = np.where(linear <= 0.0031308, linear * 12.92,
                        1.055 * np.maximum(linear, 0.0) ** (1.0 / 2.4) - 0.055)
        if jpeg:
            image = Image.fromarray(np.uint8(np.clip(srgb, 0.0, 1.0) * 255.0 + 0.5), "RGB")
        else:
            pixels[..., :3] = srgb
            image = Image.fromarray(np.uint8(np.clip(pixels, 0.0, 1.0) * 255.0 + 0.5), "RGBA")
    buffer = io.BytesIO()
    if jpeg:
        image.save(buffer, "JPEG", quality=93, subsampling=0, optimize=True)
    else:
        image.save(buffer, "PNG", optimize=True)
    return buffer.getvalue(), ".jpg" if jpeg else ".png"


def _encode_normal(image):
    image = image.convert("RGB")
    red, green, blue = image.split()
    image = Image.merge("RGB", (red, green.point(lambda value: 255 - value), blue))
    buffer = io.BytesIO()
    # 4:4:4 avoids chroma smearing on tangent-space normals; q96 keeps the
    # original detail with a small quantization error and manageable VRAM/files.
    image.save(buffer, "JPEG", quality=96, subsampling=0, optimize=True)
    return buffer.getvalue(), ".jpg"


def _encode_roughness(image):
    red = image.convert("RGBA").getchannel("R")
    # StandardMaterial3D multiplies this texture by the established roughness.
    # High Source exponents become subtly glossier, never rougher than before.
    multiplier = red.point(lambda value: max(0, min(255, round(255.0 * (1.0 - 0.30 * value / 255.0)))))
    buffer = io.BytesIO()
    multiplier.save(buffer, "JPEG", quality=95, optimize=True)
    return buffer.getvalue(), ".jpg"


def _source_commit(source):
    try:
        return subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def _build(source, project):
    source = source.resolve()
    project = project.resolve()
    out_dir = project / OUT_REL
    out_dir.mkdir(parents=True, exist_ok=True)
    index = _vmt_index(source)
    tasks = {}
    missing = []
    for material_name in sorted(_material_names(project)):
        candidates = index.get(material_name, [])
        if not candidates:
            missing.append(material_name)
            continue
        vmt_path = _choose_vmt(candidates)
        materials_root = _materials_root(vmt_path)
        text = vmt_path.read_text(encoding="utf-8", errors="ignore")
        base_reference = _value(text, "$basetexture")
        base_path = _texture(materials_root, base_reference)
        if base_path is None:
            missing.append(material_name)
            continue
        alpha = any(_bool_value(text, key) for key in ("$alphatest", "$translucent", "$additive"))
        blend_tint = _bool_value(text, "$blendtintbybasealpha")
        tint = _tint(text)
        masked_tint = tint if tint is not None and blend_tint else None
        tasks[material_name] = {
            "vmt": vmt_path,
            "color": (base_path, not alpha, masked_tint),
            "normal": (_texture(materials_root, _value(text, "$bumpmap")),),
            "roughness": (_texture(materials_root, _value(text, "$phongexponenttexture")),),
        }

    assets_by_key = {}
    names_by_key = {}
    used_names = {}
    catalog = {}
    total_bytes = 0
    for material_name, task in sorted(tasks.items()):
        entry = {"source_vmt": task["vmt"].relative_to(source).as_posix()}
        for kind in KINDS:
            arguments = task[kind]
            path = arguments[0]
            if path is None:
                continue
            source_hash = hashlib.sha256(path.read_bytes()).hexdigest()
            # Colour pixels also depend on Source alpha/tint treatment. Normal
            # and roughness assets depend only on their source texels.
            semantic_key = ((arguments[1], tuple(arguments[2]) if arguments[2] is not None else None)
                            if kind == "color" else ())
            key = (kind, source_hash, semantic_key)
            if key not in assets_by_key:
                stem = path.stem
                stem = re.sub(r"_(?:c|n|m)$", "", stem, flags=re.IGNORECASE)
                extension = ".jpg" if kind != "color" or arguments[1] else ".png"
                filename = "%s_%s%s" % (stem, kind, extension)
                if filename in used_names and used_names[filename] != key:
                    filename = "%s_%s_%s%s" % (stem, kind, source_hash[:8], extension)
                used_names[filename] = key
                image = _decode(path, keep_alpha=kind == "color")
                if kind == "color":
                    data, extension = _encode_color(image, arguments[1], arguments[2])
                    if extension != ".jpg":
                        filename = filename[:-4] + extension
                        used_names[filename] = key
                elif kind == "normal":
                    data, extension = _encode_normal(image)
                else:
                    data, extension = _encode_roughness(image)
                destination = out_dir / filename
                destination.write_bytes(data)
                total_bytes += len(data)
                assets_by_key[key] = {"path": "res://" + (OUT_REL / filename).as_posix(),
                                      "size": list(image.size), "sha256": hashlib.sha256(data).hexdigest()}
            entry[kind] = assets_by_key[key]["path"]
            entry[kind + "_size"] = assets_by_key[key]["size"]
        catalog[material_name] = entry

    document = {
        "source": "ShadowNigth/archi",
        "source_commit": _source_commit(source),
        "max_resolution": MAX_SIZE,
        "normal_convention": "Source tangent space with green channel inverted for Godot (+Y)",
        "roughness_convention": "source _m red Phong exponent -> 1 - 0.30 * red multiplier; never metalness",
        "materials": catalog,
    }
    catalog_path = project / CATALOG_REL
    catalog_path.write_text(json.dumps(document, indent=2, ensure_ascii=False, sort_keys=True) + "\n",
                            encoding="utf-8")
    print("Built %d material entries, %d shared textures (%.1f MiB)" %
          (len(catalog), len(assets_by_key), total_bytes / 1024 ** 2))
    print("Materials without an archi VMT/base texture (left unchanged):", ", ".join(sorted(missing)))
    return document


def _check(project):
    project = project.resolve()
    document = json.loads((project / CATALOG_REL).read_text(encoding="utf-8"))
    materials = document.get("materials", {})
    if len(materials) < 40:
        raise AssertionError("incomplete archi material catalog")
    checked = set()
    hd_counts = {kind: 0 for kind in KINDS}
    for name, entry in materials.items():
        if "arms" in name or "glove" in name:
            raise AssertionError("character material must not be enhanced: " + name)
        for kind in KINDS:
            relative = entry.get(kind)
            if not relative:
                continue
            path = project / relative.removeprefix("res://")
            if not path.is_file():
                raise FileNotFoundError(path)
            with Image.open(path) as image:
                expected = tuple(entry[kind + "_size"])
                if image.size != expected:
                    raise AssertionError("%s size differs for %s" % (name, kind))
                if max(image.size) > MAX_SIZE:
                    raise AssertionError("oversized texture: " + str(path))
                if max(image.size) == MAX_SIZE:
                    hd_counts[kind] += 1
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            identity = (relative, digest)
            if identity in checked:
                continue
            checked.add(identity)
    # Small engine-style lens/liquid images are valid at their native size;
    # require the substantial 2K weapon set instead of rejecting those files.
    if min(hd_counts.values()) < 40:
        raise AssertionError("incomplete 2K weapon texture set: %s" % hd_counts)
    print("PASS: %d materials, %d shared HD texture files; 2K entries %s" %
          (len(materials), len(checked), hd_counts))


def main():
    check_only = "--check" in sys.argv[1:]
    args = [arg for arg in sys.argv[1:] if arg != "--check"]
    if check_only:
        if len(args) > 1:
            raise SystemExit(__doc__)
        _check(Path(args[0]) if args else ROOT)
        return
    if len(args) not in (1, 2):
        raise SystemExit(__doc__)
    _build(Path(args[0]), Path(args[1]) if len(args) == 2 else ROOT)


if __name__ == "__main__":
    main()
