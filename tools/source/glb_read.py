"""Minimal GLB reader (JSON chunk + BIN accessor views) used by the M.A.T. build scripts."""
import json
import struct

import numpy as np

COMP = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def load(path):
    with open(path, "rb") as f:
        data = f.read()
    total = struct.unpack_from("<I", data, 8)[0]
    off = 12
    js = binb = None
    while off < total:
        clen, ctype = struct.unpack_from("<I4s", data, off)
        off += 8
        if ctype == b"JSON":
            js = json.loads(data[off:off + clen].decode())
        elif ctype.startswith(b"BIN"):
            binb = data[off:off + clen]
        off += clen
    return js, binb


def acc(js, binb, idx):
    a = js["accessors"][idx]
    bv = js["bufferViews"][a["bufferView"]]
    dt = COMP[a["componentType"]]
    n = NCOMP[a["type"]]
    start = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = bv.get("byteStride", 0)
    itemsize = np.dtype(dt).itemsize * n
    if stride and stride != itemsize:
        raw = np.frombuffer(binb, dtype=np.uint8, count=stride * a["count"], offset=start)
        raw = raw.reshape(a["count"], stride)[:, :itemsize].copy()
        arr = np.frombuffer(raw.tobytes(), dtype=dt)
    else:
        arr = np.frombuffer(binb, dtype=dt, count=a["count"] * n, offset=start)
    return arr.reshape(a["count"], n) if n > 1 else arr
