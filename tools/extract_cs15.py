#!/usr/bin/env python3
"""
Master Counter-Strike 1.5 Retail -> Godot 4 Asset & Data Extractor.

Usage:
  python3 tools/extract_cs15.py [--source /path/to/counterstrike-betas/cstrike] [--output .]

If --source is omitted, clones https://github.com/Ch0wW/counterstrike-betas (branch cs15_retail)
into a temporary directory and extracts the retained 15 maps, 110+ models, 379 WAV sounds, HUD sprites,
VGUI portraits, skyboxes, radar overviews, and cs_i386.so binary weapon statistics.
"""

import argparse
import json
import os
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from goldsrc.audio_converter import run_audio_extraction
from goldsrc.binary_stats import run_binary_stats_extraction
from goldsrc.bsp_converter import run_bsp_extraction
from goldsrc.mdl_converter import run_models_extraction
from goldsrc.wad_spr_ui import (
    collect_wad_catalog,
    extract_spr_files,
    extract_ui_and_overviews,
)

CS15_REPO_URL = "https://github.com/Ch0wW/counterstrike-betas.git"
CS15_BRANCH = "cs15_retail"


def ensure_source_dir(source_arg: str) -> str:
    if source_arg:
        cstrike_cand = os.path.join(source_arg, "cstrike")
        if os.path.isdir(cstrike_cand):
            return cstrike_cand
        if os.path.isdir(source_arg):
            return source_arg
        raise FileNotFoundError(f"Source directory not found: {source_arg}")

    tmp_clone = os.path.join(tempfile.gettempdir(), "cs15_retail_clone")
    cstrike_dir = os.path.join(tmp_clone, "cstrike")
    if not os.path.isdir(cstrike_dir):
        print(f"[extract_cs15] Cloning {CS15_REPO_URL} ({CS15_BRANCH}) -> {tmp_clone} ...")
        subprocess.check_call(
            ["git", "clone", "--depth", "1", "--branch", CS15_BRANCH, CS15_REPO_URL, tmp_clone]
        )
    return cstrike_dir


def main() -> None:
    parser = argparse.ArgumentParser(description="Extract Counter-Strike 1.5 Retail assets for Godot 4")
    parser.add_argument("--source", default="", help="Path to counterstrike-betas or cstrike folder")
    parser.add_argument(
        "--output",
        default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        help="Root directory of the Godot 4 project",
    )
    args = parser.parse_args()

    t0 = time.time()
    cstrike_dir = ensure_source_dir(args.source)
    out_root = os.path.abspath(args.output)
    out_data = os.path.join(out_root, "data")
    out_assets = os.path.join(out_root, "assets")

    print(f"[extract_cs15] Source: {cstrike_dir}")
    print(f"[extract_cs15] Output: {out_root}")

    # 1. Weapon stats (cs_i386.so), classes, HUD rects, materials, radio, titles
    run_binary_stats_extraction(cstrike_dir, out_data)

    # 2. Sanitized RIFF PCM WAV sounds (sound/ + media/)
    run_audio_extraction(cstrike_dir, os.path.join(out_assets, "sounds"))

    # 3. Index WAD3 archives & convert the retained 15 BSP v30 maps + lightmaps + Bot nav graphs
    wad_catalog = collect_wad_catalog(cstrike_dir)
    print(f"[extract_cs15] Indexed {len(wad_catalog)} WAD3 textures across cstrike/*.wad")
    _, used_skies = run_bsp_extraction(
        cstrike_dir,
        wad_catalog,
        os.path.join(out_assets, "textures", "world"),
        os.path.join(out_assets, "maps"),
        out_data,
    )

    # 4. SPR v2 HUD & VFX sprites
    spr_meta = extract_spr_files(
        os.path.join(cstrike_dir, "sprites"),
        os.path.join(out_assets, "sprites"),
    )
    with open(os.path.join(out_data, "sprites_meta.json"), "w", encoding="utf-8") as f:
        json.dump(spr_meta, f, indent=2)
    print(f"[extract_cs15] Extracted {len(spr_meta)} SPR v2 sprites -> assets/sprites/")

    # 5. VGUI cards, WON Shell graphics, Radar Overviews, Skyboxes, Project Icon
    extract_ui_and_overviews(
        cstrike_dir,
        os.path.join(out_assets, "ui"),
        os.path.join(out_assets, "textures", "sky"),
        out_data,
        used_skies,
    )

    # 6. StudioMDL v10 -> Skinned Animated glTF 2.0 (.glb) models
    run_models_extraction(cstrike_dir, os.path.join(out_assets, "models"), out_data)

    elapsed = time.time() - t0
    print(f"\n[extract_cs15] Completed full CS 1.5 -> Godot 4 extraction in {elapsed:.1f}s!")


if __name__ == "__main__":
    main()
