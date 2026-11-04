#!/usr/bin/env python3
"""Build every weapon asset from ShadowNigth/archi's extracted CS2GO files.

    PYTHONPATH=<SourceIO parent> python -m tools.source.build_archi_weapons \
        <archi checkout> <reference weapons dir> <arms port glb> <out dir> [weapon ...]

The output directory receives v_/p_/w_ GLBs, inventory PNGs, the original archi
WAVs, models_meta.json and build_report.json.  Nothing is installed into the game
until the generated rigs have been inspected.  SourceIO is only a build-time
dependency; the resulting GLBs have no external resource references.
"""
import glob
import json
import os
import re
import shutil
import struct
import sys

import numpy as np

from .build_csco_viewmodels import (SILENCER_BONE, OFFSET, _finish_animation, add_arms,
                                    attachment_points, mdl_rig, mesh_primitives)
from .build_csco_worldmodels import fit_best, mdl_triangles
from .build_csgo_viewmodels import game_names, load_arms
from .build_csgo_worldmodels import glb_positions, write_static_glb
from .mdl_reader import load_model
from .smd import quat_mul
from .smd_converter import QA, RA, SCALE, build_glb, encode_texture, globals_of, to_godot_local

# game slot -> (extracted package, viewmodel stem, inventory image)
SOURCES = {
    "knife": ("m_cs2_knife_kukri", "v_knife_kukri", "weapon_knife_kukri"),
    "usp": ("m_cs2_usp", "v_pist_223", "weapon_usp_silencer"),
    "glock18": ("m_cs2_glock", "v_pist_glock18", "weapon_glock"),
    "deagle": ("m_cs2_deagle", "v_pist_deagle", "weapon_deagle"),
    "p228": ("m_cs2_p250", "v_pist_p250", "weapon_p250"),
    "elite": ("m_cs2_elite", "v_pist_elite", "weapon_elite"),
    "fiveseven": ("m_cs2_fiveseven", "v_pist_fiveseven", "weapon_fiveseven"),
    "m3": ("m_cs2_nova", "v_shot_nova", "weapon_nova"),
    "xm1014": ("m_cs2_xm1014", "v_shot_xm1014", "weapon_xm1014"),
    "mp5navy": ("m_cs2_mp5sd", "v_smg_mp5sd", "weapon_mp5sd"),
    "tmp": ("m_cs2_mp9", "v_smg_mp9", "weapon_mp9"),
    "p90": ("m_cs2_p90", "v_smg_p90", "weapon_p90"),
    "mac10": ("m_cs2_mac10", "v_smg_mac10", "weapon_mac10"),
    "ump45": ("m_cs2_ump45", "v_smg_ump45", "weapon_ump45"),
    "ak47": ("m_cs2_ak47", "v_rif_ak47", "weapon_ak47"),
    "sg552": ("m_cs2_sg556", "v_rif_sg556", "weapon_sg556"),
    "m4a1": ("m_cs2_m4a1s", "v_rif_m4a1_s", "weapon_m4a1_silencer"),
    "aug": ("m_cs2_aug", "v_rif_aug", "weapon_aug"),
    "scout": ("m_cs2_ssg08", "v_snip_ssg08", "weapon_ssg08"),
    "awp": ("m_cs2_awp", "v_snip_awp", "weapon_awp"),
    "g3sg1": ("m_cs2_g3sg1", "v_snip_g3sg1", "weapon_g3sg1"),
    "sg550": ("m_cs2_scar20", "v_snip_scar20", "weapon_scar20"),
    "m249": ("m_cs2_m249", "v_mach_m249para", "weapon_m249"),
    "flashbang": ("m_cs2_grenade_flashbang", "v_eq_flashbang", "weapon_flashbang"),
    "hegrenade": ("m_cs2_grenade_he", "v_eq_fraggrenade", "weapon_hegrenade"),
    "smokegrenade": ("m_cs2_grenade_smoke", "v_eq_smokegrenade", "weapon_smokegrenade"),
    "c4": ("m_cs2_c4", "v_ied", "weapon_c4"),
    # Weapons added by the archi refresh.
    "p2000": ("m_cs2_p2000", "v_pist_hkp2000", "weapon_hkp2000"),
    "cz75": ("m_cs2_cz75a", "v_pist_cz_75", "weapon_cz75a"),
    "revolver": ("m_cs2_revolver", "v_pist_revolver", "weapon_revolver"),
    "tec9": ("m_cs2_tec9", "v_pist_tec9", "weapon_tec9"),
    "famas": ("m_cs2_famas", "v_rif_famas", "weapon_famas"),
    "galil": ("m_cs2_galilar", "v_rif_galilar", "weapon_galilar"),
    "m4a4": ("m_cs2_m4a4", "v_rif_m4a1", "weapon_m4a1"),
    "mag7": ("m_cs2_mag7", "v_shot_mag7", "weapon_mag7"),
    "sawedoff": ("m_cs2_sawedoff", "v_shot_sawedoff", "weapon_sawedoff"),
    "negev": ("m_cs2_negev", "v_mach_negev", "weapon_negev"),
    "bizon": ("m_cs2_bizon", "v_smg_bizon", "weapon_bizon"),
    "mp7": ("m_cs2_mp7", "v_smg_mp7", "weapon_mp7"),
    "taser": ("m_cs2_taser", "v_eq_taser", "weapon_taser"),
    "decoy": ("m_cs2_grenade_decoy", "v_eq_decoy", "weapon_decoy"),
    "molotov": ("m_cs2_grenade_molotov", "v_eq_molotov", "weapon_molotov"),
    "incendiary": ("m_cs2_grenade_incendary", "v_eq_incendiarygrenade", "weapon_incgrenade"),
}

