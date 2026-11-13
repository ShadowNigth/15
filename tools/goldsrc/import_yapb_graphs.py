#!/usr/bin/env python3
"""Import official human-curated YaPB (.graph, Unlicense) tactical waypoint graphs
into data/maps/*.json for the retained Counter-Strike 1.5 maps, cross-validated
against each map's exact CS 1.5 BSP30 Hull-1/Hull-3 clipnodes:
  - Simulates GoldSrc step-walking along every link against BSP Hull-1 clipnodes to
    automatically flag every >=18u ledge/crate step as LINK_JUMP with launch velocity!
  - Marks ramp, stair, and ledge entry/exit nodes with FLAG_NARROW so bots align
    dead-center on ramp entrances instead of clipping side retaining walls!
"""

import glob
import json
import math
import os
import struct
import sys
import numpy as np

SCALE = 1.0 / 32.0
MAGIC_YAPB = 0x59415042
MAGIC_UBOT = 0x544F4255

FLAG_CROUCH = 1 << 2
FLAG_LADDER = 1 << 5
FLAG_CAMP = 1 << 7
FLAG_NARROW = 1 << 10
FLAG_SNIPER = 1 << 28

CS15_GRAPH_OVERRIDES = {
    "de_aztec": "de_aztec15.graph",
    "de_cbble": "de_cbble(cs 1.5).graph",
    "de_inferno": "de_inferno(cs 1.5).graph",
    "de_piranesi": "de_piranesi(cs 1.5).graph",
}


def get_lump(bsp: bytes, lid: int) -> bytes:
    ofs, sz = struct.unpack_from("<2i", bsp, 4 + lid * 8)
    return bsp[ofs : ofs + sz]


def pc_hull(cn: np.ndarray, pn: np.ndarray, pd: np.ndarray, node: int, x: float, y: float, z: float) -> int:
    while node >= 0:
        pi = int(cn["p"][node])
        n = pn[pi]
        d = x * float(n[0]) + y * float(n[1]) + z * float(n[2]) - float(pd[pi])
        node = int(cn["c"][node][0 if d >= 0.0 else 1])
    return node


def can_step_walk_hull(
    cn: np.ndarray,
    pn: np.ndarray,
    pd: np.ndarray,
    hull_head: int,
    ux: float,
    uy: float,
    uz: float,
    vx: float,
    vy: float,
    vz: float,
) -> bool:
    """Simulate GoldSrc ground step-up walking (<=16u per substep) from u to v."""
    dist_xy = math.hypot(vx - ux, vy - uy)
    steps = max(8, int(dist_xy / 10.0) + 2)
    cur_z = uz
    for s in range(1, steps + 1):
        t = s / float(steps)
        px = ux + (vx - ux) * t
        py = uy + (vy - uy) * t
        found = False
        for try_dz in (0.0, 5.0, 10.0, 16.0, -6.0, -14.0, -24.0):
            if pc_hull(cn, pn, pd, hull_head, px, py, cur_z + try_dz) != -2:
                z_test = cur_z + try_dz
                for _ in range(8):
                    if pc_hull(cn, pn, pd, hull_head, px, py, z_test - 4.0) != -2:
                        z_test -= 4.0
                    else:
                        break
                cur_z = z_test
                found = True
                break
        if not found:
            return False
    return (vz - cur_z) <= 18.0


def ulz_decompress(src: bytes, out_len: int) -> bytes:
    ip = 0
    in_len = len(src)
    out = bytearray(out_len)
    op = 0

    def decode_var_int() -> int:
        nonlocal ip
        val = 0
        for shift in (0, 7, 14, 21, 28):
            if ip >= in_len:
                return val
            cur = src[ip]
            ip += 1
            val += cur << shift
            if cur < 128:
                break
        return val

    while ip < in_len:
        token = src[ip]
        ip += 1
        run = token >> 5
        if run != 0:
            if run == 7:
                run += decode_var_int()
            out[op : op + run] = src[ip : ip + run]
            op += run
            ip += run
            if ip >= in_len:
                break
        length = (token & 15) + 4
        if length == 19:
            length += decode_var_int()
        dist = ((token & 16) << 12) + (src[ip] | (src[ip + 1] << 8))
        ip += 2
        cp = op - dist
        if dist >= length:
            out[op : op + length] = out[cp : cp + length]
            op += length
        else:
            for _ in range(length):
                out[op] = out[cp]
                op += 1
                cp += 1

    if ip != in_len or op != out_len:
        raise ValueError(f"ULZ size mismatch: ip={ip}/{in_len}, op={op}/{out_len}")
    return bytes(out)


