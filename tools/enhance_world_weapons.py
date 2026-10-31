#!/usr/bin/env python3
"""
Enhances GoldSrc world & third-person weapon textures inside assets/models/weapons/[wp]_*.glb:
  1. Rasterizes exact mesh UV triangles (TEXCOORD_0) and pads ONLY pure-black (0,0,0) pixels strictly
     outside UV islands (3px) so bilinear/mipmap filtering never bleeds black gutter into silhouette seams,
     while 100% preserving black barrels, scopes, rails, and grips inside UV islands.
  2. Applies hue-preserving luminance shadow-lift (exact RGB ratios preserved — zero orange/yellow hue shift!)
     so dark sRGB-crushed gunmetal details (selector switches, rails, rivets, receiver grooves) become crisp and readable.
  3. Upscales 2x-3x (Lanczos + UnsharpMask) and packs compact 8-bit mode='P' PNGs with LINEAR_MIPMAP_LINEAR samplers.
"""
import glob
import io
import json
import os
import struct
import subprocess
import numpy as np
from PIL import Image, ImageDraw, ImageFilter


def load_original_glb_bytes(path: str) -> bytes:
    raw = open(path, "rb").read()
    jlen, _ = struct.unpack("<II", raw[12:20])
    gltf = json.loads(raw[20 : 20 + jlen].decode("utf-8"))
    if gltf.get("asset", {}).get("w_tex_enhanced"):
        res = subprocess.run(["git", "show", f"HEAD:{path}"], capture_output=True)
        if res.returncode == 0 and len(res.stdout) > 32:
            return res.stdout
    return raw


def build_uv_mask_for_image(gltf: dict, bin_data: bytes, img_idx: int, w: int, h: int) -> np.ndarray:
    tex_indices = {ti for ti, t in enumerate(gltf.get("textures", [])) if t.get("source") == img_idx}
    mat_indices = set()
    for mi, m in enumerate(gltf.get("materials", [])):
        pbr = m.get("pbrMetallicRoughness", {})
        bct = pbr.get("baseColorTexture", {})
        if bct.get("index") in tex_indices:
            mat_indices.add(mi)

    mask_img = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(mask_img)
    drew_any = False

    for mesh in gltf.get("meshes", []):
        for prim in mesh.get("primitives", []):
            if prim.get("material") not in mat_indices:
                continue
            uv_acc_idx = prim.get("attributes", {}).get("TEXCOORD_0")
            idx_acc_idx = prim.get("indices")
            if uv_acc_idx is None or idx_acc_idx is None:
                continue
            uv_acc = gltf["accessors"][uv_acc_idx]
            bv_uv = gltf["bufferViews"][uv_acc["bufferView"]]
            uvs = np.frombuffer(
                bin_data[bv_uv["byteOffset"] : bv_uv["byteOffset"] + bv_uv["byteLength"]],
                dtype=np.float32,
            ).reshape(-1, 2)

            idx_acc = gltf["accessors"][idx_acc_idx]
            bv_i = gltf["bufferViews"][idx_acc["bufferView"]]
            dt = np.uint16 if idx_acc["componentType"] == 5123 else np.uint32
            tris = np.frombuffer(
                bin_data[bv_i["byteOffset"] : bv_i["byteOffset"] + bv_i["byteLength"]],
                dtype=dt,
            ).reshape(-1, 3)

            for t0, t1, t2 in tris:
                u0, v0 = float(np.clip(uvs[t0, 0], 0.0, 1.0)), float(np.clip(uvs[t0, 1], 0.0, 1.0))
                u1, v1 = float(np.clip(uvs[t1, 0], 0.0, 1.0)), float(np.clip(uvs[t1, 1], 0.0, 1.0))
                u2, v2 = float(np.clip(uvs[t2, 0], 0.0, 1.0)), float(np.clip(uvs[t2, 1], 0.0, 1.0))
                pts = [
                    (u0 * (w - 1), v0 * (h - 1)),
                    (u1 * (w - 1), v1 * (h - 1)),
                    (u2 * (w - 1), v2 * (h - 1)),
                ]
                draw.polygon(pts, fill=255, outline=255)
                drew_any = True

    arr = np.asarray(mask_img, dtype=np.uint8) > 0
    if not drew_any or arr.sum() < 16:
        return np.ones((h, w), dtype=bool)
    return arr


