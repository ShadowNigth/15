#!/usr/bin/env python3
"""Restore normal world sizes, or optionally apply the experimental calibration.

    python -m tools.source.calibrate_weapon_world_scale [project root]
    python -m tools.source.calibrate_weapon_world_scale --calibrate [project root]

Normal presentation is 1.0 for firearms/tools and 0.90 for grenades. The older
length-fitting pass remains available only behind --calibrate; it is not the
accepted default because it made the third-person weapons too small. The source
GLBs are deliberately not rewritten. Held, dropped, thrown and planted models
share the resulting value, so pickups never change size abruptly.
"""
import json
import os
import struct
import sys

# Approximate overall real-world lengths in metres, used as visual calibration
# targets against the 1.8 m GoldSrc player silhouettes.  The MP7 is already
# correctly sized and remains at 1.0.  Grenades retain the previously accepted
# shared 0.90 scale.  These values affect presentation, never weapon mechanics.
TARGET_LENGTHS = {
    "knife": 0.32,
    "usp": 0.32,  # includes the suppressor
    "glock18": 0.204,
    "deagle": 0.273,
    "p228": 0.188,  # the installed model is a P250
    "elite": 0.217,
    "fiveseven": 0.208,
    "m3": 0.90,  # the installed model is a Nova
    "xm1014": 0.889,
    "mp5navy": 0.68,
    "tmp": 0.52,  # the installed model is an MP9
    "p90": 0.50,
    "mac10": 0.269,
    "ump45": 0.454,
    "ak47": 0.88,
    "sg552": 0.73,  # the installed model is an SG 556
    "m4a1": 0.84,
    "aug": 0.79,
    "scout": 1.00,  # the installed model is an SSG 08
    "awp": 1.12,
    "g3sg1": 1.025,
    "sg550": 0.998,  # the installed model is a SCAR-20
    "m249": 1.04,
    "c4": 0.28,
    "p2000": 0.18,
    "cz75": 0.206,
    "revolver": 0.29,
    "tec9": 0.27,
    "famas": 0.757,
    "galil": 0.98,
    "m4a4": 0.84,
    "mag7": 0.552,
    "sawedoff": 0.635,
    "negev": 1.02,
    "bizon": 0.66,
    "taser": 0.19,
}
FIXED_SCALE = {"mp7": 1.0}
GRENADE_SCALE = 0.90


def glb_bounds(path):
    with open(path, "rb") as handle:
        raw = handle.read()
    if raw[:4] != b"glTF":
        raise ValueError("not a GLB: " + path)
    json_length = struct.unpack_from("<I", raw, 12)[0]
    document = json.loads(raw[20:20 + json_length])
    lower = [float("inf")] * 3
    upper = [float("-inf")] * 3
    for mesh in document.get("meshes", []):
        for primitive in mesh["primitives"]:
            accessor = document["accessors"][primitive["attributes"]["POSITION"]]
            for axis in range(3):
                lower[axis] = min(lower[axis], accessor["min"][axis])
                upper[axis] = max(upper[axis], accessor["max"][axis])
    if not all(value < float("inf") for value in lower):
        raise ValueError("model has no positions: " + path)
    return [upper[axis] - lower[axis] for axis in range(3)]


def main():
    calibrate = "--calibrate" in sys.argv[1:]
    arguments = [arg for arg in sys.argv[1:] if arg != "--calibrate"]
    if len(arguments) > 1 or any(arg.startswith("--") for arg in arguments):
        raise SystemExit(__doc__)
    project = os.path.abspath(arguments[0] if arguments else
                              os.path.join(os.path.dirname(__file__), "../.."))
    path = os.path.join(project, "data", "weapons.json")
    with open(path, encoding="utf-8") as handle:
        database = json.load(handle)
    weapons = database["weapons"]
    if not calibrate:
        for spec in weapons.values():
            spec["world_scale"] = GRENADE_SCALE if spec.get("grenade", False) else 1.0
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(database, handle, indent=2, ensure_ascii=False)
            handle.write("\n")
        print("Restored normal world scale for %d weapons; grenades remain %.2f" %
              (len(weapons), GRENADE_SCALE))
        return

    grenades = {key for key, spec in weapons.items() if spec.get("grenade", False)}
    expected = set(weapons) - grenades - set(FIXED_SCALE)
    if expected != set(TARGET_LENGTHS):
        raise AssertionError("scale map does not cover roster: %s" % sorted(expected ^ set(TARGET_LENGTHS)))

    report = []
    for weapon, spec in weapons.items():
        if weapon in grenades:
            scale = GRENADE_SCALE
            original = 0.0
        elif weapon in FIXED_SCALE:
            scale = FIXED_SCALE[weapon]
            original = 0.0
        else:
            model = os.path.join(project, "assets", "models", "weapons", spec["p_model"] + ".glb")
            dimensions = glb_bounds(model)
            original = max(dimensions)
            if original < 0.01:
                raise ValueError("invalid source dimensions for " + weapon)
            # Do not enlarge a model that is already consistent with the player.
            scale = min(1.0, TARGET_LENGTHS[weapon] / original)
        scale = round(scale, 3)
        if not 0.45 <= scale <= 1.0:
            raise ValueError("implausible scale for %s: %.3f" % (weapon, scale))
        spec["world_scale"] = scale
        report.append((weapon, scale, original * scale if original else 0.0))

    with open(path, "w", encoding="utf-8") as handle:
        json.dump(database, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    for weapon, scale, calibrated in report:
        suffix = " -> %.3f m" % calibrated if calibrated else ""
        print("%-13s %.3f%s" % (weapon, scale, suffix))
    print("Calibrated %d held/dropped weapon presentations; grenades remain %.2f" %
          (len(report), GRENADE_SCALE))


if __name__ == "__main__":
    main()
