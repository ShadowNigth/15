#!/usr/bin/env python3
"""Install authentic per-weapon CS2 WAVs from Source2Sounds/cs2.

    python -m tools.source.install_cs2_weapon_sounds /path/to/cs2 [project root]

The source checkout can be sparse: only the mapped files beneath
sounds/weapons/ are required.  Unlike the original archi installer, this does
not substitute another weapon's firing sample when a weapon has its own CS2
recording.  Source: https://github.com/Source2Sounds/cs2
"""
import json
import os
import shutil
import sys
import wave

SOURCE_URL = "https://github.com/Source2Sounds/cs2"

# Paths are relative to sounds/weapons/ in Source2Sounds/cs2.  CS2 calls the
# M4A4 "m4a1" and the M4A1-S unsuppressed variant "m4a1_us"; they are not
# interchangeable.  Legacy slot names remain unchanged in the game database.
FIRE_SOUNDS = {
    "knife": ["knife/knife_slash1.wav", "knife/knife_slash2.wav"],
    "usp": ["usp/usp_unsilenced_01.wav", "usp/usp_unsilenced_02.wav", "usp/usp_unsilenced_03.wav"],
    "glock18": ["glock18/glock_01.wav", "glock18/glock_02.wav"],
    "deagle": ["deagle/deagle_01.wav", "deagle/deagle_02.wav"],
    "p228": ["p250/p250_01.wav"],
    "elite": ["elite/elites_01.wav", "elite/elites_02.wav", "elite/elites_03.wav", "elite/elites_04.wav"],
    "fiveseven": ["fiveseven/fiveseven_01.wav"],
    "m3": ["nova/nova-1.wav"],
    "xm1014": ["xm1014/xm1014-1.wav"],
    "mp5navy": ["mp5/mp5_01.wav"],
    "tmp": ["mp9/mp9_01.wav", "mp9/mp9_02.wav", "mp9/mp9_03.wav", "mp9/mp9_04.wav"],
    "p90": ["p90/p90_01.wav", "p90/p90_02.wav"],
    "mac10": ["mac10/mac10_01.wav", "mac10/mac10_02.wav"],
    "ump45": ["ump45/ump45_02.wav"],
    "ak47": ["ak47/ak47_01.wav", "ak47/ak47_02.wav", "ak47/ak47_03.wav", "ak47/ak47_04.wav"],
    "sg552": ["sg556/sg556_01.wav", "sg556/sg556_02.wav", "sg556/sg556_03.wav", "sg556/sg556_04.wav"],
    "m4a1": ["m4a1/m4a1_us_01.wav", "m4a1/m4a1_us_02.wav", "m4a1/m4a1_us_03.wav", "m4a1/m4a1_us_04.wav"],
    "aug": ["aug/aug_01.wav", "aug/aug_02.wav", "aug/aug_03.wav", "aug/aug_04.wav"],
    "scout": ["ssg08/ssg08_01.wav"],
    "awp": ["awp/awp_01.wav", "awp/awp_02.wav"],
    "g3sg1": ["g3sg1/g3sg1_01.wav", "g3sg1/g3sg1_02.wav", "g3sg1/g3sg1_03.wav"],
    "sg550": ["scar20/scar20_01.wav", "scar20/scar20_02.wav", "scar20/scar20_03.wav"],
    "m249": ["m249/m249_01.wav", "m249/m249_02.wav", "m249/m249_03.wav"],
    "p2000": ["hkp2000/hkp2000_01.wav", "hkp2000/hkp2000_02.wav", "hkp2000/hkp2000_03.wav"],
    "cz75": ["cz75a/cz75_01.wav", "cz75a/cz75_02.wav", "cz75a/cz75_03.wav"],
    "revolver": ["revolver/revolver-1_01.wav"],
    "tec9": ["tec9/tec9_02.wav"],
    "famas": ["famas/famas_01.wav", "famas/famas_02.wav", "famas/famas_03.wav"],
    "galil": ["galilar/galil_01.wav", "galilar/galil_02.wav", "galilar/galil_03.wav", "galilar/galil_04.wav"],
    "m4a4": ["m4a1/m4a1_01.wav", "m4a1/m4a1_02.wav", "m4a1/m4a1_03.wav", "m4a1/m4a1_04.wav"],
    "mag7": ["mag7/mag7_01.wav", "mag7/mag7_02.wav"],
    "sawedoff": ["sawedoff/sawedoff-1.wav"],
    "negev": ["negev/negev_01.wav", "negev/negev_02.wav"],
    "bizon": ["bizon/bizon_01.wav", "bizon/bizon_02.wav"],
    "mp7": ["mp7/mp7_01.wav", "mp7/mp7_02.wav", "mp7/mp7_03.wav", "mp7/mp7_04.wav"],
    "taser": ["taser/taser_shoot.wav"],
}