def gs_angles_to_godot_dir(pitch_deg: float, yaw_deg: float) -> list[float]:
    p = math.radians(pitch_deg)
    y = math.radians(yaw_deg)
    cp = math.cos(p)
    vx_gs = cp * math.cos(y)
    vy_gs = cp * math.sin(y)
    vz_gs = -math.sin(p)
    dx, dy, dz = -vy_gs, vz_gs, -vx_gs
    ln = math.sqrt(dx * dx + dy * dy + dz * dz)
    if ln < 1e-6:
        return [0.0, 0.0, -1.0]
    return [round(dx / ln, 3), round(dy / ln, 3), round(dz / ln, 3)]


def import_graph_for_map(map_json_path: str, graph_dir: str, bsp_dir: str) -> tuple[dict, int]:
    mname = os.path.splitext(os.path.basename(map_json_path))[0].lower()
    with open(map_json_path, "r", encoding="utf-8") as f:
        md = json.load(f)

    gfile = CS15_GRAPH_OVERRIDES.get(mname, f"{mname}.graph")
    gpath = os.path.join(graph_dir, gfile)
    raw = open(gpath, "rb").read()
    magic, _ver, _opts, length, comp_sz, uncomp_sz = struct.unpack_from("<6i", raw, 0)
    if magic not in (MAGIC_YAPB, MAGIC_UBOT):
        raise ValueError(f"Invalid magic in {gpath}")

    buf = ulz_decompress(raw[24 : 24 + comp_sz], uncomp_sz)
    stride = uncomp_sz // length

    # Load BSP clipnodes if available for physics-exact step/jump verification
    has_bsp = False
    cn = pn = pd = None
    h1 = h3 = 0
    bsp_candidates = glob.glob(os.path.join(bsp_dir, "*.[bB][sS][pP]"))
    for bp in bsp_candidates:
        if os.path.splitext(os.path.basename(bp))[0].lower() == mname:
            bsp_bytes = open(bp, "rb").read()
            pl_raw = get_lump(bsp_bytes, 1)
            pl = np.frombuffer(
                pl_raw[: (len(pl_raw) // 20) * 20],
                dtype=np.dtype([("n", "<3f4"), ("d", "<f4"), ("t", "<i4")]),
            )
            pn, pd = pl["n"], pl["d"]
            cn_raw = get_lump(bsp_bytes, 9)
            cn = np.frombuffer(
                cn_raw[: (len(cn_raw) // 8) * 8],
                dtype=np.dtype([("p", "<i4"), ("c", "<2i2")]),
            )
            _h0, h1, _h2, h3 = struct.unpack_from("<4i", get_lump(bsp_bytes, 14), 36)
            has_bsp = True
            break

    waypoints = []
    wp_flags = []
    wp_radius = []
    wp_camp = {}
    nav_links = []
    nav_adj = []
    raw_gs = []

    for i in range(length):
        ofs = i * stride
        _num, flags, ox, oy, oz, sx, sy, _sz, ex, ey, _ez, radius, _light, _disp = struct.unpack_from(
            "<2i3f3f3f3f", buf, ofs
        )
        is_ladder = bool(flags & FLAG_LADDER)
        z_foot_gs = oz if is_ladder else (oz - (18.0 if (flags & FLAG_CROUCH) else 36.0))
        waypoints.append([round(-oy * SCALE, 3), round(z_foot_gs * SCALE, 3), round(-ox * SCALE, 3)])
        wp_flags.append(int(flags))
        wp_radius.append(round(max(0.0, float(radius)) * SCALE, 2))
        raw_gs.append((ox, oy, oz, z_foot_gs, int(flags)))

        if (flags & FLAG_CAMP) or (flags & FLAG_SNIPER):
            wp_camp[str(i)] = gs_angles_to_godot_dir(sx, sy) + gs_angles_to_godot_dir(ex, ey)

    promoted_jumps = 0
    for i in range(length):
        ofs = i * stride
        ux, uy, uz, u_foot_z, u_flags = raw_gs[i]
        u_lad = bool(u_flags & FLAG_LADDER)
        links_i = []
        adj_i = []

        for k in range(8):
            lvx, lvy, lvz, _dist, lflags, lidx = struct.unpack_from("<3fiHh", buf, ofs + 56 + k * 20)
            if 0 <= lidx < length and lidx != i:
                vx, vy, vz, v_foot_z, v_flags = raw_gs[int(lidx)]
                v_lad = bool(v_flags & FLAG_LADDER)
                dy_m = (v_foot_z - u_foot_z) * SCALE
                dx_m = (-vy - (-uy)) * SCALE
                dz_m = (-vx - (-ux)) * SCALE
                dxz_m = math.hypot(dx_m, dz_m)

                # Mark ramp, stair, and ledge endpoints as FLAG_NARROW so bots center cleanly!
                if abs(dy_m) >= 0.32:
                    wp_flags[i] |= FLAG_NARROW
                    wp_flags[int(lidx)] |= FLAG_NARROW

                if not u_lad and not v_lad and dy_m > 1.95:
                    continue

                eff_lflags = int(lflags)
                jvx_m = -lvy * SCALE
                jvy_m = lvz * SCALE
                jvz_m = -lvx * SCALE

                # Check upward links > 0.38m against BSP Hull-1/Hull-3 step simulation!
                if not u_lad and not v_lad and (eff_lflags & 1) == 0 and dy_m > 0.38:
                    needs_jump = False
                    if has_bsp:
                        hull_check = h3 if ((u_flags | v_flags) & FLAG_CROUCH) else h1
                        if not can_step_walk_hull(cn, pn, pd, hull_check, ux, uy, uz, vx, vy, vz):
                            needs_jump = True
                    elif dy_m >= 0.62 and dxz_m < 1.85:
                        needs_jump = True

                    if needs_jump:
                        eff_lflags |= 1
                        promoted_jumps += 1
                        if math.hypot(jvx_m, jvz_m) < 0.5 and dxz_m > 0.05:
                            spd = 6.9
                            jvx_m = (dx_m / dxz_m) * spd
                            jvz_m = (dz_m / dxz_m) * spd

                adj_i.append(int(lidx))
                if eff_lflags != 0 or abs(jvx_m) > 0.05 or abs(jvz_m) > 0.05:
                    links_i.append(
                        [
                            int(lidx),
                            int(eff_lflags),
                            round(jvx_m, 2),
                            round(jvy_m, 2),
                            round(jvz_m, 2),
                        ]
                    )
                else:
                    links_i.append([int(lidx)])

        nav_links.append(links_i)
        nav_adj.append(adj_i)

    md["waypoints"] = waypoints
    md["wp_flags"] = wp_flags
    md["wp_radius"] = wp_radius
    md["wp_camp"] = wp_camp
    md["nav_links"] = nav_links
    md["nav_adj"] = nav_adj
    md["nav_source"] = f"yapb:{gfile}"

    with open(map_json_path, "w", encoding="utf-8") as f:
        json.dump(md, f, separators=(",", ":"))

    return (
        {
            "name": mname,
            "mode": md["mode"],
            "skyname": md["skyname"],
            "ct_spawns": len(md["ct_spawns"]),
            "t_spawns": len(md["t_spawns"]),
            "bombsites": len(md["bombsites"]),
            "hostages": len(md["hostages"]),
            "waypoints": len(waypoints),
            "briefing": md["briefing"][:300],
        },
        promoted_jumps,
    )


def main() -> None:
    graph_dir = sys.argv[1] if len(sys.argv) > 1 else "/tmp/yapb_graph/graph"
    bsp_dir = sys.argv[2] if len(sys.argv) > 2 else "/tmp/cs15_src/cstrike/maps"
    maps_dir = os.path.join(os.path.dirname(__file__), "..", "..", "data", "maps")
    index_path = os.path.join(os.path.dirname(__file__), "..", "..", "data", "maps_index.json")

    maps_index = []
    total_promoted = 0
    for mp in sorted(glob.glob(os.path.join(maps_dir, "*.json"))):
        info, prom = import_graph_for_map(mp, graph_dir, bsp_dir)
        maps_index.append(info)
        total_promoted += prom
        print(f"  {info['name']:14s}: {info['waypoints']:4d} wps | +{prom:3d} BSP-detected ledge jumps")

    with open(index_path, "w", encoding="utf-8") as f:
        json.dump(maps_index, f, indent=2)

    print(f"Done! {len(maps_index)} maps updated, +{total_promoted} ledge steps promoted to LINK_JUMP.")


if __name__ == "__main__":
    main()
