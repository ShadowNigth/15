#!/usr/bin/env python3
"""CS15 asset packs — a VPK-style, lossless, organised archive set for `assets/`.

Like Source's `pak01_dir.vpk` + `pak01_000.vpk`, the project's models, maps,
textures and sounds live in a handful of category archives under `packs/`
plus one directory index (`packs/pak_dir.idx`).  Unlike VPK the payload is
really compressed, and everything is restored **byte for byte** (every file
is verified against its SHA-256), so nothing loses quality.

    python tools/pak.py unpack     # packs/ -> assets/   (run once after cloning)
    python tools/pak.py pack       # assets/ -> packs/   (run after changing assets)
    python tools/pak.py status     # what differs between assets/ and packs/
    python tools/pak.py verify     # integrity check of the archives (--deep = decode all)
    python tools/pak.py list       # contents per archive

Only the Python standard library is needed (Python 3.8+).

How the size is won without touching quality
--------------------------------------------
* GLB files are split at their internal boundaries (JSON chunk, every
  bufferView, every embedded image).  Identical pieces — the same arm texture
  embedded in 40 view models, the same animation track, the same mesh — are
  stored once for the whole project (content addressed, across archives).
* Whole files that are byte-identical are stored once.
* Geometry / animation / JSON go through solid LZMA2 blocks; PCM WAV goes
  through a sample-aligned delta filter + LZMA2 (FLAC-like, still bit exact).
* Already-compressed payloads (PNG, JPG, WebP, OGG) are stored as they are.
"""
from __future__ import annotations

import argparse
import concurrent.futures as cf
import hashlib
import json
import lzma
import os
import shutil
import struct
import sys
import tempfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = "assets"
PACKS = "packs"
INDEX_NAME = "pak_dir.idx"
CONTENTS_NAME = "CONTENTS.md"
STATE_NAME = ".local_state.json"
FORMAT_VERSION = 1
PART_MAGIC = b"CS15PAK\x01"
PART_HEADER = 16

# Archive of a file = first matching prefix (relative to assets/, '/' separated).
# Order here is also the build order (earlier archives own shared pieces).
ARCHIVES = [
    ("maps", ["maps/"]),
    ("models_weapons", ["models/weapons/", "models/props/", "models/native/"]),
    ("models_held", ["models/held/"]),
    ("models_arms", ["models/native_view/", "models/agent_arms/", "models/sport_gloves/"]),
    ("models_players", ["models/players/", "models/modern/"]),
    ("models_misc", ["models/"]),
    ("textures_world", ["textures/world/", "textures/sky/", "textures/graffiti/"]),
    ("textures_weapons", ["textures/archi/", "textures/weapon_skins/", "textures/cs2_catalog/", "textures/cs2go/"]),
    ("textures_gloves", ["textures/native_sport/", "textures/sport_gloves/", "textures/moto_smoke_out"]),
    ("textures_misc", ["textures/"]),
    ("sounds_weapons", ["sounds/weapons/"]),
    ("sounds_native", ["sounds/native/"]),
    ("sounds_world", ["sounds/"]),
    ("ui", ["ui/", "sprites/", "polish/"]),
    ("misc", [""]),
]
# Kept as normal, diffable files in git (never packed).
LOOSE_PREFIXES = ["shaders/"]

BLOCK_MAX = 40 << 20          # uncompressed bytes per solid block
RAW_BLOCK_MAX = 16 << 20      # stored (already compressed) data per block
PART_MAX = 48 << 20           # archive part size cap (GitHub warns above 50 MB)
DEDUPE_MIN = 512              # do not chase duplicates smaller than this
STORED_EXT = {".png", ".jpg", ".jpeg", ".webp", ".ogg", ".mp3", ".ktx", ".ktx2", ".basis", ".zip", ".gz", ".xz"}
TEXT_EXT = {".import", ".json", ".txt", ".svg", ".md", ".cfg", ".tres", ".tscn", ".gltf", ".obj", ".mtl", ".csv", ".gdshader"}
IMAGE_EXT = {".png", ".jpg", ".jpeg", ".webp"}


# ----------------------------------------------------------------------------
# helpers
# ----------------------------------------------------------------------------

def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while True:
            b = f.read(1 << 20)
            if not b:
                break
            h.update(b)
    return h.hexdigest()


def human(n: float) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if abs(n) < 1024 or unit == "GB":
            return ("%d %s" % (n, unit)) if unit == "B" else ("%.1f %s" % (n, unit))
        n /= 1024.0
    return "%d" % n


def archive_of(rel: str) -> str:
    for name, prefixes in ARCHIVES:
        for p in prefixes:
            if rel.startswith(p):
                return name
    return "misc"