def pad_outside_black_gutter(rgb: np.ndarray, uv_mask: np.ndarray, passes: int = 3) -> np.ndarray:
    """Pads ONLY pure-black (<=2) texels strictly outside uv_mask so weapon pixels are 100% untouched."""
    out = rgb.copy()
    max_ch = out.max(axis=2)
    known = uv_mask | (max_ch > 2.0)

    offsets = [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (-1, 1), (1, -1), (1, 1)]
    for _ in range(passes):
        if known.all():
            break
        acc = np.zeros_like(out, dtype=np.float32)
        cnt = np.zeros(known.shape, dtype=np.float32)
        for dy, dx in offsets:
            shifted_k = np.roll(np.roll(known, dy, axis=0), dx, axis=1)
            shifted_c = np.roll(np.roll(out, dy, axis=0), dx, axis=1)
            acc += shifted_c * shifted_k[:, :, None]
            cnt += shifted_k.astype(np.float32)
        fill = (~known) & (cnt > 0.0)
        if not fill.any():
            break
        out[fill] = acc[fill] / cnt[fill, None]
        known[fill] = True
    return out


def enhance_weapon_image(pil_img: Image.Image, uv_mask: np.ndarray) -> Image.Image:
    rgb = np.asarray(pil_img.convert("RGB"), dtype=np.float32)
    h, w, _ = rgb.shape

    # 1. Pad 3px into pure-black gutter outside UV islands without touching any interior texel
    rgb = pad_outside_black_gutter(rgb, uv_mask, passes=3)

    # 2. Hue-preserving luminance tone curve (lifts sRGB-crushed dark gunmetal without bleaching or hue-shifting!)
    norm = rgb / 255.0
    luma = 0.299 * norm[:, :, 0] + 0.587 * norm[:, :, 1] + 0.114 * norm[:, :, 2]
    val = np.maximum(np.maximum(norm[:, :, 0], norm[:, :, 1]), norm[:, :, 2])
    lvl = 0.5 * luma + 0.5 * val

    active = lvl[uv_mask & (val > 0.02)]
    if active.size < 16:
        active = lvl[val > 0.02]
    if active.size >= 8:
        p50 = float(np.percentile(active, 50))
        p96 = float(np.percentile(active, 96))
    else:
        p50, p96 = 0.25, 0.75

    # Modest highlight headroom expansion ONLY for ultra-dim textures (like sg552 max=73/255, m4a1 max=89/255)
    gain = 1.0
    if p96 < 0.62:
        gain = float(np.clip(0.68 / max(0.32, p96), 1.0, 1.38))

    lvl_g = np.clip(lvl * gain, 0.0, 1.0)
    gamma = 0.78 if (p50 * gain) < 0.26 else 0.86
    lvl_new = np.power(lvl_g, gamma)
    # Crisp micro-contrast S-curve keeping dark gunmetal authentically dark while separating grooves/rivets
    lvl_new = np.clip((lvl_new - 0.35) * 1.08 + 0.35, 0.0, 0.98)

    ratio = np.where(lvl > 1e-4, lvl_new / np.maximum(lvl, 1e-4), 1.0)
    out_rgb = np.clip(norm * ratio[:, :, None], 0.0, 1.0)
    # Prevent single-channel saturation clip while keeping natural richness
    restored = Image.fromarray(np.clip(out_rgb * 255.0 + 0.5, 0, 255).astype(np.uint8), mode="RGB")

    # 3. 3x / 2x High-Precision Lanczos Upscale + Crisp Edge-Preserving Unsharp Detail
    scale = 3 if min(w, h) < 92 else 2
    nw, nh = w * scale, h * scale
    up = restored.resize((nw, nh), Image.Resampling.LANCZOS)
    up = up.filter(ImageFilter.UnsharpMask(radius=1.05, percent=150, threshold=2))

    # 4. Compact 8-bit 256-color optimal palette PNG
    quant = up.quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    return quant