SILENCED_SOUNDS = {
    "usp": ["usp/usp_01.wav", "usp/usp_02.wav", "usp/usp_03.wav"],
    "m4a1": ["m4a1/m4a1_silencer_01.wav"],
}

# Non-fire placeholders that were demonstrably assigned from another weapon.
SPECIAL_SOUNDS = {
    "knife": {
        "hit_sounds": ["knife/knife_hit1.wav", "knife/knife_hit2.wav"],
        "stab_sound": "knife/knife_stab.wav",
    },
    "glock18": {"burst_sound": "glock18/glock_02.wav"},
    "molotov": {
        "deploy_sound": "molotov/molotov_draw.wav",
        "pinpull_sound": "molotov/molotov_draw.wav",
        "throw_sound": "molotov/grenade_throw.wav",
        "explode_sounds": [
            "molotov/molotov_detonate_1.wav",
            "molotov/molotov_detonate_2.wav",
            "molotov/molotov_detonate_3.wav",
        ],
    },
    "incendiary": {
        "deploy_sound": "incgrenade/inc_grenade_draw.wav",
        "throw_sound": "incgrenade/inc_grenade_throw.wav",
        "pinpull_sound": "incgrenade/pinpull_start.wav",
        "explode_sounds": [
            "incgrenade/inc_grenade_detonate_1.wav",
            "incgrenade/inc_grenade_detonate_2.wav",
            "incgrenade/inc_grenade_detonate_3.wav",
        ],
    },
}

# Animation foley absent from archi. MP3 sources are decoded to mono/stereo
# 44.1 kHz signed PCM16 WAV at install time (the miniaudio build dependency).
FOLEY_SOUNDS = [
    "m4a1/m4a1_clipin.mp3",
    "m4a1/m4a1_clipout.mp3",
    "m4a1/m4a1_cliphit.wav",
    "m4a1/m4a1_draw.mp3",
    "m4a1/m4a1_boltback.mp3",
    "m4a1/m4a1_boltforward.mp3",
    "cz75a/cz75_clipin_01.mp3",
    "tec9/tec9_clipin.mp3",
    "tec9/tec9_clipout.wav",
    "tec9/tec9_draw.mp3",
    "tec9/tec9_boltpull.wav",
    "tec9/tec9_boltrelease.wav",
    "mag7/mag7_clipin.mp3",
    "mag7/mag7_clipout.wav",
    "mag7/mag7_draw.mp3",
    "mag7/mag7_pump_back.mp3",
    "mag7/mag7_pump_forward.wav",
    "bizon/bizon_clipin.mp3",
    "bizon/bizon_clipout.wav",
    "bizon/bizon_draw.wav",
    "bizon/bizon_boltback.wav",
    "bizon/bizon_boltforward.wav",
    "decoy/decoy_draw.wav",
    "decoy/pinpull_start.wav",
    "decoy/pinpull.wav",
    "incgrenade/pinpull.wav",
]

# Values below are installed WAV paths relative to sounds/weapons/. Only
# semantically equivalent events are replaced. In particular CZ75 keeps its
# other legacy events because Source2Sounds does not provide dedicated takes.
FOLEY_FIELDS = {
    "m4a4": {
        "reload_sound": "m4a1/m4a1_clipin.wav",
        "deploy_sound": "m4a1/m4a1_draw.wav",
    },
    "cz75": {"reload_sound": "cz75a/cz75_clipin_01.wav"},
    "tec9": {
        "reload_sound": "tec9/tec9_clipin.wav",
        "deploy_sound": "tec9/tec9_draw.wav",
    },
    "mag7": {
        "reload_sound": "mag7/mag7_clipin.wav",
        "deploy_sound": "mag7/mag7_draw.wav",
    },
    "bizon": {
        "reload_sound": "bizon/bizon_clipin.wav",
        "deploy_sound": "bizon/bizon_draw.wav",
    },
    "decoy": {
        "deploy_sound": "decoy/decoy_draw.wav",
        "pinpull_sound": "decoy/pinpull_start.wav",
    },
}

