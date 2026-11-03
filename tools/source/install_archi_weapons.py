#!/usr/bin/env python3
"""Install a validated build_archi_weapons output and update game weapon data.

    python -m tools.source.install_archi_weapons /tmp/archi_build /tmp/archi

Run from the repository root.  The source checkout is used only to make sure the
complete archi sound set (including #pak zoom/fire variants) is present.
"""
import copy
import json
import os
import shutil
import sys

from .build_archi_weapons import (FIRE_SOUNDS, SILENCED_SOUNDS, SOURCES, ArchiSounds,
                                  core_sound, model_base)

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

# id, template, name, slot, category, order, team, price, clip, reserve, ammo,
# damage, cycle, automatic, max speed
NEW_SPECS = {
    "p2000": dict(template="p228", name="P2000", slot=2, buy_cat=1, buy_num=7, team="CT", price=200,
                  clip_size=13, max_ammo=52, ammo_type="9mm", damage=30, cycle_time=0.15,
                  automatic=False, max_speed=250.0, armor_ratio=1.05, range_modifier=0.79,
                  recoil_up=1.8, recoil_lat=0.35, spread_base=0.009, spread_move=0.075),
    "cz75": dict(template="glock18", name="CZ75-Auto", slot=2, buy_cat=1, buy_num=8, team="ANY", price=500,
                 clip_size=12, max_ammo=12, ammo_type="9mm", damage=31, cycle_time=0.085,
                 automatic=True, max_speed=250.0, armor_ratio=1.15, range_modifier=0.80,
                 recoil_up=2.4, recoil_lat=0.65, spread_base=0.018, spread_move=0.09),
    "revolver": dict(template="deagle", name="R8 Revolver", slot=2, buy_cat=1, buy_num=9, team="ANY", price=600,
                     clip_size=8, max_ammo=8, ammo_type="50ae", damage=86, cycle_time=0.65,
                     automatic=False, max_speed=240.0, armor_ratio=1.65, range_modifier=0.92,
                     penetration=2, recoil_up=4.6, recoil_lat=0.9, spread_base=0.006, spread_move=0.12,
                     primary_delay=0.20, alt_damage=76, alt_cycle_time=0.12, alt_spread=0.065, alt_recoil=5.2,
                     prepare_sound="weapons/archi/cs2_revolver/prepare.wav"),
    "tec9": dict(template="glock18", name="Tec-9", slot=2, buy_cat=1, buy_num=10, team="T", price=500,
                 clip_size=18, max_ammo=90, ammo_type="9mm", damage=33, cycle_time=0.12,
                 automatic=False, max_speed=250.0, armor_ratio=1.15, range_modifier=0.79,
                 recoil_up=2.2, recoil_lat=0.55, spread_base=0.012, spread_move=0.085),
    "famas": dict(template="m4a1", name="FAMAS", slot=1, buy_cat=4, buy_num=9, team="CT", price=2050,
                  clip_size=25, max_ammo=90, ammo_type="556nato", damage=30, cycle_time=0.09,
                  automatic=True, max_speed=230.0, armor_ratio=1.4, range_modifier=0.96,
                  recoil_up=1.7, recoil_lat=0.5, spread_base=0.011, spread_move=0.08,
                  burst=True, burst_count=3, burst_interval=0.055, burst_cooldown=0.42),
    "galil": dict(template="ak47", name="Galil AR", slot=1, buy_cat=4, buy_num=10, team="T", price=1800,
                  clip_size=35, max_ammo=90, ammo_type="556nato", damage=30, cycle_time=0.09,
                  automatic=True, max_speed=225.0, armor_ratio=1.4, range_modifier=0.96,
                  recoil_up=1.9, recoil_lat=0.55, spread_base=0.012, spread_move=0.085),
    "m4a4": dict(template="m4a1", name="M4A4", slot=1, buy_cat=4, buy_num=11, team="CT", price=3100,
                 clip_size=30, max_ammo=90, ammo_type="556nato", damage=33, cycle_time=0.09,
                 automatic=True, max_speed=225.0, armor_ratio=1.4, range_modifier=0.97,
                 recoil_up=1.8, recoil_lat=0.5, spread_base=0.010, spread_move=0.075),
    "mag7": dict(template="xm1014", name="MAG-7", slot=1, buy_cat=2, buy_num=3, team="CT", price=1300,
                 clip_size=5, max_ammo=32, ammo_type="buckshot", damage=24, cycle_time=0.85,
                 automatic=True, max_speed=225.0, armor_ratio=1.0, range_modifier=0.72,
                 pellets=9, penetration=0, recoil_up=4.7, recoil_lat=1.1, spread_base=0.052, spread_move=0.075),
    "sawedoff": dict(template="m3", name="Sawed-Off", slot=1, buy_cat=2, buy_num=4, team="T", price=1100,
                     clip_size=7, max_ammo=32, ammo_type="buckshot", damage=22, cycle_time=0.85,
                     automatic=True, max_speed=230.0, armor_ratio=1.0, range_modifier=0.68,
                     pellets=8, penetration=0, recoil_up=5.2, recoil_lat=1.3, spread_base=0.085, spread_move=0.09,
                     shotgun_reload=True),
    "negev": dict(template="m249", name="Negev", slot=1, buy_cat=5, buy_num=2, team="ANY", price=1700,
                  clip_size=150, max_ammo=200, ammo_type="556natobox", damage=30, cycle_time=0.075,
                  automatic=True, max_speed=195.0, armor_ratio=1.5, range_modifier=0.97,
                  penetration=2, recoil_up=2.5, recoil_lat=0.9, spread_base=0.020, spread_move=0.11),
    "bizon": dict(template="ump45", name="PP-Bizon", slot=1, buy_cat=3, buy_num=6, team="ANY", price=1400,
                  clip_size=64, max_ammo=120, ammo_type="9mm", damage=27, cycle_time=0.08,
                  automatic=True, max_speed=250.0, armor_ratio=1.1, range_modifier=0.84,
                  recoil_up=1.2, recoil_lat=0.40, spread_base=0.014, spread_move=0.055),
    "mp7": dict(template="mp5navy", name="MP7", slot=1, buy_cat=3, buy_num=7, team="ANY", price=1500,
                clip_size=30, max_ammo=120, ammo_type="9mm", damage=25, cycle_time=0.08,
                automatic=True, max_speed=250.0, armor_ratio=1.15, range_modifier=0.84,
                recoil_up=1.25, recoil_lat=0.42, spread_base=0.011, spread_move=0.05),
    "taser": dict(template="deagle", name="Zeus x27", slot=4, buy_cat=9, buy_num=1, team="ANY", price=200,
                  clip_size=1, max_ammo=0, ammo_type="none", damage=200, cycle_time=1.0,
                  automatic=False, max_speed=245.0, armor_ratio=2.0, range=180.0, range_modifier=1.0,
                  penetration=0, recoil_up=0.4, recoil_lat=0.1, spread_base=0.0, spread_move=0.0),
    "decoy": dict(template="flashbang", name="Decoy Grenade", slot=4, buy_cat=8, buy_num=6, team="ANY", price=50,
                  clip_size=1, max_ammo=1, ammo_type="decoy", damage=0, cycle_time=0.8,
                  automatic=False, max_speed=245.0, grenade=True),
    "molotov": dict(template="hegrenade", name="Molotov", slot=4, buy_cat=8, buy_num=7, team="T", price=400,
                    clip_size=1, max_ammo=1, ammo_type="molotov", damage=0, cycle_time=0.8,
                    automatic=False, max_speed=245.0, grenade=True),
    "incendiary": dict(template="hegrenade", name="Incendiary Grenade", slot=4, buy_cat=8, buy_num=8, team="CT", price=600,
                       clip_size=1, max_ammo=1, ammo_type="incendiary", damage=0, cycle_time=0.8,
                       automatic=False, max_speed=245.0, grenade=True),
}


