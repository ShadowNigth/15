"""Minimal Valve SMD (Source / Crowbar decompile) reader.

parse_smd(path) -> dict(
    nodes=[(name, parent)],                  # index = bone id
    frames=[{bone: (pos[3], rot[3])}, ...],  # skeleton blocks in time order
    triangles=[(material, [(bone, pos, nrm, uv, links), x3])],
)
links = [(bone, weight), ...] (falls back to [(bone, 1.0)])
"""
import math

import numpy as np


def parse_smd(path, want_triangles=True):
    nodes = []
    frames = []
    tris = []
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        lines = f.read().splitlines()
    i = 0
    n = len(lines)
    while i < n:
        ln = lines[i].strip()
        i += 1
        if ln == "nodes":
            while i < n and lines[i].strip() != "end":
                s = lines[i].strip()
                i += 1
                if not s:
                    continue
                q1 = s.index('"')
                q2 = s.index('"', q1 + 1)
                idx = int(s[:q1])
                name = s[q1 + 1:q2]
                parent = int(s[q2 + 1:].split()[0])
                while len(nodes) <= idx:
                    nodes.append(("", -1))
                nodes[idx] = (name, parent)
            i += 1
        elif ln == "skeleton":
            cur = None
            while i < n and lines[i].strip() != "end":
                s = lines[i].split()
                i += 1
                if not s:
                    continue
                if s[0] == "time":
                    cur = {}
                    frames.append(cur)
                    continue
                b = int(s[0])
                vals = [float(x) for x in s[1:7]]
                cur[b] = (vals[0:3], vals[3:6])
            i += 1
        elif ln == "triangles":
            if not want_triangles:
                while i < n and lines[i].strip() != "end":
                    i += 1
                i += 1
                continue
            while i < n and lines[i].strip() != "end":
                mat = lines[i].strip()
                i += 1
                if not mat:
                    continue
                vs = []
                for _ in range(3):
                    s = lines[i].split()
                    i += 1
                    b = int(s[0])
                    pos = [float(x) for x in s[1:4]]
                    nrm = [float(x) for x in s[4:7]]
                    uv = [float(x) for x in s[7:9]]
                    links = []
                    if len(s) > 9:
                        nl = int(s[9])
                        for k in range(nl):
                            links.append((int(s[10 + 2 * k]), float(s[11 + 2 * k])))
                    if not links:
                        links = [(b, 1.0)]
                    vs.append((b, pos, nrm, uv, links))
                tris.append((mat, vs))
            i += 1
    # fill missing bones in later frames with previous values (Source semantics)
    for fi in range(1, len(frames)):
        prev = frames[fi - 1]
        for b, v in prev.items():
            frames[fi].setdefault(b, v)
    return {"nodes": nodes, "frames": frames, "triangles": tris}


def angle_quat(rx, ry, rz):
    """Source AngleQuaternion(RadianEuler) -> (x, y, z, w)."""
    sr, cr = math.sin(rx * 0.5), math.cos(rx * 0.5)
    sp, cp = math.sin(ry * 0.5), math.cos(ry * 0.5)
    sy, cy = math.sin(rz * 0.5), math.cos(rz * 0.5)
    return np.array([
        sr * cp * cy - cr * sp * sy,
        cr * sp * cy + sr * cp * sy,
        cr * cp * sy - sr * sp * cy,
        cr * cp * cy + sr * sp * sy,
    ], dtype=np.float64)


def quat_mul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return np.array([
        aw * bx + ax * bw + ay * bz - az * by,
        aw * by - ax * bz + ay * bw + az * bx,
        aw * bz + ax * by - ay * bx + az * bw,
        aw * bw - ax * bx - ay * by - az * bz,
    ])


def quat_inv(q):
    return np.array([-q[0], -q[1], -q[2], q[3]])


def quat_mat(q):
    x, y, z, w = q
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ])


def trs(t, q, s=None):
    m = np.eye(4)
    m[:3, :3] = quat_mat(q)
    if s is not None:
        m[:3, :3] = m[:3, :3] @ np.diag(s)
    m[:3, 3] = t
    return m
