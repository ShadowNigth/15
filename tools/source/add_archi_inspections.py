#!/usr/bin/env python3
"""Append archi's unused inspection clips without rebuilding any weapon mesh.

    PYTHONPATH=<SourceIO parent> python -m tools.source.add_archi_inspections \
        /tmp/archi /home/user/15
    PYTHONPATH=<SourceIO parent> python -m tools.source.add_archi_inspections \
        /tmp/archi /home/user/15 --check

Only new animation accessors are appended to the eight affected viewmodels.
Existing geometry, UVs, images, materials, skins, nodes, accessors and clips are
preserved. Source event timing is written to models_meta.json so the new clips
retain their authentic foley. Runtime selection lives in PlayerController.gd.
"""
import copy
import json
import os
import re
import sys

import numpy as np

from .build_archi_weapons import (ArchiSounds, SOURCES, VIEW_ROOT_OFFSET, archi_events,
                                  find_package, model_path, sequence_poses)
from .build_csco_viewmodels import OFFSET, _finish_animation, mdl_rig
from .mdl_reader import load_model
from .refine_weapon_animations import append_accessor, read_glb, write_glb
from .smd_converter import to_godot_local
from .build_archi_weapons import calibrate_viewmodel

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
MODEL_DIR = os.path.join("assets", "models", "weapons")
META_PATH = os.path.join("data", "models_meta.json")

TARGETS = {
    "deagle": {"lookat02": "inspect_2"},
    "c4": {"lookat02": "inspect_2", "lookat03": "inspect_3"},
    "flashbang": {"lookat02": "inspect_2"},
    "hegrenade": {"lookat02": "inspect_2"},
    "smokegrenade": {"lookat02": "inspect_2"},
    "decoy": {"lookat02": "inspect_2"},
    "molotov": {"lookat02": "inspect_2"},
    "incendiary": {"lookat02": "inspect_2"},
    # mac10_inspect was reviewed and intentionally excluded: its decoded motion
    # is only float compression noise (~4.3e-5 quaternion components), so it is
    # a static pose rather than a useful second inspection on the installed rig.
}


def _model_base(weapon):
    return "mp5" if weapon == "mp5navy" else weapon


def _node_indices(document, names):
    result = []
    for name in names:
        matches = [index for index, node in enumerate(document.get("nodes", []))
                   if node.get("name") == name]
        if len(matches) != 1:
            raise AssertionError("expected one node named %s, found %d" % (name, len(matches)))
        result.append(matches[0])
    return result


def _append_clip(document, binary, rig, clip):
    name, times, translations, rotations, scales = clip
    if any(item.get("name") == name for item in document.get("animations", [])):
        return False
    if len(times) < 2 or len(translations) != len(times) or len(rotations) != len(times):
        raise AssertionError("invalid frames for " + name)
    nodes = _node_indices(document, rig.names)
    full_time = append_accessor(document, binary, np.asarray(times, dtype=float).tolist(), "SCALAR")
    constant_time = full_time
    if len(times) > 2:
        constant_time = append_accessor(document, binary, [float(times[0]), float(times[-1])], "SCALAR")
    samplers, channels = [], []

    def add(node, path, values, value_type, tolerance):
        values = np.asarray(values, dtype=float)
        constant = len(times) > 2 and float(np.max(np.abs(values - values[0]))) < tolerance
        output_values = np.array([values[0], values[-1]]) if constant else values
        output = append_accessor(document, binary, output_values.tolist(), value_type)
        samplers.append({"input": constant_time if constant else full_time,
                         "interpolation": "LINEAR", "output": output})
        channels.append({"sampler": len(samplers) - 1,
                         "target": {"node": node, "path": path}})

    for bone, node in enumerate(nodes):
        add(node, "translation", translations[:, bone, :], "VEC3", 1e-5)
        add(node, "rotation", rotations[:, bone, :], "VEC4", 1e-5)
    for bone, values in (scales or {}).items():
        add(nodes[bone], "scale", values, "VEC3", 1e-6)
    document.setdefault("animations", []).append({
        "name": name, "samplers": samplers, "channels": channels,
    })
    return True


def _extract(weapon, package, sounds):
    stem = SOURCES[weapon][1]
    model = load_model(model_path(package, stem), want_mesh=False)
    rig = mdl_rig(model)
    by_name = {str(seq["name"]).lower(): seq for seq in model["sequences"]}
    animations, sequences, durations, events, sources = [], [], {}, {}, {}
    for raw, game_name in TARGETS[weapon].items():
        if raw not in by_name:
            raise AssertionError("%s is missing source sequence %s" % (weapon, raw))
        seq = by_name[raw]
        poses, fps = sequence_poses(model, seq)
        if poses is None or fps <= 0.0:
            raise AssertionError("%s/%s has no decodable animation" % (weapon, raw))
        duration = max(len(poses) - 1, 1) / fps
        event_list, show, hide = archi_events(seq, weapon, duration, sounds)
        _finish_animation(weapon, [game_name], poses, fps, event_list, show, hide, rig,
                          animations, sequences, durations, events, raw, sources)
    bind_t, bind_q = to_godot_local(rig, rig.bind, OFFSET)
    calibrate_viewmodel(rig, bind_t, bind_q, [], animations)
    return rig, animations, sequences, durations, events, sources


