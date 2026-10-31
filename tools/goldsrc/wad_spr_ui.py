#!/usr/bin/env python3
"""
Extracts and optimizes GoldSrc WAD3 textures, procedural Half-Life fallback textures,
SPR v2 HUD & VFX sprites, VGUI TGA cards, WON Shell BMPs, Skyboxes, and Map Overviews.
"""

import glob
import hashlib
import json
import os
import re
import struct
from typing import Dict, Optional, Set, Tuple

import numpy as np
from PIL import Image, ImageDraw


def sanitize_tex_name(name: str) -> str:
    """Produces a filesystem-safe lowercase texture identifier."""
    s = name.strip().lower()
    out = []
    for ch in s:
        if ch.isalnum() or ch in ("_", "-"):
            out.append(ch)
        elif ch == "{":
            out.append("mask_")
        elif ch == "!":
            out.append("water_")
        elif ch == "+":
            out.append("anim_")
        elif ch == "~":
            out.append("lgt_")
        else:
            out.append("_")
    res = "".join(out).strip("_")
    return res if res else "default_tex"


def decode_miptex(data: bytes, base_ofs: int) -> Optional[Tuple[str, int, int, bytes, bytes]]:
    """Decodes a GoldSrc miptex_t at base_ofs -> (raw_name, w, h, indices_mip0, palette_768)."""
    if base_ofs + 40 > len(data):
        return None
    raw_name = data[base_ofs : base_ofs + 16].split(b"\x00")[0].decode("latin1", errors="ignore")
    w, h, o0, o1, o2, o3 = struct.unpack_from("<6I", data, base_ofs + 16)
    if w == 0 or h == 0 or w > 2048 or h > 2048 or o0 == 0:
        return None
    pix_start = base_ofs + o0
    pix_end = pix_start + w * h
    # Palette sits right after mip3: mip0 (w*h) + mip1 (w*h//4) + mip2 (w*h//16) + mip3 (w*h//64) + 2-byte count
    mip3_end = base_ofs + o3 + max(1, (w // 8) * (h // 8))
    pal_cnt_ofs = mip3_end
    if pal_cnt_ofs + 2 + 768 > len(data):
        return None
    pal_cnt = struct.unpack_from("<H", data, pal_cnt_ofs)[0]
    if pal_cnt == 0 or pal_cnt > 256:
        pal_cnt = 256
    pal = data[pal_cnt_ofs + 2 : pal_cnt_ofs + 2 + pal_cnt * 3]
    if len(pal) < 768:
        pal = pal + b"\x00" * (768 - len(pal))
    indices = data[pix_start:pix_end]
    if len(indices) != w * h:
        return None
    return raw_name, w, h, indices, pal


def save_miptex_png(raw_name: str, w: int, h: int, indices: bytes, pal: bytes, out_path: str) -> bool:
    """Saves a GoldSrc miptex as a clean 24-bit RGB or 32-bit RGBA PNG (bleeding RGB across '{' colorkey)."""
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    is_masked = raw_name.startswith("{")
    arr = np.frombuffer(indices, dtype=np.uint8).reshape((h, w))
    pal_arr = np.frombuffer(pal[:768], dtype=np.uint8).reshape((256, 3))
    rgb = pal_arr[arr]

    if is_masked:
        alpha = np.where(arr == 255, np.uint8(0), np.uint8(255))
        # Replace pure-blue colorkey RGB (0, 0, 255) on transparent texels with average opaque RGB to prevent mipmap blue fringes!
        opaque_mask = arr != 255
        fill_rgb = rgb[opaque_mask].mean(axis=0).astype(np.uint8) if np.any(opaque_mask) else np.array([64, 64, 64], dtype=np.uint8)
        rgb = np.where(opaque_mask[..., None], rgb, fill_rgb)
        rgba = np.dstack([rgb, alpha])
        im = Image.fromarray(rgba, mode="RGBA")
        if im.width > 256 or im.height > 256:
            im = im.resize((min(256, im.width), min(256, im.height)), Image.Resampling.BILINEAR)
        im.save(out_path, format="PNG", optimize=True)
        return True

    im = Image.fromarray(rgb, mode="RGB")
    if im.width > 128 or im.height > 128:
        scale = 128.0 / float(max(im.width, im.height))
        im = im.resize((max(8, int(round(im.width * scale))), max(8, int(round(im.height * scale)))), Image.Resampling.BILINEAR)
    im.quantize(colors=256).save(out_path, format="PNG", optimize=True)
    return False


def generate_fallback_hl_texture(raw_name: str, w: int, h: int, out_path: str) -> bool:
    """
    Generates authentic Half-Life 1 (halflife.wad) industrial, architectural, security door,
    corrugated warehouse, vehicle, console, crate, glass, and masked ladder/vent textures
    with neutral GoldSrc palettes (zero purple tinting!) at exact miptex aspect ratios.
    """
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    w = max(16, min(128, int(w or 64)))
    h = max(16, min(128, int(h or 64)))
    lname = raw_name.lower()
    # Strip GoldSrc animated/toggle prefixes (+0, +a, -0, ~, etc.) for clean material matching
    clean = re.sub(r"^[+\-][0-9a-z]", "", lname).lstrip("~")
    seed = int(hashlib.md5(clean.encode("utf-8")).hexdigest()[:8], 16)
    rng = np.random.default_rng(seed)

    # 1. Masked '{' textures: ladders, duct vents, railings, chain-link fences, razorwire, grates
    if raw_name.startswith("{"):
        rgba = np.zeros((h, w, 4), dtype=np.uint8)
        is_rust = "rust" in clean
        metal = np.array([112, 86, 68, 255] if is_rust else [132, 138, 144, 255], dtype=np.uint8)
        hi_m = np.clip(metal.astype(np.int16) + 34, 0, 255).astype(np.uint8)
        hi_m[3] = 255
        dark = np.clip(metal.astype(np.int16) - 42, 0, 255).astype(np.uint8)
        dark[3] = 255

        if any(k in clean for k in ("rung", "ladder")):
            rail_w = max(3, w // 8)
            # Left & right tubular steel rails with cylindrical highlight
            rgba[:, :rail_w] = dark
            rgba[:, 1 : max(2, rail_w - 1)] = metal
            if rail_w >= 4:
                rgba[:, 1] = hi_m
            rgba[:, -rail_w:] = dark
            rgba[:, -max(2, rail_w - 1) : -1] = metal
            if rail_w >= 4:
                rgba[:, -rail_w + 1] = hi_m
            step_h = max(8, h // 4)
            rung_t = max(2, step_h // 5)
            for ry in range(step_h // 2, h, step_h):
                y0, y1 = max(0, ry - rung_t), min(h, ry + rung_t)
                rgba[y0:y1, :] = metal
                rgba[y0, :] = hi_m
                if y1 - 1 >= y0:
                    rgba[y1 - 1, :] = dark
        elif "vnt" in clean or "vent" in clean:
            # Slatted air-duct vent louvers with see-through dark slots
            b = max(3, min(w, h) // 10)
            rgba[:b, :] = metal
            rgba[-b:, :] = dark
            rgba[:, :b] = metal
            rgba[:, -b:] = dark
            slat_step = max(6, h // 7)
            for sy in range(b + 2, h - b - 1, slat_step):
                rgba[sy : min(h - b, sy + max(2, slat_step - 3)), b : w - b] = metal
                rgba[sy, b : w - b] = hi_m
            rgba[:, w // 2 - 1 : w // 2 + 1] = dark
        elif "razor" in clean:
            yy, xx = np.mgrid[0:h, 0:w]
            coil1 = np.abs(np.sin(xx * np.pi * 3.0 / w) * (h * 0.42) + h * 0.5 - yy) < 1.8
            coil2 = np.abs(np.cos(xx * np.pi * 3.0 / w) * (h * 0.42) + h * 0.5 - yy) < 1.8
            rgba[coil1 | coil2] = [142, 146, 150, 255]
        elif "rail" in clean:
            bar = max(3, h // 10)
            rgba[:bar, :] = metal
            rgba[0, :] = hi_m
            rgba[-bar:, :] = dark
            rgba[h // 2 - max(1, bar // 2) : h // 2 + max(1, bar // 2), :] = metal
            post_step = max(12, w // 4)
            for px in range(0, w, post_step):
                rgba[:, px : min(w, px + max(2, bar))] = metal
        elif "fence" in clean:
            yy, xx = np.mgrid[0:h, 0:w]
            wire = (((xx + yy) % 8 <= 1) | ((xx - yy) % 8 <= 1))
            rgba[wire] = [138, 144, 148, 255]
            rgba[:2, :] = dark
            rgba[-2:, :] = dark
        else:
            cell = 8
            yy, xx = np.mgrid[0:h, 0:w]
            bars = ((xx % cell) < 2) | ((yy % cell) < 2)
            rgba[bars] = metal
            rgba[:2, :] = dark
            rgba[-2:, :] = dark
            rgba[:, :2] = dark
            rgba[:, -2:] = dark
        Image.fromarray(rgba, mode="RGBA").save(out_path, format="PNG", optimize=True)
        return True

    # 2. Water / Slime
    if "water" in clean or "slime" in clean or raw_name.startswith("!"):
        base = np.array([42, 96, 76] if ("green" in clean or "slime" in clean) else [44, 86, 132], dtype=np.float32)
        yy, xx = np.mgrid[0:h, 0:w]
        wave = (
            np.sin(xx * 2 * np.pi / w * 2.0 + yy * 0.14) * 16.0
            + np.cos(yy * 2 * np.pi / h * 2.0 - xx * 0.11) * 14.0
            + np.sin((xx + yy) * 2 * np.pi / max(w, h) * 3.0) * 8.0
        )
        rgb = np.clip(base + wave[..., None], 0, 255).astype(np.uint8)
        Image.fromarray(rgb, mode="RGB").quantize(colors=48).save(out_path, format="PNG", optimize=True)
        return False

    # 3. Light fixtures, Emergency beacons & EXIT signs
    if any(k in clean for k in ("lgt", "light", "lght", "emerg", "exit", "spotyellow")) or "~" in lname:
        if "comp" not in clean and "crt" not in clean:
            base = np.array([242, 236, 212], dtype=np.float32)
            if "emerg" in clean or "red" in clean:
                base = np.array([235, 76, 58], dtype=np.float32)
            elif "exit" in clean:
                base = np.array([58, 206, 88], dtype=np.float32)
            elif "yellow" in clean:
                base = np.array([244, 216, 118], dtype=np.float32)
            elif "blue" in clean:
                base = np.array([150, 198, 242], dtype=np.float32)
            yy, xx = np.mgrid[0:h, 0:w]
            glow = 1.0 - 0.16 * (np.abs(xx - w * 0.5) / (w * 0.5)) - 0.16 * (np.abs(yy - h * 0.5) / (h * 0.5))
            rgb = np.clip(base * glow[..., None], 0, 255).astype(np.uint8)
            b = max(2, min(w, h) // 8)
            rgb[:b, :] = [52, 56, 60]
            rgb[-b:, :] = [52, 56, 60]
            rgb[:, :b] = [52, 56, 60]
            rgb[:, -b:] = [52, 56, 60]
            Image.fromarray(rgb, mode="RGB").quantize(colors=32).save(out_path, format="PNG", optimize=True)
            return False

    # 4. Hazard Stripes & Warning Signs (stripes2, sign*)
    if "stripe" in clean or clean.startswith("sign"):
        im = Image.new("RGB", (w, h), (196, 158, 36) if "stripe" in clean else (188, 186, 178))
        dr = ImageDraw.Draw(im)
        if "stripe" in clean:
            yy, xx = np.mgrid[0:h, 0:w]
            blk = ((xx + yy) // max(6, min(w, h) // 4)) % 2 == 0
            arr = np.array(im, dtype=np.int16)
            arr[blk] = [34, 34, 36]
            arr += rng.integers(-8, 9, size=(h, w, 1))
            Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), mode="RGB").quantize(colors=32).save(out_path, format="PNG", optimize=True)
            return False
        else:
            dr.rectangle([0, 0, w - 1, h - 1], outline=(48, 52, 56), width=2)
            dr.rectangle([3, 3, w - 4, max(7, h // 3)], fill=(182, 54, 42))
            for ty in range(max(10, h // 3 + 4), h - 5, 5):
                dr.line([(6, ty), (w - 8, ty)], fill=(58, 60, 64), width=2)
            arr = np.clip(np.array(im, dtype=np.int16) + rng.integers(-6, 7, size=(h, w, 1)), 0, 255).astype(np.uint8)
            Image.fromarray(arr, mode="RGB").quantize(colors=32).save(out_path, format="PNG", optimize=True)
            return False

    # 5. Half-Life Automatic Sliding Security Doors & Hinged Facility Doors
    #    Matches: c1a3secdr02, fifties_dr2/5b/5d/8b, babtech_dr4c, elev2_dr, introdr1e, trk_door, *door*, *_dr*
    if any(k in clean for k in ("secdr", "door", "introdr", "elev2_dr")) or re.search(r"(?:^|_)dr\d", clean):
        is_wood_dr = "wood" in clean
        bg = (118, 86, 56) if is_wood_dr else ((98, 106, 114) if "secdr" in clean or "elev" in clean else (114, 118, 122))
        im = Image.new("RGB", (w, h), bg)
        dr = ImageDraw.Draw(im)
        fr = max(3, min(w, h) // 10)
        # Heavy dark steel outer door frame + inner bevel
        dr.rectangle([0, 0, w - 1, h - 1], outline=(46, 50, 54), width=fr)
        if w >= 32 and h >= 48:
            # Upper & lower recessed blast panels
            mid_y = int(h * 0.54)
            p_in = fr + 3
            dr.rectangle([p_in, p_in, w - p_in - 1, mid_y - 5], fill=(bg[0] - 12, bg[1] - 12, bg[2] - 10), outline=(58, 62, 68), width=1)
            dr.rectangle([p_in, mid_y + 5, w - p_in - 1, h - p_in - 1], fill=(bg[0] - 16, bg[1] - 16, bg[2] - 14), outline=(58, 62, 68), width=1)
            # Small armored vision slit / security window on upper door leaf
            if "secdr" in clean or "fifties_dr" in clean:
                wx0, wx1 = int(w * 0.28), int(w * 0.72)
                wy0, wy1 = int(h * 0.16), int(h * 0.34)
                dr.rectangle([wx0, wy0, wx1, wy1], fill=(56, 78, 92), outline=(38, 42, 46), width=2)
                dr.line([(wx0 + 2, wy1 - 3), (wx1 - 2, wy0 + 3)], fill=(118, 152, 168), width=1)
            # Horizontal lock bar + caution stripe on industrial security doors
            dr.rectangle([fr, mid_y - 3, w - fr - 1, mid_y + 3], fill=(72, 76, 82))
            if "secdr" in clean or "babtech" in clean:
                sy0 = h - fr - max(5, h // 12)
                for sx in range(fr, w - fr, 8):
                    col_s = (196, 158, 36) if ((sx // 8) % 2 == 0) else (38, 40, 42)
                    dr.rectangle([sx, sy0, min(w - fr - 1, sx + 7), h - fr - 1], fill=col_s)
            # Door latch / handle plate
            hx = w - fr - max(5, w // 7)
            dr.rectangle([hx, mid_y - 6, hx + 4, mid_y + 6], fill=(164, 168, 172), outline=(42, 44, 48))
        arr = np.array(im, dtype=np.int16)
        # Brushed vertical steel sheen
        grad = (np.sin(np.linspace(0, np.pi, w)) * 10.0).astype(np.int16)[None, :, None]
        arr = np.clip(arr + grad + rng.integers(-6, 7, size=(h, w, 1)), 0, 255).astype(np.uint8)
        Image.fromarray(arr, mode="RGB").quantize(colors=48).save(out_path, format="PNG", optimize=True)
        return False

    # 6. Glass & Skylights (glass_bright, glass_med, glassblue1, skkylite)
    if "glass" in clean or "skkylite" in clean:
        base = np.array([118, 158, 176] if "blue" not in clean else [88, 134, 172], dtype=np.float32)
        yy, xx = np.mgrid[0:h, 0:w]
        diag = ((xx + yy * 0.7) % max(24, w // 2)) < 5
        arr = np.broadcast_to(base, (h, w, 3)).copy()
        arr[diag] += 26.0
        arr += rng.integers(-4, 5, size=(h, w, 1))
        arr[:2, :] = [64, 74, 82]
        arr[-2:, :] = [64, 74, 82]
        arr[:, :2] = [64, 74, 82]
        arr[:, -2:] = [64, 74, 82]
        Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), mode="RGB").quantize(colors=32).save(out_path, format="PNG", optimize=True)
        return False

    # 7. Wooden, Military & Cardboard Crates (crate*, bcrate*, xcrate*, cardbox*, ammo*)
    if any(k in clean for k in ("crate", "bcrate", "cardbox", "ammo", "out_box")):
        if "cardbox" in clean:
            im = Image.new("RGB", (w, h), (164, 134, 92))
            dr = ImageDraw.Draw(im)
            dr.rectangle([0, 0, w - 1, h - 1], outline=(112, 88, 56), width=2)
            dr.line([(0, h // 2), (w - 1, h // 2)], fill=(124, 96, 62), width=2)
        elif "ammo" in clean or "c3a1_crate" in clean:
            # Olive-drab military ordnance crate
            im = Image.new("RGB", (w, h), (86, 96, 68))
            dr = ImageDraw.Draw(im)
            fr = max(2, min(w, h) // 8)
            dr.rectangle([0, 0, w - 1, h - 1], outline=(48, 54, 38), width=fr)
            dr.line([(fr, h // 2), (w - fr - 1, h // 2)], fill=(186, 158, 54), width=max(2, h // 14))
        else:
            im = Image.new("RGB", (w, h), (148, 110, 68))
            dr = ImageDraw.Draw(im)
            plank_h = max(6, h // 6)
            for py in range(0, h, plank_h):
                shade = int(rng.integers(-10, 11))
                dr.rectangle([0, py, w - 1, min(h - 1, py + plank_h - 1)], fill=(148 + shade, 110 + shade, 68 + shade // 2))
                dr.line([(0, py), (w - 1, py)], fill=(96, 68, 38), width=1)
            frame = max(3, min(w, h) // 9)
            dr.line([(frame, frame), (w - frame - 1, h - frame - 1)], fill=(122, 88, 50), width=max(2, frame - 1))
            dr.rectangle([0, 0, w - 1, frame], fill=(126, 92, 54))
            dr.rectangle([0, h - frame - 1, w - 1, h - 1], fill=(116, 84, 48))
            dr.rectangle([0, 0, frame, h - 1], fill=(124, 90, 52))
            dr.rectangle([w - frame - 1, 0, w - 1, h - 1], fill=(114, 82, 46))
            dr.rectangle([0, 0, w - 1, h - 1], outline=(76, 52, 28), width=1)
        arr = np.clip(np.array(im, dtype=np.int16) + rng.integers(-7, 8, size=(h, w, 1)), 0, 255).astype(np.uint8)
        Image.fromarray(arr, mode="RGB").quantize(colors=48).save(out_path, format="PNG", optimize=True)
        return False

    if any(k in clean for k in ("wood", "plank", "trrm", "bks", "book", "dsk")):
        arr = np.full((h, w, 3), [134, 96, 58] if "dsk" not in clean else [118, 114, 106], dtype=np.int16)
        plank_h = max(8, h // 4)
        for py in range(0, h, plank_h):
            arr[py : py + plank_h] += int(rng.integers(-10, 11))
            arr[py, :] -= 24
        rgb = np.clip(arr + rng.integers(-8, 9, size=(h, w, 1)), 0, 255).astype(np.uint8)
        Image.fromarray(rgb, mode="RGB").quantize(colors=48).save(out_path, format="PNG", optimize=True)
        return False

    # 8. Corrugated Warehouse Siding (cs_assault blue warehouse `baseblue`, `silo2_cor`, `out_galv*`)
    if any(k in clean for k in ("baseblue", "silo2_cor", "galv", "corrug")):
        base = np.array([68, 98, 138] if "blue" in clean else [128, 134, 138], dtype=np.float32)
        yy, xx = np.mgrid[0:h, 0:w]
        ribs = np.sin(xx * 2.0 * np.pi / 8.0) * 18.0
        arr = base + ribs[..., None] + rng.integers(-6, 7, size=(h, w, 1))
        for sy in range(0, h, max(32, h // 2)):
            arr[sy : min(h, sy + 2), :] -= 26.0
        Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), mode="RGB").quantize(colors=48).save(out_path, format="PNG", optimize=True)
        return False

    # 9. Computers, Security Camera Racks & Power Consoles (lab1_comp*, lab_crt*, recharged, c1a4_pow)
    if any(k in clean for k in ("comp", "crt", "scrn", "recharg", "c1a4_pow")):
        im = Image.new("RGB", (w, h), (62, 66, 72))
        dr = ImageDraw.Draw(im)
        dr.rectangle([0, 0, w - 1, h - 1], outline=(36, 38, 42), width=2)
        # CRT monitor screen
        sy0, sy1 = max(4, h // 7), max(12, h // 2)
        sx0, sx1 = max(4, w // 7), max(10, w - w // 7 - 1)
        if sx1 > sx0 + 4 and sy1 > sy0 + 4:
            dr.rectangle([sx0, sy0, sx1, sy1], fill=(22, 54, 44), outline=(32, 34, 38), width=2)
            for ly in range(sy0 + 3, sy1 - 2, 4):
                dr.line([(sx0 + 3, ly), (sx1 - 3, ly)], fill=(68, 196, 118), width=1)
        # Rack indicator LEDs & switches below screen
        for by in range(sy1 + 5, h - 5, 8):
            for bx in range(6, w - 6, 8):
                led_c = (210, 72, 54) if ((bx + by) % 16 == 0) else ((78, 198, 98) if ((bx + by) % 24 == 0) else (112, 116, 122))
                dr.rectangle([bx, by, min(w - 3, bx + 4), min(h - 3, by + 3)], fill=led_c)
        arr = np.clip(np.array(im, dtype=np.int16) + rng.integers(-6, 7, size=(h, w, 1)), 0, 255).astype(np.uint8)
        Image.fromarray(arr, mode="RGB").quantize(colors=48).save(out_path, format="PNG", optimize=True)
        return False

    # 10. Trucks, Vehicles & Industrial Dumpsters (trk_*, tankrear, out_dmp*)
    if clean.startswith("trk_") or "tankrear" in clean or "out_dmp" in clean:
        if "tire" in clean or "tread" in clean or "rim" in clean:
            im = Image.new("RGB", (w, h), (38, 40, 42))
            dr = ImageDraw.Draw(im)
            if "tire" in clean:
                r_out = min(w, h) // 2 - 2
                dr.ellipse([w // 2 - r_out, h // 2 - r_out, w // 2 + r_out, h // 2 + r_out], fill=(32, 34, 36), outline=(56, 58, 60), width=2)
                r_rim = max(4, r_out // 2)
                dr.ellipse([w // 2 - r_rim, h // 2 - r_rim, w // 2 + r_rim, h // 2 + r_rim], fill=(116, 120, 124), outline=(72, 74, 78), width=2)
            else:
                for tx in range(0, w, 6):
                    dr.line([(tx, 0), (tx, h - 1)], fill=(58, 60, 64), width=2)
        elif "grille" in clean:
            im = Image.new("RGB", (w, h), (52, 56, 60))
            dr = ImageDraw.Draw(im)
            for gx in range(4, w - 4, 5):
                dr.line([(gx, 3), (gx, h - 4)], fill=(124, 128, 134), width=2)
        elif "out_dmp" in clean:
            im = Image.new("RGB", (w, h), (58, 92, 66) if "lid" not in clean else (44, 46, 48))
            dr = ImageDraw.Draw(im)
            dr.rectangle([0, 0, w - 1, h - 1], outline=(38, 54, 42), width=2)
            for rx in range(w // 4, w, max(8, w // 4)):
                dr.rectangle([rx - 2, 2, rx + 2, h - 3], fill=(46, 76, 54))
        else:
            col_v = (138, 132, 108) if "canvas" in clean else (76, 88, 78)
            im = Image.new("RGB", (w, h), col_v)
            dr = ImageDraw.Draw(im)
            dr.rectangle([0, 0, w - 1, h - 1], outline=(48, 54, 48), width=2)
        arr = np.clip(np.array(im, dtype=np.int16) + rng.integers(-7, 8, size=(h, w, 1)), 0, 255).astype(np.uint8)
        Image.fromarray(arr, mode="RGB").quantize(colors=48).save(out_path, format="PNG", optimize=True)
        return False

    # 11. Industrial Metal / Ducts / Lab Trim / Silo / Babtech / Generic Metal Panels
    if any(k in clean for k in ("steel", "mtl", "metal", "duct", "vent", "elev", "babtech", "silo", "pnl", "trim", "generic")):
        shade_ofs = ((seed & 15) - 8)
        base = np.clip(np.array([112 + shade_ofs, 116 + shade_ofs, 120 + shade_ofs], dtype=np.int16), 64, 162)
        arr = np.broadcast_to(base, (h, w, 3)).copy()
        arr = arr + rng.integers(-9, 10, size=(h, w, 1))
        step_x = max(16, w // 2)
        step_y = max(16, h // 2)
        for gy in range(0, h, step_y):
            arr[gy, :] -= 28
            if gy + 1 < h:
                arr[gy + 1, :] += 16
        for gx in range(0, w, step_x):
            arr[:, gx] -= 28
            if gx + 1 < w:
                arr[:, gx + 1] += 16
        if "flr" in clean:
            # Diamond-plate industrial metal floor pattern
            yy, xx = np.mgrid[0:h, 0:w]
            tread = (((xx + yy) % 8 == 0) & ((xx % 8) < 4)) | (((xx - yy) % 8 == 0) & ((yy % 8) < 4))
            arr[tread] += 18
        rgb = np.clip(arr, 0, 255).astype(np.uint8)
        Image.fromarray(rgb, mode="RGB").quantize(colors=48).save(out_path, format="PNG", optimize=True)
        return False

    # 12. Half-Life Facility / Black Mesa Interior Walls (c1a*, c2a*, c3a*, fifties_*, lab*)
    if re.match(r"^c[0-9]a[0-9]", clean) or "fifties" in clean or "lab" in clean:
        arr = np.full((h, w, 3), [142, 140, 134], dtype=np.int16)
        if "flr" in clean:
            # Clean checkered/tiled laboratory floor (neutral slate & warm grey)
            yy, xx = np.mgrid[0:h, 0:w]
            tile_sz = max(16, min(w, h) // 4)
            chk = ((xx // tile_sz) + (yy // tile_sz)) % 2 == 0
            arr[chk] = [124, 128, 132]
            arr[~chk] = [152, 150, 144]
            arr[(xx % tile_sz == 0) | (yy % tile_sz == 0)] -= 24
        else:
            # Classic Half-Life two-tone painted concrete wall with lower wainscot & stripe!
            split_y = int(h * 0.62)
            arr[:split_y, :] = [148, 146, 138]
            arr[split_y:, :] = [104, 108, 112]
            stripe_h = max(3, h // 20)
            arr[max(0, split_y - stripe_h) : min(h, split_y + stripe_h), :] = [74, 82, 92]
            for gx in range(0, w, max(32, w // 2)):
                arr[:, gx] -= 20
        arr += rng.integers(-8, 9, size=(h, w, 1))
        Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), mode="RGB").quantize(colors=48).save(out_path, format="PNG", optimize=True)
        return False

    # 13. Neutral Concrete, Tunnel Walls/Floors, Asphalt, Gravel, Grass & Brick (ZERO purple tint!)
    if "grss" in clean or "grass" in clean:
        base = np.array([78, 104, 58], dtype=np.int16)
    elif any(k in clean for k in ("rock", "rk", "cliff", "dirt", "sand", "gravel")):
        base = np.array([134, 120, 96], dtype=np.int16)
    elif "pave" in clean or "asph" in clean:
        base = np.array([92, 94, 98], dtype=np.int16)
    elif "yellow" in clean:
        base = np.array([198, 166, 48], dtype=np.int16)
    elif "black" in clean:
        base = np.array([24, 24, 26], dtype=np.int16)
    elif "white" in clean:
        base = np.array([216, 214, 208], dtype=np.int16)
    else:
        # Strictly neutral concrete/stone luminance variation (R~=G~=B, warm-cool within +-4!)
        lum_ofs = ((seed & 31) - 15)
        warm = ((seed >> 6) & 7) - 3
        base = np.clip(np.array([132 + lum_ofs + warm, 131 + lum_ofs, 128 + lum_ofs - warm], dtype=np.int16), 78, 178)

    fine = rng.integers(-10, 11, size=(h, w, 1))
    coarse = rng.integers(-10, 11, size=(max(2, h // 4), max(2, w // 4), 1)).repeat(4, axis=0).repeat(4, axis=1)[:h, :w]
    arr = base + fine + coarse
    if "flr" in clean or "pave" in clean:
        slab = max(16, min(w, h) // 2)
        for gy in range(0, h, slab):
            arr[gy, :] -= 20
        for gx in range(0, w, slab):
            arr[:, gx] -= 20
    elif "black" not in clean and "white" not in clean and "grss" not in clean and "gravel" not in clean:
        row_h = max(12, min(24, h // 4))
        col_w = max(24, min(48, w // 2))
        for r_idx, ry in enumerate(range(0, h, row_h)):
            arr[ry, :] -= 22
            if ry + 1 < h:
                arr[ry + 1, :] += 10
            offset = (col_w // 2) if (r_idx % 2 == 1) else 0
            for cx in range(offset, w, col_w):
                arr[ry : min(h, ry + row_h), cx] -= 18
    rgb = np.clip(arr, 0, 255).astype(np.uint8)
    Image.fromarray(rgb, mode="RGB").quantize(colors=48).save(out_path, format="PNG", optimize=True)
    return False


def collect_wad_catalog(cstrike_dir: str) -> Dict[str, Tuple[str, int]]:
    """Indexes all WAD3 lumps across cstrike/*.wad -> {lower_name: (wad_path, filepos)}."""
    catalog: Dict[str, Tuple[str, int]] = {}
    for wp in sorted(glob.glob(os.path.join(cstrike_dir, "*.[wW][aA][dD]"))):
        with open(wp, "rb") as f:
            hdr = f.read(12)
            if len(hdr) < 12 or hdr[:4] not in (b"WAD2", b"WAD3"):
                continue
            num, dirofs = struct.unpack_from("<ii", hdr, 4)
            f.seek(dirofs)
            entries = f.read(num * 32)
        for i in range(num):
            e_ofs = i * 32
            filepos, disksize, size, ltype, comp = struct.unpack_from("<iiiBB", entries, e_ofs)
            if ltype not in (0x43, 0x42, 0x40):  # 0x43 = WAD3 miptex
                continue
            name = entries[e_ofs + 16 : e_ofs + 32].split(b"\x00")[0].decode("latin1", errors="ignore").lower()
            if name and name not in catalog:
                catalog[name] = (wp, filepos)
    return catalog


def extract_spr_files(sprites_dir: str, out_sprites_dir: str) -> Dict[str, dict]:
    """Converts all GoldSrc SPR v2 files into RGBA PNGs (first frame + key animated frames)."""
    os.makedirs(out_sprites_dir, exist_ok=True)
    meta = {}
    for sp in sorted(glob.glob(os.path.join(sprites_dir, "*.[sS][pP][rR]"))):
        sname = os.path.splitext(os.path.basename(sp))[0].lower()
        with open(sp, "rb") as f:
            d = f.read()
        if len(d) < 42 or d[:4] != b"IDSP":
            continue
        ver, stype, texfmt, radius, maxw, maxh, nframes, beamlen, synctype = struct.unpack_from("<iiifiiiii", d, 4)
        if ver != 2:
            continue
        pal_cnt = struct.unpack_from("<H", d, 40)[0]
        pos = 42 + pal_cnt * 3
        pal = np.frombuffer(d[42:pos], dtype=np.uint8).reshape((-1, 3))
        if len(pal) < 256:
            pad = np.zeros((256 - len(pal), 3), dtype=np.uint8)
            pal = np.vstack([pal, pad])

        frames_saved = []
        max_export_frames = 8
        for fi in range(nframes):
            if pos + 4 > len(d):
                break
            group = struct.unpack_from("<i", d, pos)[0]
            pos += 4
            if group == 0:
                if pos + 16 > len(d):
                    break
                ox, oy, fw, fh = struct.unpack_from("<4i", d, pos)
                pos += 16
                pix = d[pos : pos + fw * fh]
                pos += fw * fh
                subframes = [(fw, fh, pix)]
            else:
                nb = struct.unpack_from("<i", d, pos)[0]
                pos += 4 + nb * 4
                subframes = []
                for _ in range(nb):
                    ox, oy, fw, fh = struct.unpack_from("<4i", d, pos)
                    pos += 16
                    pix = d[pos : pos + fw * fh]
                    pos += fw * fh
                    subframes.append((fw, fh, pix))

            if fi >= max_export_frames or not subframes:
                continue
            fw, fh, pix = subframes[0]
            if len(pix) != fw * fh or fw <= 0 or fh <= 0:
                continue
            idx = np.frombuffer(pix, dtype=np.uint8).reshape((fh, fw))
            rgba = np.zeros((fh, fw, 4), dtype=np.uint8)
            rgb = pal[idx]

            if texfmt == 0:  # SPR_NORMAL
                rgba[..., :3] = rgb
                rgba[..., 3] = 255
            elif texfmt == 1:  # SPR_ADDITIVE (HUD sprites, muzzle flashes, glows)
                lum = rgb.max(axis=-1)
                rgba[..., 3] = lum
                nonzero = lum > 0
                # Preserve pure color tint so Godot modulate works cleanly without dark fringes
                rgba[nonzero, :3] = np.clip(
                    rgb[nonzero].astype(np.float32) * (255.0 / lum[nonzero, None]), 0, 255
                ).astype(np.uint8)
            elif texfmt == 2:  # SPR_INDEXALPHA
                rgba[..., :3] = pal[255]
                rgba[..., 3] = idx
            else:  # SPR_ALPHTEST (3)
                rgba[..., :3] = rgb
                rgba[..., 3] = np.where(idx == 255, 0, 255)

            fname = f"{sname}.png" if fi == 0 else f"{sname}_{fi}.png"
            out_p = os.path.join(out_sprites_dir, fname)
            Image.fromarray(rgba, mode="RGBA").save(out_p, format="PNG", optimize=True)
            frames_saved.append(fname)

        meta[sname] = {
            "width": maxw,
            "height": maxh,
            "texfmt": texfmt,
            "frames": frames_saved,
        }
    return meta


def extract_ui_and_overviews(cstrike_dir: str, out_ui_dir: str, out_sky_dir: str, out_data_dir: str, used_skies: Set[str]) -> None:
    # 1. VGUI weapon & class portraits (gfx/vgui/*.tga)
    vgui_out = os.path.join(out_ui_dir, "vgui")
    os.makedirs(vgui_out, exist_ok=True)
    vgui_count = 0
    for tp in sorted(glob.glob(os.path.join(cstrike_dir, "gfx", "vgui", "*.[tT][gG][aA]"))):
        name = os.path.splitext(os.path.basename(tp))[0].lower()
        try:
            im = Image.open(tp).convert("RGBA")
            im.save(os.path.join(vgui_out, f"{name}.png"), format="PNG", optimize=True)
            vgui_count += 1
        except Exception:
            pass

    # 2. Classic CS 1.5 WON shell menu assets (splash.bmp, btns_main.bmp, headers)
    shell_out = os.path.join(out_ui_dir, "shell")
    os.makedirs(shell_out, exist_ok=True)
    for bp in sorted(glob.glob(os.path.join(cstrike_dir, "gfx", "shell", "*.[bB][mM][pP]"))):
        name = os.path.splitext(os.path.basename(bp))[0].lower()
        try:
            im = Image.open(bp).convert("RGBA")
            arr = np.array(im)
            if name != "splash":
                # Black background in GoldSrc shell BMP buttons/headers is transparent
                mask = (arr[..., 0] < 8) & (arr[..., 1] < 8) & (arr[..., 2] < 8)
                arr[mask, 3] = 0
            Image.fromarray(arr, mode="RGBA").save(os.path.join(shell_out, f"{name}.png"), format="PNG", optimize=True)
        except Exception:
            pass

    # 3. Project icon from cstrike.ico
    ico_path = os.path.join(cstrike_dir, "cstrike.ico")
    if os.path.exists(ico_path):
        try:
            im = Image.open(ico_path).convert("RGBA").resize((128, 128), Image.NEAREST)
            im.save(os.path.join(os.path.dirname(out_data_dir), "icon.png"), format="PNG", optimize=True)
        except Exception:
            pass

    # 4. Radar map overviews (overviews/*.bmp + *.txt) -> 512x384 RGBA PNG + data/overviews.json
    ov_out = os.path.join(out_ui_dir, "overviews")
    os.makedirs(ov_out, exist_ok=True)
    overviews_meta = {}
    for txt_p in sorted(glob.glob(os.path.join(cstrike_dir, "overviews", "*.txt"))):
        mname = os.path.splitext(os.path.basename(txt_p))[0].lower()
        raw = open(txt_p, "r", encoding="latin1", errors="ignore").read()
        zoom_m = re.search(r"ZOOM\s+([-\d.]+)", raw, re.I)
        orig_m = re.search(r"ORIGIN\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)", raw, re.I)
        rot_m = re.search(r"ROTATED\s+(\d+)", raw, re.I)
        img_m = re.search(r'IMAGE\s+"?([^"\s]+)"?', raw, re.I)

        bmp_name = os.path.basename(img_m.group(1)) if img_m else f"{mname}.bmp"
        bmp_candidates = glob.glob(os.path.join(cstrike_dir, "overviews", "*"))
        bmp_path = next((c for c in bmp_candidates if os.path.basename(c).lower() == bmp_name.lower()), None)
        png_rel = ""
        if bmp_path and os.path.exists(bmp_path):
            try:
                im = Image.open(bmp_path).convert("RGBA")
                arr = np.array(im)
                # Bright green (0, 255, 0) is CS 1.5 overview colorkey
                bg = arr[0, 0, :3]
                green_mask = ((arr[..., 1] > 240) & (arr[..., 0] < 20) & (arr[..., 2] < 20)) | (
                    (np.abs(arr[..., 0].astype(int) - int(bg[0])) < 5)
                    & (np.abs(arr[..., 1].astype(int) - int(bg[1])) < 5)
                    & (np.abs(arr[..., 2].astype(int) - int(bg[2])) < 5)
                    & (int(bg[1]) > 200)
                )
                arr[green_mask, 3] = 0
                im_clean = Image.fromarray(arr, mode="RGBA").resize((512, 384), Image.BILINEAR)
                out_png = os.path.join(ov_out, f"{mname}.png")
                im_clean.save(out_png, format="PNG", optimize=True)
                png_rel = f"res://assets/ui/overviews/{mname}.png"
            except Exception:
                pass

        overviews_meta[mname] = {
            "zoom": float(zoom_m.group(1)) if zoom_m else 1.5,
            "origin": [float(orig_m.group(1)), float(orig_m.group(2)), float(orig_m.group(3))] if orig_m else [0.0, 0.0, 0.0],
            "rotated": int(rot_m.group(1)) if rot_m else 0,
            "image": png_rel,
        }

    with open(os.path.join(out_data_dir, "overviews.json"), "w", encoding="utf-8") as f:
        json.dump(overviews_meta, f, indent=2)

    # 5. Skyboxes (gfx/env/*.tga) for all skies referenced by the 26 maps
    os.makedirs(out_sky_dir, exist_ok=True)
    env_dir = os.path.join(cstrike_dir, "gfx", "env")
    env_files = {os.path.basename(p).lower(): p for p in glob.glob(os.path.join(env_dir, "*"))}
    sky_count = 0
    all_skies = set(s.lower() for s in used_skies if s) | {"des", "desert", "2desert", "morningdew", "city1", "backalley", "office", "snow", "tornsky", "trainyard", "hav", "cx", "badlands", "de_storm"}
    for sky in sorted(all_skies):
        for side in ("bk", "dn", "ft", "lf", "rt", "up"):
            for ext in (".tga", ".bmp"):
                cand = f"{sky}{side}{ext}"
                if cand in env_files:
                    try:
                        im = Image.open(env_files[cand]).convert("RGB")
                        if im.width > 256 or im.height > 256:
                            im = im.resize((256, 256), Image.BILINEAR)
                        im.quantize(colors=256).save(os.path.join(out_sky_dir, f"{sky}{side}.png"), format="PNG", optimize=True)
                        sky_count += 1
                        break
                    except Exception:
                        pass

    print(
        f"[wad_spr_ui] Exported {vgui_count} VGUI cards, {len(overviews_meta)} radar overviews, "
        f"{sky_count} skybox faces."
    )
