#!/usr/bin/env python3
"""Upscale the original GoldSrc world artwork without replacing its visual design.

The runtime UVs and data/world_textures.json logical w/h values intentionally stay
unchanged. Original PNGs remain untouched; restored x4 artwork is written as HD
WebP. Masked artwork keeps its alpha channel; fully transparent RGB is inpainted
before inference to avoid dark or palette-blue fringes at cutout edges.

Tested model: FSRCNN_x4.pb from Saafke/FSRCNN_Tensorflow (models directory),
https://github.com/Saafke/FSRCNN_Tensorflow . The model is an external build-time
input and is not required by the Godot project at runtime.

Example:
  PYTHONPATH=/tmp/task47-py python3 tools/upscale_world_textures.py \
    --model /tmp/FSRCNN_Tensorflow-master/models/FSRCNN_x4.pb --jobs 1

Requires opencv-contrib-python-headless, NumPy and Pillow.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
from pathlib import Path
import sys
import time

import cv2
import numpy as np
from PIL import Image

MODEL_PATH = ""
SCALE = 4
PALETTE = 256
_SR = None


def _super_resolver():
    global _SR
    if _SR is None:
        cv2.setNumThreads(1)
        _SR = cv2.dnn_superres.DnnSuperResImpl_create()
        _SR.readModel(MODEL_PATH)
        _SR.setModel("fsrcnn", SCALE)
    return _SR


def _fill_hidden_rgb(rgb: np.ndarray, alpha: np.ndarray | None) -> np.ndarray:
    if alpha is None:
        return rgb
    hidden = (alpha < 250).astype(np.uint8) * 255
    if not np.any(hidden) or not np.any(alpha >= 250):
        return rgb
    # Inference sees plausible neighbouring surface colour instead of the RGB
    # left in transparent palette cells. Only hidden pixels are changed here.
    return cv2.inpaint(rgb, hidden, 3.0, cv2.INPAINT_TELEA)


def upscale_one(job: tuple[str, str, bool, int, int]) -> dict:
    src_text, dst_text, force_alpha, logical_w, logical_h = job
    src = Path(src_text)
    dst = Path(dst_text)
    with Image.open(src) as im:
        original_mode = im.mode
        has_alpha = "A" in im.getbands() or "transparency" in im.info
        rgba = np.asarray(im.convert("RGBA"))
        rgb = rgba[:, :, :3].copy()
        alpha = rgba[:, :, 3].copy() if has_alpha or force_alpha else None
        old_size = im.size

    inference_size = (logical_w, logical_h) if logical_w > 0 and logical_h > 0 else old_size
    if inference_size != old_size:
        # Older exports capped opaque textures at 128px. Recover the correct
        # logical aspect/resolution even for a fallback source; native BSP/WAD
        # extractions already have this size and lose no pixels to resampling.
        rgba = np.asarray(Image.fromarray(rgba, "RGBA").resize(inference_size, Image.Resampling.LANCZOS)).copy()
        rgb = rgba[:, :, :3].copy()
        alpha = rgba[:, :, 3].copy() if has_alpha or force_alpha else None

    inferred_rgb = _fill_hidden_rgb(rgb, alpha)
    bgr = cv2.cvtColor(inferred_rgb, cv2.COLOR_RGB2BGR)
    up_bgr = _super_resolver().upsample(bgr)
    up_rgb = cv2.cvtColor(up_bgr, cv2.COLOR_BGR2RGB)
    result = Image.fromarray(up_rgb, "RGB")

    if alpha is not None:
        alpha_image = Image.fromarray(alpha, "L").resize(result.size, Image.Resampling.LANCZOS)
        alpha_up = np.asarray(alpha_image).copy()
        alpha_up[alpha_up < 2] = 0
        alpha_up[alpha_up > 253] = 255
        result = Image.fromarray(np.dstack((np.asarray(result), alpha_up)), "RGBA")
    elif original_mode == "P":
        # Palette artwork without transparency still becomes ordinary RGB.
        result = result.convert("RGB")

    expected = (inference_size[0] * SCALE, inference_size[1] * SCALE)
    if result.size != expected:
        raise RuntimeError(f"{src.name}: expected {expected}, got {result.size}")

    has_output_alpha = result.mode == "RGBA"
    if PALETTE > 0:
        # GoldSrc artwork was palette-based. Keeping a 256-colour palette after
        # inference preserves that visual identity and avoids storing hundreds
        # of MiB of imperceptible RGB interpolation noise. Alpha remains in the
        # PNG transparency table for masked fences, foliage, ladders and water.
        method = Image.Quantize.FASTOCTREE if has_output_alpha else Image.Quantize.MEDIANCUT
        result = result.quantize(colors=PALETTE, method=method, dither=Image.Dither.NONE)
        transparency = result.info.get("transparency")
        if has_output_alpha and isinstance(transparency, (bytes, bytearray)):
            alpha_table = bytearray(transparency)
            for i, value in enumerate(alpha_table):
                if value < 2 or (force_alpha and value < 114):
                    # These texels are already discarded by the masked world's
                    # 0.45 alpha scissor; store unambiguous zero alpha instead.
                    alpha_table[i] = 0
                elif value > 253:
                    alpha_table[i] = 255
            result.info["transparency"] = bytes(alpha_table)

    dst.parent.mkdir(parents=True, exist_ok=True)
    tmp = dst.with_suffix(dst.suffix + ".upscale-tmp")
    if dst.suffix.lower() == ".webp":
        save_image = result.convert("RGBA" if has_output_alpha else "RGB")
        if has_output_alpha:
            save_image.putalpha(save_image.getchannel("A").point(
                lambda value: 0 if value < 2 or (force_alpha and value < 114) else (255 if value > 253 else value)
            ))
        save_image.save(tmp, format="WEBP", quality=85, method=4, alpha_quality=100)
    else:
        result.save(tmp, format="PNG", compress_level=6, optimize=True)
    os.replace(tmp, dst)
    return {
        "name": src.name,
        "old": old_size,
        "new": result.size,
        "alpha": has_output_alpha,
        "bytes": dst.stat().st_size,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", required=True, help="Path to FSRCNN_x{2,3,4}.pb")
    parser.add_argument("--scale", type=int, choices=(2, 3, 4), default=4)
    parser.add_argument("--palette", type=int, default=256, help="PNG palette colours; 0 keeps full RGB/RGBA")
    parser.add_argument("--source", type=Path, default=Path("assets/textures/world"))
    parser.add_argument("--output", type=Path, default=Path("assets/textures/world/hd"))
    parser.add_argument("--format", choices=("webp", "png"), default="webp")
    parser.add_argument("--metadata", type=Path, default=Path("data/world_textures.json"))
    parser.add_argument("--jobs", type=int, default=1)
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--only", default="", help="Optional substring filter")
    args = parser.parse_args()

    global MODEL_PATH, SCALE, PALETTE
    MODEL_PATH = str(Path(args.model).resolve())
    SCALE = args.scale
    if not 0 <= args.palette <= 256:
        parser.error("--palette must be between 0 and 256")
    PALETTE = args.palette
    if not Path(MODEL_PATH).is_file():
        parser.error(f"Model not found: {MODEL_PATH}")
    if not args.source.is_dir():
        parser.error(f"Texture directory not found: {args.source}")
    meta = json.loads(args.metadata.read_text(encoding="utf-8")) if args.metadata.is_file() else {}

    files = sorted(args.source.glob("*.png"))
    if args.only:
        files = [p for p in files if args.only in p.name]
    if args.limit > 0:
        files = files[: args.limit]
    if not files:
        parser.error("No source PNGs selected")
    out_root = args.output
    jobs = []
    for src in files:
        safe = src.stem.lower()
        force_alpha = bool(meta.get(safe, {}).get("masked", False))
        dst = out_root / (src.stem + "." + args.format)
        logical_w = int(meta.get(safe, {}).get("w", 0))
        logical_h = int(meta.get(safe, {}).get("h", 0))
        jobs.append((str(src.resolve()), str(dst.resolve()), force_alpha, logical_w, logical_h))

    t0 = time.monotonic()
    total_before = sum(p.stat().st_size for p in files)
    total_after = 0
    pixels_before = 0
    pixels_after = 0
    alpha_count = 0
    workers = max(1, args.jobs)
    print(f"[upscale] {len(jobs)} textures, FSRCNN x{SCALE}, palette={PALETTE}, {workers} worker(s)", flush=True)
    with concurrent.futures.ProcessPoolExecutor(max_workers=workers) as pool:
        for index, info in enumerate(pool.map(upscale_one, jobs), 1):
            total_after += info["bytes"]
            pixels_before += info["old"][0] * info["old"][1]
            pixels_after += info["new"][0] * info["new"][1]
            alpha_count += int(info["alpha"])
            if index % 100 == 0 or index == len(jobs):
                elapsed = time.monotonic() - t0
                print(f"[upscale] {index}/{len(jobs)} ({index / elapsed:.1f} textures/s)", flush=True)

    print(
        f"[upscale] complete: {pixels_before:,} -> {pixels_after:,} pixels; "
        f"{total_before / 1048576:.1f} -> {total_after / 1048576:.1f} MiB; "
        f"{alpha_count} alpha textures; {time.monotonic() - t0:.1f}s",
        flush=True,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
