#!/usr/bin/env python3
"""Append all 44 shipped gun finishes, retaining every accepted BDS finish.
Use the established nwm1-nearest-surface-v5 correspondence for legacy artwork.
Never change weapon geometry, original UVs, scopes, hardware, rigs or clips.
"""
import hashlib
import json
from pathlib import Path
import sys

from PIL import Image

from . import weapon_skin_reprojection as uv
from .refine_weapon_animations import read_glb
from .add_cs2_knives import SOURCE_COMMIT

ROOT = Path(__file__).resolve().parents[2]
ALIASES = dict(m4a1s="m4a1", usp_silencer="usp", p250="p228", mp9="tmp", ssg08="scout", hkp2000="p2000", cz75a="cz75", galilar="galil", mp5sd="mp5navy", scar20="sg550", sg556="sg552", nova="m3")
ENGLISH = dict(cu_m4a4_temukau="Temukau", cu_m4a1_howling="Howl", cu_usp_printstream="Printstream", cu_deag_printstream="Printstream", so_whiteout="Whiteout", am_emerald_marbleized_glock="Gamma Doppler Emerald", gs_famas_mecha="Mecha Industries", an_red="Hot Rod", **{"cu_p90-asiimov": "Asiimov", "cu_ssg08_dragonfire_scope": "Dragonfire", "cu_fiveseven_hyperbeast": "Hyper Beast", "gs_p2000-sport": "Turf", "gs_tec9_supercharged": "Fuel Injector", "cu_cz75_precision": "Pole Position", "cu_mac10_sakkaku": "Sakkaku", "mp7_smoking_kills_v2": "Smoking Kills", "aa_fade_ump": "Fade", "cu_bizon_Curse": "Judgement of Anubis", "cu_galil_candychaos": "Sugar Rush", "gs_mp5_neon_flektarn": "Phosphor", "cu_scar20_intervention": "Cardiac", "so_green": "Green Apple", "cu_anime_aug": "Akihabara Accept", "cu_sg553_caution": "Hazard Pay", "cu_nova_toy_soldier": "Toy Soldier", "cu_xm1014_caritas": "Tranquility", "cu_sawedoff_kisslove": "Kiss Love", "hy_geometric_steps_green": "Counter Terrace", "gs_m249_nebula_crusader": "Nebula Crusader", "gs_negev_thor": "Mjolnir", "gs_revolver_purple_elite": "Crazy 8", "sp_dry_wood": "Drift Wood", "zeus_thunder_god": "Olympus"})


def main(source):
    source = Path(source)
    textures = source / "src/ScCsgoKnives/Assets/Textures/ScCsgoKnives"
    source_catalog = json.loads((source / "tools/gun_skins_catalog.json").read_text())
    additional = json.loads((source / "src/ScCsgoKnives/AnimationData/gun_additional_skins.json").read_text())
    rows = source_catalog["skins"] + additional
    assert len(rows) == 44
    catalog_path = ROOT / "data/weapon_skins.json"
    catalog = json.loads(catalog_path.read_text())
    weapons = json.loads((ROOT / "data/weapons.json").read_text())["weapons"]
    archi = json.loads((ROOT / "data/archi_materials.json").read_text())["materials"]
    report = {"source_commit": SOURCE_COMMIT, "algorithm": uv.ALGORITHM, "finishes": []}
    mappings = {}
    for row in rows:
        asset, key = row["gun"], row["key"]
        wid = ALIASES.get(asset, asset)
        assert wid in weapons, "No game weapon for " + asset
        model_path = ROOT / ("assets/models/weapons/" + weapons[wid]["v_model"] + ".glb")
        if wid not in catalog["weapons"]:
            document, _ = read_glb(str(model_path))
            mat = next(m["name"] for m in document["materials"] if m["name"].startswith("weapon_"))
            catalog["weapons"][wid] = {"display_name": weapons[wid]["name"], "materials": [mat], "options": []}
        entry = catalog["weapons"][wid]
        adapted = row.get("displayBody", "legacy" if row.get("legacy", False) else "hd") == "legacy"
        source_file = textures / (asset + "_hd__" + key + ".png")
        image = Image.open(source_file).convert("RGB")
        mapping = None
        if adapted:
            if asset not in mappings:
                print("MAPPING", asset, flush=True)
                mappings[asset] = uv.correspondence(source, asset, size=512)
            mapping = mappings[asset]
            preserve, hardware = uv.hardware_mask(model_path, entry["materials"], size=512)
            default_path = ROOT / archi[entry["materials"][0]]["color"].removeprefix("res://")
            image = uv.reproject(image.resize((512, 512), Image.Resampling.LANCZOS), Image.open(default_path), mapping, preserve)
        relative = Path("assets/textures/weapon_skins") / wid / ("sc_" + key + ".png")
        (ROOT / relative).parent.mkdir(parents=True, exist_ok=True)
        image.save(ROOT / relative, compress_level=9)
        from .build_weapon_skins import _import_sidecar
        (ROOT / (relative.as_posix() + ".import")).write_text(_import_sidecar(relative))
        name = row.get("nameEn", ENGLISH.get(key, key))
        option = {"id": "sc_" + key, "name": entry["display_name"] + " | " + name, "finish": name, "menu_label": name + " (CS2 catalog)", "paint_kit": key, "paint_id": row["paintId"], "texture": "res://" + relative.as_posix(), "source": "zh667/ScCsgoKnives@" + SOURCE_COMMIT + "/" + source_file.name, "source_sha256": hashlib.sha256(source_file.read_bytes()).hexdigest(), "uv_layout": "legacy_to_current_hd" if adapted else "native_current_hd", "uv_algorithm": uv.ALGORITHM if adapted else "native"}
        entry["options"] = [o for o in entry["options"] if o["id"] != option["id"]] + [option]
        record = {"weapon": wid, "paint": key, "adapted": adapted, "source_sha256": option["source_sha256"]}
        if mapping is not None:
            record.update(mesh_sha256=mapping["mesh_hashes"], parts=mapping["report"], original_hardware_preserved=hardware)
        report["finishes"].append(record)
        print("SKIN", wid, name, "v5" if adapted else "native", flush=True)
    catalog["shipped_cs2_catalog"] = {"source_commit": SOURCE_COMMIT, "gun_finishes": 44, "knife_models": 22, "knife_painted_finishes": 20, "knife_factory_finishes": 22, "report": "res://data/shipped_cs2_uv_report.json", "limitations": "All shipped baked finishes, not all Valve paint kits; fixed patterns, no official wear/compositor."}
    catalog_path.write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + "\n")
    (ROOT / "data/shipped_cs2_uv_report.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main(sys.argv[1])
