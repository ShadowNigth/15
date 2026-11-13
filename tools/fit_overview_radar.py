#!/usr/bin/env python3
"""Fit world->overview-image affine projections for the retained CS 1.5 maps.

The extracted overview PNGs (assets/ui/overviews/*.png, resized to 512x384) keep the
original GoldSrc overview textures, but the .txt `origin`/`zoom` camera convention does
not translate 1:1 to pixel space after the forced resize. This tool fits, per map, the
axis-aligned affine (scale + flips + axis swap for `rotated` overviews + offsets) that
maximizes the fraction of YaPB navigation waypoints landing on visible map pixels.

Output: data/overviews.json gains per-map:
  "affine": [b, a, d, c]   -> px = b * GX + a ; py = d * GY + c   (GS plan units, rot=0)
                              px = b * GY + a ; py = d * GX + c   (rot=1 axis swap)
  "fit_coverage": <waypoint visibility score 0..1>
"""
import json
import os
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OVERVIEWS_PATH = os.path.join(ROOT, "data", "overviews.json")


def load_vis(ov: dict):
    img_path = ov["image"].replace("res://", "")
    im = Image.open(os.path.join(ROOT, img_path)).convert("RGBA")
    a = np.array(im).astype(int)
    vis = (a[..., 3] > 30) & ((a[..., 0] + a[..., 1] + a[..., 2]) > 40)
    return vis


def load_wp_gs(map_name: str):
    with open(os.path.join(ROOT, "data", "maps", f"{map_name}.json")) as f:
        d = json.load(f)
    wps = np.array(d["waypoints"], dtype=np.float64)
    return wps[:, 0] / 0.03125, wps[:, 2] / 0.03125


def fit_map(map_name: str, ov: dict) -> dict:
    vis = load_vis(ov)
    gx, gy = load_wp_gs(map_name)
    H, W = vis.shape
    n = len(gx)
    ys_v, xs_v = np.nonzero(vis)
    vis_w = float(xs_v.max() - xs_v.min())
    vis_h = float(ys_v.max() - ys_v.min())
    best = None  # (coverage, s, rot, fx, fy, ox, oy)

    for rot in (0, 1):
        ax, ay = (gx, gy) if rot == 0 else (gy, gx)
        amin_x, amax_x = float(ax.min()), float(ax.max())
        amin_y, amax_y = float(ay.min()), float(ay.max())
        span_x = amax_x - amin_x
        span_y = amax_y - amin_y
        for s in np.arange(0.035, 0.165, 0.0025):
            wpx = span_x * s
            hpx = span_y * s
            if wpx > W + 40 or hpx > H + 40 or wpx < 50 or hpx < 50:
                continue
            for fx in (1, -1):
                px = (ax - amin_x) * s if fx == 1 else (amax_x - ax) * s
                for fy in (1, -1):
                    py = (amax_y - ay) * s if fy == 1 else (ay - amin_y) * s
                    # Extent guard: a tiny cluster inside any visible blob trivially scores
                    # coverage=1.0 — the projected waypoint hull must MATCH the visible
                    # map footprint size (55%..145% per axis), otherwise skip this scale.
                    if wpx < 0.55 * vis_w or hpx < 0.55 * vis_h:
                        continue
                    if wpx > 1.45 * vis_w or hpx > 1.45 * vis_h:
                        continue
                    for oy in range(-24, H + 24 - int(hpx), 6):
                        for ox in range(-24, W + 24 - int(wpx), 6):
                            ix = np.round(px + ox).astype(np.int32)
                            iy = np.round(py + oy).astype(np.int32)
                            ok = (ix >= 0) & (ix < W) & (iy >= 0) & (iy < H)
                            n_ok = int(ok.sum())
                            if n_ok < int(n * 0.6):
                                continue
                            cov = float(vis[iy[ok], ix[ok]].mean())
                            if best is None or cov > best[0]:
                                best = (cov, float(s), rot, fx, fy, ox, oy)

    if best is None:
        print(f"[WARN] {map_name}: no fit found, leaving affine unset")
        return ov

    cov, s, rot, fx, fy, ox, oy = best

    # Fine refinement: offsets +-6 at step 1, then scale +-0.0025 at step 0.0005
    def eval_at(s_, rot_, fx_, fy_, ox_, oy_):
        ax, ay = (gx, gy) if rot_ == 0 else (gy, gx)
        amin_x, amax_x = float(ax.min()), float(ax.max())
        amin_y, amax_y = float(ay.min()), float(ay.max())
        px = (ax - amin_x) * s_ if fx_ == 1 else (amax_x - ax) * s_
        py = (amax_y - ay) * s_ if fy_ == 1 else (ay - amin_y) * s_
        ix = np.round(px + ox_).astype(np.int32)
        iy = np.round(py + oy_).astype(np.int32)
        ok = (ix >= 0) & (ix < W) & (iy >= 0) & (iy < H)
        if int(ok.sum()) < int(n * 0.6):
            return -1.0
        return float(vis[iy[ok], ix[ok]].mean())

    improved = True
    while improved:
        improved = False
        for dy in (-3, -2, -1, 0, 1, 2, 3):
            for dx in (-3, -2, -1, 0, 1, 2, 3):
                c2 = eval_at(s, rot, fx, fy, ox + dx, oy + dy)
                if c2 > cov + 1e-6:
                    cov, ox, oy = c2, ox + dx, oy + dy
                    improved = True
        for s2 in np.arange(s - 0.003, s + 0.0031, 0.0005):
            if abs(s2 - s) < 1e-9:
                continue
            c2 = eval_at(float(s2), rot, fx, fy, ox, oy)
            if c2 > cov + 1e-6:
                cov, s = c2, float(s2)
                improved = True

    # Bake direct affine: px = b*src_a + a ; py = d*src_b + c (src_a=GX or GY per rot)
    ax, ay = (gx, gy) if rot == 0 else (gy, gx)
    amin_x, amax_x = float(ax.min()), float(ax.max())
    amin_y, amax_y = float(ay.min()), float(ay.max())
    if fx == 1:
        b, a = s, ox - amin_x * s
    else:
        b, a = -s, ox + amax_x * s
    if fy == 1:  # py = (amax_y - ay) * s + oy
        d, c = -s, oy + amax_y * s
    else:  # py = (ay - amin_y) * s + oy
        d, c = s, oy - amin_y * s

    ov = dict(ov)
    ov["affine"] = [round(b, 8), round(a, 4), round(d, 8), round(c, 4)]
    ov["fit_rot"] = rot
    ov["fit_coverage"] = round(cov, 4)
    print(f"[OK] {map_name}: coverage={cov:.4f} s={s:.4f} rot={rot} fx={fx} fy={fy} off=({ox},{oy})")
    return ov