MODEL_BASE = {"mp5navy": "mp5"}
WORLD_STEM = {"m249": "w_mach_m249"}
WORLD_ALIGNMENT = {"elite": "deagle"}  # avoid fitting a two-gun cloud to the legacy broken p_elite
# Rigid placement reference for newly introduced slots. Existing slots use their
# already calibrated p_/w_ GLBs; additions use the closest classic weapon shape.
REFERENCE = {
    "p2000": "usp", "cz75": "glock18", "revolver": "deagle", "tec9": "mac10",
    "famas": "aug", "galil": "ak47", "m4a4": "m4a1", "mag7": "xm1014",
    "sawedoff": "m3", "negev": "m249", "bizon": "ump45", "mp7": "mp5navy",
    "taser": "deagle", "decoy": "flashbang", "molotov": "hegrenade",
    "incendiary": "hegrenade",
}
ARCHI_SILENCER_BONES = {"usp": "v_weapon_silencer", "m4a1": "v_weapon.M4A1_Silencer"}
# These CS2 v49 viewmodels use the older pre-rotation in their mesh/bone data.
# A second +90-degree root turn and (-2, 0, +2)-Source-unit offset puts them in
# the same camera space as the project's validated viewmodels (and on the right
# after PlayerController applies its right-handed mirror).
VIEW_ROOT_OFFSET = np.array([-2.0 * SCALE, 0.0, 2.0 * SCALE])
SKIP_SEQUENCES = re.compile(r"(?:^cs2_|additive|throwcharge|^inv|_sticker|^ammo_|^bolt_state$|^bolt_reload$|^cylrotate$)")

# Original archi fire sounds.  A few new weapons did not ship a dedicated firing
# WAV in archi; those use the closest included archi firearm sample, never a
# synthetic file or an old asset from another repository.
FIRE_SOUNDS = {
    "knife": ["cs2_hegren/grenade_throw.wav"],
    "usp": ["usp_unsil-1.wav"], "glock18": ["glock18-1.wav", "glock18-2.wav"],
    "deagle": ["deagle-1.wav", "deagle-2.wav"], "p228": ["p228-1.wav"],
    "elite": ["elite_fire.wav"], "fiveseven": ["fiveseven-1.wav"],
    "m3": ["m3-1.wav"], "xm1014": ["xm1014-1.wav"],
    "mp5navy": ["mp5-1.wav", "mp5-2.wav"], "tmp": ["tmp-1.wav", "tmp-2.wav"],
    "p90": ["p90-1.wav"], "mac10": ["mac10-1.wav"], "ump45": ["ump45-1.wav"],
    "ak47": ["ak47-1.wav", "ak47-2.wav"], "sg552": ["sg552-1.wav", "sg552-2.wav"],
    "m4a1": ["m4a1_unsil-1.wav", "m4a1_unsil-2.wav"], "aug": ["aug-1.wav"],
    "scout": ["scout_fire-1.wav"], "awp": ["awp1.wav"], "g3sg1": ["g3sg1-1.wav"],
    "sg550": ["sg550-1.wav"], "m249": ["m249-1.wav", "m249-2.wav"],
    "p2000": ["usp_unsil-1.wav"], "cz75": ["glock18-1.wav", "glock18-2.wav"],
    "revolver": ["deagle-1.wav", "deagle-2.wav"], "tec9": ["mac10-1.wav"],
    "famas": ["famas-1.wav", "famas-2.wav"], "galil": ["galil-1.wav", "galil-2.wav"],
    "m4a4": ["m4a1_unsil-1.wav", "m4a1_unsil-2.wav"], "mag7": ["m3-1.wav"],
    "sawedoff": ["m3-1.wav"], "negev": ["m249-1.wav", "m249-2.wav"],
    "bizon": ["ump45-1.wav"], "mp7": ["mp5-1.wav", "mp5-2.wav"],
    "taser": ["cs2_taser/taser_charging.wav"],
}
SILENCED_SOUNDS = {"usp": ["usp1.wav", "usp2.wav"], "m4a1": ["m4a1-1.wav"]}