def is_loose(rel: str) -> bool:
    return any(rel.startswith(p) for p in LOOSE_PREFIXES)


def scan_assets(root: str) -> list:
    base = os.path.join(root, ASSETS)
    out = []
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames.sort()
        for fn in sorted(filenames):
            rel = os.path.relpath(os.path.join(dirpath, fn), base).replace(os.sep, "/")
            if is_loose(rel) or fn.startswith(".") or fn.endswith((".tmp", ".import.tmp")):
                continue
            out.append(rel)
    out.sort()
    return out


def filters_for(codec: str, dict_size: int):
    lz = {"id": lzma.FILTER_LZMA2, "preset": 9, "dict_size": dict_size}
    if codec == "lzma":
        return [lz]
    if codec.startswith("delta"):
        return [{"id": lzma.FILTER_DELTA, "dist": int(codec[5:].split("+")[0])}, lz]
    raise ValueError("unknown codec " + codec)


def dict_size_for(n: int) -> int:
    d = 1 << 20
    while d < n and d < (64 << 20):
        d <<= 1
    return d


# ----------------------------------------------------------------------------
# file segmentation
# ----------------------------------------------------------------------------

def wav_block_align(data: bytes) -> int:
    if len(data) < 12 or data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        return 0
    pos = 12
    while pos + 8 <= len(data):
        cid, size = struct.unpack_from("<4sI", data, pos)
        if cid == b"fmt " and size >= 16:
            fmt, _ch, _rate, _bps, align = struct.unpack_from("<HHIIH", data, pos + 8)
            return align if fmt in (1, 0xFFFE) and align in (1, 2, 3, 4, 6, 8) else 0
        pos += 8 + size + (size & 1)
    return 0


def glb_segments(data: bytes):
    """Split a GLB into (kind, start, end) pieces covering the file exactly."""
    if len(data) < 28 or data[:4] != b"glTF":
        return None
    version, total = struct.unpack_from("<II", data, 4)
    json_len, json_type = struct.unpack_from("<II", data, 12)
    if version != 2 or json_type != 0x4E4F534A or 20 + json_len > len(data):
        return None
    try:
        doc = json.loads(data[20:20 + json_len].decode("utf-8"))
    except Exception:
        return None
    segs = [("gltf", 0, 20 + json_len)]
    pos = 20 + json_len
    if pos + 8 <= len(data):
        bin_len, bin_type = struct.unpack_from("<II", data, pos)
        if bin_type == 0x004E4942 and pos + 8 + bin_len <= len(data):
            base = pos + 8
            segs.append(("gltf", pos, base))
            pos = base
            image_views = {}
            for im in doc.get("images", []) or []:
                if isinstance(im, dict) and "bufferView" in im:
                    image_views[im["bufferView"]] = str(im.get("mimeType", ""))
            views = []
            for i, bv in enumerate(doc.get("bufferViews", []) or []):
                if not isinstance(bv, dict) or bv.get("buffer", 0) != 0:
                    continue
                a = base + int(bv.get("byteOffset", 0))
                b = a + int(bv.get("byteLength", 0))
                if a < base or b > base + bin_len or b <= a:
                    continue
                views.append((a, b, i))
            views.sort()
            for a, b, i in views:
                if a < pos:
                    continue  # overlapping view: already covered
                if a > pos:
                    segs.append(("bin", pos, a))
                mime = image_views.get(i)
                kind = "raw" if mime in ("image/png", "image/jpeg", "image/webp") else "bin"
                segs.append((kind, a, b))
                pos = b
    if pos < len(data):
        segs.append(("bin", pos, len(data)))
    return segs


def segments_for(rel: str, data: bytes):
    ext = os.path.splitext(rel)[1].lower()
    if ext == ".glb":
        segs = glb_segments(data)
        if segs:
            return segs
        return [("bin", 0, len(data))]
    if ext == ".wav":
        align = wav_block_align(data)
        return [("delta%d" % align if align else "bin", 0, len(data))]
    if ext in STORED_EXT:
        return [("raw", 0, len(data))]
    if ext in TEXT_EXT:
        return [("text", 0, len(data))]
    return [("bin", 0, len(data))]


def godot_extracted_texture(rel: str, all_set: set, base: str, cache: dict) -> bool:
    """True for textures Godot's importer extracted next to a .glb on import."""
    d, fn = os.path.split(rel)
    stem, ext = os.path.splitext(fn)
    if ext.lower() not in IMAGE_EXT or "_" not in stem:
        return False
    parts = stem.split("_")
    for i in range(len(parts) - 1, 0, -1):
        glb = (d + "/" if d else "") + "_".join(parts[:i]) + ".glb"
        if glb in all_set:
            if glb not in cache:
                try:
                    with open(os.path.join(base, glb), "rb") as f:
                        head = f.read(20)
                        n = struct.unpack_from("<I", head, 12)[0]
                        doc = json.loads(f.read(n).decode("utf-8"))
                    cache[glb] = any("bufferView" in im for im in doc.get("images", []) or [])
                except Exception:
                    cache[glb] = False
            if cache[glb]:
                return True
    return False


