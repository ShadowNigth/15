#!/usr/bin/env python3
"""
Converts and sanitizes all GoldSrc WAV files from cstrike/sound and cstrike/media
into clean standard RIFF PCM WAV files compatible with Godot 4's audio importer.
"""

import glob
import os
import struct


def sanitize_wav(src_path: str, dst_path: str) -> bool:
    """Reads a GoldSrc WAV and writes a clean standard PCM RIFF WAV (fmt + data only)."""
    with open(src_path, "rb") as f:
        raw = f.read()
    if len(raw) < 44 or raw[:4] != b"RIFF" or raw[8:12] != b"WAVE":
        return False

    pos = 12
    fmt_chunk = None
    data_chunk = None
    while pos + 8 <= len(raw):
        cid = raw[pos : pos + 4]
        csz = struct.unpack_from("<I", raw, pos + 4)[0]
        body_start = pos + 8
        body_end = min(len(raw), body_start + csz)
        if cid == b"fmt " and csz >= 16:
            audio_fmt, channels, sample_rate, byte_rate, block_align, bits_per_sample = (
                struct.unpack_from("<HHIIHH", raw, body_start)
            )
            if audio_fmt == 1:  # PCM
                # Keep standard 16-byte PCM fmt header
                fmt_chunk = struct.pack(
                    "<HHIIHH",
                    1,
                    channels,
                    sample_rate,
                    sample_rate * channels * max(1, bits_per_sample // 8),
                    channels * max(1, bits_per_sample // 8),
                    bits_per_sample,
                )
        elif cid == b"data":
            data_chunk = raw[body_start:body_end]
        pos = body_start + csz + (csz & 1)

    os.makedirs(os.path.dirname(dst_path), exist_ok=True)
    if fmt_chunk is None or data_chunk is None:
        # Fallback direct copy if non-PCM (e.g., IMA ADPCM if any)
        with open(dst_path, "wb") as out:
            out.write(raw)
        return True

    # Ensure even byte alignment on ALL PCM chunks (RIFF requires 2-byte word alignment;
    # Godot 4's audio_stream_wav.cpp seeks to file_pos + chunksize + (chunksize & 1))
    bits = struct.unpack_from("<H", fmt_chunk, 14)[0]
    if len(data_chunk) & 1:
        if bits == 8:
            data_chunk = data_chunk + b"\x80"  # 1 sample of unsigned 8-bit silence
        else:
            data_chunk = data_chunk[:-1]

    riff_size = 4 + (8 + len(fmt_chunk)) + (8 + len(data_chunk))
    with open(dst_path, "wb") as out:
        out.write(b"RIFF")
        out.write(struct.pack("<I", riff_size))
        out.write(b"WAVE")
        out.write(b"fmt ")
        out.write(struct.pack("<I", len(fmt_chunk)))
        out.write(fmt_chunk)
        out.write(b"data")
        out.write(struct.pack("<I", len(data_chunk)))
        out.write(data_chunk)
    return True


def run_audio_extraction(cstrike_dir: str, out_sounds_dir: str) -> None:
    count = 0
    for subdir in ("sound", "media"):
        src_root = os.path.join(cstrike_dir, subdir)
        if not os.path.isdir(src_root):
            continue
        for wav_path in sorted(glob.glob(os.path.join(src_root, "**", "*.[wW][aA][vV]"), recursive=True)):
            rel = os.path.relpath(wav_path, src_root).replace("\\", "/").lower()
            prefix = "ui" if subdir == "media" else ""
            dst_path = os.path.join(out_sounds_dir, prefix, rel) if prefix else os.path.join(out_sounds_dir, rel)
            if sanitize_wav(wav_path, dst_path):
                count += 1
    print(f"[audio_converter] Sanitized & exported {count} WAV files -> {out_sounds_dir}")