EVENT_PREFIX = {
    "ak47": "cs2_ak47", "aug": "cs2_aug", "awp": "cs2_awp", "c4": "cs2_c4",
    "deagle": "cs2_deagle", "elite": "cs2_elites", "elites": "cs2_elites",
    "famas": "cs2_famas", "fiveseven": "cs2_fiveseven", "flashbang": "cs2_flashbang",
    "g3sg1": "cs2_g3sg1", "galil": "cs2_galilar", "galilar": "cs2_galilar",
    "glock": "cs2_glock18", "glock18": "cs2_glock18", "hegrenade": "cs2_hegren",
    "hkp2000": "cs2_p2000", "m249": "cs2_m249", "m4a1": "cs2_m4a1s",
    "m4a4": "cs2_m4a1s", "mac10": "cs2_mac10", "mag7": "cs2_ump45",
    "mp5": "cs2_mp5sd", "mp5sd": "cs2_mp5sd", "mp7": "cs2_mp7", "mp9": "cs2_mp9",
    "negev": "cs2_negev", "nova": "cs2_nova", "p2000": "cs2_p2000",
    "p250": "cs2_p250", "p90": "cs2_p90", "revolver": "cs2_revolver",
    "sawedoff": "cs2_sawedoff", "scar20": "cs2_scar20", "sg556": "cs2_sg553",
    "sg553": "cs2_sg553", "smokegrenade": "cs2_smokegren", "ssg08": "cs2_ssg08",
    "taser": "cs2_taser", "ump45": "cs2_ump45", "usp": "cs2_usps",
    "xm1014": "cs2_xm1014", "cz75": "cs2_glock18", "cz75a": "cs2_glock18",
    "tec9": "cs2_mac10", "bizon": "cs2_ump45", "decoy": "cs2_hegren",
    "molotov": "cs2_hegren", "incgrenade": "cs2_hegren", "incendiarygrenade": "cs2_hegren",
}


def model_base(weapon):
    return MODEL_BASE.get(weapon, weapon)


def core_sound(path):
    return "weapons/archi/" + (path if "/" in path else "core/" + path)


def find_package(root, weapon):
    package = SOURCES[weapon][0]
    matches = []
    for base, dirs, _files in os.walk(root):
        if os.path.basename(base) == package and "EXTRAIDOS" in base:
            matches.append(base)
            dirs[:] = []
    if not matches:
        raise FileNotFoundError("archi package %s for %s" % (package, weapon))
    if weapon == "smokegrenade":
        vanilla = [p for p in matches if "Vanilla (Default)" in p]
        if vanilla:
            return vanilla[0]
    # The plain Kukri package is distinct from the _ct/_t packages.
    return sorted(matches, key=len)[0]


def model_path(package, stem):
    for base in (os.path.join(package, "#pak"), package):
        path = os.path.join(base, "models", "weapons", stem + ".mdl")
        if os.path.exists(path):
            return path
    raise FileNotFoundError(stem + ".mdl in " + package)


