#!/usr/bin/env python3
"""Install the curated authentic CS weapon-finish UV maps.

    python -m tools.source.build_weapon_skins /tmp/cs16-skin-inventory /home/user/15
    python -m tools.source.build_weapon_skins --check /tmp/cs16-skin-inventory /home/user/15

Source: ellingtoncody81-ctrl/cs16-skin-inventory, cstrike/CSGO Texture Pack.
The pack credits Valve and the CS:GO Ports/BDS porters. Its MIT license covers
only the repository's own source code, not these game assets; retain the source
and attribution in data/weapon_skins.json and tools/source/README.md.

Only six identifiable, authentic finishes per supported weapon are curated.
Custom recolours, cross-weapon artwork and numerically named files that cannot
be identified reliably are deliberately excluded. PNG conversion is lossless:
geometry, UVs, normals, animations and the original HD default are not rebuilt.
"""
import hashlib
import io
import json
import subprocess
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCE_COMMIT = "1cabb2dea3d2bda05cac1d6977abf2c9cc65d0de"
PACK_REL = Path("cstrike/CSGO Texture Pack")
OUT_REL = Path("assets/textures/weapon_skins")
CATALOG_REL = Path("data/weapon_skins.json")

# weapon id, display name, Source material names, pack folder, six finishes.
WEAPONS = [
    ("ak47", "AK-47", ["weapon_rif_ak47"], "AK-47", [
        ("redline", "Redline", "redline.bmp"),
        ("asiimov", "Asiimov", "assimov.bmp"),
        ("vulcan", "Vulcan", "vulcan.bmp"),
        ("bloodsport", "Bloodsport", "bloodsport.bmp"),
        ("fire_serpent", "Fire Serpent", "fireserpent.bmp"),
        ("case_hardened", "Case Hardened", "casehardened.bmp"),
    ]),
    ("aug", "AUG", ["weapon_rif_aug", "aug_mag_opaque"], "AUG", [
        ("akihabara_accept", "Akihabara Accept", "akihabara accept.bmp"),
        ("chameleon", "Chameleon", "chameleon.bmp"),
        ("momentum", "Momentum", "momentum.bmp"),
        ("ricochet", "Ricochet", "ricochet.bmp"),
        ("syd_mead", "Syd Mead", "syd mead.bmp"),
        ("torque", "Torque", "torque.bmp"),
    ]),
    ("awp", "AWP", ["weapon_snip_awp"], "AWP", [
        ("asiimov", "Asiimov", "asiimov2.bmp"),
        ("dragon_lore", "Dragon Lore", "dragonlore1.bmp"),
        ("hyper_beast", "Hyper Beast", "hyperbeast.bmp"),
        ("medusa", "Medusa", "medusa.bmp"),
        ("oni_taiji", "Oni Taiji", "Oni Taiji.bmp"),
        ("lightning_strike", "Lightning Strike", "lightingstrike.bmp"),
    ]),
    ("deagle", "Desert Eagle", ["weapon_pist_deagle"], "Desert Eagle", [
        ("kumicho_dragon", "Kumicho Dragon", "kumichodragon.bmp"),
        ("mecha_industries", "Mecha Industries", "mechaindustries.bmp"),
        ("midnight_storm", "Midnight Storm", "midnightstorm.bmp"),
        ("naga", "Naga", "naga.bmp"),
        ("oxide_blaze", "Oxide Blaze", "oxideblaze.bmp"),
        ("heirloom", "Heirloom", "heirloom.bmp"),
    ]),
    ("elite", "Dual Berettas", ["weapon_pist_elite"], "Dual Elites", [
        ("cobra_strike", "Cobra Strike", "Cobra Strike.bmp"),
        ("dualing_dragons", "Dualing Dragons", "dualing dragons.bmp"),
        ("hemoglobin", "Hemoglobin", "hemoglobin.bmp"),
        ("marina", "Marina", "marina.bmp"),
        ("panther", "Panther", "panther.bmp"),
        ("royal_consorts", "Royal Consorts", "royal consorts.bmp"),
    ]),
    ("famas", "FAMAS", ["weapon_rif_famas"], "FAMAS", [
        ("djinn", "Djinn", "Djinn.bmp"),
        ("afterimage", "Afterimage", "afterimage.bmp"),
        ("eye_of_athena", "Eye of Athena", "eye of athena.bmp"),
        ("mecha_industries", "Mecha Industries", "mecha industries.bmp"),
        ("neural_net", "Neural Net", "neural net.bmp"),
        ("roll_cage", "Roll Cage", "roll cage.bmp"),
    ]),
    ("fiveseven", "Five-SeveN", ["weapon_pist_fiveseven"], "Fiveseven", [
        ("capillary", "Capillary", "Capillary.bmp"),
        ("fowl_play", "Fowl Play", "fowl_play.bmp"),
        ("hyper_beast", "Hyper Beast", "hyperbeast.bmp"),
        ("kami", "Kami", "kami.bmp"),
        ("monkey_business", "Monkey Business", "monkey_business.bmp"),
        ("triumvirate", "Triumvirate", "triumvirate.bmp"),
    ]),
    ("g3sg1", "G3SG1", ["weapon_snip_g3sg1"], "G3SG1", [
        ("chronos", "Chronos", "chronos.bmp"),
        ("demeter", "Demeter", "demeter.bmp"),
        ("dream_glade", "Dream Glade", "dream glade.bmp"),
        ("flux", "Flux", "flux.bmp"),
        ("high_seas", "High Seas", "high seas.bmp"),
        ("the_executioner", "The Executioner", "the executioner.bmp"),
    ]),
    ("galil", "Galil AR", ["weapon_rif_galilar"], "Galil", [
        ("cerberus", "Cerberus", "cerberus.bmp"),
        ("chatterbox", "Chatterbox", "chatterbox.bmp"),
        ("chromatic_aberration", "Chromatic Aberration", "chromatic aberration.bmp"),
        ("eco", "Eco", "eco.bmp"),
        ("firefight", "Firefight", "firefight.bmp"),
        ("rocket_pop", "Rocket Pop", "rocket pop.bmp"),
    ]),
    ("glock18", "Glock-18", ["weapon_pist_glock"], "Glock 18", [
        ("water_elemental", "Water Elemental", "waterelemental.bmp"),
        ("wasteland_rebel", "Wasteland Rebel", "wastelandrebel.bmp"),
        ("dragon_tattoo", "Dragon Tattoo", "dragon tattoo.bmp"),
        ("off_world", "Off World", "off world.bmp"),
        ("royal_legion", "Royal Legion", "royallegion.bmp"),
        ("bunsen_burner", "Bunsen Burner", "bunsenburner.bmp"),
    ]),
    ("m249", "M249", ["weapon_mach_m249"], "M249", [
        ("nebula_crusader", "Nebula Crusader", "nebula_crusader.bmp"),
        ("system_lock", "System Lock", "system lock.bmp"),
        ("deep_relief", "Deep Relief", "deep relief.bmp"),
        ("downtown", "Downtown", "downtown.bmp"),
        ("shipping_forecast", "Shipping Forecast", "shipping forecast.bmp"),
        ("spectre", "Spectre", "spectre.bmp"),
    ]),
    ("m4a1", "M4A1-S", ["weapon_rif_m4a1_silencer"], "M4A1-s", [
        ("hyper_beast", "Hyper Beast", "hyperbeast.bmp"),
        ("cyrex", "Cyrex", "cyrex.bmp"),
        ("decimator", "Decimator", "decimator.bmp"),
        ("golden_coil", "Golden Coil", "golden_coil.bmp"),
        ("master_piece", "Master Piece", "masterpiece.bmp"),
        ("mecha_industries", "Mecha Industries", "mecha_industries.bmp"),
    ]),
    ("mac10", "MAC-10", ["weapon_smg_mac10"], "MAC10", [
        ("carnivore", "Carnivore", "carnivore.bmp"),
        ("curse", "Curse", "curse.bmp"),
        ("graven", "Graven", "graven.bmp"),
        ("rangeen", "Rangeen", "rangeen.bmp"),
        ("tatter", "Tatter", "tatter.bmp"),
        ("ultraviolet", "Ultraviolet", "ultraviolet.bmp"),
    ]),
    ("mp7", "MP7", ["weapon_smg_mp7"], "MP7", [
        ("nemesis", "Nemesis", "nemesis.bmp"),
        ("cirrus", "Cirrus", "cirrus.bmp"),
        ("ocean_foam", "Ocean Foam", "oceamfoam.bmp"),
        ("skulls", "Skulls", "skulls.bmp"),
        ("special_delivery", "Special Delivery", "specialdelivery.bmp"),
        ("whiteout", "Whiteout", "whiteout.bmp"),
    ]),
    ("tmp", "MP9", ["weapon_smg_mp9"], "MP9", [
        ("airlock", "Airlock", "airlock.bmp"),
        ("bulldozer", "Bulldozer", "bulldozer.bmp"),
        ("deadly_poison", "Deadly Poison", "deadlypoison.bmp"),
        ("hot_rod", "Hot Rod", "hotrod.bmp"),
        ("ruby_poison_dart", "Ruby Poison Dart", "rubypoison.bmp"),
        ("dart", "Dart", "dart.bmp"),
    ]),
    ("m3", "Nova", ["weapon_shot_nova"], "Nova", [
        ("hyper_beast", "Hyper Beast", "hyper beast.bmp"),
        ("antique", "Antique", "antique.bmp"),
        ("bloomstick", "Bloomstick", "bloomstick.bmp"),
        ("koi", "Koi", "koi.bmp"),
        ("rising_skull", "Rising Skull", "rising skull.bmp"),
        ("tempest", "Tempest", "tempest.bmp"),
    ]),
    ("p228", "P250", ["weapon_pist_p250"], "P250", [
        ("asiimov", "Asiimov", "assimov.bmp"),
        ("cartel", "Cartel", "cartel.bmp"),
        ("franklin", "Franklin", "franklin.bmp"),
        ("mehndi", "Mehndi", "mehndi.bmp"),
        ("muertos", "Muertos", "muertos.bmp"),
        ("see_ya_later", "See Ya Later", "see ya later.bmp"),
    ]),
    ("p90", "P90", ["weapon_smg_p90", "mag_inside"], "P90", [
        ("asiimov", "Asiimov", "assimov.bmp"),
        ("death_by_kitty", "Death by Kitty", "deathbykitty.bmp"),
        ("emerald_dragon", "Emerald Dragon", "emeralddragon.bmp"),
        ("shallow_grave", "Shallow Grave", "shallowgrave.bmp"),
        ("shapewood", "Shapewood", "shapewood.bmp"),
        ("trigon", "Trigon", "trigon.bmp"),
    ]),
    ("sg550", "SCAR-20", ["weapon_snip_scar20"], "SG550", [
        ("bloodsport", "Bloodsport", "bloodsport.bmp"),
        ("cardiac", "Cardiac", "cardiac.bmp"),
        ("cyrex", "Cyrex", "cyrex.bmp"),
        ("emerald", "Emerald", "emerald.bmp"),
        ("outbreak", "Outbreak", "outbreak.bmp"),
        ("powercore", "Powercore", "powercore.bmp"),
    ]),
    ("usp", "USP-S", ["weapon_pist_usp_silencer"], "USP-S", [
        ("kill_confirmed", "Kill Confirmed", "kill_confirmed.bmp"),
        ("neo_noir", "Neo-Noir", "Neo-Noir.bmp"),
        ("blueprint", "Blueprint", "blueprint.bmp"),
        ("caiman", "Caiman", "caiman.bmp"),
        ("guardian", "Guardian", "guardian.bmp"),
        ("lead_conduit", "Lead Conduit", "leadconcuit.bmp"),
    ]),
]