def first_event(meta, *sequences):
    events = meta.get("seq_events", {})
    for sequence in sequences:
        values = events.get(sequence, [])
        if values:
            return str(values[0].get("wav", ""))
    return ""


def copy_tree_contents(source, destination):
    if not os.path.isdir(source):
        return
    for base, _dirs, files in os.walk(source):
        for fn in files:
            src = os.path.join(base, fn)
            rel = os.path.relpath(src, source)
            dst = os.path.join(destination, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy2(src, dst)


def apply_common(spec, weapon, meta):
    base = model_base(weapon)
    spec["id"] = weapon
    spec["v_model"] = "v_" + base
    spec["p_model"] = "p_" + base
    spec["w_model"] = "w_" + base
    spec["vgui"] = "640_" + base
    spec["fire_sounds"] = [core_sound(path) for path in FIRE_SOUNDS.get(weapon, [])]
    if weapon in SILENCED_SOUNDS:
        spec["silenced_sounds"] = [core_sound(path) for path in SILENCED_SOUNDS[weapon]]
    deploy = first_event(meta, "draw", "deploy")
    if deploy:
        spec["deploy_sound"] = deploy
    elif weapon not in ("knife",):
        spec["deploy_sound"] = ""
    reload_sound = first_event(meta, "reload", "reload_unsil", "start_reload")
    if reload_sound:
        spec["reload_sound"] = reload_sound
    elif "reload_sound" in spec:
        spec["reload_sound"] = ""
    insert = first_event(meta, "insert")
    if insert:
        spec["insert_sound"] = insert
    pump = first_event(meta, "after_reload")
    if pump:
        spec["pump_sound"] = pump
    if spec.get("grenade"):
        pin = first_event(meta, "pullpin")
        if not pin:
            folder = "cs2_flashbang" if weapon == "flashbang" else ("cs2_smokegren" if weapon == "smokegrenade" else "cs2_hegren")
            pin = "weapons/archi/%s/pinpull.wav" % folder
        spec["pinpull_sound"] = pin
        spec["throw_sound"] = "weapons/archi/cs2_hegren/grenade_throw.wav"
        spec["bounce_sound"] = "weapons/archi/cs2_hegren/he_bounce-1.wav"
    if not spec.get("grenade") and weapon not in ("knife", "c4"):
        spec["dryfire_sound"] = "weapons/archi/cs2_revolver/hammer.wav"


def update_data(build_dir, generated_meta):
    path = os.path.join(REPO, "data", "weapons.json")
    with open(path) as handle:
        data = json.load(handle)
    weapons = data["weapons"]
    for weapon in SOURCES:
        if weapon not in weapons:
            continue
        meta = generated_meta["weapons/v_" + model_base(weapon)]
        apply_common(weapons[weapon], weapon, meta)

    weapons["usp"]["silencer_on_sound"] = "weapons/archi/cs2_usps/sil_on.wav"
    weapons["usp"]["silencer_off_sound"] = "weapons/archi/cs2_usps/sil_off.wav"
    weapons["m4a1"]["silencer_on_sound"] = "weapons/archi/cs2_m4a1s/sil_on.wav"
    weapons["m4a1"]["silencer_off_sound"] = "weapons/archi/cs2_m4a1s/sil_off.wav"
    weapons["knife"]["hit_sounds"] = ["weapons/archi/cs2_flashbang/hit1.wav"]
    weapons["knife"]["wall_sound"] = "weapons/archi/cs2_flashbang/hit1.wav"
    weapons["knife"]["stab_sound"] = "weapons/archi/cs2_flashbang/hit1.wav"
    weapons["knife"]["deploy_sound"] = "weapons/archi/cs2_hegren/grenade_throw.wav"
    weapons["glock18"]["burst_sound"] = "weapons/archi/core/glock18-2.wav"
    weapons["c4"]["plant_sound"] = "weapons/archi/cs2_c4/c4_initiate.wav"
    weapons["c4"]["explode_sounds"] = ["weapons/archi/core/hegrenade-1.wav"]
    weapons["c4"]["beep_sounds"] = ["weapons/archi/cs2_c4/key_press%d.wav" % i for i in range(1, 6)]
    grenade_audio = {
        "flashbang": (["weapons/archi/core/flashbang-1.wav", "weapons/archi/core/flashbang-2.wav"],
                      ["weapons/archi/cs2_flashbang/hit1.wav"]),
        "hegrenade": (["weapons/archi/core/hegrenade-1.wav", "weapons/archi/core/hegrenade-2.wav"],
                      ["weapons/archi/cs2_hegren/he_bounce-1.wav"]),
        "smokegrenade": (["weapons/archi/core/sg_explode.wav"], ["weapons/archi/cs2_flashbang/hit1.wav"]),
        "decoy": (["weapons/archi/core/sg_explode.wav"], ["weapons/archi/cs2_flashbang/hit1.wav"]),
        "molotov": (["weapons/archi/core/hegrenade-1.wav"], ["weapons/archi/cs2_hegren/he_bounce-1.wav"]),
        "incendiary": (["weapons/archi/core/hegrenade-1.wav"], ["weapons/archi/cs2_hegren/he_bounce-1.wav"]),
    }
    for weapon, sound in {
        "aug": "weapons/archi/cs2_aug/zoom_in.wav", "sg552": "weapons/archi/cs2_sg553/zoom_in.wav",
        "awp": "weapons/archi/cs2_awp/zoom_in.wav", "g3sg1": "weapons/archi/cs2_g3sg1/zoom_in.wav",
        "scout": "weapons/archi/cs2_ssg08/zoom.wav", "sg550": "weapons/archi/cs2_scar20/zoom.wav",
    }.items():
        weapons[weapon]["zoom_sound"] = sound

    for weapon, values in NEW_SPECS.items():
        template = values["template"]
        spec = copy.deepcopy(weapons[template])
        for key, value in values.items():
            if key != "template":
                spec[key] = value
        # Remove template-only mechanics that do not belong to the new weapon.
        for key in ("silencer", "silenced_sounds", "silenced_damage", "silencer_on_sound", "silencer_off_sound",
                    "zoom_fovs", "zoomed_cycle_time", "sniper_scope", "burst_sound", "burst"):
            if key not in values:
                spec.pop(key, None)
        if weapon != "sawedoff" and "shotgun_reload" not in values:
            spec.pop("shotgun_reload", None)
        meta = generated_meta["weapons/v_" + model_base(weapon)]
        apply_common(spec, weapon, meta)
        if not spec.get("grenade") and weapon != "taser":
            spec["reload_time"] = round(float(meta.get("seq_durations", {}).get("reload", spec.get("reload_time", 2.5))), 3)
        spec["description"] = "%s from the ShadowNigth/archi CS2GO weapon set." % spec["name"]
        weapons[weapon] = spec

    for weapon, (explosions, bounces) in grenade_audio.items():
        weapons[weapon]["explode_sounds"] = explosions
        weapons[weapon]["bounce_sounds"] = bounces

    # Keep the classic weapon order, then present additions in a predictable order.
    ordered = {}
    for key in list(SOURCES):
        if key in weapons:
            ordered[key] = weapons[key]
    for key, value in weapons.items():
        if key not in ordered:
            ordered[key] = value
    data["weapons"] = ordered
    with open(path, "w") as handle:
        json.dump(data, handle, indent=2)
        handle.write("\n")


def main():
    build_dir = sys.argv[1]
    archi_root = sys.argv[2] if len(sys.argv) > 2 else ""
    with open(os.path.join(build_dir, "models_meta.json")) as handle:
        generated = json.load(handle)
    expected = {"weapons/v_" + model_base(weapon) for weapon in SOURCES}
    missing = sorted(expected - set(generated))
    if missing:
        raise RuntimeError("build is missing: " + ", ".join(missing))
    if archi_root:
        # Refresh audio with package #pak variants as well as the root sound tree.
        ArchiSounds(archi_root, build_dir).install_all()

    copy_tree_contents(os.path.join(build_dir, "weapons"), os.path.join(REPO, "assets", "models", "weapons"))
    copy_tree_contents(os.path.join(build_dir, "icons"), os.path.join(REPO, "assets", "ui", "vgui"))
    copy_tree_contents(os.path.join(build_dir, "audio"), os.path.join(REPO, "assets", "sounds", "weapons", "archi"))

    meta_path = os.path.join(REPO, "data", "models_meta.json")
    with open(meta_path) as handle:
        combined = json.load(handle)
    combined.update(generated)
    with open(meta_path, "w") as handle:
        json.dump(combined, handle, indent=2)
        handle.write("\n")
    update_data(build_dir, generated)
    print("Installed", len(generated), "archi viewmodels and", len(SOURCES), "weapon slots")


if __name__ == "__main__":
    main()