class ArchiMaterials:
    """Case-insensitive VMT/VTF resolver with Source alpha and nocull semantics."""

    def __init__(self, package):
        self.root = os.path.join(package, "materials")
        self.files = {}
        for base, _dirs, files in os.walk(self.root):
            for fn in files:
                path = os.path.join(base, fn)
                rel = os.path.relpath(path, self.root).replace("\\", "/").lower()
                self.files[rel] = path
        self.cache = {}
        self.missing = []

    def path(self, rel):
        return self.files.get(rel.replace("\\", "/").strip("/").lower())

    @staticmethod
    def values(text, key):
        # VMTs in the pack use both quoted and unquoted keys, / and \\ paths.
        pattern = r"(?im)^\s*[\"']?\\?" + re.escape(key) + r"[\"']?\s+([^\r\n]+)"
        match = re.search(pattern, text)
        if not match:
            return None
        value = match.group(1).strip()
        quoted = re.match(r"[\"']([^\"']+)[\"']", value)
        return quoted.group(1) if quoted else value.split()[0]

    def material(self, model, material):
        for cd in model["cdmaterials"]:
            stem = cd.replace("\\", "/").strip("/") + "/" + material
            vmt = self.path(stem + ".vmt")
            if vmt:
                return vmt
        # A handful of model material names omit their cdmaterials directory.
        suffix = "/" + material.lower() + ".vmt"
        for rel, path in self.files.items():
            if rel.endswith(suffix):
                return path
        return None

    def texture(self, model, material):
        vmt = self.material(model, material)
        text = ""
        if vmt:
            with open(vmt, encoding="utf-8", errors="ignore") as handle:
                text = handle.read()
            base = self.values(text, "$basetexture")
            if base:
                vtf = self.path(base + ".vtf")
                if vtf:
                    return vtf, text
        for cd in model["cdmaterials"]:
            stem = cd.replace("\\", "/").strip("/") + "/" + material
            direct = self.path(stem + ".vtf")
            if direct:
                return direct, text
        return None, text

    def entry(self, model, material, max_size=1024):
        key = (model["name"], material, max_size)
        if key in self.cache:
            return self.cache[key]
        path, vmt = self.texture(model, material)
        if not path:
            self.missing.append(material)
            if material.lower() == "c4_light":
                # The extracted p_/w_ C4 references this tiny Source material but
                # the package omits its VMT/VTF.  Preserve the armed indicator as
                # a red emissive surface instead of an untextured grey patch.
                result = {"name": material, "color": [0.8, 0.015, 0.005, 1.0],
                          "emissive": [1.0, 0.02, 0.005]}
            else:
                result = {"name": material, "color": [0.12, 0.13, 0.14, 1.0]}
            self.cache[key] = result
            return result
        alphatest = (self.values(vmt, "$alphatest") or "0").strip("\"'") not in ("0", "0.0", "")
        translucent = (self.values(vmt, "$translucent") or "0").strip("\"'") not in ("0", "0.0", "")
        additive = (self.values(vmt, "$additive") or "0").strip("\"'") not in ("0", "0.0", "")
        nocull = (self.values(vmt, "$nocull") or "0").strip("\"'") not in ("0", "0.0", "")
        alpha = self.values(vmt, "$alpha")
        blend_tint = (self.values(vmt, "$blendtintbybasealpha") or "0").strip("\"'") not in ("0", "0.0", "")
        use_alpha = alphatest or translucent or additive
        colour2 = re.search(r"(?im)^\s*[\"']?\$color2[\"']?\s+[\"']?\[([^]]+)\]", vmt)
        tint_rgb = None
        if colour2:
            try:
                values = [float(value) for value in colour2.group(1).replace(",", " ").split()[:3]]
                if len(values) == 3:
                    tint_rgb = [max(0.0, min(1.0, value)) for value in values]
            except ValueError:
                pass
        from srctools.vtf import VTF
        with open(path, "rb") as handle:
            pil = VTF.read(handle).get().to_PIL()
        # The alpha in most CS2 weapon _c textures is a tint mask, not opacity.
        # Bake that mask before the opaque JPEG conversion; otherwise bright
        # untinted islands look like a second camouflage texture on the weapon.
        masked_tint = tint_rgb if tint_rgb is not None and blend_tint else None
        result = {"name": material,
                  "image": encode_texture(pil, max_size, not use_alpha, masked_tint)}
        if use_alpha:
            result["alpha_mode"] = "MASK" if alphatest and not (translucent or additive) else "BLEND"
            if result["alpha_mode"] == "MASK":
                try:
                    result["alpha_cutoff"] = float(self.values(vmt, "$alphatestreference") or 0.5)
                except ValueError:
                    result["alpha_cutoff"] = 0.5
        if nocull:
            result["double_sided"] = True
        if alpha:
            try:
                result["color"] = [1.0, 1.0, 1.0, float(alpha)]
            except ValueError:
                pass
        # An unmasked $color2 is a genuine whole-surface glTF colour factor
        # (black scope lenses and the Molotov's green liquid).
        if tint_rgb is not None and not blend_tint:
            alpha_value = result.get("color", [1, 1, 1, 1])[3]
            result["color"] = tint_rgb + [alpha_value]
        self.cache[key] = result
        return result


