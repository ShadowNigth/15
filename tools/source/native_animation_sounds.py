"""Resolve native Sound events to existing archi recordings (no synthetic foley).

Resolver shared in behavior with the archi importer, without its SourceIO build dependencies.
ID/particle events are never passed to this resolver.
"""
import os
import re

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

class NativeSounds:
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