# Reviewed against SteamDatabase/GameTracking-CS2 items_game.txt and
# csgo_english.txt at 1a3016b053eb006daaf741396f0d0416388519ca.
PAINT_KITS = {
    'ak47': {
        'asiimov': 'cu_ak47_asiimov',
        'bloodsport': 'gs_ak47_bloodsport',
        'case_hardened': 'aq_oiled',
        'fire_serpent': 'cu_fireserpent_ak47_bravo',
        'redline': 'cu_ak47_cobra',
        'vulcan': 'cu_ak47_rubber',
    },
    'aug': {
        'akihabara_accept': 'cu_anime_aug',
        'chameleon': 'cu_aug_chameleonaire',
        'momentum': 'cu_aug_momentum',
        'ricochet': 'am_aug_jumble',
        'syd_mead': 'gs_aug_syd_mead',
        'torque': 'cu_aug_progressiv',
    },
    'awp': {
        'asiimov': 'cu_awp_asimov',
        'dragon_lore': 'cu_medieval_dragon_awp',
        'hyper_beast': 'cu_awp_hyper_beast',
        'lightning_strike': 'am_lightning_awp',
        'medusa': 'cu_medusa_awp',
        'oni_taiji': 'cu_awp_hannya',
    },
    'deagle': {
        'heirloom': 'aq_engraved_deagle',
        'kumicho_dragon': 'aq_deserteagle_kumichodragon',
        'mecha_industries': 'gs_deagle_mecha',
        'midnight_storm': 'am_seastorm',
        'naga': 'aq_deagle_naga',
        'oxide_blaze': 'cu_desert_eagle_corroden',
    },
    'elite': {
        'cobra_strike': 'gs_dualberettas_cobra',
        'dualing_dragons': 'cu_dualberretta_dragons',
        'hemoglobin': 'am_ossify_red',
        'marina': 'hy_marina_sunrise',
        'panther': 'so_panther',
        'royal_consorts': 'gs_dual_berettas_golden_venice',
    },
    'famas': {
        'afterimage': 'cu_broken_path_famas',
        'djinn': 'aq_famas_jinn',
        'eye_of_athena': 'cu_famas_owl_orange',
        'mecha_industries': 'gs_famas_mecha',
        'neural_net': 'am_famas_dots',
        'roll_cage': 'gs_famas_rally',
    },
    'fiveseven': {
        'capillary': 'cu_fiveseven_vein',
        'fowl_play': 'aq_57_feathers',
        'hyper_beast': 'cu_fiveseven_hyperbeast',
        'kami': 'hy_kami',
        'monkey_business': 'cu_fiveseven_banana',
        'triumvirate': 'cu_fiveseven_augmented',
    },
    'g3sg1': {
        'chronos': 'cu_chronos_g3sg1',
        'demeter': 'hy_bluepolygon_bravo',
        'dream_glade': 'cu_g3sg1_glade',
        'flux': 'gs_g3sg1_flux_purple',
        'high_seas': 'gs_g3sg1_buccaneer',
        'the_executioner': 'cu_g3sg1_executioner',
    },
    'galil': {
        'cerberus': 'cu_cerbrus_galil',
        'chatterbox': 'cu_galil_abrasion',
        'chromatic_aberration': 'cu_galil_chroma_pink',
        'eco': 'cu_galil_eco',
        'firefight': 'gs_galilar_incenerator',
        'rocket_pop': 'cu_galilar_particles',
    },
    'glock18': {
        'bunsen_burner': 'aq_glock18_flames_blue',
        'dragon_tattoo': 'am_dragon_glock',
        'off_world': 'cu_glock_indigo',
        'royal_legion': 'gs_glock18_award',
        'wasteland_rebel': 'cu_glock_wasteland_rebel',
        'water_elemental': 'cu_glock-liquescent',
    },
    'm249': {
        'deep_relief': 'cu_m249_deep_relief',
        'downtown': 'cu_m249_downvote',
        'nebula_crusader': 'gs_m249_nebula_crusader',
        'shipping_forecast': 'hy_zodiac3',
        'spectre': 'cu_m249_spectre',
        'system_lock': 'cu_m249_sektor',
    },
    'm3': {
        'antique': 'cu_nova_antique',
        'bloomstick': 'cu_spring_nova',
        'hyper_beast': 'cu_nova_hyperbeast',
        'koi': 'cu_nova_koi',
        'rising_skull': 'cu_skull_nova',
        'tempest': 'hy_seaside_bravo',
    },
    'm4a1': {
        'cyrex': 'cu_m4a1s_cyrex',
        'decimator': 'gs_m4a1_decimator',
        'golden_coil': 'gs_m4a1s_snakebite_gold',
        'hyper_beast': 'cu_m4a1_hyper_beast',
        'master_piece': 'cu_m4a1-s_silence',
        'mecha_industries': 'gs_m4a1_mecha_industries',
    },
    'mac10': {
        'carnivore': 'aq_mac_10_alien_camo',
        'curse': 'cu_mac10_decay',
        'graven': 'aq_etched_mac10_bravo',
        'rangeen': 'cu_mac10_alekhya_duo',
        'tatter': 'cu_korupt',
        'ultraviolet': 'so_purple',
    },
    'mp7': {
        'cirrus': 'gs_final_pooldeadv2',
        'nemesis': 'cu_mp7_nemsis',
        'ocean_foam': 'am_ossify_blue',
        'skulls': 'hy_skulls',
        'special_delivery': 'cu_mp7_classified',
        'whiteout': 'so_whiteout',
    },
    'p228': {
        'asiimov': 'cu_p250_asiimov',
        'cartel': 'aq_p250_cartel',
        'franklin': 'cu_money',
        'mehndi': 'cu_p250_refined',
        'muertos': 'cu_p250_mandala',
        'see_ya_later': 'cu_p250_cybercroc',
    },
    'p90': {
        'asiimov': 'cu_p90-asiimov',
        'death_by_kitty': 'cu_catskulls_p90',
        'emerald_dragon': 'cu_dragon_p90_bravo',
        'shallow_grave': 'gs_p90_shallow_grave',
        'shapewood': 'cu_p90_shapewood',
        'trigon': 'cu_p90_trigon',
    },
    'sg550': {
        'bloodsport': 'gs_scar20_bloodsport',
        'cardiac': 'cu_scar20_intervention',
        'cyrex': 'cu_scar_cyrex',
        'emerald': 'an_emerald_bravo',
        'outbreak': 'hy_scar20_jungler',
        'powercore': 'gs_scar20_powercore',
    },
    'tmp': {
        'airlock': 'cu_mp9_narcis',
        'bulldozer': 'so_yellow',
        'dart': 'cu_mp9_chevron',
        'deadly_poison': 'cu_mp9_deadly_poison',
        'hot_rod': 'an_red',
        'ruby_poison_dart': 'am_mp9_nitrogen',
    },
    'usp': {
        'blueprint': 'cu_usps_blueprint',
        'caiman': 'cu_kaiman',
        'guardian': 'cu_usp_elegant',
        'kill_confirmed': 'cu_usp_kill_confirmed',
        'lead_conduit': 'gs_usp_voltage',
        'neo_noir': 'cu_usps_noir',
    },
}