class ArchiSounds:
    def __init__(self, root, out_dir):
        self.root = root
        self.sound_root = os.path.join(root, "sound")
        self.out_dir = out_dir
        self.files = {}
        for base, _dirs, files in os.walk(self.sound_root):
            for fn in files:
                if not fn.lower().endswith(".wav"):
                    continue
                src = os.path.join(base, fn)
                rel = os.path.relpath(src, self.sound_root).replace("\\", "/")
                self.files[rel.lower()] = src
        # Include the additional firing/zoom recordings stored inside #pak.
        for src in glob.glob(os.path.join(root, "**", "*.wav"), recursive=True):
            if os.path.commonpath([self.sound_root, src]) == self.sound_root:
                continue
            parts = src.replace("\\", "/").split("/")
            package = next((part for part in parts if part.startswith("m_cs2_")), "")
            prefix = package.replace("m_cs2_", "")
            folder = EVENT_PREFIX.get(prefix)
            if not folder:
                continue
            rel = folder + "/" + os.path.basename(src).lower()
            if rel in self.files:
                # Keep both recordings when a package and the root sound tree use
                # the same logical name (G3SG1 ships two different zoom takes).
                stem, extension = os.path.splitext(rel)
                self.files.setdefault(stem + "_pak" + extension, src)
            else:
                self.files[rel] = src
        self.installed = set()
        self.unresolved = {}

    def install_all(self):
        for rel, src in sorted(self.files.items()):
            dest = os.path.join(self.out_dir, "audio", *core_sound(rel).split("/")[2:])
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            with open(src, "rb") as handle:
                raw = bytearray(handle.read())
            # Several CS2GO WAVs declare a RIFF payload six bytes larger than
            # the actual file although their fmt/data chunks are complete. Godot
            # trusts that header and seeks past EOF, so repair only the container
            # size (and word alignment); every audio sample remains untouched.
            if len(raw) >= 12 and raw[:4] == b"RIFF" and raw[8:12] == b"WAVE":
                if len(raw) & 1:
                    raw.append(0)
                struct.pack_into("<I", raw, 4, len(raw) - 8)
                with open(dest, "wb") as handle:
                    handle.write(raw)
            else:
                shutil.copy2(src, dest)
            self.installed.add(rel)

    def find(self, event_name, weapon):
        if "." not in event_name:
            return None
        prefix, suffix = event_name.split(".", 1)
        prefix = prefix.lower().replace("weapon_", "")
        folder = EVENT_PREFIX.get(prefix)
        if not folder:
            return None
        suffix = suffix.lower()
        if "weaponmove" in suffix or "barrelroll" in suffix:
            return None  # no corresponding archi recording; do not substitute a click
        if "pullpin" in suffix:
            suffix = "pinpull_start" if "start" in suffix else "pinpull"
        if suffix == "pumpduringshot":
            suffix = "pump"
        if suffix == "sliderelease2":
            suffix = "sliderelease"
        candidates = [suffix + ".wav"]
        if folder == "cs2_hegren" and suffix == "draw":
            candidates.insert(0, "he_draw.wav")
        if folder == "cs2_smokegren" and suffix == "draw":
            candidates.insert(0, "s_draw.wav")
        if folder == "cs2_flashbang" and "throw" in suffix:
            candidates.insert(0, "throw.wav")
        if folder == "cs2_taser":
            candidates.insert(0, "taser_" + suffix + ".wav")
            if suffix == "draw":
                candidates.append("taser_charging.wav")
        if folder == "cs2_c4":
            if suffix == "draw":
                candidates.insert(0, "c4_draw.wav")
            elif suffix == "initiate":
                candidates.insert(0, "c4_initiate.wav")
            elif "keypress" in suffix:
                candidates.insert(0, "key_press1.wav")
        if folder == "cs2_deagle" and re.fullmatch(r"lookat\d+", suffix):
            # The long Deagle inspection's authored LookAt009/036/... events
            # correspond to the shipped lookat_f009/lookat_f036/... recordings.
            candidates.insert(0, suffix.replace("lookat", "lookat_f", 1) + ".wav")
        if prefix in ("elite", "elites"):
            if suffix == "lclipin":
                candidates.insert(0, "leftclipin.wav")
            elif suffix == "rclipin":
                candidates.insert(0, "rightclipin.wav")
            elif suffix.startswith("taunt"):
                candidates.append("taunt_tap.wav")
        if suffix == "grab":
            candidates.append("draw.wav")
        if suffix == "boltpull":
            candidates.append("boltback.wav")
        if suffix == "boltrelease":
            candidates.extend(["boltforward.wav", "boltrelease.wav"])
        if suffix == "silencerscrewoffend":
            candidates.insert(0, "sil_screw_off_end.wav")
        if folder == "cs2_ump45" and suffix in ("pumpback", "pumpforward"):
            rel = "cs2_ump45/" + ("boltback.wav" if suffix == "pumpback" else "boltforward.wav")
            if rel in self.files:
                return rel
        if suffix.startswith("pump") and folder == "cs2_ump45":
            rel = "cs2_nova/pump.wav"
            if rel in self.files:
                return rel
        if suffix.startswith("silencerscrew"):
            tail = suffix[len("silencerscrew"):].replace("_", "")
            candidates.extend(["sil_screw" + tail + ".wav", "sil_screw_" + tail + ".wav"])
        if suffix.startswith("silencer") and "start" in suffix:
            candidates.extend(["sil_screw_on_start.wav", "sil_screw_off_end.wav"])
        for fn in candidates:
            rel = folder + "/" + fn
            if rel in self.files:
                return rel
        # Normalized fallback handles InsertShell -> insertshell_01 and minor punctuation.
        wanted = re.sub(r"[^a-z0-9]", "", suffix)
        for rel in sorted(self.files):
            if not rel.startswith(folder + "/"):
                continue
            stem = re.sub(r"[^a-z0-9]", "", os.path.splitext(os.path.basename(rel))[0])
            if stem == wanted or (wanted == "insertshell" and stem.startswith("insertshell")):
                return rel
        self.unresolved.setdefault(weapon, set()).add(event_name)
        return None

    def simple(self, weapon, suffix):
        package = SOURCES[weapon][0]
        # Prefer the weapon's own event prefix, then its model-name equivalent.
        candidates = [package.replace("m_cs2_", ""), model_base(weapon)]
        for prefix in candidates:
            folder = EVENT_PREFIX.get(prefix)
            if folder:
                return self.find("Weapon_%s.%s" % (prefix, suffix), weapon)
        return None