FOLEY_EVENTS = {
    "weapons/v_m4a4": {
        "clipout.wav": "m4a1/m4a1_clipout.wav",
        "clipin.wav": "m4a1/m4a1_clipin.wav",
        "cliphit.wav": "m4a1/m4a1_cliphit.wav",
        "draw.wav": "m4a1/m4a1_draw.wav",
        "boltback.wav": "m4a1/m4a1_boltback.wav",
        "boltforward.wav": "m4a1/m4a1_boltforward.wav",
    },
    "weapons/v_cz75": {"clipin.wav": "cz75a/cz75_clipin_01.wav"},
    "weapons/v_tec9": {
        "clipout.wav": "tec9/tec9_clipout.wav",
        "clipin.wav": "tec9/tec9_clipin.wav",
        "draw.wav": "tec9/tec9_draw.wav",
        "boltback.wav": "tec9/tec9_boltpull.wav",
        "boltforward.wav": "tec9/tec9_boltrelease.wav",
    },
    "weapons/v_mag7": {
        "clipout.wav": "mag7/mag7_clipout.wav",
        "clipin.wav": "mag7/mag7_clipin.wav",
        "draw.wav": "mag7/mag7_draw.wav",
        "boltback.wav": "mag7/mag7_pump_back.wav",
        "boltforward.wav": "mag7/mag7_pump_forward.wav",
    },
    "weapons/v_bizon": {
        "clipout.wav": "bizon/bizon_clipout.wav",
        "clipin.wav": "bizon/bizon_clipin.wav",
        "draw.wav": "bizon/bizon_draw.wav",
        "boltback.wav": "bizon/bizon_boltback.wav",
        "boltforward.wav": "bizon/bizon_boltforward.wav",
    },
    "weapons/v_decoy": {
        "he_draw.wav": "decoy/decoy_draw.wav",
        "pinpull_start.wav": "decoy/pinpull_start.wav",
        "pinpull.wav": "decoy/pinpull.wav",
    },
    "weapons/v_molotov": {"he_draw.wav": "molotov/molotov_draw.wav"},
    "weapons/v_incendiary": {
        "he_draw.wav": "incgrenade/inc_grenade_draw.wav",
        "pinpull_start.wav": "incgrenade/pinpull_start.wav",
        "pinpull.wav": "incgrenade/pinpull.wav",
    },
}


def destination(relative):
    return "weapons/cs2/" + relative


def validate_wav(path):
    with wave.open(path, "rb") as handle:
        if handle.getnchannels() not in (1, 2) or handle.getframerate() < 8000:
            raise ValueError("unsupported WAV format: " + path)
        return handle.getsampwidth(), handle.getnchannels(), handle.getframerate(), handle.getnframes()


def foley_wav_path(relative):
    return os.path.splitext(relative)[0] + ".wav"


def decode_mp3_to_wav(source, destination_path):
    try:
        import miniaudio
    except ImportError as exc:
        raise RuntimeError("MP3 foley conversion requires: pip install miniaudio") from exc
    decoded = miniaudio.decode_file(
        source,
        output_format=miniaudio.SampleFormat.SIGNED16,
        nchannels=2,
        sample_rate=44100,
    )
    with wave.open(destination_path, "wb") as handle:
        handle.setnchannels(2)
        handle.setsampwidth(2)
        handle.setframerate(44100)
        handle.writeframes(decoded.samples)


