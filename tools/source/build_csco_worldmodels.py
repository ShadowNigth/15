#!/usr/bin/env python3
"""Build p_/w_ static weapon models from Classic-Offensive VVD/VTX meshes.

    PYTHONPATH=<SourceIO parent> python -m tools.source.build_csco_worldmodels \
        <CSCO checkout> <M.A.T>/Source <reference p_/w_ dir> <out_dir> [weapon ...]

CSCO has only a handful of usable third-person w_ models, so the script derives the
static mesh from each CSCO v_ model (which contains no arms) and rigidly fits it to
the already calibrated p_/w_ model of the same slot. A 24-axis ICP seed handles the
Galil-derived MP5 and other custom reference poses without changing their scale.
Elite, G3SG1 and M249 have no CSCO v_ mesh: their M.A.T. world geometry is rebuilt
with the matching CSCO texture instead.
"""
import json
import os
import sys

import numpy as np

from .build_csco_viewmodels import (CSCO_MODELS, GRENADES, MAT_WITH_CSCO_TEXTURE, MaterialLibrary, OFFSET)
from .build_csgo_viewmodels import WEAPONS
from .build_csgo_worldmodels import (_proper_axis_rotations, _ortho, build as build_mat_world,
                                     fit_to_reference, glb_positions, write_static_glb)
from .mdl_reader import load_model
from .smd_converter import L, RA, SCALE


def mdl_triangles(model):
    """[(material, [(position_m, normal, uv), ...] * 3)] in Godot viewmodel axes."""
    triangles = []
    for mesh in model["meshes"]:
        pos = RA(L(mesh["pos"]) * SCALE) + OFFSET
        nrm = RA(L(mesh["nrm"]))
        nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-8)
        # VVD/VTF coordinates already match glTF's top-left texture origin.
        # Do not apply the SMD/Blender V inversion to direct Source meshes.
        uv = np.asarray(mesh["uv"], dtype=np.float64).copy()
        for tri in np.asarray(mesh["idx"], dtype=np.int64):
            triangles.append((mesh["material"], [(pos[i], nrm[i], uv[i]) for i in tri]))
    return triangles


def fit_best(points, reference):
    best = None
    for initial in _proper_axis_rotations():
        fit = fit_to_reference(points, reference, initial, iters=18)
        if best is None or fit[2] < best[2]:
            best = fit
    # Refine the winning octant/axis convention more thoroughly.
    refined = fit_to_reference(points, reference, best[0], iters=60)
    if refined[2] <= best[2]:
        best = refined
    return best


def build_one(weapon, csco_root, ref_dir, out_dir, library, report):
    model = load_model(os.path.join(csco_root, "models", "weapons", CSCO_MODELS[weapon] + ".mdl"))
    triangles = mdl_triangles(model)
    points = np.array([v[0] for _, tri in triangles for v in tri])
    cache = {}

    def materials_for(name):
        entry = library.entry(model, name, 512, weapon)
        return entry.get("image"), entry.get("color")

    game = "mp5" if weapon == "mp5" else weapon
    info = {}
    for prefix in ("p", "w"):
        reference_path = os.path.join(ref_dir, "%s_%s.glb" % (prefix, game))
        reference = glb_positions(reference_path)
        rotation, translation, residual, angle = fit_best(points, reference)
        write_static_glb(os.path.join(out_dir, "%s_%s.glb" % (prefix, game)), "%s_%s" % (prefix, game),
                         [(triangles, _ortho(rotation), translation)], materials_for)
        info[prefix + "_fit"] = {"residual_m": round(residual, 5), "deg_from_seed": round(angle, 2)}
        print("  %s_%s residual %.4f m" % (prefix, game, residual), flush=True)
    report[weapon] = info
    return info


def main():
    csco_root, mat_root, ref_dir, out_dir = sys.argv[1:5]
    only = sys.argv[5:] or list(WEAPONS) + list(GRENADES) + ["c4"]
    os.makedirs(out_dir, exist_ok=True)
    library = MaterialLibrary(csco_root, mat_root)
    report, mat_report = {}, {}
    for weapon in only:
        print(weapon, flush=True)
        if weapon in MAT_WITH_CSCO_TEXTURE:
            build_mat_world(weapon, mat_root, ref_dir, out_dir, mat_report,
                            texture_override=os.path.join(csco_root, MAT_WITH_CSCO_TEXTURE[weapon]))
            report[weapon] = mat_report.get(weapon, {})
            report[weapon]["source"] = "M.A.T. geometry + CSCO texture"
        else:
            build_one(weapon, csco_root, ref_dir, out_dir, library, report)
    if library.missing:
        report["_missing_csco_materials"] = sorted(set(library.missing))
    if library.fallbacks:
        report["_mat_texture_fallbacks"] = sorted(set(library.fallbacks))
    with open(os.path.join(out_dir, "world_report.json"), "w") as f:
        json.dump(report, f, indent=1)
    print("built", len(only), "weapon slots")


if __name__ == "__main__":
    main()