def archi_events(seq, weapon, duration, sounds):
    events, show, hide = [], None, None
    keypad = 0
    for cycle, code, options, name, _event_type in seq["events"]:
        time = float(cycle) * duration
        sound_name = ""
        if code == 5004 and options:
            sound_name = options
        elif name == "AE_CL_PLAYSOUND" and options:
            sound_name = options
        if sound_name:
            if weapon == "c4" and "keypress" in sound_name.lower():
                keypad += 1
                candidate = "cs2_c4/key_press%d.wav" % ((keypad - 1) % 7 + 1)
                rel = candidate if candidate in sounds.files else sounds.find(sound_name, weapon)
            else:
                rel = sounds.find(sound_name, weapon)
            if rel:
                events.append({"t": round(time, 3), "wav": core_sound(rel)})
        if name == "AE_CL_SHOW_SILENCER":
            show = time
        elif name == "AE_CL_HIDE_SILENCER":
            hide = time
        # Some C4 builds use numbered 5004 events instead of named key events.
        if weapon == "c4" and code == 5004 and not sound_name:
            keypad += 1
            rel = "cs2_c4/key_press%d.wav" % ((keypad - 1) % 7 + 1)
            if rel in sounds.files:
                events.append({"t": round(time, 3), "wav": core_sound(rel)})
    events.sort(key=lambda event: event["t"])
    return events, show, hide


def sequence_poses(model, seq):
    anim_index = next((index for index in seq["anims"] if index in model["anims"]), None)
    if anim_index is None:
        return None, 0.0
    anim = model["anims"][anim_index]
    frames = anim["frames"]
    if len(frames) == 0:
        return None, 0.0
    poses = []
    for frame in frames:
        poses.append([(np.array(frame["pos"][bone], dtype=np.float64),
                       np.array(frame["rot"][bone], dtype=np.float64)) for bone in range(len(model["bones"]))])
    return poses, float(anim["fps"] or 30.0)