def _source_commit(source):
    try:
        return subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"],
                                       text=True, stderr=subprocess.DEVNULL).strip()
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def _resource_uid(relative):
    value = int.from_bytes(hashlib.sha256(("weapon_skin:" + relative.as_posix()).encode("utf-8")).digest()[:8], "big")
    value &= 0x7FFFFFFFFFFFFFFF
    alphabet = "abcdefghijklmnopqrstuvwxy012345678"
    encoded = ""
    while True:
        encoded = alphabet[value % len(alphabet)] + encoded
        value //= len(alphabet)
        if value == 0:
            return "uid://" + encoded


def _import_sidecar(relative):
    source = "res://" + relative.as_posix()
    imported = "res://.godot/imported/%s-%s.ctex" % (relative.name, hashlib.md5(source.encode("utf-8")).hexdigest())
    return """[remap]\n\nimporter=\"texture\"\ntype=\"CompressedTexture2D\"\nuid=\"%s\"\npath=\"%s\"\nmetadata={\n\"vram_texture\": false\n}\n\n[deps]\n\nsource_file=\"%s\"\ndest_files=[\"%s\"]\n\n[params]\n\ncompress/mode=0\ncompress/high_quality=false\ncompress/lossy_quality=0.7\ncompress/uastc_level=0\ncompress/rdo_quality_loss=0.0\ncompress/hdr_compression=1\ncompress/normal_map=0\ncompress/channel_pack=0\nmipmaps/generate=true\nmipmaps/limit=-1\nroughness/mode=0\nroughness/src_normal=\"\"\nprocess/channel_remap/red=0\nprocess/channel_remap/green=1\nprocess/channel_remap/blue=2\nprocess/channel_remap/alpha=3\nprocess/fix_alpha_border=true\nprocess/premult_alpha=false\nprocess/normal_map_invert_y=false\nprocess/hdr_as_srgb=false\nprocess/hdr_clamp_exposure=false\nprocess/size_limit=0\ndetect_3d/compress_to=0\n""" % (_resource_uid(relative), imported, source, imported)


