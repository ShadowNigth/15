"""Audit side mapping and handedness of production native rig corrections.

This checks numerical transforms only. A positive determinant cannot establish
which artwork looks like a palm, whether an arm is twisted, or weapon contact.
"""
import json
import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SIDE = re.compile(r"_(L|R)(?:_|$)")
TARGET_SIDE = re.compile(r"(?:_|\.)(L|R)(?:_|\.|$)")


def determinant(values):
    a, b, c, _, d, e, f, _, g, h, i, _ = values
    return a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)


def main():
    data = json.loads((ROOT / "data/native_view_rigs.json").read_text())
    totals = {"agents": 0, "gloves": 0}
    failures = []
    for kind in totals:
        for name, definition in data[kind].items():
            for model, drivers in definition.get("drivers", {}).items():
                for source, entry in drivers.items():
                    totals[kind] += 1
                    target = str(entry["target"])
                    source_side = SIDE.search(source)
                    target_side = TARGET_SIDE.search(target)
                    if source_side and (not target_side or source_side[1] != target_side[1]):
                        failures.append(f"{kind}/{name}/{model}: {source} -> {target}")
                    values = entry["correction"]
                    if len(values) != 12 or not all(math.isfinite(v) for v in values):
                        failures.append(f"{kind}/{name}/{model}/{source}: invalid transform")
                    elif determinant(values) <= 1e-6:
                        failures.append(f"{kind}/{name}/{model}/{source}: reflected or singular correction")
    for failure in failures[:30]:
        print("FAIL", failure)
    print(f"NATIVE RIG ORIENTATION: {totals['agents']} agent + {totals['gloves']} glove mappings; {len(failures)} failures")
    if not all(totals.values()) or failures:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