def _inspect_sort_key(name):
    match = re.fullmatch(r"inspect(?:_(\d+))?", name)
    return int(match.group(1) or 1) if match else 999


def _check_model(document, weapon):
    expected = set(TARGETS[weapon].values())
    present = {item.get("name") for item in document.get("animations", [])}
    missing = sorted(expected - present)
    if missing:
        raise AssertionError("%s lacks clips %s" % (weapon, ", ".join(missing)))
    by_name = {item.get("name"): item for item in document["animations"]}
    for name in expected:
        clip = by_name[name]
        if not clip.get("channels") or not clip.get("samplers"):
            raise AssertionError("%s/%s is empty" % (weapon, name))
        if "inspect" in by_name and clip.get("samplers") == by_name["inspect"].get("samplers"):
            raise AssertionError("%s/%s aliases the first inspection accessors" % (weapon, name))


def main():
    check_only = "--check" in sys.argv[1:]
    args = [arg for arg in sys.argv[1:] if arg != "--check"]
    if len(args) > 2 or any(arg.startswith("--") for arg in args):
        raise SystemExit(__doc__)
    source = os.path.abspath(args[0]) if args else "/tmp/archi"
    project = os.path.abspath(args[1]) if len(args) == 2 else ROOT
    meta_file = os.path.join(project, META_PATH)
    with open(meta_file, encoding="utf-8") as handle:
        metadata = json.load(handle)
    sounds = ArchiSounds(source, project)
    changed_models = 0
    for weapon in TARGETS:
        base = _model_base(weapon)
        model_name = "v_" + base
        path = os.path.join(project, MODEL_DIR, model_name + ".glb")
        document, binary = read_glb(path)
        if check_only:
            _check_model(document, weapon)
            info = metadata.get("weapons/" + model_name, {})
            clips = info.get("inspect_clips", [])
            if not set(TARGETS[weapon].values()).issubset(set(clips)):
                raise AssertionError(model_name + " lacks inspect_clips metadata")
            print("PASS", model_name, ", ".join(sorted(TARGETS[weapon].values(), key=_inspect_sort_key)))
            continue

        rig, animations, sequences, durations, events, sources = _extract(
            weapon, find_package(source, weapon), sounds)
        old_document = copy.deepcopy(document)
        old_binary = bytes(binary)
        appended = []
        for clip in animations:
            if _append_clip(document, binary, rig, clip):
                appended.append(clip[0])
        if appended:
            if bytes(binary[:len(old_binary)]) != old_binary:
                raise AssertionError("existing binary data changed in " + model_name)
            for key in ("nodes", "meshes", "materials", "textures", "images", "skins"):
                if document.get(key) != old_document.get(key):
                    raise AssertionError("existing %s changed in %s" % (key, model_name))
            for key in ("accessors", "bufferViews"):
                if document[key][:len(old_document[key])] != old_document[key]:
                    raise AssertionError("existing %s changed in %s" % (key, model_name))
            if document["animations"][:len(old_document.get("animations", []))] != old_document.get("animations", []):
                raise AssertionError("existing animations changed in " + model_name)
            _check_model(document, weapon)
            write_glb(path, document, binary)
            verified, verified_binary = read_glb(path)
            _check_model(verified, weapon)
            if bytes(verified_binary[:len(old_binary)]) != old_binary:
                raise AssertionError("written binary prefix differs in " + model_name)
            changed_models += 1

        info = metadata["weapons/" + model_name]
        for name in sequences:
            if name not in info["sequences"]:
                info["sequences"].append(name)
        info.setdefault("seq_durations", {}).update(durations)
        info.setdefault("seq_events", {}).update(events)
        info.setdefault("inspect_sources", {}).update(sources)
        clips = [name for name in info["sequences"] if re.fullmatch(r"inspect(?:_\d+)?", name)]
        info["inspect_clips"] = sorted(set(clips), key=_inspect_sort_key)
        print(model_name, "appended" if appended else "already present",
              ", ".join(info["inspect_clips"]))
    if not check_only:
        with open(meta_file, "w", encoding="utf-8") as handle:
            json.dump(metadata, handle, indent=2, ensure_ascii=False)
            handle.write("\n")
        if sounds.unresolved:
            print("Unresolved source events:", {key: sorted(value) for key, value in sounds.unresolved.items()})
        print("Updated %d GLBs; all prior mesh/material/animation data preserved" % changed_models)


if __name__ == "__main__":
    main()