def main():
    if len(sys.argv) not in (2, 3):
        raise SystemExit(__doc__)
    source = os.path.abspath(sys.argv[1])
    project = os.path.abspath(sys.argv[2] if len(sys.argv) == 3 else
                              os.path.join(os.path.dirname(__file__), "../.."))
    source_root = os.path.join(source, "sounds", "weapons")
    database_path = os.path.join(project, "data", "weapons.json")
    with open(database_path, encoding="utf-8") as handle:
        database = json.load(handle)
    weapons = database["weapons"]
    expected = {key for key, spec in weapons.items() if spec.get("fire_sounds")}
    if expected != set(FIRE_SOUNDS):
        raise AssertionError("fire-sound map does not cover the roster: %s" % sorted(expected ^ set(FIRE_SOUNDS)))

    assignments = {}
    for weapon, paths in FIRE_SOUNDS.items():
        assignments.setdefault(weapon, {})["fire_sounds"] = paths
    for weapon, paths in SILENCED_SOUNDS.items():
        assignments.setdefault(weapon, {})["silenced_sounds"] = paths
    for weapon, fields in SPECIAL_SOUNDS.items():
        for field, value in fields.items():
            assignments.setdefault(weapon, {})[field] = value

    required = sorted({path for fields in assignments.values() for value in fields.values()
                       for path in (value if isinstance(value, list) else [value])})
    formats = {}
    for relative in required:
        path = os.path.join(source_root, relative)
        if not os.path.isfile(path):
            raise FileNotFoundError(path)
        formats[relative] = validate_wav(path)
    for relative in FOLEY_SOUNDS:
        path = os.path.join(source_root, relative)
        if not os.path.isfile(path):
            raise FileNotFoundError(path)
        if relative.endswith(".wav"):
            formats[relative] = validate_wav(path)

    # No firing sample may be shared by two different weapon IDs.  Variants of
    # the silenced/unsuppressed state of one weapon are handled separately.
    owners = {}
    for weapon, paths in FIRE_SOUNDS.items():
        for relative in paths:
            if relative in owners:
                raise AssertionError("shared fire sample %s: %s / %s" % (relative, owners[relative], weapon))
            owners[relative] = weapon

    installed = set(required)
    for relative in required:
        src = os.path.join(source_root, relative)
        dst = os.path.join(project, "assets", "sounds", destination(relative))
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(src, dst)
    for source_relative in FOLEY_SOUNDS:
        relative = foley_wav_path(source_relative)
        src = os.path.join(source_root, source_relative)
        dst = os.path.join(project, "assets", "sounds", destination(relative))
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        if source_relative.endswith(".mp3"):
            decode_mp3_to_wav(src, dst)
        else:
            shutil.copy2(src, dst)
        formats[relative] = validate_wav(dst)
        installed.add(relative)

    for weapon, fields in assignments.items():
        for field, value in fields.items():
            weapons[weapon][field] = ([destination(path) for path in value]
                                      if isinstance(value, list) else destination(value))
    for weapon, fields in FOLEY_FIELDS.items():
        for field, value in fields.items():
            weapons[weapon][field] = destination(value)
    # This existing recording is a real knife-on-wall impact, replacing the
    # old flashbang placeholder without confusing it with flesh hit sounds.
    weapons["knife"]["wall_sound"] = "weapons/knife_hitwall1.wav"

    with open(database_path, "w", encoding="utf-8") as handle:
        json.dump(database, handle, indent=2, ensure_ascii=False)
        handle.write("\n")

    metadata_path = os.path.join(project, "data", "models_meta.json")
    with open(metadata_path, encoding="utf-8") as handle:
        metadata = json.load(handle)
    foley_changes = 0
    for model, replacements in FOLEY_EVENTS.items():
        for events in metadata[model].get("seq_events", {}).values():
            for event in events:
                suffix = event["wav"].rsplit("/", 1)[-1]
                if suffix in replacements:
                    updated = destination(replacements[suffix])
                    if event["wav"] != updated:
                        event["wav"] = updated
                        foley_changes += 1
    if foley_changes:
        with open(metadata_path, "w", encoding="utf-8") as handle:
            json.dump(metadata, handle, indent=2, ensure_ascii=False)
            handle.write("\n")

    widths = sorted({value[0] for value in formats.values()})
    print("Installed %d authentic CS2 WAVs for %d weapons; PCM sample widths: %s bytes" %
          (len(installed), len(FIRE_SOUNDS), widths))
    print("Updated %d animation foley events with dedicated CS2 recordings" % foley_changes)
    print("M4A4=m4a1_01..04; M4A1-S unsuppressed=m4a1_us_01..04 (distinct)")
    print("Source: " + SOURCE_URL)


if __name__ == "__main__":
    main()
