"""Fetch fire animation and kill indicators from the existing pinned upstream tree."""
import base64
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REPO = "zh667/ScCsgoKnives"

def api(path):
    return json.loads(subprocess.check_output(["gh", "api", path]))

def main():
    pin = json.loads((ROOT / "data/polish_assets.json").read_text())["tree"]
    paths = ["src/ScCsgoKnives/Assets/Textures/ScCsgoKnives/grenade_fire_atlas.png"]
    paths += ["src/ScCsgoDeathmatch/Assets/Textures/ScCsgoDeathmatch/hud/kill_" + name + ".png"
              for name in ["headshot", "smoke", "noscope", "blind", "penetrate"]]
    tree = api(f"repos/{REPO}/git/trees/{pin}?recursive=1")
    nodes = {node["path"]: node for node in tree["tree"]}
    entries = []
    for path in paths:
        node = nodes[path]
        data = base64.b64decode(api(f"repos/{REPO}/git/blobs/{node['sha']}")["content"])
        target = ROOT / "assets/polish" / Path(path).name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        entries.append({"source": path, "git_blob": node["sha"], "target": str(target.relative_to(ROOT)),
                        "sha256": hashlib.sha256(data).hexdigest()})
    (ROOT / "data/kill_polish_assets.json").write_text(json.dumps(
        {"repository": REPO, "tree": pin, "assets": entries}, indent=2) + "\n")
    print(f"Fetched {len(entries)} pinned assets")

if __name__ == "__main__":
    main()