# ----------------------------------------------------------------------------
# index
# ----------------------------------------------------------------------------

def index_path(root: str) -> str:
    return os.path.join(root, PACKS, INDEX_NAME)


def load_index(root: str):
    p = index_path(root)
    if not os.path.exists(p):
        return None
    with open(p, "rb") as f:
        idx = json.loads(lzma.decompress(f.read()).decode("utf-8"))
    if idx.get("format") != FORMAT_VERSION:
        sys.exit("Unsupported pack format %r (this tool reads %d)." % (idx.get("format"), FORMAT_VERSION))
    return idx


def save_index(root: str, idx: dict) -> None:
    raw = json.dumps(idx, separators=(",", ":"), sort_keys=True).encode("utf-8")
    with open(index_path(root), "wb") as f:
        f.write(lzma.compress(raw, preset=9))


def state_path(root: str) -> str:
    return os.path.join(root, PACKS, STATE_NAME)


def load_state(root: str) -> dict:
    try:
        with open(state_path(root), "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}


def save_state(root: str, idx: dict, synced=None) -> None:
    """Remember what the working copy looked like when it matched the packs.

    `synced` = files known to match the index right now (None = all of them);
    other files keep whatever was recorded before.
    """
    base = os.path.join(root, ASSETS)
    old = load_state(root).get("files", {}) if synced is not None else {}
    files = {}
    for rel, info in idx["files"].items():
        if synced is not None and rel not in synced:
            if rel in old:
                files[rel] = old[rel]
            continue
        try:
            st = os.stat(os.path.join(base, rel))
        except OSError:
            continue
        files[rel] = [info["sha256"], st.st_size, st.st_mtime_ns]
    os.makedirs(os.path.join(root, PACKS), exist_ok=True)
    with open(state_path(root), "w", encoding="utf-8") as f:
        json.dump({"files": files}, f, separators=(",", ":"))


def current_sha(base: str, rel: str, state_files: dict):
    """SHA-256 of a working file, using the (size, mtime) cache when valid."""
    p = os.path.join(base, rel)
    try:
        st = os.stat(p)
    except OSError:
        return None
    cached = state_files.get(rel)
    if cached and cached[1] == st.st_size and cached[2] == st.st_mtime_ns:
        return cached[0]
    return sha256_file(p)


# ----------------------------------------------------------------------------
# pack
# ----------------------------------------------------------------------------

class BlockWriter:
    """Accumulates pieces into solid blocks spooled to temporary files."""

    def __init__(self, tmp: str):
        self.tmp = tmp
        self.blocks = []        # {"archive","kind","usize"}
        self.open = {}          # (archive, kind) -> [block_id, bytearray]

    def _flush(self, key) -> None:
        bid, buf = self.open.pop(key)
        with open(os.path.join(self.tmp, "%06d.raw" % bid), "wb") as f:
            f.write(buf)
        self.blocks[bid]["usize"] = len(buf)

    def add(self, archive: str, kind: str, data) -> list:
        """Append bytes; returns extents [(block, offset, length), ...]."""
        limit = RAW_BLOCK_MAX if kind == "raw" else BLOCK_MAX
        key = (archive, kind)
        extents = []
        view = memoryview(data)
        pos = 0
        n = len(view)
        while pos < n:
            if key not in self.open:
                self.blocks.append({"archive": archive, "kind": kind, "usize": 0})
                self.open[key] = [len(self.blocks) - 1, bytearray()]
            bid, buf = self.open[key]
            room = limit - len(buf)
            # keep small pieces whole; only split pieces that cannot fit a block
            if room <= 0 or (n - pos > room and n - pos <= limit and len(buf) > 0):
                self._flush(key)
                continue
            take = min(room, n - pos)
            extents.append((bid, len(buf), take))
            buf += view[pos:pos + take]
            pos += take
        return extents

    def finish(self, archive=None) -> None:
        for key in list(self.open):
            if archive is None or key[0] == archive:
                self._flush(key)


def _compress_block(args):
    tmp, bid, kind = args
    src = os.path.join(tmp, "%06d.raw" % bid)
    with open(src, "rb") as f:
        raw = f.read()
    codec, dsize, out = "raw", 0, raw
    if kind != "raw":
        codec = kind if kind.startswith("delta") else "lzma"
        dsize = dict_size_for(len(raw))
        packed = lzma.compress(raw, format=lzma.FORMAT_RAW, filters=filters_for(codec, dsize))
        if len(packed) < len(raw) * 0.98:
            out = packed
        else:
            codec, dsize = "raw", 0
    dst = os.path.join(tmp, "%06d.blk" % bid)
    with open(dst, "wb") as f:
        f.write(out)
    os.remove(src)
    return bid, codec, dsize, len(out), len(raw)


def merge_extents(extents: list) -> list:
    out = []
    for b, o, n in extents:
        if out and out[-1][0] == b and out[-1][1] + out[-1][2] == o:
            out[-1][2] += n
        else:
            out.append([b, o, n])
    return out


def cmd_pack(args) -> int:
    root = args.root
    base = os.path.join(root, ASSETS)
    if not os.path.isdir(base):
        sys.exit("No assets/ directory. Run `python tools/pak.py unpack` first.")
    old = load_index(root)
    all_files = scan_assets(root)
    all_set = set(all_files)
    known = set(old["files"]) if old else set()

    # Godot writes .import files and extracted GLB textures next to the sources
    # when it imports the project; those are not project content.
    skipped_generated = []
    files = []
    glb_cache = {}
    for rel in all_files:
        if old is not None and rel not in known and not args.all:
            if rel.endswith(".import"):
                skipped_generated.append(rel)
                continue
            if godot_extracted_texture(rel, all_set, base, glb_cache):
                skipped_generated.append(rel)
                continue
        files.append(rel)

    if old and not args.force:
        missing = [r for r in known if r not in all_set]
        if len(missing) > max(20, len(known) // 5):
            sys.exit("%d of %d packed files are missing from assets/. Did you forget "
                     "`python tools/pak.py unpack`?  Use --force to pack anyway (this "
                     "DELETES them from the packs)." % (len(missing), len(known)))

    order = {name: i for i, (name, _) in enumerate(ARCHIVES)}
    files.sort(key=lambda r: (order[archive_of(r)], r))
    t0 = time.time()
    tmp = tempfile.mkdtemp(prefix="cs15pak_", dir=args.tmp)
    try:
        writer = BlockWriter(tmp)
        seen = {}            # sha1 digest -> extents
        entries = {}
        total = 0
        dup_bytes = 0
        last_arch = archive_of(files[0]) if files else None
        for n, rel in enumerate(files):
            with open(os.path.join(base, rel), "rb") as f:
                data = f.read()
            total += len(data)
            arch = archive_of(rel)
            if arch != last_arch:
                writer.finish(last_arch)
                last_arch = arch
            extents = []
            whole = None
            if len(data) >= DEDUPE_MIN:
                whole = hashlib.sha1(data).digest() + b"F"
                if whole in seen:
                    extents = list(seen[whole])
                    dup_bytes += len(data)
            if not extents:
                mv = memoryview(data)
                for kind, a, b in segments_for(rel, data):
                    piece = mv[a:b]
                    key = None
                    if b - a >= DEDUPE_MIN:
                        key = hashlib.sha1(piece).digest()
                        hit = seen.get(key)
                        if hit is not None:
                            extents.extend(hit)
                            dup_bytes += b - a
                            continue
                    ext = writer.add(arch, kind, piece)
                    extents.extend(ext)
                    if key is not None:
                        seen[key] = ext
                extents = merge_extents(extents)
                if whole is not None:
                    seen[whole] = extents
            entries[rel] = {
                "archive": arch,
                "size": len(data),
                "sha256": hashlib.sha256(data).hexdigest(),
                "extents": [x for e in extents for x in e],
            }
            if not args.quiet and (n % 500 == 0 or n == len(files) - 1):
                print("\r  reading %d/%d files" % (n + 1, len(files)), end="", flush=True)
        writer.finish()
        if not args.quiet:
            print("\n  %s in %d files; %s of repeated content stored once; compressing %d blocks…"
                  % (human(total), len(files), human(dup_bytes), len(writer.blocks)), flush=True)

        jobs = [(tmp, bid, b["kind"]) for bid, b in enumerate(writer.blocks)]
        jobs.sort(key=lambda j: -writer.blocks[j[1]]["usize"])
        results = {}
        with cf.ProcessPoolExecutor(max_workers=args.jobs) as pool:
            for k, res in enumerate(pool.map(_compress_block, jobs)):
                results[res[0]] = res
                if not args.quiet:
                    print("\r  compressed %d/%d blocks" % (k + 1, len(jobs)), end="", flush=True)
        if not args.quiet:
            print(flush=True)

        # ---- assemble archive parts --------------------------------------
        staging = os.path.join(tmp, "out")
        os.makedirs(staging)
        blocks_meta = [None] * len(writer.blocks)
        parts = []           # {"name","archive","size","sha256"}
        for arch, _ in ARCHIVES:
            bids = [i for i, b in enumerate(writer.blocks) if b["archive"] == arch]
            if not bids:
                continue
            fh = None
            hsh = None
            size = 0
            serial = 0

            def close_part():
                nonlocal fh
                if fh is not None:
                    fh.close()
                    parts[-1]["size"] = size
                    parts[-1]["sha256"] = hsh.hexdigest()
                    fh = None

            for bid in bids:
                _, codec, dsize, csize, usize = results[bid]
                if fh is None or size + csize > PART_MAX:
                    close_part()
                    name = "%s_%03d.pak" % (arch, serial)
                    serial += 1
                    parts.append({"name": name, "archive": arch, "size": 0, "sha256": ""})
                    fh = open(os.path.join(staging, name), "wb")
                    hsh = hashlib.sha256()
                    head = PART_MAGIC + struct.pack("<II", FORMAT_VERSION, 0)
                    fh.write(head)
                    hsh.update(head)
                    size = PART_HEADER
                with open(os.path.join(tmp, "%06d.blk" % bid), "rb") as f:
                    payload = f.read()
                fh.write(payload)
                hsh.update(payload)
                blocks_meta[bid] = [len(parts) - 1, size, csize, usize, codec, dsize]
                size += csize
            close_part()

        idx = {
            "format": FORMAT_VERSION,
            "tool": "tools/pak.py",
            "parts": parts,
            "blocks": blocks_meta,
            "files": entries,
        }

        # ---- verify from the staged archives before replacing anything ---
        if not args.no_verify:
            if not args.quiet:
                print("  verifying every file can be rebuilt bit-exactly…", flush=True)
            bad = deep_verify(idx, staging, args.jobs, quiet=True)
            if bad:
                sys.exit("INTERNAL ERROR: %d files do not round-trip (%s). Packs left untouched."
                         % (len(bad), ", ".join(bad[:5])))

        packs_dir = os.path.join(root, PACKS)
        os.makedirs(packs_dir, exist_ok=True)
        keep = {p["name"] for p in parts}
        for fn in os.listdir(packs_dir):
            if fn.endswith(".pak") and fn not in keep:
                os.remove(os.path.join(packs_dir, fn))
        for p in parts:
            shutil.move(os.path.join(staging, p["name"]), os.path.join(packs_dir, p["name"]))
        save_index(root, idx)
        write_contents(root, idx)
        save_state(root, idx)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    packed = sum(p["size"] for p in idx["parts"]) + os.path.getsize(index_path(root))
    print("Packed %d files: %s -> %s (%.1f%%) in %d archive files, %.0fs."
          % (len(entries), human(total), human(packed), 100.0 * packed / max(total, 1),
             len(idx["parts"]), time.time() - t0))
    if skipped_generated:
        print("Ignored %d files generated by the Godot importer (.import / extracted GLB "
              "textures). Use --all to pack them too." % len(skipped_generated))
    if old:
        removed = sorted(known - set(entries))
        added = sorted(set(entries) - known)
        if added:
            print("Added %d files (e.g. %s)" % (len(added), ", ".join(added[:3])))
        if removed:
            print("Removed %d files (e.g. %s)" % (len(removed), ", ".join(removed[:3])))
    return 0


def write_contents(root: str, idx: dict) -> None:
    per = {}
    for rel, info in idx["files"].items():
        a = per.setdefault(info["archive"], {"files": 0, "size": 0, "dirs": {}})
        a["files"] += 1
        a["size"] += info["size"]
        top = "/".join(rel.split("/")[:-1][:2]) or "."
        a["dirs"][top] = a["dirs"].get(top, 0) + 1
    psize = {}
    pcount = {}
    for p in idx["parts"]:
        psize[p["archive"]] = psize.get(p["archive"], 0) + p["size"]
        pcount[p["archive"]] = pcount.get(p["archive"], 0) + 1
    lines = [
        "# Asset packs",
        "",
        "Generated by `python tools/pak.py pack` — do not edit by hand.",
        "Restore the editable `assets/` tree with `python tools/pak.py unpack`.",
        "",
        "| Archive | Parts | Files | Original | Packed | Contents (`assets/…`) |",
        "| :--- | ---: | ---: | ---: | ---: | :--- |",
    ]
    tot_files = tot_size = tot_packed = tot_parts = 0
    for arch, _ in ARCHIVES:
        if arch not in per:
            continue
        a = per[arch]
        dirs = ", ".join("`%s` (%d)" % (d, c) for d, c in sorted(a["dirs"].items()))
        lines.append("| `%s_NNN.pak` | %d | %d | %s | %s | %s |" % (
            arch, pcount.get(arch, 0), a["files"], human(a["size"]), human(psize.get(arch, 0)), dirs))
        tot_files += a["files"]
        tot_size += a["size"]
        tot_packed += psize.get(arch, 0)
        tot_parts += pcount.get(arch, 0)
    lines.append("| **Total** | **%d** | **%d** | **%s** | **%s** | |" % (
        tot_parts, tot_files, human(tot_size), human(tot_packed)))
    lines += [
        "",
        "An archive may be smaller than its share of the content: a piece that is",
        "identical to one already stored by an earlier archive (for example the arm",
        "textures embedded in every view model) is referenced, not stored again.",
        "`pak_dir.idx` is the directory: file → SHA-256 + where its pieces live.",
        "",
    ]
    with open(os.path.join(root, PACKS, CONTENTS_NAME), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))


# ----------------------------------------------------------------------------
# decode
# ----------------------------------------------------------------------------

def read_block(packs_dir: str, idx: dict, bid: int) -> bytes:
    part, off, csize, usize, codec, dsize = idx["blocks"][bid]
    with open(os.path.join(packs_dir, idx["parts"][part]["name"]), "rb") as f:
        if f.read(len(PART_MAGIC)) != PART_MAGIC:
            raise IOError("%s is not a CS15 pack" % idx["parts"][part]["name"])
        f.seek(off)
        data = f.read(csize)
    if len(data) != csize:
        raise IOError("%s is truncated" % idx["parts"][part]["name"])
    if codec != "raw":
        data = lzma.decompress(data, format=lzma.FORMAT_RAW, filters=filters_for(codec, dsize))
    if len(data) != usize:
        raise IOError("block %d decoded to the wrong size" % bid)
    return data


def plan_blocks(idx: dict, wanted) -> dict:
    """block id -> [(rel, file_offset, block_offset, length), ...]"""
    plan = {}
    for rel in wanted:
        ext = idx["files"][rel]["extents"]
        pos = 0
        for i in range(0, len(ext), 3):
            b, o, n = ext[i], ext[i + 1], ext[i + 2]
            plan.setdefault(b, []).append((rel, pos, o, n))
            pos += n
        if pos != idx["files"][rel]["size"]:
            raise IOError("index is inconsistent for " + rel)
    return plan


_W = {}


def _init_worker(packs_dir, idx_file, out_base):
    _W["packs"] = packs_dir
    _W["out"] = out_base
    with open(idx_file, "rb") as f:
        _W["idx"] = json.loads(f.read().decode("utf-8"))


def _write_block(job):
    bid, writes = job
    data = read_block(_W["packs"], _W["idx"], bid)
    view = memoryview(data)
    by_file = {}
    for rel, fpos, o, n in writes:
        by_file.setdefault(rel, []).append((fpos, o, n))
    for rel, items in by_file.items():
        with open(os.path.join(_W["out"], rel), "r+b") as f:
            for fpos, o, n in items:
                f.seek(fpos)
                f.write(view[o:o + n])
    return bid


def _hash_block(job):
    """Verify-only path: return the bytes each file needs from this block."""
    bid, writes = job
    data = read_block(_W["packs"], _W["idx"], bid)
    return [(rel, fpos, data[o:o + n]) for rel, fpos, o, n in writes]


def _hash_file(job):
    base, rel = job
    return rel, sha256_file(os.path.join(base, rel))


def extract(idx: dict, packs_dir: str, out_base: str, wanted: list, jobs: int, quiet: bool) -> list:
    """Write `wanted` files under out_base. Returns the list of files that failed."""
    for rel in wanted:
        p = os.path.join(out_base, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "wb") as f:
            f.truncate(idx["files"][rel]["size"])
    plan = plan_blocks(idx, wanted)
    fd, idx_file = tempfile.mkstemp(prefix="cs15idx_", suffix=".json")
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(json.dumps({"parts": idx["parts"], "blocks": idx["blocks"]}).encode("utf-8"))
        tasks = sorted(plan.items(), key=lambda kv: -idx["blocks"][kv[0]][3])
        with cf.ProcessPoolExecutor(max_workers=jobs, initializer=_init_worker,
                                    initargs=(packs_dir, idx_file, out_base)) as pool:
            for k, _ in enumerate(pool.map(_write_block, tasks)):
                if not quiet:
                    print("\r  unpacked %d/%d blocks" % (k + 1, len(tasks)), end="", flush=True)
            if not quiet and tasks:
                print(flush=True)
            bad = []
            hashes = pool.map(_hash_file, [(out_base, r) for r in wanted], chunksize=64)
            for rel, digest in hashes:
                if digest != idx["files"][rel]["sha256"]:
                    bad.append(rel)
    finally:
        os.remove(idx_file)
    return bad


def deep_verify(idx: dict, packs_dir: str, jobs: int, quiet: bool) -> list:
    """Rebuild every file in a scratch directory and compare SHA-256."""
    tmp = tempfile.mkdtemp(prefix="cs15verify_", dir=os.environ.get("CS15PAK_TMP"))
    try:
        return extract(idx, packs_dir, tmp, sorted(idx["files"]), jobs, quiet)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# ----------------------------------------------------------------------------
# commands
# ----------------------------------------------------------------------------

def require_index(root: str) -> dict:
    idx = load_index(root)
    if idx is None:
        sys.exit("packs/%s not found — nothing has been packed yet." % INDEX_NAME)
    return idx


def check_parts(root: str, idx: dict, full: bool) -> list:
    problems = []
    for p in idx["parts"]:
        path = os.path.join(root, PACKS, p["name"])
        if not os.path.exists(path):
            problems.append("%s is missing" % p["name"])
        elif os.path.getsize(path) != p["size"]:
            problems.append("%s has the wrong size (incomplete download / Git LFS pointer?)" % p["name"])
        elif full and sha256_file(path) != p["sha256"]:
            problems.append("%s is corrupted (SHA-256 mismatch)" % p["name"])
    return problems


def cmd_unpack(args) -> int:
    root = args.root
    idx = require_index(root)
    problems = check_parts(root, idx, full=False)
    if problems:
        sys.exit("Cannot unpack:\n  " + "\n  ".join(problems))
    base = os.path.join(root, ASSETS)
    state_files = load_state(root).get("files", {})
    t0 = time.time()
    wanted, modified, ok = [], [], 0
    synced = set()
    for rel, info in sorted(idx["files"].items()):
        if args.only and not any(rel.startswith(o) or info["archive"] == o for o in args.only):
            continue
        p = os.path.join(base, rel)
        if not os.path.exists(p):
            wanted.append(rel)
            continue
        if args.force:
            if os.path.getsize(p) == info["size"] and sha256_file(p) == info["sha256"]:
                ok += 1
                synced.add(rel)
            else:
                wanted.append(rel)
            continue
        cur = current_sha(base, rel, state_files)
        if cur == info["sha256"]:
            ok += 1
            synced.add(rel)
        elif rel in state_files and cur == state_files[rel][0]:
            wanted.append(rel)      # untouched since last sync; packs are newer
        else:
            modified.append(rel)    # edited locally: never overwrite silently
    stale = []
    if not args.only:
        for rel in state_files:
            if rel not in idx["files"] and os.path.exists(os.path.join(base, rel)):
                if current_sha(base, rel, state_files) == state_files[rel][0]:
                    stale.append(rel)
    if wanted:
        if not args.quiet:
            print("Unpacking %d files (%s) into assets/ …" % (
                len(wanted), human(sum(idx["files"][r]["size"] for r in wanted))), flush=True)
        bad = extract(idx, os.path.join(root, PACKS), base, wanted, args.jobs, args.quiet)
        if bad:
            sys.exit("ERROR: %d files failed verification, e.g. %s" % (len(bad), ", ".join(bad[:5])))
    for rel in stale:   # removed from the packs upstream and untouched locally
        os.remove(os.path.join(base, rel))
        if os.path.exists(os.path.join(base, rel + ".import")) and (rel + ".import") not in idx["files"]:
            os.remove(os.path.join(base, rel + ".import"))
    save_state(root, idx, synced | set(wanted))
    print("assets/ ready: %d restored, %d already up to date%s (%.0fs). Every restored file "
          "matched its SHA-256." % (len(wanted), ok,
                                    (", %d obsolete removed" % len(stale)) if stale else "",
                                    time.time() - t0))
    if modified:
        print("\n%d files were changed locally and were NOT overwritten:" % len(modified))
        for rel in modified[:15]:
            print("  assets/" + rel)
        if len(modified) > 15:
            print("  … and %d more" % (len(modified) - 15))
        print("Keep them with `python tools/pak.py pack`, or discard them with "
              "`python tools/pak.py unpack --force`.")
    return 0


def compute_status(root: str, idx: dict):
    base = os.path.join(root, ASSETS)
    state_files = load_state(root).get("files", {})
    on_disk = set(scan_assets(root)) if os.path.isdir(base) else set()
    modified, missing = [], []
    for rel, info in idx["files"].items():
        if rel not in on_disk:
            missing.append(rel)
        elif current_sha(base, rel, state_files) != info["sha256"]:
            modified.append(rel)
    new, generated = [], []
    cache = {}
    for rel in sorted(on_disk - set(idx["files"])):
        if rel.endswith(".import") or godot_extracted_texture(rel, on_disk, base, cache):
            generated.append(rel)
        else:
            new.append(rel)
    return sorted(modified), sorted(missing), new, generated


def cmd_status(args) -> int:
    root = args.root
    idx = require_index(root)
    problems = check_parts(root, idx, full=False)
    for p in problems:
        print("PACK PROBLEM: " + p)
    modified, missing, new, generated = compute_status(root, idx)
    total = len(idx["files"])
    if len(missing) == total:
        print("assets/ has not been unpacked yet. Run: python tools/pak.py unpack")
        return 1
    for title, rows in (("Modified (not yet packed)", modified), ("New (not yet packed)", new),
                        ("Missing from assets/ (will be removed from packs on next pack, or "
                         "restored by unpack)", missing)):
        if rows:
            print("%s: %d" % (title, len(rows)))
            for rel in rows[:args.limit]:
                print("  assets/" + rel)
            if len(rows) > args.limit:
                print("  … and %d more" % (len(rows) - args.limit))
    if generated:
        print("Ignored: %d files generated by the Godot importer." % len(generated))
    if not (modified or missing or new or problems):
        print("assets/ and packs/ are in sync (%d files)." % total)
        return 0
    if modified or new or missing:
        print("\nRun `python tools/pak.py pack` and commit packs/ to keep these changes.")
    return 1


def cmd_verify(args) -> int:
    root = args.root
    idx = require_index(root)
    problems = check_parts(root, idx, full=True)
    if problems:
        print("FAILED:\n  " + "\n  ".join(problems))
        return 1
    print("%d archive files match their SHA-256." % len(idx["parts"]))
    if args.deep:
        os.environ.setdefault("CS15PAK_TMP", args.tmp or tempfile.gettempdir())
        bad = deep_verify(idx, os.path.join(root, PACKS), args.jobs, args.quiet)
        if bad:
            print("FAILED: %d files do not rebuild correctly, e.g. %s" % (len(bad), ", ".join(bad[:5])))
            return 1
        print("All %d files rebuild bit-exactly from the packs." % len(idx["files"]))
    return 0


def cmd_list(args) -> int:
    idx = require_index(args.root)
    rows = sorted(idx["files"].items(), key=lambda kv: (kv[1]["archive"], kv[0]))
    cur = None
    for rel, info in rows:
        if args.archive and info["archive"] != args.archive:
            continue
        if info["archive"] != cur:
            cur = info["archive"]
            print("[%s]" % cur)
        print("  %10d  %s  assets/%s" % (info["size"], info["sha256"][:12], rel))
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0],
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", default=ROOT, help="project root (default: this repository)")
    ap.add_argument("-j", "--jobs", type=int, default=max(1, min(os.cpu_count() or 1, 8)),
                    help="worker processes (packing needs ~0.7 GB RAM per worker)")
    ap.add_argument("-q", "--quiet", action="store_true")
    ap.add_argument("--tmp", default=None, help="scratch directory (needs room for the unpacked assets)")
    # the global options are accepted after the command too
    common = argparse.ArgumentParser(add_help=False, argument_default=argparse.SUPPRESS)
    common.add_argument("--root")
    common.add_argument("-j", "--jobs", type=int)
    common.add_argument("-q", "--quiet", action="store_true")
    common.add_argument("--tmp")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("unpack", parents=[common], help="restore assets/ from packs/")
    p.add_argument("--force", action="store_true", help="overwrite locally modified files too")
    p.add_argument("--only", nargs="+", metavar="ARCHIVE_OR_PREFIX",
                   help="restore only these archives / path prefixes (e.g. maps sounds/radio/)")
    p.set_defaults(func=cmd_unpack)

    p = sub.add_parser("pack", parents=[common], help="rebuild packs/ from assets/")
    p.add_argument("--all", action="store_true",
                   help="also pack new .import files and textures extracted by Godot")
    p.add_argument("--force", action="store_true", help="pack even if most files are missing")
    p.add_argument("--no-verify", action="store_true", help="skip the round-trip verification")
    p.set_defaults(func=cmd_pack)

    p = sub.add_parser("status", parents=[common], help="compare assets/ with packs/")
    p.add_argument("--limit", type=int, default=25)
    p.set_defaults(func=cmd_status)

    p = sub.add_parser("verify", parents=[common], help="check archive integrity")
    p.add_argument("--deep", action="store_true", help="decode every file and compare SHA-256")
    p.set_defaults(func=cmd_verify)

    p = sub.add_parser("list", parents=[common], help="list packed files")
    p.add_argument("archive", nargs="?")
    p.set_defaults(func=cmd_list)

    args = ap.parse_args(argv)
    args.root = os.path.abspath(args.root)
    if args.tmp:
        os.environ["CS15PAK_TMP"] = args.tmp
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
