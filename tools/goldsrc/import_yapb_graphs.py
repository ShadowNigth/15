#!/usr/bin/env python3
"""Import official human-curated YaPB (.graph, Unlicense) tactical waypoint graphs
into data/maps/*.json for all 26 Counter-Strike 1.5 retail maps.

Preserves exact CS 1.5 map geometry overrides (de_aztec15, de_cbble(cs 1.5),
de_inferno(cs 1.5), de_piranesi(cs 1.5), as_oilrig_1) and converts GoldSrc
coordinates, crouch/stand heights, directed links, jump velocities, radii,
and camp/sniper look vectors into Godot 4 coordinates (SCALE = 1/32).
"""

import glob
import json
import math
import os
import struct
import sys

SCALE = 1.0 / 32.0
MAGIC_YAPB = 0x59415042
MAGIC_UBOT = 0x544F4255

# NodeFlag constants (from yapb/inc/graph.h)
FLAG_CROUCH = 1 << 2
FLAG_CAMP = 1 << 7
FLAG_SNIPER = 1 << 28

# Explicit CS 1.5 retail BSP-matched graph overrides where CS 1.6 altered geometry
CS15_GRAPH_OVERRIDES = {
    "as_oilrig": "as_oilrig_1.graph",
    "de_aztec": "de_aztec15.graph",
    "de_cbble": "de_cbble(cs 1.5).graph",
    "de_inferno": "de_inferno(cs 1.5).graph",
    "de_piranesi": "de_piranesi(cs 1.5).graph",
}


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


def import_graph_for_map(map_json_path: str, graph_dir: str) -> dict:
    mname = os.path.splitext(os.path.basename(map_json_path))[0].lower()
    with open(map_json_path, "r", encoding="utf-8") as f:
        md = json.load(f)

    gfile = CS15_GRAPH_OVERRIDES.get(mname, f"{mname}.graph")
    gpath = os.path.join(graph_dir, gfile)
    if not os.path.exists(gpath):
        raise FileNotFoundError(f"Missing YaPB graph: {gpath}")

    raw = open(gpath, "rb").read()
    magic, _ver, _opts, length, comp_sz, uncomp_sz = struct.unpack_from("<6i", raw, 0)
    if magic not in (MAGIC_YAPB, MAGIC_UBOT):
        raise ValueError(f"Invalid magic in {gpath}")

    buf = ulz_decompress(raw[24 : 24 + comp_sz], uncomp_sz)
    stride = uncomp_sz // length

    waypoints = []
    wp_flags = []
    wp_radius = []
    wp_camp = {}
    nav_links = []
    nav_adj = []

    for i in range(length):
        ofs = i * stride
        _num, flags, ox, oy, oz, sx, sy, _sz, ex, ey, _ez, radius, _light, _disp = struct.unpack_from(
            "<2i3f3f3f3f", buf, ofs
        )
        # Convert GoldSrc waist origin (+36u stand / +18u crouch) to Godot foot floor height!
        is_ladder = bool(flags & (1 << 5))
        z_foot_gs = oz if is_ladder else (oz - (18.0 if (flags & FLAG_CROUCH) else 36.0))
        waypoints.append([round(-oy * SCALE, 3), round(z_foot_gs * SCALE, 3), round(-ox * SCALE, 3)])
        wp_flags.append(int(flags))
        wp_radius.append(round(max(0.0, float(radius)) * SCALE, 2))

        if (flags & FLAG_CAMP) or (flags & FLAG_SNIPER):
            d_start = gs_angles_to_godot_dir(sx, sy)
            d_end = gs_angles_to_godot_dir(ex, ey)
            wp_camp[str(i)] = d_start + d_end

        links_i = []
        adj_i = []
        for k in range(8):
            vx, vy, vz, _dist, lflags, lidx = struct.unpack_from("<3fiHh", buf, ofs + 56 + k * 20)
            if 0 <= lidx < length and lidx != i:
                adj_i.append(int(lidx))
                if lflags != 0 or abs(vx) > 0.1 or abs(vy) > 0.1:
                    links_i.append(
                        [
                            int(lidx),
                            int(lflags),
                            round(-vy * SCALE, 2),
                            round(vz * SCALE, 2),
                            round(-vx * SCALE, 2),
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

    return {
        "name": mname,
        "mode": md["mode"],
        "skyname": md["skyname"],
        "ct_spawns": len(md["ct_spawns"]),
        "t_spawns": len(md["t_spawns"]),
        "bombsites": len(md["bombsites"]),
        "hostages": len(md["hostages"]),
        "waypoints": len(waypoints),
        "briefing": md["briefing"][:300],
    }


def main() -> None:
    graph_dir = sys.argv[1] if len(sys.argv) > 1 else "/tmp/yapb_graph/graph"
    maps_dir = os.path.join(os.path.dirname(__file__), "..", "..", "data", "maps")
    index_path = os.path.join(os.path.dirname(__file__), "..", "..", "data", "maps_index.json")

    maps_index = []
    for mp in sorted(glob.glob(os.path.join(maps_dir, "*.json"))):
        info = import_graph_for_map(mp, graph_dir)
        maps_index.append(info)

    with open(index_path, "w", encoding="utf-8") as f:
        json.dump(maps_index, f, indent=2)

    print(f"Successfully imported YaPB graphs into all {len(maps_index)} maps!")


if __name__ == "__main__":
    main()
