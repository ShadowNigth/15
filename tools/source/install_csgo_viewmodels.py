#!/usr/bin/env python3
"""Install the CS:GO M.A.T. viewmodels produced by build_csgo_viewmodels.py.

usage: python3 -m tools.source.install_csgo_viewmodels <build_out_dir> [repo_root]

Copies <out>/v_*.glb into assets/models/weapons/ and updates data/models_meta.json PER KEY
(never wholesale), keeping any attachment point the new model cannot provide (e.g. knife).
"""
import json
import os
import shutil
import sys

REPLACED = ("sequences", "seq_durations", "seq_events", "bones")
POINTS = ("muzzle", "muzzle_unsil", "muzzle_alt", "eject")


def main():
    out_dir = sys.argv[1]
    root = sys.argv[2] if len(sys.argv) > 2 else os.getcwd()
    meta_path = os.path.join(root, "data", "models_meta.json")
    with open(meta_path) as f:
        meta = json.load(f)
    with open(os.path.join(out_dir, "csgo_meta.json")) as f:
        new = json.load(f)
    for key, info in sorted(new.items()):
        if not key.startswith("weapons/"):
            continue
        name = key.split("/", 1)[1]
        src = os.path.join(out_dir, name + ".glb")
        shutil.copyfile(src, os.path.join(root, "assets", "models", "weapons", name + ".glb"))
        entry = meta.setdefault(key, {})
        for k in REPLACED:
            entry[k] = info.get(k, {} if k.startswith("seq_") else [])
        entry.pop("hitboxes", None)  # GoldSrc hitboxes do not exist for these models
        if any(p in info for p in POINTS):
            for p in POINTS:
                if p in info:
                    entry[p] = info[p]
                else:
                    entry.pop(p, None)
        entry["source"] = info.get("source", "ilunp/CSGO-M.A.T")
        print("installed", name, len(entry["sequences"]), "seqs")
    with open(meta_path, "w") as f:
        json.dump(meta, f, indent=1)
        f.write("\n")


if __name__ == "__main__":
    main()