def _build_outputs(source):
    pack = source / PACK_REL
    if not pack.is_dir():
        raise AssertionError("Missing CSGO Texture Pack: " + str(pack))
    commit = _source_commit(source)
    if commit != SOURCE_COMMIT:
        raise AssertionError("Reviewed source commit is %s, found %s" % (SOURCE_COMMIT, commit))
    outputs = {}
    catalog_weapons = {}
    for wid, display, materials, folder, finishes in WEAPONS:
        if len(finishes) != 6 or len({item[0] for item in finishes}) != 6:
            raise AssertionError("Each weapon must have six unique finishes: " + wid)
        if set(PAINT_KITS.get(wid, {})) != {item[0] for item in finishes}:
            raise AssertionError("Official paint-kit identities do not match curated finishes: " + wid)
        options = []
        for skin_id, finish, filename in finishes:
            source_path = pack / folder / filename
            if not source_path.is_file():
                raise AssertionError("Missing curated texture: " + str(source_path))
            source_bytes = source_path.read_bytes()
            with Image.open(io.BytesIO(source_bytes)) as image:
                if image.size != (512, 512):
                    raise AssertionError("Unexpected UV-map dimensions: " + str(source_path))
                # Preserve the source's 8-bit palette losslessly. Besides being
                # faithful to the ported UV map, this keeps 120 finishes compact.
                converted = image.copy()
                buffer = io.BytesIO()
                converted.save(buffer, "PNG", compress_level=6)
            relative = OUT_REL / wid / (skin_id + ".png")
            outputs[relative] = buffer.getvalue()
            outputs[Path(relative.as_posix() + ".import")] = _import_sidecar(relative).encode("utf-8")
            options.append({
                "id": skin_id,
                "name": display + " | " + finish,
                "finish": finish,
                "paint_kit": PAINT_KITS[wid][skin_id],
                "texture": "res://" + relative.as_posix(),
                "source": (PACK_REL / folder / filename).as_posix(),
                "source_sha256": hashlib.sha256(source_bytes).hexdigest(),
            })
        catalog_weapons[wid] = {
            "display_name": display,
            "materials": materials,
            "options": options,
        }
    catalog = {
        "schema": 1,
        "default": "original",
        "finish_identity": {
            "repository": "https://github.com/SteamDatabase/GameTracking-CS2",
            "commit": "1a3016b053eb006daaf741396f0d0416388519ca",
            "files": ["game/csgo/pak01_dir/scripts/items/items_game.txt",
                      "game/csgo/pak01_dir/resource/csgo_english.txt"],
        },
        "source": {
            "repository": "https://github.com/ellingtoncody81-ctrl/cs16-skin-inventory",
            "commit": SOURCE_COMMIT,
            "pack": PACK_REL.as_posix(),
            "upstream": "Valve; CS:GO Ports studio; BDS 1424 CSGO Texture Pack (GameBanana mod 228944)",
            "asset_terms": "Game assets are not covered by the source repository's MIT code license; original Valve/porter terms and attribution apply.",
        },
        "weapons": catalog_weapons,
    }
    outputs[CATALOG_REL] = (json.dumps(catalog, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
    return outputs


def main():
    check_only = "--check" in sys.argv[1:]
    args = [arg for arg in sys.argv[1:] if arg != "--check"]
    if len(args) not in (1, 2):
        raise SystemExit(__doc__)
    source = Path(args[0]).resolve()
    project = Path(args[1]).resolve() if len(args) == 2 else ROOT
    outputs = _build_outputs(source)
    changed = 0
    for relative, data in sorted(outputs.items(), key=lambda item: item[0].as_posix()):
        destination = project / relative
        if check_only:
            if not destination.is_file() or destination.read_bytes() != data:
                raise AssertionError("Out-of-date or missing output: " + str(relative))
        elif not destination.is_file() or destination.read_bytes() != data:
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)
            changed += 1
    finish_count = sum(len(item[4]) for item in WEAPONS)
    print("%s: %d authentic finishes across %d weapon families, %d files; %d changed" %
          ("CHECK PASS" if check_only else "BUILD", finish_count, len(WEAPONS), len(outputs), changed))


if __name__ == "__main__":
    main()