def calibrate_viewmodel(rig, bind_t, bind_q, prims, animations):
    """Apply the archi camera-space correction to mesh, bind pose and every clip."""
    for prim in prims:
        prim["pos"] = RA(prim["pos"]) + VIEW_ROOT_OFFSET
        prim["nrm"] = RA(prim["nrm"])
    roots = [index for index, parent in enumerate(rig.parents) if parent < 0]
    for index in roots:
        bind_t[index] = RA(bind_t[index]) + VIEW_ROOT_OFFSET
        bind_q[index] = quat_mul(QA, bind_q[index])
    seen_t, seen_q = set(), set()
    for _name, _times, ts, qs, _scales in animations:
        if id(ts) not in seen_t:
            for index in roots:
                ts[:, index, :] = RA(ts[:, index, :]) + VIEW_ROOT_OFFSET
            seen_t.add(id(ts))
        if id(qs) not in seen_q:
            for index in roots:
                qs[:, index, :] = np.array([quat_mul(QA, q) for q in qs[:, index, :]])
            seen_q.add(id(qs))


def build_view(weapon, package, arms_parts, sounds, out_dir, report):
    stem = SOURCES[weapon][1]
    model = load_model(model_path(package, stem))
    rig = mdl_rig(model)
    bind_t, bind_q = to_godot_local(rig, rig.bind, OFFSET)
    bind_g = globals_of(rig, bind_t, bind_q)
    library = ArchiMaterials(package)
    materials, mat_ids = [], {}

    def mat_index(name):
        if name not in mat_ids:
            materials.append(library.entry(model, name, 1024))
            mat_ids[name] = len(materials) - 1
        return mat_ids[name]

    prims = mesh_primitives(model, rig, bind_g, mat_index)
    add_arms(prims, materials, rig, bind_g, arms_parts, weapon, report)
    out_anims, meta_seqs, durations, event_map, source_map = [], [], {}, {}, {}
    for seq in model["sequences"]:
        raw = str(seq["name"]).lower()
        if SKIP_SEQUENCES.search(raw):
            continue
        names = game_names(weapon, raw)
        if weapon == "mag7" and raw == "shoot2":
            names = ["shoot1", "shoot2"]
        if weapon == "revolver" and raw == "fire":
            names = ["fire", "shoot1"]
        if not names:
            continue
        poses, fps = sequence_poses(model, seq)
        if poses is None or fps <= 0.0:
            continue
        duration = max(len(poses) - 1, 1) / fps
        events, show, hide = archi_events(seq, weapon, duration, sounds)
        _finish_animation(weapon, names, poses, fps, events, show, hide, rig, out_anims,
                          meta_seqs, durations, event_map, raw, source_map)
    if not out_anims:
        raise RuntimeError("no usable animations for " + weapon)
    calibrate_viewmodel(rig, bind_t, bind_q, prims, out_anims)
    base = model_base(weapon)
    output = os.path.join(out_dir, "weapons", "v_" + base + ".glb")
    build_glb(output, rig, bind_t, bind_q, prims, materials, out_anims)
    info = {"sequences": meta_seqs, "seq_durations": durations, "seq_events": event_map,
            "bones": len(rig.names), "offset": [round(float(x), 4) for x in OFFSET],
            "source": "ShadowNigth/archi", "source_model": stem,
            "materials": [m["name"] for m in materials],
            "vertices": int(sum(len(p["pos"]) for p in prims))}
    info.update(attachment_points(model, rig, out_anims))
    report.setdefault("animation_sources", {})[weapon] = source_map
    report.setdefault("arms_missing_bones", {})
    if library.missing:
        report.setdefault("missing_materials", {})[weapon] = sorted(set(library.missing))
    return info