def enhance_glb(path: str) -> tuple[int, int, list]:
    orig_bytes = load_original_glb_bytes(path)
    jlen, _ = struct.unpack("<II", orig_bytes[12:20])
    gltf = json.loads(orig_bytes[20 : 20 + jlen].decode("utf-8"))
    bin_data = orig_bytes[20 + jlen + 8 :]

    images = gltf.get("images", [])
    if not images:
        return len(orig_bytes), len(orig_bytes), []

    img_bv_indices = {im["bufferView"] for im in images}

    new_pngs = {}
    stats = []
    for img_idx, im in enumerate(images):
        bv_idx = im["bufferView"]
        bv = gltf["bufferViews"][bv_idx]
        raw_png = bin_data[bv["byteOffset"] : bv["byteOffset"] + bv["byteLength"]]
        pil = Image.open(io.BytesIO(raw_png))
        w, h = pil.size
        uv_mask = build_uv_mask_for_image(gltf, bin_data, img_idx, w, h)
        old_med = float(np.median(np.asarray(pil.convert("L"))[uv_mask]))

        enhanced_pil = enhance_weapon_image(pil, uv_mask)
        ew, eh = enhanced_pil.size
        uv_mask_up = np.asarray(
            Image.fromarray((uv_mask.astype(np.uint8) * 255)).resize((ew, eh), Image.Resampling.NEAREST)
        ) > 0
        new_med = float(np.median(np.asarray(enhanced_pil.convert("L"))[uv_mask_up]))

        buf = io.BytesIO()
        enhanced_pil.save(buf, format="PNG", optimize=True)
        new_pngs[bv_idx] = buf.getvalue()
        stats.append((im.get("name", ""), f"{w}x{h}->{ew}x{eh}", f"med:{old_med:.0f}->{new_med:.0f}"))

    for smp in gltf.get("samplers", []):
        smp["magFilter"] = 9729  # LINEAR
        smp["minFilter"] = 9987  # LINEAR_MIPMAP_LINEAR

    new_bin = bytearray()
    for bv_idx, bv in enumerate(gltf["bufferViews"]):
        while len(new_bin) % 4 != 0:
            new_bin.append(0)
        if bv_idx in img_bv_indices:
            chunk = new_pngs[bv_idx]
        else:
            chunk = bin_data[bv["byteOffset"] : bv["byteOffset"] + bv["byteLength"]]
        bv["byteOffset"] = len(new_bin)
        bv["byteLength"] = len(chunk)
        new_bin.extend(chunk)

    while len(new_bin) % 4 != 0:
        new_bin.append(0)

    gltf["buffers"][0]["byteLength"] = len(new_bin)
    gltf.setdefault("asset", {})["w_tex_enhanced"] = True

    json_bytes = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    while len(json_bytes) % 4 != 0:
        json_bytes += b" "

    total_len = 12 + 8 + len(json_bytes) + 8 + len(new_bin)
    with open(path, "wb") as out:
        out.write(struct.pack("<III", 0x46546C67, 2, total_len))
        out.write(struct.pack("<II", len(json_bytes), 0x4E4F534A))
        out.write(json_bytes)
        out.write(struct.pack("<II", len(new_bin), 0x004E4942))
        out.write(new_bin)

    return len(orig_bytes), total_len, stats


def main() -> None:
    paths = sorted(glob.glob("assets/models/weapons/[wp]_*.glb"))
    old_total = 0
    new_total = 0
    for p in paths:
        ob, nb, st = enhance_glb(p)
        old_total += ob
        new_total += nb
        if os.path.basename(p).startswith("w_"):
            print(f"{os.path.basename(p):22s} | {ob//1024:3d}KB -> {nb//1024:3d}KB | {st}")
    print(f"\nEnhanced {len(paths)} weapon GLBs: {old_total/1024:.1f} KB -> {new_total/1024:.1f} KB (delta +{(new_total-old_total)/1024:.1f} KB)")


if __name__ == "__main__":
    main()
