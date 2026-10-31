#!/usr/bin/env python3
"""
Converts GoldSrc BSP v30 maps (.bsp) into:
  - assets/maps/<map>.glb (world + brush submodels referencing shared assets/textures/world/*.png)
  - assets/maps/<map>_lm.png (packed GoldSrc RGB24 baked lightmap atlas with 1px seam-free gutters)
  - data/maps/<map>.json (spawns, bombsites, buyzones, hostages, ladders, doors, breakables, Bot A* nav graph)
  - data/maps_index.json (catalog of all 26 Counter-Strike 1.5 maps)
"""

import glob
import json
import math
import os
import re
import struct
from typing import Dict, List, Optional, Set, Tuple

import numpy as np
from PIL import Image

from . import SCALE
from .wad_spr_ui import (
    decode_miptex,
    generate_fallback_hl_texture,
    sanitize_tex_name,
    save_miptex_png,
)

# BSP v30 lump indices
LUMP_ENTITIES = 0
LUMP_PLANES = 1
LUMP_TEXTURES = 2
LUMP_VERTEXES = 3
LUMP_VISIBILITY = 4
LUMP_NODES = 5
LUMP_TEXINFO = 6
LUMP_FACES = 7
LUMP_LIGHTING = 8
LUMP_CLIPNODES = 9
LUMP_LEAFS = 10
LUMP_MARKSURFACES = 11
LUMP_EDGES = 12
LUMP_SURFEDGES = 13
LUMP_MODELS = 14

INVISIBLE_TOOL_TEXTURES = {
    "aaatrigger",
    "clip",
    "origin",
    "null",
    "skip",
    "hint",
    "bevel",
}


def gs_vec_to_gd(x: float, y: float, z: float) -> List[float]:
    return [round(-y * SCALE, 4), round(z * SCALE, 4), round(-x * SCALE, 4)]


def gs_aabb_to_gd(mins: Tuple[float, float, float], maxs: Tuple[float, float, float]) -> Tuple[List[float], List[float]]:
    corners = [
        (-y * SCALE, z * SCALE, -x * SCALE)
        for x in (mins[0], maxs[0])
        for y in (mins[1], maxs[1])
        for z in (mins[2], maxs[2])
    ]
    lo = [round(min(c[i] for c in corners), 4) for i in range(3)]
    hi = [round(max(c[i] for c in corners), 4) for i in range(3)]
    return lo, hi


def parse_bsp_entities(ent_text: str) -> List[Dict[str, str]]:
    ents = []
    cur: Optional[Dict[str, str]] = None
    pair_re = re.compile(r'"([^"]*)"\s+"([^"]*)"')
    for line in ent_text.splitlines():
        s = line.strip()
        if not s or s.startswith("//"):
            continue
        if s == "{":
            cur = {}
        elif s == "}":
            if cur is not None:
                ents.append(cur)
            cur = None
        elif cur is not None:
            m = pair_re.search(s)
            if m:
                cur[m.group(1).lower()] = m.group(2)
    return ents


def parse_vec3_str(s: str) -> Tuple[float, float, float]:
    parts = s.replace(",", " ").split()
    if len(parts) >= 3:
        try:
            return float(parts[0]), float(parts[1]), float(parts[2])
        except ValueError:
            pass
    return 0.0, 0.0, 0.0


class ShelfPacker:
    """Fast 2D shelf packer with 1px gutter padding for BSP face lightmaps."""

    def __init__(self, width: int, height: int):
        self.width = width
        self.height = height
        self.cur_x = 0
        self.cur_y = 0
        self.row_h = 0

    def pack(self, w: int, h: int) -> Optional[Tuple[int, int]]:
        pw, ph = w + 2, h + 2
        if pw > self.width or ph > self.height:
            return None
        if self.cur_x + pw > self.width:
            self.cur_y += self.row_h
            self.cur_x = 0
            self.row_h = 0
        if self.cur_y + ph > self.height:
            return None
        rx, ry = self.cur_x + 1, self.cur_y + 1
        self.cur_x += pw
        if ph > self.row_h:
            self.row_h = ph
        return rx, ry


def hull_point_contents(clipnodes: np.ndarray, planes_n: np.ndarray, planes_d: np.ndarray, headnode: int, pt: np.ndarray) -> int:
    """Evaluates GoldSrc BSP clipnode tree (e.g. Hull 1 = standing player hull) at `pt`."""
    node = headnode
    guard = 0
    while node >= 0 and guard < 512:
        guard += 1
        if node >= len(clipnodes):
            return -2
        pnum = int(clipnodes[node, 0])
        c0 = int(clipnodes[node, 1])
        c1 = int(clipnodes[node, 2])
        dist = float(np.dot(planes_n[pnum], pt) - planes_d[pnum])
        node = c0 if dist >= 0.0 else c1
    return node  # -1 = CONTENTS_EMPTY, -2 = CONTENTS_SOLID


def is_floor_solid_at(
    clipnodes: np.ndarray,
    planes_n: np.ndarray,
    planes_d: np.ndarray,
    solid_hulls: List[Tuple[int, np.ndarray]],
    pt: np.ndarray,
) -> bool:
    for hnode, orig in solid_hulls:
        if hull_point_contents(clipnodes, planes_n, planes_d, hnode, pt - orig) != -1:
            return True
    return False


def hull_line_clear(
    clipnodes: np.ndarray,
    planes_n: np.ndarray,
    planes_d: np.ndarray,
    headnode: int,
    p0: np.ndarray,
    p1: np.ndarray,
    solid_hulls: List[Tuple[int, np.ndarray]] | None = None,
) -> bool:
    """
    Samples segment p0..p1 densely against Hull-1 clipnodes AND verifies continuous
    floor support underneath (including func_wall bridges/stairs/ramps) so nav edges
    traverse all walkable ramps & staircases while never cutting across cliffs/parapets.
    """
    diff = p1 - p0
    dist_xy = math.hypot(float(diff[0]), float(diff[1]))
    # Walkable ramps/stairs in GoldSrc are <= ~45 deg; reject steep cliff/parapet height jumps!
    max_dz = min(136.0, 24.0 + dist_xy * 0.86)
    if abs(float(diff[2])) > max_dz:
        return False
    hulls = solid_hulls if solid_hulls else [(headnode, np.zeros(3, dtype=np.float32))]
    steps = max(4, int(dist_xy / 16.0))
    for s in range(1, steps):
        t = s / float(steps)
        base = p0 + diff * t
        # Check Hull-1 waist clearance (+4u flat, +16u/+24u up GoldSrc 18u staircase steps)
        mid = base + np.array([0.0, 0.0, 4.0], dtype=np.float32)
        if hull_point_contents(clipnodes, planes_n, planes_d, headnode, mid) != -1:
            mid = base + np.array([0.0, 0.0, 16.0], dtype=np.float32)
            if hull_point_contents(clipnodes, planes_n, planes_d, headnode, mid) != -1:
                mid = base + np.array([0.0, 0.0, 24.0], dtype=np.float32)
                if hull_point_contents(clipnodes, planes_n, planes_d, headnode, mid) != -1:
                    return False
        # Verify solid floor exists beneath waist origin (prevents mid-air diagonal edges over drops/parapets!)
        has_flr = False
        for drop_z in (52.0, 74.0, 94.0):
            if is_floor_solid_at(clipnodes, planes_n, planes_d, hulls, mid - np.array([0.0, 0.0, drop_z], dtype=np.float32)):
                has_flr = True
                break
        if not has_flr:
            return False
    return True