def build_world(weapon, package, reference_dir, out_dir, root):
    stem = WORLD_STEM.get(weapon, "w_" + SOURCES[weapon][1][2:])
    model = load_model(model_path(package, stem))
    if weapon == "elite":
        # w_pist_elite is a buy-menu pose containing both pistols ~43 Source
        # units apart.  A dropped/third-person weapon is attached to one hand,
        # so retaining the left mesh would create a huge floating second gun.
        model = dict(model)
        model["meshes"] = [mesh for mesh in model["meshes"]
                           if "right" in str(mesh.get("model", "")).lower()]
    triangles = mdl_triangles(model)
    points = np.array([vertex[0] for _mat, tri in triangles for vertex in tri])
    library = ArchiMaterials(package)

    def materials_for(name):
        entry = library.entry(model, name, 512)
        options = {key: entry[key] for key in ("alpha_mode", "alpha_cutoff", "double_sided", "emissive") if key in entry}
        return entry.get("image"), entry.get("color"), options

    reference_weapon = REFERENCE.get(weapon, weapon)
    reference_base = model_base(reference_weapon)
    base = model_base(weapon)
    info = {"source_model": stem, "reference": reference_base}
    alignment_weapon = WORLD_ALIGNMENT.get(weapon)
    if alignment_weapon:
        info["alignment_model"] = "filtered elite right pistol -> deagle reference"
    for prefix in ("p", "w"):
        reference = glb_positions(os.path.join(reference_dir, "%s_%s.glb" % (prefix, model_base(alignment_weapon) if alignment_weapon else reference_base)))
        rotation, translation, residual, angle = fit_best(points, reference)
        write_static_glb(os.path.join(out_dir, "weapons", "%s_%s.glb" % (prefix, base)),
                         "%s_%s" % (prefix, base), [(triangles, rotation, translation)], materials_for)
        info[prefix + "_fit"] = {"residual_m": round(residual, 5), "deg_from_seed": round(angle, 2)}
    if library.missing:
        info["missing_materials"] = sorted(set(library.missing))
    return info


def install_icon(weapon, package, out_dir):
    icon = SOURCES[weapon][2] + ".png"
    matches = glob.glob(os.path.join(package, "**", icon), recursive=True)
    if not matches:
        raise FileNotFoundError(icon + " in " + package)
    dest = os.path.join(out_dir, "icons", "640_" + model_base(weapon) + ".png")
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    shutil.copy2(matches[0], dest)


def main():
    root, reference_dir, arms_port, out_dir = sys.argv[1:5]
    only = sys.argv[5:] or list(SOURCES)
    os.makedirs(os.path.join(out_dir, "weapons"), exist_ok=True)
    arms_parts = load_arms(arms_port) if arms_port else []
    sounds = ArchiSounds(root, out_dir)
    sounds.install_all()
    # The archi models use the actual CS2 silencer bone names.
    SILENCER_BONE.update(ARCHI_SILENCER_BONES)
    meta_path = os.path.join(out_dir, "models_meta.json")
    report_path = os.path.join(out_dir, "build_report.json")
    meta = {}
    report = {"source": "https://github.com/ShadowNigth/archi", "weapons": {}}
    if os.path.exists(meta_path):
        with open(meta_path) as handle:
            meta = json.load(handle)
    if os.path.exists(report_path):
        with open(report_path) as handle:
            report = json.load(handle)
        report.setdefault("weapons", {})
    for weapon in only:
        print("BUILD", weapon, flush=True)
        package = find_package(root, weapon)
        view = build_view(weapon, package, arms_parts, sounds, out_dir, report)
        world = build_world(weapon, package, reference_dir, out_dir, root)
        view["world"] = world
        install_icon(weapon, package, out_dir)
        meta["weapons/v_" + model_base(weapon)] = view
        report["weapons"][weapon] = {
            "package": os.path.relpath(package, root), "sequences": view["sequences"],
            "vertices": view["vertices"], "world": world,
            "fire_sounds": [core_sound(path) for path in FIRE_SOUNDS.get(weapon, [])],
        }
        print("  %d sequences, %d vertices" % (len(view["sequences"]), view["vertices"]), flush=True)
    unresolved = report.setdefault("unresolved_sounds", {})
    for weapon in only:
        unresolved.pop(weapon, None)
    for key, value in sounds.unresolved.items():
        unresolved[key] = sorted(value)
    if not unresolved:
        report.pop("unresolved_sounds", None)
    report["audio_files"] = len(sounds.installed)
    with open(os.path.join(out_dir, "models_meta.json"), "w") as handle:
        json.dump(meta, handle, indent=2)
    with open(os.path.join(out_dir, "build_report.json"), "w") as handle:
        json.dump(report, handle, indent=2)
    print("Built", len(only), "archi weapon slots in", out_dir, flush=True)


if __name__ == "__main__":
    main()