def save_debug_overlay(map_name: str, ov: dict, out_dir: str = "/tmp/ov_fits") -> None:
    os.makedirs(out_dir, exist_ok=True)
    vis = load_vis(ov)
    img_path = ov["image"].replace("res://", "")
    im = Image.open(os.path.join(ROOT, img_path)).convert("RGB")
    from PIL import ImageDraw

    gx, gy = load_wp_gs(map_name)
    b, a, d, c = ov["affine"]
    if int(ov.get("fit_rot", ov.get("rotated", 0))) == 1:
        px, py = b * gy + a, d * gx + c
    else:
        px, py = b * gx + a, d * gy + c
    dr = ImageDraw.Draw(im)
    for x, y in zip(px, py):
        dr.ellipse([x - 2, y - 2, x + 2, y + 2], fill=(80, 255, 120))
    with open(os.path.join(ROOT, "data", "maps", f"{map_name}.json")) as f:
        md = json.load(f)
    for e in md.get("ct_spawns", []):
        p = e["pos"]
        X, Y = (b * (p[2] / 0.03125) + a, d * (p[0] / 0.03125) + c) if int(ov.get("fit_rot", ov.get("rotated", 0))) == 1 else (b * (p[0] / 0.03125) + a, d * (p[2] / 0.03125) + c)
        dr.ellipse([X - 5, Y - 5, X + 5, Y + 5], fill=(70, 140, 255))
    for e in md.get("t_spawns", []):
        p = e["pos"]
        X, Y = (b * (p[2] / 0.03125) + a, d * (p[0] / 0.03125) + c) if int(ov.get("fit_rot", ov.get("rotated", 0))) == 1 else (b * (p[0] / 0.03125) + a, d * (p[2] / 0.03125) + c)
        dr.ellipse([X - 5, Y - 5, X + 5, Y + 5], fill=(255, 70, 50))
    for e in md.get("bombsites", []):
        p = e["center"]
        X, Y = (b * (p[2] / 0.03125) + a, d * (p[0] / 0.03125) + c) if int(ov.get("fit_rot", ov.get("rotated", 0))) == 1 else (b * (p[0] / 0.03125) + a, d * (p[2] / 0.03125) + c)
        dr.ellipse([X - 7, Y - 7, X + 7, Y + 7], outline=(255, 220, 40), width=2)
    im.save(os.path.join(out_dir, f"{map_name}.png"))


def main() -> None:
    with open(OVERVIEWS_PATH) as f:
        overviews = json.load(f)
    maps_dir = os.path.join(ROOT, "data", "maps")
    updated = {}
    for map_name in sorted(overviews.keys()):
        if not os.path.exists(os.path.join(maps_dir, f"{map_name}.json")):
            print(f"[SKIP] {map_name}: no map json")
            updated[map_name] = overviews[map_name]
            continue
        updated[map_name] = fit_map(map_name, overviews[map_name])
        if "affine" in updated[map_name]:
            save_debug_overlay(map_name, updated[map_name])
    with open(OVERVIEWS_PATH, "w", encoding="utf-8") as f:
        json.dump(updated, f, indent=1)
    covs = [v["fit_coverage"] for v in updated.values() if "fit_coverage" in v]
    print(f"[DONE] {len(covs)} maps fitted, coverage min={min(covs):.3f} avg={sum(covs)/len(covs):.3f}")


if __name__ == "__main__":
    main()