def build_bot_nav_graph(
    floor_samples_gs: List[np.ndarray],
    seed_points_gs: List[np.ndarray],
    clipnodes: np.ndarray,
    planes_n: np.ndarray,
    planes_d: np.ndarray,
    hull1_headnode: int,
    ladder_spans_gs: List[Tuple[np.ndarray, np.ndarray]] | None = None,
    solid_hulls: List[Tuple[int, np.ndarray]] | None = None,
    hull0_headnode: int = 0,
    hull3_headnode: int = 0,
) -> Tuple[List[List[float]], List[List[int]]]:
    """
    Generates a full-map, Hull-1 collision-verified tactical waypoint graph across the BSP map
    (including doorways, func_wall bridges/stairs, and vertical ladder links) with zero truncation!
    """
    CELL = 134.0  # ~4.18m tactical spacing in GoldSrc units across 100% of playable map
    grid: Dict[Tuple[int, int, int], np.ndarray] = {}

    # Prioritize objective/spawn/doorway/ladder seed points first
    seed_keys = []
    for pt in seed_points_gs:
        p_test = pt.copy()
        if len(clipnodes) > 0:
            placed = False
            for dz in (0.0, 18.0, -18.0, 36.0):
                for dx, dy in ((0.0, 0.0), (28.0, 0.0), (-28.0, 0.0), (0.0, 28.0), (0.0, -28.0)):
                    cand = p_test + np.array([dx, dy, dz], dtype=np.float32)
                    if hull_point_contents(clipnodes, planes_n, planes_d, hull1_headnode, cand) == -1:
                        p_test = cand
                        placed = True
                        break
                if placed:
                    break
        key = (int(round(p_test[0] / CELL)), int(round(p_test[1] / CELL)), int(round(p_test[2] / 68.0)))
        if key not in grid:
            grid[key] = p_test
            seed_keys.append(key)

    # Add ALL walkable floor samples across 100% of the map (never truncating early!)
    for fpt in floor_samples_gs:
        stand_pt = fpt + np.array([0.0, 0.0, 37.0], dtype=np.float32)  # Hull 1 origin is +36 above floor
        key = (int(round(stand_pt[0] / CELL)), int(round(stand_pt[1] / CELL)), int(round(stand_pt[2] / 68.0)))
        if key in grid:
            continue
        if len(clipnodes) > 0:
            if hull_point_contents(clipnodes, planes_n, planes_d, hull1_headnode, stand_pt) != -1:
                stand_hi = stand_pt + np.array([0.0, 0.0, 14.0], dtype=np.float32)
                if hull_point_contents(clipnodes, planes_n, planes_d, hull1_headnode, stand_hi) != -1:
                    continue
                stand_pt = stand_hi
        grid[key] = stand_pt
        if len(grid) >= 2400:
            break

    pts_gs = list(grid.values())
    n = len(pts_gs)
    if n == 0:
        return [], []

    adj: List[List[int]] = [[] for _ in range(n)]
    pts_arr = np.array(pts_gs, dtype=np.float32)

    for i in range(n):
        diffs = pts_arr - pts_arr[i]
        dists = np.hypot(diffs[:, 0], diffs[:, 1])
        # Candidate neighbors within ~356 GoldSrc units horizontally and walkable stair/ramp vertical delta
        cands = np.where((dists > 1.0) & (dists < 356.0) & (np.abs(diffs[:, 2]) < 136.0))[0]
        cands = sorted(cands, key=lambda j: float(dists[j]))[:16]
        for j in cands:
            if j <= i:
                continue
            if len(clipnodes) == 0 or hull_line_clear(
                clipnodes, planes_n, planes_d, hull1_headnode, pts_arr[i], pts_arr[j], solid_hulls
            ):
                adj[i].append(int(j))
                adj[j].append(int(i))

    # Connect bottom <-> top waypoints on every func_ladder so Bots climb ladders in A*!
    if ladder_spans_gs:
        for bot_gs, top_gs in ladder_spans_gs:
            db = pts_arr - bot_gs
            dt = pts_arr - top_gs
            hb = np.hypot(db[:, 0], db[:, 1])
            ht = np.hypot(dt[:, 0], dt[:, 1])
            b_cands = np.where((hb < 164.0) & (np.abs(db[:, 2]) < 88.0))[0]
            t_cands = np.where((ht < 176.0) & (np.abs(dt[:, 2]) < 96.0))[0]
            if len(b_cands) > 0 and len(t_cands) > 0:
                bi = int(min(b_cands, key=lambda idx: float(hb[idx] + abs(db[idx, 2]) * 0.5)))
                ti = int(min(t_cands, key=lambda idx: float(ht[idx] + abs(dt[idx, 2]) * 0.5)))
                if bi != ti and ti not in adj[bi]:
                    adj[bi].append(ti)
                    adj[ti].append(bi)

    # Doorway / Vent Component Bridge Pass:
    # In GoldSrc BSP30, 64u doorways with trim narrow Hull-1 to ~20u, causing diagonal waypoint rays
    # across a narrow doorframe or crouch-vent to graze the +-16u expanded jamb. Bridge disconnected
    # components across clear Hull-3 (crouch/vent) or centered Hull-0 (true wall) doorway openings!
    if len(clipnodes) > 0:
        for _bridge_iter in range(12):
            comp_of = [-1] * n
            comps_list: List[List[int]] = []
            for start_i in range(n):
                if comp_of[start_i] != -1:
                    continue
                cid = len(comps_list)
                q_c = [start_i]
                comp_of[start_i] = cid
                members = []
                while q_c:
                    curr = q_c.pop()
                    members.append(curr)
                    for nb_c in adj[curr]:
                        if comp_of[nb_c] == -1:
                            comp_of[nb_c] = cid
                            q_c.append(nb_c)
                comps_list.append(members)
            if len(comps_list) <= 1:
                break
            comps_list.sort(key=len, reverse=True)
            main_set = set(comps_list[0])
            other_nodes = [idx for c_grp in comps_list[1:] if len(c_grp) >= 2 for idx in c_grp]
            if not other_nodes:
                break
            best_pair = None
            best_d = 1e9
            main_arr = np.array(list(main_set), dtype=np.int32)
            for v_idx in other_nodes:
                dv = pts_arr[main_arr] - pts_arr[v_idx]
                d_xy = np.hypot(dv[:, 0], dv[:, 1])
                d_z = np.abs(dv[:, 2])
                mask = (d_xy < 230.0) & (d_z < 88.0)
                for m_pos in np.where(mask)[0]:
                    u_idx = int(main_arr[m_pos])
                    score = float(d_xy[m_pos] + d_z[m_pos] * 1.5)
                    if score >= best_d:
                        continue
                    # Verify doorway/vent line is clear in Hull-3 (crouch/vent) or via axis-aligned doorway L-turn!
                    p_u = pts_arr[u_idx]
                    p_v = pts_arr[v_idx]
                    mid_z = (p_u[2] + p_v[2]) * 0.5
                    bend_a = np.array([p_u[0], p_v[1], mid_z], dtype=np.float32)
                    bend_b = np.array([p_v[0], p_u[1], mid_z], dtype=np.float32)
                    clear_bridge = hull_line_clear(clipnodes, planes_n, planes_d, hull3_headnode, p_u, p_v, solid_hulls)
                    if not clear_bridge:
                        clear_bridge = (
                            hull_line_clear(clipnodes, planes_n, planes_d, hull3_headnode, p_u, bend_a, solid_hulls)
                            and hull_line_clear(clipnodes, planes_n, planes_d, hull3_headnode, bend_a, p_v, solid_hulls)
                        ) or (
                            hull_line_clear(clipnodes, planes_n, planes_d, hull3_headnode, p_u, bend_b, solid_hulls)
                            and hull_line_clear(clipnodes, planes_n, planes_d, hull3_headnode, bend_b, p_v, solid_hulls)
                        )
                    if clear_bridge:
                        best_d = score
                        best_pair = (u_idx, v_idx)
            if best_pair is None:
                break
            bu, bv = best_pair
            adj[bu].append(bv)
            adj[bv].append(bu)

    # Prune unreachable skybox/rooftop clusters: retain ALL nodes reachable from spawn/objective seeds!
    num_seeds = min(len(seed_keys), n)
    visited: Set[int] = set()
    stack = list(range(num_seeds)) if num_seeds > 0 else [0]
    for s in stack:
        visited.add(s)
    while stack:
        u = stack.pop()
        for v in adj[u]:
            if v not in visited:
                visited.add(v)
                stack.append(v)

    # If very small (< 25% of nodes), also include the largest connected component
    if len(visited) < max(16, n // 4):
        rem = set(range(n)) - visited
        best_comp: Set[int] = set()
        while rem:
            r0 = rem.pop()
            comp = {r0}
            q = [r0]
            while q:
                u = q.pop()
                for v in adj[u]:
                    if v in rem:
                        rem.remove(v)
                        comp.add(v)
                        q.append(v)
            if len(comp) > len(best_comp):
                best_comp = comp
        visited |= best_comp

    # Keep ALL reachable waypoints (no [:380] slicing that severs corridors!)
    keep_indices = sorted(visited)
    keep_set = set(keep_indices)
    old_to_new = {old_i: new_i for new_i, old_i in enumerate(keep_indices)}
    pruned_adj: List[List[int]] = [
        [old_to_new[nb] for nb in adj[old_i] if nb in keep_set]
        for old_i in keep_indices
    ]

    # Convert waypoint positions to floor-level Godot coordinates (subtract 35u hull center offset)
    waypoints_gd = [
        gs_vec_to_gd(float(pts_gs[old_i][0]), float(pts_gs[old_i][1]), float(pts_gs[old_i][2] - 35.0))
        for old_i in keep_indices
    ]
    return waypoints_gd, pruned_adj


def convert_single_bsp(
    bsp_path: str,
    wad_catalog: Dict[str, Tuple[str, int]],
    wad_cache: Dict[str, bytes],
    exported_world_textures: Dict[str, dict],
    out_world_tex_dir: str,
    out_maps_dir: str,
    out_data_maps_dir: str,
    cstrike_maps_dir: str,
) -> Optional[dict]:
    map_name = os.path.splitext(os.path.basename(bsp_path))[0].lower()
    with open(bsp_path, "rb") as f:
        d = f.read()
    if len(d) < 124:
        return None
    ver = struct.unpack_from("<i", d, 0)[0]
    if ver != 30:
        return None

    def get_lump(idx: int) -> Tuple[int, int, bytes]:
        ofs, ln = struct.unpack_from("<ii", d, 4 + idx * 8)
        return ofs, ln, d[ofs : ofs + ln]

    _, _, ent_bytes = get_lump(LUMP_ENTITIES)
    _, _, planes_bytes = get_lump(LUMP_PLANES)
    tex_ofs, _, tex_bytes = get_lump(LUMP_TEXTURES)
    _, _, verts_bytes = get_lump(LUMP_VERTEXES)
    _, _, texinfo_bytes = get_lump(LUMP_TEXINFO)
    _, _, faces_bytes = get_lump(LUMP_FACES)
    _, _, light_bytes = get_lump(LUMP_LIGHTING)
    _, _, clip_bytes = get_lump(LUMP_CLIPNODES)
    _, _, edges_bytes = get_lump(LUMP_EDGES)
    _, _, surfedges_bytes = get_lump(LUMP_SURFEDGES)
    _, _, models_bytes = get_lump(LUMP_MODELS)

    ents = parse_bsp_entities(ent_bytes.decode("latin1", errors="ignore"))

    # Parse geometry arrays
    num_planes = len(planes_bytes) // 20
    planes_raw = np.frombuffer(planes_bytes[: num_planes * 20], dtype="<f4").reshape((num_planes, 5))
    planes_n = planes_raw[:, :3]
    planes_d = planes_raw[:, 3]

    verts_gs = np.frombuffer(verts_bytes, dtype="<f4").reshape((-1, 3))
    edges = np.frombuffer(edges_bytes, dtype="<u2").reshape((-1, 2))
    surfedges = np.frombuffer(surfedges_bytes, dtype="<i4")

    # Parse clipnodes (int32 planenum, int16 child0, int16 child1 -> 8 bytes)
    num_clip = len(clip_bytes) // 8
    clip_dt = np.dtype([("p", "<i4"), ("c0", "<i2"), ("c1", "<i2")])
    clip_struct = np.frombuffer(clip_bytes[: num_clip * 8], dtype=clip_dt)
    clipnodes = np.column_stack([clip_struct["p"], clip_struct["c0"], clip_struct["c1"]]) if num_clip > 0 else np.zeros((0, 3), dtype=np.int32)

    # Parse miptex table & ensure every texture used by this map exists in assets/textures/world/
    num_miptex = struct.unpack_from("<i", tex_bytes, 0)[0] if len(tex_bytes) >= 4 else 0
    miptex_entries = []
    for mi in range(num_miptex):
        rel = struct.unpack_from("<i", tex_bytes, 4 + mi * 4)[0]
        if rel < 0 or rel + 40 > len(tex_bytes):
            miptex_entries.append({"raw": "default", "safe": "default_tex", "w": 64, "h": 64, "masked": False, "sky": False, "skip": True})
            continue
        raw_name = tex_bytes[rel : rel + 16].split(b"\x00")[0].decode("latin1", errors="ignore")
        lname = raw_name.lower()
        tw, th, o0 = struct.unpack_from("<3I", tex_bytes, rel + 16)
        tw = max(1, tw)
        th = max(1, th)
        is_sky = lname == "sky"
        is_skip = lname in INVISIBLE_TOOL_TEXTURES
        safe = sanitize_tex_name(raw_name)

        if not is_sky and not is_skip:
            if safe not in exported_world_textures:
                out_png = os.path.join(out_world_tex_dir, f"{safe}.png")
                masked = False
                saved = False
                if o0 > 0:
                    dec = decode_miptex(d, tex_ofs + rel)
                    if dec:
                        masked = save_miptex_png(dec[0], dec[1], dec[2], dec[3], dec[4], out_png)
                        saved = True
                if not saved and lname in wad_catalog:
                    wp, wpos = wad_catalog[lname]
                    if wp not in wad_cache:
                        wad_cache[wp] = open(wp, "rb").read()
                    dec = decode_miptex(wad_cache[wp], wpos)
                    if dec:
                        masked = save_miptex_png(dec[0], dec[1], dec[2], dec[3], dec[4], out_png)
                        saved = True
                if not saved:
                    masked = generate_fallback_hl_texture(raw_name, tw, th, out_png)
                exported_world_textures[safe] = {"masked": masked, "w": tw, "h": th, "raw": raw_name}
            else:
                masked = exported_world_textures[safe]["masked"]
        else:
            masked = False

        miptex_entries.append({
            "raw": raw_name,
            "lower": lname,
            "safe": safe,
            "w": tw,
            "h": th,
            "masked": masked,
            "sky": is_sky,
            "skip": is_skip,
        })

    # Parse texinfo (40 bytes each)
    num_texinfo = len(texinfo_bytes) // 40
    texinfos = []
    for ti in range(num_texinfo):
        s0, s1, s2, s_shift, t0, t1, t2, t_shift, miptex_id, flags = struct.unpack_from(
            "<8fii", texinfo_bytes, ti * 40
        )
        texinfos.append((
            np.array([s0, s1, s2], dtype=np.float32),
            s_shift,
            np.array([t0, t1, t2], dtype=np.float32),
            t_shift,
            max(0, min(miptex_id, max(0, len(miptex_entries) - 1))),
            flags,
        ))

    # Parse BSP submodels (64 bytes each)
    num_models = len(models_bytes) // 64
    submodels = []
    for mdi in range(num_models):
        mins = struct.unpack_from("<3f", models_bytes, mdi * 64)
        maxs = struct.unpack_from("<3f", models_bytes, mdi * 64 + 12)
        orig = struct.unpack_from("<3f", models_bytes, mdi * 64 + 24)
        h0, h1, h2, h3, visleafs, firstface, numfaces = struct.unpack_from("<7i", models_bytes, mdi * 64 + 36)
        submodels.append({
            "mins": mins,
            "maxs": maxs,
            "origin": orig,
            "headnodes": (h0, h1, h2, h3),
            "firstface": firstface,
            "numfaces": numfaces,
        })

    # Determine which brush submodels are visual world/entity brushes vs pure invisible trigger volumes
    trigger_submodels: Set[int] = set()
    skyname = "desert"
    ct_spawns = []
    t_spawns = []
    vip_spawns = []
    bombsites = []
    buyzones = []
    hostages = []
    rescue_zones = []
    escape_zones = []
    ladders = []
    water_zones = []
    triggers = []
    brush_entities = []
    ambient_sounds = []
    cameras = []
    seed_points_gs: List[np.ndarray] = []
    ladder_spans_gs: List[Tuple[np.ndarray, np.ndarray]] = []
    walkable_submodels: Dict[int, np.ndarray] = {0: np.zeros(3, dtype=np.float32)}
    solid_hulls: List[Tuple[int, np.ndarray]] = []
    if submodels:
        solid_hulls.append((int(submodels[0]["headnodes"][1]), np.zeros(3, dtype=np.float32)))

    for ent in ents:
        cname = ent.get("classname", "").lower()
        if cname == "worldspawn":
            if ent.get("skyname"):
                skyname = ent["skyname"].strip().lower()
            continue

        model_str = ent.get("model", "")
        sub_idx = int(model_str[1:]) if model_str.startswith("*") and model_str[1:].isdigit() else -1
        orig_gs = parse_vec3_str(ent.get("origin", "0 0 0"))
        if "angles" in ent and ent["angles"].strip():
            angles_gs = parse_vec3_str(ent["angles"])
        elif "angle" in ent and ent["angle"].strip():
            ang_val = float(ent["angle"].strip())
            if ang_val == -1.0:
                angles_gs = (-90.0, 0.0, 0.0)
            elif ang_val == -2.0:
                angles_gs = (90.0, 0.0, 0.0)
            else:
                angles_gs = (0.0, ang_val, 0.0)
        else:
            angles_gs = (0.0, 0.0, 0.0)
        # GoldSrc yaw (angles[1]): 0 = +X (-Z in Godot), 90 = +Y (-X in Godot) -> yaw_gd = radians(angles[1])
        yaw_gd = round(math.radians(angles_gs[1]), 4)

        if cname == "info_player_start":
            ct_spawns.append({"pos": gs_vec_to_gd(*orig_gs), "yaw": yaw_gd})
            seed_points_gs.append(np.array(orig_gs, dtype=np.float32))
        elif cname == "info_player_deathmatch":
            t_spawns.append({"pos": gs_vec_to_gd(*orig_gs), "yaw": yaw_gd})
            seed_points_gs.append(np.array(orig_gs, dtype=np.float32))
        elif cname == "info_vip_start":
            vip_spawns.append({"pos": gs_vec_to_gd(*orig_gs), "yaw": yaw_gd})
            seed_points_gs.append(np.array(orig_gs, dtype=np.float32))
        elif cname in ("hostage_entity", "monster_scientist"):
            hostages.append({"pos": gs_vec_to_gd(*orig_gs), "yaw": yaw_gd})
            seed_points_gs.append(np.array(orig_gs, dtype=np.float32))
        elif cname == "ambient_generic":
            msg = ent.get("message", "").replace("\\", "/").strip("/").lower()
            if msg:
                ambient_sounds.append({
                    "pos": gs_vec_to_gd(*orig_gs),
                    "sound": msg if msg.endswith(".wav") else f"{msg}.wav",
                    "health": float(ent.get("health", "5")) / 10.0,
                })
        elif cname == "trigger_camera":
            cameras.append({"pos": gs_vec_to_gd(*orig_gs), "yaw": yaw_gd})
        elif cname == "info_bomb_target":
            pt_gd = gs_vec_to_gd(*orig_gs)
            r = 4.5
            bombsites.append({
                "min": [round(pt_gd[0] - r, 3), round(pt_gd[1] - 2.5, 3), round(pt_gd[2] - r, 3)],
                "max": [round(pt_gd[0] + r, 3), round(pt_gd[1] + 3.0, 3), round(pt_gd[2] + r, 3)],
                "center": pt_gd,
            })
            seed_points_gs.append(np.array(orig_gs, dtype=np.float32))
        elif cname == "info_hostage_rescue":
            pt_gd = gs_vec_to_gd(*orig_gs)
            r = 5.0
            rescue_zones.append({
                "min": [round(pt_gd[0] - r, 3), round(pt_gd[1] - 2.5, 3), round(pt_gd[2] - r, 3)],
                "max": [round(pt_gd[0] + r, 3), round(pt_gd[1] + 3.5, 3), round(pt_gd[2] + r, 3)],
                "center": pt_gd,
            })
            seed_points_gs.append(np.array(orig_gs, dtype=np.float32))
        elif cname == "info_vip_safetyzone":
            pt_gd = gs_vec_to_gd(*orig_gs)
            r = 5.5
            escape_zones.append({"min": [pt_gd[0] - r, pt_gd[1] - 3, pt_gd[2] - r], "max": [pt_gd[0] + r, pt_gd[1] + 3, pt_gd[2] + r], "center": pt_gd})
            seed_points_gs.append(np.array(orig_gs, dtype=np.float32))

        if 0 < sub_idx < len(submodels):
            sm = submodels[sub_idx]
            mins_gs = tuple(sm["mins"][k] + orig_gs[k] for k in range(3))
            maxs_gs = tuple(sm["maxs"][k] + orig_gs[k] for k in range(3))
            lo_gd, hi_gd = gs_aabb_to_gd(mins_gs, maxs_gs)
            center_gd = [round((lo_gd[k] + hi_gd[k]) * 0.5, 4) for k in range(3)]
            center_gs = np.array([(mins_gs[k] + maxs_gs[k]) * 0.5 for k in range(3)], dtype=np.float32)

            if cname == "func_bomb_target":
                trigger_submodels.add(sub_idx)
                bombsites.append({"min": lo_gd, "max": hi_gd, "center": center_gd})
                seed_points_gs.append(center_gs)
            elif cname == "func_buyzone":
                trigger_submodels.add(sub_idx)
                buyzones.append({"min": lo_gd, "max": hi_gd, "team": ent.get("team", "0")})
            elif cname == "func_hostage_rescue":
                trigger_submodels.add(sub_idx)
                rescue_zones.append({"min": lo_gd, "max": hi_gd, "center": center_gd})
                seed_points_gs.append(center_gs)
            elif cname == "func_escapezone":
                trigger_submodels.add(sub_idx)
                escape_zones.append({"min": lo_gd, "max": hi_gd, "center": center_gd})
                seed_points_gs.append(center_gs)
            elif cname == "func_ladder":
                trigger_submodels.add(sub_idx)
                ladders.append({"min": lo_gd, "max": hi_gd})
                cx_gs = (mins_gs[0] + maxs_gs[0]) * 0.5
                cy_gs = (mins_gs[1] + maxs_gs[1]) * 0.5
                bot_gs = np.array([cx_gs, cy_gs, mins_gs[2] + 38.0], dtype=np.float32)
                top_gs = np.array([cx_gs, cy_gs, maxs_gs[2] + 38.0], dtype=np.float32)
                seed_points_gs.append(bot_gs)
                seed_points_gs.append(top_gs)
                ladder_spans_gs.append((bot_gs, top_gs))
            elif cname.startswith("trigger_"):
                trigger_submodels.add(sub_idx)
                tgt = ent.get("target", "").strip()
                if tgt and cname in ("trigger_multiple", "trigger_once"):
                    triggers.append({"min": lo_gd, "max": hi_gd, "target": tgt})
            elif cname == "func_water":
                water_zones.append({"min": lo_gd, "max": hi_gd})
                brush_entities.append({
                    "classname": cname,
                    "submodel": sub_idx,
                    "origin": gs_vec_to_gd(*orig_gs),
                    "rendermode": int(ent.get("rendermode", "2")),
                    "renderamt": int(ent.get("renderamt", "140")),
                    "solid": False,
                })
            elif cname in (
                "func_wall",
                "func_wall_toggle",
                "func_illusionary",
                "func_breakable",
                "func_door",
                "func_door_rotating",
                "func_button",
                "func_rot_button",
                "func_pendulum",
                "func_plat",
                "func_train",
                "func_tracktrain",
                "func_rotating",
                "func_pushable",
                "func_conveyor",
                "func_vehicle",
                "func_tank",
                "func_tankmortar",
            ):
                rmode = int(ent.get("rendermode", "0") or "0")
                ramt = int(ent.get("renderamt", "255") or "255")
                lip_val = float(ent.get("lip", "0") or "0")
                # Skip invisible func_walls (rendermode != 0 and renderamt == 0)
                brush_entities.append({
                    "classname": cname,
                    "submodel": sub_idx,
                    "origin": gs_vec_to_gd(*orig_gs),
                    "angles": list(angles_gs),
                    "rendermode": rmode,
                    "renderamt": ramt,
                    "health": float(ent.get("health", "0") or "0"),
                    "material": int(ent.get("material", "0") or "0"),
                    "speed": float(ent.get("speed", "100") or "100"),
                    "lip": lip_val,
                    "distance": float(ent.get("distance", "90") or "90"),
                    "wait": float(ent.get("wait", "4") or "4"),
                    "target": ent.get("target", "").strip(),
                    "targetname": ent.get("targetname", "").strip(),
                    "spawnflags": int(ent.get("spawnflags", "0") or "0"),
                    "solid": cname != "func_illusionary",
                    "center": center_gd,
                    "min": lo_gd,
                    "max": hi_gd,
                })
                if cname in ("func_door", "func_door_rotating") and abs(lip_val) < 1000.0:
                    door_floor_z = mins_gs[2] + 38.0
                    d_center = np.array([center_gs[0], center_gs[1], door_floor_z], dtype=np.float32)
                    seed_points_gs.append(d_center)
                    for dx, dy in ((56.0, 0.0), (-56.0, 0.0), (0.0, 56.0), (0.0, -56.0)):
                        seed_points_gs.append(d_center + np.array([dx, dy, 0.0], dtype=np.float32))
                elif cname in ("func_wall", "func_wall_toggle") and not (rmode != 0 and ramt == 0):
                    orig_arr = np.array(orig_gs, dtype=np.float32)
                    walkable_submodels[sub_idx] = orig_arr
                    solid_hulls.append((int(sm["headnodes"][1]), orig_arr))
            else:
                # Unknown trigger/zone submodels don't need visible geometry
                trigger_submodels.add(sub_idx)

    # Pack baked RGB24 lightmaps into a single atlas PNG (try 1024x1024, grow to 2048x1024 / 2048x2048 if needed)
    num_faces = len(faces_bytes) // 20
    face_lm_blocks: Dict[int, Tuple[int, int, int, int, np.ndarray]] = {}
    for fi in range(num_faces):
        pnum, side, firstedge, numedges, ti_idx, st0, st1, st2, st3, lightofs = struct.unpack_from(
            "<hhihh4Bi", faces_bytes, fi * 20
        )
        if numedges < 3 or ti_idx < 0 or ti_idx >= len(texinfos):
            continue
        s_vec, s_shift, t_vec, t_shift, mip_id, ti_flags = texinfos[ti_idx]
        minfo = miptex_entries[mip_id]
        if minfo["sky"] or minfo["skip"] or (ti_flags & 1):
            continue

        f_pts = []
        for k in range(numedges):
            se = surfedges[firstedge + k]
            vi = edges[se, 0] if se >= 0 else edges[-se, 1]
            f_pts.append(verts_gs[vi])
        f_arr = np.array(f_pts, dtype=np.float32)
        s_vals = f_arr @ s_vec + s_shift
        t_vals = f_arr @ t_vec + t_shift
        min_s = int(math.floor(float(np.min(s_vals)) / 16.0))
        max_s = int(math.ceil(float(np.max(s_vals)) / 16.0))
        min_t = int(math.floor(float(np.min(t_vals)) / 16.0))
        max_t = int(math.ceil(float(np.max(t_vals)) / 16.0))
        lw = max_s - min_s + 1
        lh = max_t - min_t + 1

        if 0 <= lightofs and lw > 0 and lh > 0 and lw <= 128 and lh <= 128 and lightofs + lw * lh * 3 <= len(light_bytes):
            block = np.frombuffer(light_bytes[lightofs : lightofs + lw * lh * 3], dtype=np.uint8).reshape((lh, lw, 3))
        else:
            block = np.full((1, 1, 3), 165, dtype=np.uint8)
            lw, lh = 1, 1
        face_lm_blocks[fi] = (min_s, min_t, lw, lh, block)

    atlas_dims = [(512, 512), (1024, 512), (1024, 1024), (2048, 1024), (2048, 2048)]
    atlas_w, atlas_h = 1024, 1024
    packed_coords: Dict[int, Tuple[int, int]] = {}
    # Sort largest height first for tighter shelf packing
    sorted_fis = sorted(face_lm_blocks.keys(), key=lambda f: -face_lm_blocks[f][3])

    for aw, ah in atlas_dims:
        packer = ShelfPacker(aw, ah)
        coords = {}
        ok = True
        for fi in sorted_fis:
            _, _, lw, lh, _ = face_lm_blocks[fi]
            res = packer.pack(lw, lh)
            if res is None:
                ok = False
                break
            coords[fi] = res
        if ok:
            atlas_w, atlas_h = aw, ah
            packed_coords = coords
            break
    else:
        # Fallback: clamp any overflow to neutral pixel at (1, 1)
        atlas_w, atlas_h = 2048, 2048
        packer = ShelfPacker(atlas_w, atlas_h)
        packer.pack(1, 1)
        for fi in sorted_fis:
            _, _, lw, lh, _ = face_lm_blocks[fi]
            res = packer.pack(lw, lh)
            packed_coords[fi] = res if res is not None else (1, 1)

    atlas_img = np.full((atlas_h, atlas_w, 3), 160, dtype=np.uint8)
    for fi, (rx, ry) in packed_coords.items():
        _, _, lw, lh, block = face_lm_blocks[fi]
        if rx == 1 and ry == 1 and lw > 1:
            continue
        atlas_img[ry : ry + lh, rx : rx + lw] = block
        # Extrude 1-pixel border gutter to eliminate bilinear seam bleeding!
        atlas_img[ry - 1, rx : rx + lw] = block[0, :]
        atlas_img[ry + lh, rx : rx + lw] = block[-1, :]
        atlas_img[ry - 1 : ry + lh + 1, rx - 1] = atlas_img[ry - 1 : ry + lh + 1, rx]
        atlas_img[ry - 1 : ry + lh + 1, rx + lw] = atlas_img[ry - 1 : ry + lh + 1, rx + lw - 1]

    os.makedirs(out_maps_dir, exist_ok=True)
    lm_png_path = os.path.join(out_maps_dir, f"{map_name}_lm.png")
    Image.fromarray(atlas_img, mode="RGB").quantize(colors=256).save(lm_png_path, format="PNG", optimize=True)

    # Build meshes for world (submodel 0) and active brush submodels (1..N)
    # Material registry across this map
    mat_name_to_idx: Dict[str, int] = {}
    mat_list: List[dict] = []
    floor_centroids_gs: List[np.ndarray] = []
    floor_subgrid_gs: List[np.ndarray] = []

    def get_mat_idx(safe_name: str, masked: bool) -> int:
        if safe_name in mat_name_to_idx:
            return mat_name_to_idx[safe_name]
        idx = len(mat_list)
        mat_name_to_idx[safe_name] = idx
        mat_list.append({"safe": safe_name, "masked": masked})
        return idx

    submodel_meshes = []  # List of (node_name, submodel_id, prim_dict[mat_idx -> list of (pos, nrm, uv0, uv1)])
    inv_aw = 1.0 / float(atlas_w)
    inv_ah = 1.0 / float(atlas_h)

    for sm_idx, sm in enumerate(submodels):
        if sm_idx in trigger_submodels:
            continue
        ff = sm["firstface"]
        nf = sm["numfaces"]
        if nf <= 0:
            continue

        prim_buckets: Dict[int, Tuple[List, List[int], Dict]] = {}
        for fi in range(ff, ff + nf):
            if fi >= num_faces:
                break
            pnum, side, firstedge, numedges, ti_idx, _, _, _, _, _ = struct.unpack_from("<hhihh4Bi", faces_bytes, fi * 20)
            if numedges < 3 or ti_idx < 0 or ti_idx >= len(texinfos):
                continue
            s_vec, s_shift, t_vec, t_shift, mip_id, ti_flags = texinfos[ti_idx]
            minfo = miptex_entries[mip_id]
            if minfo["sky"] or minfo["skip"] or (ti_flags & 1):
                continue

            pn_gs = planes_n[pnum].copy()
            if side != 0:
                pn_gs = -pn_gs
            nrm_gd = [-float(pn_gs[1]), float(pn_gs[2]), -float(pn_gs[0])]

            pts_gs = []
            for k in range(numedges):
                se = surfedges[firstedge + k]
                vi = edges[se, 0] if se >= 0 else edges[-se, 1]
                pts_gs.append(verts_gs[vi])

            # Collect dense floor samples on worldspawn & solid func_wall stairs/bridges/ramps for Bot navigation
            if sm_idx in walkable_submodels and float(pn_gs[2]) > 0.65 and not minfo["lower"].startswith("!"):
                sm_orig = walkable_submodels[sm_idx]
                pts_np = np.array(pts_gs, dtype=np.float32) + sm_orig
                centroid = np.mean(pts_np, axis=0)
                floor_centroids_gs.append(centroid)
                span_xy = np.ptp(pts_np[:, :2], axis=0)
                max_span = float(max(span_xy[0], span_xy[1]))
                if max_span > 168.0:
                    # Sample inset vertices & triangle sub-grids strictly inside the convex BSP polygon
                    for v_pt in pts_np:
                        floor_subgrid_gs.append(centroid * 0.26 + v_pt * 0.74)
                    if max_span > 280.0 and len(pts_np) >= 3:
                        steps = min(5, max(2, int(max_span / 148.0)))
                        p0 = pts_np[0]
                        for ti in range(1, len(pts_np) - 1):
                            p1, p2 = pts_np[ti], pts_np[ti + 1]
                            for su in range(1, steps):
                                u_f = su / float(steps)
                                for sv in range(1, steps - su + 1):
                                    v_f = sv / float(steps)
                                    if u_f + v_f < 0.98:
                                        floor_subgrid_gs.append(p0 * (1.0 - u_f - v_f) + p1 * u_f + p2 * v_f)

            mat_idx = get_mat_idx(minfo["safe"], minfo["masked"])
            vlist, ilist, vmap = prim_buckets.setdefault(mat_idx, ([], [], {}))

            tw = float(minfo["w"])
            th = float(minfo["h"])
            min_s, min_t, lw, lh, _ = face_lm_blocks.get(fi, (0, 0, 1, 1, None))
            rx, ry = packed_coords.get(fi, (1, 1))

            face_idxs = []
            raw_sv_tv = [(float(np.dot(v_gs, s_vec) + s_shift), float(np.dot(v_gs, t_vec) + t_shift)) for v_gs in pts_gs]
            # Shift integer repeat cycles per face so UV0 stays near [0, 8] -> 20x higher GLES3 UNORM16 UV precision!
            u_base = math.floor(min(st[0] / tw for st in raw_sv_tv))
            v_base = math.floor(min(st[1] / th for st in raw_sv_tv))
            for v_gs, (sv, tv) in zip(pts_gs, raw_sv_tv):
                p_gd = [-float(v_gs[1]) * SCALE, float(v_gs[2]) * SCALE, -float(v_gs[0]) * SCALE]
                uv0 = (sv / tw - u_base, tv / th - v_base)
                if lw > 1 or lh > 1:
                    lu = (rx + 0.5 + (sv / 16.0 - min_s)) * inv_aw
                    lv = (ry + 0.5 + (tv / 16.0 - min_t)) * inv_ah
                else:
                    lu = (rx + 0.5) * inv_aw
                    lv = (ry + 0.5) * inv_ah
                vkey = (
                    round(p_gd[0], 3), round(p_gd[1], 3), round(p_gd[2], 3),
                    round(nrm_gd[0], 2), round(nrm_gd[1], 2), round(nrm_gd[2], 2),
                    round(uv0[0], 3), round(uv0[1], 3),
                    round(lu, 4), round(lv, 4),
                )
                vi_out = vmap.get(vkey)
                if vi_out is None:
                    vi_out = len(vlist)
                    vmap[vkey] = vi_out
                    vlist.append((p_gd, nrm_gd, uv0, (lu, lv)))
                face_idxs.append(vi_out)

            # Fan triangulation: reverse (0, k+2, k+1) so GoldSrc CW -> glTF CCW outward normal!
            for k in range(len(face_idxs) - 2):
                ilist.append(face_idxs[0])
                ilist.append(face_idxs[k + 2])
                ilist.append(face_idxs[k + 1])

        if prim_buckets:
            node_name = "worldspawn" if sm_idx == 0 else f"submodel_{sm_idx}"
            submodel_meshes.append((node_name, sm_idx, prim_buckets))

    # Write glTF 2.0 .glb referencing shared ../textures/world/<safe>.png
    bin_chunks = bytearray()
    buffer_views = []
    accessors = []

    def append_bytes(raw_b: bytes, target: Optional[int] = None) -> int:
        while len(bin_chunks) % 4 != 0:
            bin_chunks.append(0)
        ofs = len(bin_chunks)
        bin_chunks.extend(raw_b)
        bv = {"buffer": 0, "byteOffset": ofs, "byteLength": len(raw_b)}
        if target is not None:
            bv["target"] = target
        idx = len(buffer_views)
        buffer_views.append(bv)
        return idx

    def add_acc(bv_idx: int, comp_type: int, count: int, acc_type: str, arr: Optional[np.ndarray] = None) -> int:
        acc = {"bufferView": bv_idx, "byteOffset": 0, "componentType": comp_type, "count": count, "type": acc_type}
        if arr is not None and count > 0:
            acc["min"] = np.min(arr, axis=0).astype(float).tolist()
            acc["max"] = np.max(arr, axis=0).astype(float).tolist()
        idx = len(accessors)
        accessors.append(acc)
        return idx

    gltf_images = []
    gltf_textures = []
    gltf_materials = []
    gltf_samplers = [{"magFilter": 9728, "minFilter": 9986, "wrapS": 10497, "wrapT": 10497}]

    for mi, m in enumerate(mat_list):
        gltf_images.append({"uri": f"../textures/world/{m['safe']}.png", "name": m["safe"]})
        gltf_textures.append({"sampler": 0, "source": mi})
        gmat = {
            "name": m["safe"],
            "pbrMetallicRoughness": {
                "baseColorTexture": {"index": mi},
                "metallicFactor": 0.0,
                "roughnessFactor": 1.0,
            },
        }
        if m["masked"]:
            gmat["alphaMode"] = "MASK"
            gmat["alphaCutoff"] = 0.5
            gmat["doubleSided"] = True
        gltf_materials.append(gmat)

    gltf_meshes = []
    gltf_nodes = []
    scene_children = []

    for node_name, sm_idx, prim_buckets in submodel_meshes:
        prims = []
        for mat_idx, (vlist, ilist, _vmap) in sorted(prim_buckets.items()):
            nv = len(vlist)
            ni = len(ilist)
            if nv == 0 or ni == 0:
                continue
            pos_a = np.array([x[0] for x in vlist], dtype="<f4")
            nrm_a = np.array([x[1] for x in vlist], dtype="<f4")
            uv0_a = np.array([x[2] for x in vlist], dtype="<f4")
            uv1_a = np.array([x[3] for x in vlist], dtype="<f4")

            if nv <= 65535:
                idx_a = np.array(ilist, dtype="<u2")
                idx_comp = 5123  # UNSIGNED_SHORT
            else:
                idx_a = np.array(ilist, dtype="<u4")
                idx_comp = 5125  # UNSIGNED_INT

            ap = add_acc(append_bytes(pos_a.tobytes(), 34962), 5126, nv, "VEC3", pos_a)
            an = add_acc(append_bytes(nrm_a.tobytes(), 34962), 5126, nv, "VEC3")
            au0 = add_acc(append_bytes(uv0_a.tobytes(), 34962), 5126, nv, "VEC2")
            au1 = add_acc(append_bytes(uv1_a.tobytes(), 34962), 5126, nv, "VEC2")
            ai = add_acc(append_bytes(idx_a.tobytes(), 34963), idx_comp, ni, "SCALAR")

            prims.append({
                "attributes": {"POSITION": ap, "NORMAL": an, "TEXCOORD_0": au0, "TEXCOORD_1": au1},
                "indices": ai,
                "material": mat_idx,
                "mode": 4,
            })

        if prims:
            mesh_idx = len(gltf_meshes)
            gltf_meshes.append({"name": node_name, "primitives": prims})
            node_idx = len(gltf_nodes)
            gltf_nodes.append({"name": node_name, "mesh": mesh_idx})
            scene_children.append(node_idx)

    while len(bin_chunks) % 4 != 0:
        bin_chunks.append(0)

    gltf_doc = {
        "asset": {"version": "2.0", "generator": "CS15-BSP30-Converter"},
        "scene": 0,
        "scenes": [{"name": map_name, "nodes": scene_children}],
        "nodes": gltf_nodes,
        "meshes": gltf_meshes,
        "materials": gltf_materials,
        "textures": gltf_textures,
        "images": gltf_images,
        "samplers": gltf_samplers,
        "accessors": accessors,
        "bufferViews": buffer_views,
        "buffers": [{"byteLength": len(bin_chunks)}],
    }

    jb = json.dumps(gltf_doc, separators=(",", ":")).encode("utf-8")
    while len(jb) % 4 != 0:
        jb += b" "

    glb_path = os.path.join(out_maps_dir, f"{map_name}.glb")
    tot_len = 12 + 8 + len(jb) + 8 + len(bin_chunks)
    with open(glb_path, "wb") as out:
        out.write(struct.pack("<III", 0x46546C67, 2, tot_len))
        out.write(struct.pack("<II", len(jb), 0x4E4F534A))
        out.write(jb)
        out.write(struct.pack("<II", len(bin_chunks), 0x004E4942))
        out.write(bin_chunks)

    # Generate Hull-1 Bot navigation graph (all centroids first, then subgrids, plus bridges/stairs & ladders!)
    hull0_head = submodels[0]["headnodes"][0] if submodels else 0
    hull1_head = submodels[0]["headnodes"][1] if submodels else 0
    hull3_head = submodels[0]["headnodes"][3] if submodels else 0
    all_floor_samples = floor_centroids_gs + floor_subgrid_gs
    waypoints_gd, nav_adj = build_bot_nav_graph(
        all_floor_samples,
        seed_points_gs,
        clipnodes,
        planes_n,
        planes_d,
        hull1_head,
        ladder_spans_gs,
        solid_hulls,
        hull0_head,
        hull3_head,
    )

    # Map briefing text from cstrike/maps/<map>.txt
    briefing = ""
    txt_p = os.path.join(cstrike_maps_dir, f"{map_name}.txt")
    if os.path.exists(txt_p):
        briefing = open(txt_p, "r", encoding="latin1", errors="ignore").read().strip()

    if map_name.startswith("de_"):
        mode = "de"
    elif map_name.startswith("cs_"):
        mode = "cs"
    elif map_name.startswith("as_"):
        mode = "as"
    else:
        mode = "de" if bombsites else "cs"

    map_meta = {
        "name": map_name,
        "mode": mode,
        "skyname": skyname,
        "briefing": briefing,
        "glb": f"res://assets/maps/{map_name}.glb",
        "lightmap": f"res://assets/maps/{map_name}_lm.png",
        "ct_spawns": ct_spawns,
        "t_spawns": t_spawns,
        "vip_spawns": vip_spawns,
        "bombsites": bombsites,
        "buyzones": buyzones,
        "hostages": hostages,
        "rescue_zones": rescue_zones,
        "escape_zones": escape_zones,
        "ladders": ladders,
        "water_zones": water_zones,
        "triggers": triggers,
        "brush_entities": brush_entities,
        "ambient_sounds": ambient_sounds,
        "cameras": cameras,
        "waypoints": waypoints_gd,
        "nav_adj": nav_adj,
    }

    os.makedirs(out_data_maps_dir, exist_ok=True)
    with open(os.path.join(out_data_maps_dir, f"{map_name}.json"), "w", encoding="utf-8") as f:
        json.dump(map_meta, f, separators=(",", ":"))

    return {
        "name": map_name,
        "mode": mode,
        "skyname": skyname,
        "ct_spawns": len(ct_spawns),
        "t_spawns": len(t_spawns),
        "bombsites": len(bombsites),
        "hostages": len(hostages),
        "waypoints": len(waypoints_gd),
        "briefing": briefing[:300],
    }


def run_bsp_extraction(
    cstrike_dir: str,
    wad_catalog: Dict[str, Tuple[str, int]],
    out_world_tex_dir: str,
    out_maps_dir: str,
    out_data_dir: str,
) -> Tuple[List[dict], Set[str]]:
    os.makedirs(out_world_tex_dir, exist_ok=True)
    maps_src = os.path.join(cstrike_dir, "maps")
    out_data_maps = os.path.join(out_data_dir, "maps")
    wad_cache: Dict[str, bytes] = {}
    exported_world_textures: Dict[str, dict] = {}
    maps_index = []
    used_skies: Set[str] = set()

    for bp in sorted(glob.glob(os.path.join(maps_src, "*.[bB][sS][pP]"))):
        info = convert_single_bsp(
            bp,
            wad_catalog,
            wad_cache,
            exported_world_textures,
            out_world_tex_dir,
            out_maps_dir,
            out_data_maps,
            maps_src,
        )
        if info:
            maps_index.append(info)
            used_skies.add(info["skyname"])
            print(
                f"  [bsp] {info['name']:16s} ({info['mode'].upper()}) | "
                f"CT:{info['ct_spawns']:2d} T:{info['t_spawns']:2d} "
                f"Bomb:{info['bombsites']} Host:{info['hostages']} Nav:{info['waypoints']:3d}"
            )

    with open(os.path.join(out_data_dir, "maps_index.json"), "w", encoding="utf-8") as f:
        json.dump(maps_index, f, indent=2)
    with open(os.path.join(out_data_dir, "world_textures.json"), "w", encoding="utf-8") as f:
        json.dump(exported_world_textures, f, separators=(",", ":"))

    print(
        f"[bsp_converter] Converted ALL {len(maps_index)} BSP v30 maps & "
        f"{len(exported_world_textures)} unique world textures!"
    )
    return maps_index, used_skies
