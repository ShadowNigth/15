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
    """Saves an 8-bit paletted GoldSrc miptex as an indexed PNG (with colorkey transparency for '{')."""
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    is_masked = raw_name.startswith("{")
    arr = np.frombuffer(indices, dtype=np.uint8).reshape((h, w))
    while arr.shape[0] > 128 or arr.shape[1] > 128:
        arr = arr[::2, ::2]
    img = Image.fromarray(arr, mode="P")
    img.putpalette(list(pal))
    if is_masked:
        img.save(out_path, format="PNG", optimize=True, transparency=255)
    else:
        img.save(out_path, format="PNG", optimize=True)
    return is_masked


def generate_fallback_hl_texture(raw_name: str, w: int, h: int, out_path: str) -> bool:
    """
    Generates a compact, seamless GoldSrc-styled procedural pixel texture for external halflife.wad
    textures (which belong to base Half-Life rather than the cstrike mod directory).
    """
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    w = max(16, min(64, int(w or 64)))
    h = max(16, min(64, int(h or 64)))
    lname = raw_name.lower()
    seed = int(hashlib.md5(lname.encode("utf-8")).hexdigest()[:8], 16)
    rng = np.random.default_rng(seed)

    if "water" in lname or "slime" in lname:
        base = np.array([38, 88, 72] if "green" in lname else [42, 78, 118], dtype=np.float32)
        yy, xx = np.mgrid[0:h, 0:w]
        wave = np.sin(xx * 2 * np.pi / w * 2 + yy * 0.15) * 14 + np.cos(yy * 2 * np.pi / h * 2) * 12
        rgb = np.clip(base + wave[..., None], 0, 255).astype(np.uint8)
        Image.fromarray(rgb, mode="RGB").quantize(colors=16).save(out_path, format="PNG", optimize=True)
        return False

    if any(k in lname for k in ("lgt", "light", "lght", "white", "emerg", "exit")):
        base = np.array([235, 228, 200] if "emerg" not in lname else [235, 95, 70], dtype=np.float32)
        if "exit" in lname:
            base = np.array([70, 200, 95], dtype=np.float32)
        rgb = np.clip(np.broadcast_to(base, (h, w, 3)).copy(), 0, 255).astype(np.uint8)
        b = max(2, min(w, h) // 10)
        rgb[:b, :] = [55, 58, 62]
        rgb[-b:, :] = [55, 58, 62]
        rgb[:, :b] = [55, 58, 62]
        rgb[:, -b:] = [55, 58, 62]
        Image.fromarray(rgb, mode="RGB").quantize(colors=8).save(out_path, format="PNG", optimize=True)
        return False

    if any(k in lname for k in ("wood", "crate", "box", "plank")):
        base = np.array([138, 102, 64], dtype=np.float32)
    elif any(k in lname for k in ("steel", "mtl", "metal", "duct", "vent", "elev", "lab", "babtech")):
        base = np.array([104, 110, 116], dtype=np.float32)
    elif any(k in lname for k in ("rock", "cliff", "out_", "dirt", "sand")):
        base = np.array([132, 118, 96], dtype=np.float32)
    elif "yellow" in lname:
        base = np.array([196, 168, 52], dtype=np.float32)
    elif "black" in lname:
        base = np.array([18, 18, 20], dtype=np.float32)
    else:
        tint = np.array([(seed & 31) - 15, ((seed >> 5) & 31) - 15, ((seed >> 10) & 31) - 15], dtype=np.float32)
        base = np.clip(np.array([132, 130, 124], dtype=np.float32) + tint * 0.8, 55, 195)

    noise = (rng.integers(-2, 3, size=(h // 2, w // 2, 1)) * 5).repeat(2, axis=0).repeat(2, axis=1)[:h, :w]
    rgb = np.clip(base + noise, 0, 255).astype(np.uint8)
    step_x = 32 if w >= 64 else max(8, w // 2)
    step_y = 32 if h >= 64 else max(8, h // 2)
    rgb[::step_y, :] = np.clip(rgb[::step_y, :].astype(np.int16) - 24, 0, 255).astype(np.uint8)
    rgb[:, ::step_x] = np.clip(rgb[:, ::step_x].astype(np.int16) - 24, 0, 255).astype(np.uint8)

    if raw_name.startswith("{"):
        rgba = np.dstack([rgb, np.full((h, w), 255, dtype=np.uint8)])
        for y in range(4, h - 4, 8):
            for x in range(4, w - 4, 8):
                rgba[y : y + 4, x : x + 4, 3] = 0
        Image.fromarray(rgba, mode="RGBA").save(out_path, format="PNG", optimize=True)
        return True

    Image.fromarray(rgb, mode="RGB").quantize(colors=8).save(out_path, format="PNG", optimize=True)
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
