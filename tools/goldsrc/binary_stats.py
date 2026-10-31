#!/usr/bin/env python3
"""
Extracts authentic Counter-Strike 1.5 Retail game data from:
  - cstrike/dlls/cs_i386.so (ELF32 x86 binary GetMaxSpeed floats & weapon symbols)
  - cstrike/classes/*.txt (weapon & player class descriptions)
  - cstrike/sprites/hud.txt & weapon_*.txt (HUD sprite atlas rectangles)
  - cstrike/sound/materials.txt (surface material -> footstep type mapping)
  - cstrike/titles.txt (game localized strings)
"""

import glob
import json
import os
import re
import struct
from typing import Dict, List, Tuple


def extract_elf_maxspeeds(so_path: str) -> Dict[str, List[float]]:
    """Pure-Python ELF32 i386 parser extracting GetMaxSpeed float constants per weapon class."""
    if not os.path.exists(so_path):
        return {}
    with open(so_path, "rb") as f:
        data = f.read()
    if data[:4] != b"\x7fELF" or data[4] != 1:
        return {}

    e_phoff, e_shoff = struct.unpack_from("<II", data, 28)
    e_phentsize, e_phnum, e_shentsize, e_shnum = struct.unpack_from("<HHHH", data, 42)

    segs = []
    for i in range(e_phnum):
        p_type, p_offset, p_vaddr, _, p_filesz, _ = struct.unpack_from(
            "<IIIIII", data, e_phoff + i * e_phentsize
        )
        if p_type == 1:
            segs.append((p_vaddr, p_filesz, p_offset))

    def vma_to_off(vma: int) -> int:
        for va, fsz, off in segs:
            if va <= vma < va + fsz:
                return off + (vma - va)
        return vma

    # Locate SHT_DYNSYM (11) and its linked string table
    dynsym_sh = None
    sections = []
    for i in range(e_shnum):
        sh = struct.unpack_from("<10I", data, e_shoff + i * e_shentsize)
        sections.append(sh)
        if sh[1] == 11:  # SHT_DYNSYM
            dynsym_sh = sh

    if not dynsym_sh:
        return {}

    sym_off, sym_size, str_idx, _, _, sym_entsize = (
        dynsym_sh[4],
        dynsym_sh[5],
        dynsym_sh[6],
        dynsym_sh[7],
        dynsym_sh[8],
        dynsym_sh[9] or 16,
    )
    str_off, str_size = sections[str_idx][4], sections[str_idx][5]
    strtab = data[str_off : str_off + str_size]

    results: Dict[str, List[float]] = {}
    num_syms = sym_size // sym_entsize
    for i in range(num_syms):
        st_name, st_value, st_size, st_info, _, _ = struct.unpack_from(
            "<IIIBBH", data, sym_off + i * sym_entsize
        )
        if st_value == 0 or st_name >= len(strtab):
            continue
        end = strtab.find(b"\x00", st_name)
        name = strtab[st_name:end].decode("latin1", errors="ignore")
        if not name.startswith("GetMaxSpeed__") or "CBasePlayerItem" in name:
            continue

        fn_off = vma_to_off(st_value)
        fn_len = st_size if st_size > 0 else 80
        code = data[fn_off : fn_off + fn_len]

        # Pattern in GCC 2.95 PIC x86:
        # e8 00 00 00 00        call next
        # 5b                    pop %ebx
        # 81 c3 XX XX XX XX     add $imm32, %ebx
        call_pos = code.find(b"\xe8\x00\x00\x00\x00\x5b\x81\xc3")
        if call_pos < 0:
            continue
        pop_vma = st_value + call_pos + 5
        imm32 = struct.unpack_from("<I", code, call_pos + 8)[0]
        got_vma = (pop_vma + imm32) & 0xFFFFFFFF

        # Scan for flds disp32(%ebx): opcode d9 83 XX XX XX XX
        floats = []
        pos = call_pos + 12
        while pos + 6 <= len(code):
            if code[pos] == 0xD9 and code[pos + 1] == 0x83:
                disp = struct.unpack_from("<i", code, pos + 2)[0]
                f_vma = (got_vma + disp) & 0xFFFFFFFF
                f_val = struct.unpack_from("<f", data, vma_to_off(f_vma))[0]
                floats.append(round(float(f_val), 2))
                pos += 6
            else:
                pos += 1
        cls_name = re.sub(r"^GetMaxSpeed__\d+", "", name)
        results[cls_name] = floats
    return results


def parse_class_descriptions(classes_dir: str) -> Dict[str, str]:
    descs: Dict[str, str] = {}
    for p in sorted(glob.glob(os.path.join(classes_dir, "*.txt"))):
        key = os.path.splitext(os.path.basename(p))[0].lower()
        raw = open(p, "r", encoding="latin1", errors="ignore").read()
        lines = [
            ln.strip()
            for ln in raw.splitlines()
            if ln.strip() and not set(ln.strip()) <= {"_", "-"}
        ]
        descs[key] = "\n".join(lines)
    return descs


def parse_hud_txt(sprites_dir: str) -> dict:
    hud_entries = {}
    hud_path = os.path.join(sprites_dir, "hud.txt")
    if os.path.exists(hud_path):
        for line in open(hud_path, "r", encoding="latin1", errors="ignore"):
            line = line.split("//")[0].strip()
            parts = line.split()
            if len(parts) == 7:
                name, res, spr, x, y, w, h = parts
                key = f"{name}_{res}"
                hud_entries[key] = {
                    "name": name,
                    "res": int(res),
                    "sprite": spr.lower(),
                    "rect": [int(x), int(y), int(w), int(h)],
                }

    weapon_hud = {}
    for wp in sorted(glob.glob(os.path.join(sprites_dir, "weapon_*.txt"))):
        wname = os.path.splitext(os.path.basename(wp))[0].lower()
        entries = {}
        for line in open(wp, "r", encoding="latin1", errors="ignore"):
            line = line.split("//")[0].strip()
            parts = line.split()
            if len(parts) == 7:
                ename, res, spr, x, y, w, h = parts
                entries[f"{ename}_{res}"] = {
                    "sprite": spr.lower(),
                    "rect": [int(x), int(y), int(w), int(h)],
                }
        weapon_hud[wname] = entries
    return {"hud": hud_entries, "weapons": weapon_hud}


def parse_materials_txt(sound_dir: str) -> Dict[str, str]:
    """Maps lowercase texture names (or prefixes) to GoldSrc material char (C, M, D, V, T, G, W, P, S, Y)."""
    mat_path = os.path.join(sound_dir, "materials.txt")
    mapping: Dict[str, str] = {}
    if not os.path.exists(mat_path):
        return mapping
    for line in open(mat_path, "r", encoding="latin1", errors="ignore"):
        line = line.split("//")[0].strip()
        parts = line.split()
        if len(parts) >= 2 and len(parts[0]) == 1:
            mtype = parts[0].upper()
            tex = parts[1].lower()
            mapping[tex] = mtype
    return mapping


def parse_titles_txt(cstrike_dir: str) -> Dict[str, str]:
    titles_path = os.path.join(cstrike_dir, "titles.txt")
    titles: Dict[str, str] = {}
    if not os.path.exists(titles_path):
        return titles
    lines = open(titles_path, "r", encoding="latin1", errors="ignore").read().splitlines()
    i = 0
    while i < len(lines):
        ln = lines[i].strip()
        if not ln or ln.startswith("//") or ln.startswith("$"):
            i += 1
            continue
        if i + 1 < len(lines) and lines[i + 1].strip() == "{":
            key = ln
            i += 2
            body = []
            while i < len(lines) and lines[i].strip() != "}":
                body.append(lines[i].strip())
                i += 1
            titles[key] = " ".join(body).strip()
        i += 1
    return titles


def build_weapons_database(maxspeeds: Dict[str, List[float]], descs: Dict[str, str], weapon_hud: dict) -> dict:
    """
    Builds the complete Counter-Strike 1.5 Retail 26-weapon database combining
    cs_i386.so GetMaxSpeed constants, exact CS 1.5 weapon firing/damage/economy parameters,
    VGUI portraits, viewmodels/worldmodels, and authentic sound paths.
    """
    def ms(cls: str, default_unzoomed: float) -> Tuple[float, float]:
        vals = maxspeeds.get(cls, [])
        if len(vals) >= 2:
            # In cs_i386.so: [zoomed, unzoomed]
            return vals[1], vals[0]
        if len(vals) == 1:
            return vals[0], vals[0]
        return default_unzoomed, default_unzoomed

    # Base CS 1.5 Retail specifications
    raw_weapons = [
        # --- KNIFE (Slot 3) ---
        {
            "id": "knife", "cls": "CKnife", "name": "Knife", "slot": 3, "buy_cat": 0, "buy_num": 0,
            "team": "ANY", "price": 0, "clip_size": -1, "max_ammo": 0, "ammo_type": "none",
            "damage": 20, "alt_damage": 65, "backstab_damage": 195, "armor_ratio": 1.7,
            "cycle_time": 0.4, "alt_cycle_time": 1.1, "range": 48.0, "alt_range": 32.0,
            "range_modifier": 1.0, "penetration": 0, "reload_time": 0.0, "automatic": True,
            "recoil_up": 0.0, "recoil_lat": 0.0, "spread_base": 0.0, "spread_move": 0.0,
            "v_model": "v_knife", "w_model": "w_knife", "p_model": "p_knife", "vgui": "",
            "fire_sounds": ["weapons/knife_slash1.wav", "weapons/knife_slash2.wav"],
            "hit_sounds": ["weapons/knife_hit1.wav", "weapons/knife_hit2.wav", "weapons/knife_hit3.wav"],
            "wall_sound": "weapons/knife_hitwall1.wav", "stab_sound": "weapons/knife_stab.wav",
            "deploy_sound": "weapons/knife_deploy1.wav",
        },
        # --- PISTOLS (Slot 2, Buy Cat 1) ---
        {
            "id": "usp", "cls": "CUSP", "name": "H&K USP .45 Tactical", "slot": 2, "buy_cat": 1, "buy_num": 1,
            "team": "ANY", "price": 500, "clip_size": 12, "max_ammo": 100, "ammo_type": "45acp",
            "damage": 34, "silenced_damage": 30, "armor_ratio": 1.0,
            "cycle_time": 0.15, "range": 4096.0, "range_modifier": 0.79, "penetration": 1,
            "reload_time": 2.7, "automatic": False, "silencer": True,
            "recoil_up": 2.0, "recoil_lat": 0.4, "spread_base": 0.01, "spread_move": 0.08,
            "v_model": "v_usp", "w_model": "w_usp", "p_model": "p_usp", "vgui": "640_usp",
            "fire_sounds": ["weapons/usp_unsil-1.wav"],
            "silenced_sounds": ["weapons/usp1.wav", "weapons/usp2.wav"],
            "reload_sound": "weapons/usp_clipin.wav", "deploy_sound": "weapons/usp_sliderelease.wav",
        },
        {
            "id": "glock18", "cls": "CGLOCK18", "name": "Glock 18C Select Fire", "slot": 2, "buy_cat": 1, "buy_num": 2,
            "team": "ANY", "price": 400, "clip_size": 20, "max_ammo": 120, "ammo_type": "9mm",
            "damage": 25, "armor_ratio": 1.05,
            "cycle_time": 0.15, "range": 4096.0, "range_modifier": 0.75, "penetration": 1,
            "reload_time": 2.2, "automatic": False, "burst": True,
            "recoil_up": 1.6, "recoil_lat": 0.35, "spread_base": 0.012, "spread_move": 0.07,
            "v_model": "v_glock18", "w_model": "w_glock18", "p_model": "p_glock18", "vgui": "640_glock18",
            "fire_sounds": ["weapons/glock18-2.wav"],
            "burst_sound": "weapons/glock18-1.wav",
            "reload_sound": "weapons/clipin1.wav", "deploy_sound": "weapons/sliderelease1.wav",
        },
        {
            "id": "deagle", "cls": "CDEAGLE", "name": "Desert Eagle .50 AE", "slot": 2, "buy_cat": 1, "buy_num": 3,
            "team": "ANY", "price": 650, "clip_size": 7, "max_ammo": 35, "ammo_type": "50ae",
            "damage": 54, "armor_ratio": 1.5,
            "cycle_time": 0.225, "range": 4096.0, "range_modifier": 0.81, "penetration": 2,
            "reload_time": 2.2, "automatic": False,
            "recoil_up": 4.2, "recoil_lat": 0.8, "spread_base": 0.008, "spread_move": 0.11,
            "v_model": "v_deagle", "w_model": "w_deagle", "p_model": "p_deagle", "vgui": "640_deagle",
            "fire_sounds": ["weapons/deagle-1.wav", "weapons/deagle-2.wav"],
            "reload_sound": "weapons/de_clipin.wav", "deploy_sound": "weapons/de_deploy.wav",
        },
        {
            "id": "p228", "cls": "CP228", "name": "SIG P228", "slot": 2, "buy_cat": 1, "buy_num": 4,
            "team": "ANY", "price": 600, "clip_size": 13, "max_ammo": 52, "ammo_type": "357sig",
            "damage": 32, "armor_ratio": 1.25,
            "cycle_time": 0.15, "range": 4096.0, "range_modifier": 0.8, "penetration": 1,
            "reload_time": 2.7, "automatic": False,
            "recoil_up": 2.0, "recoil_lat": 0.45, "spread_base": 0.011, "spread_move": 0.08,
            "v_model": "v_p228", "w_model": "w_p228", "p_model": "p_p228", "vgui": "640_p228",
            "fire_sounds": ["weapons/p228-1.wav"],
            "reload_sound": "weapons/p228_clipin.wav", "deploy_sound": "weapons/p228_sliderelease.wav",
        },
        {
            "id": "elite", "cls": "CELITE", "name": "Dual Beretta 96G Elite", "slot": 2, "buy_cat": 1, "buy_num": 5,
            "team": "T", "price": 1000, "clip_size": 30, "max_ammo": 120, "ammo_type": "9mm",
            "damage": 36, "armor_ratio": 1.05,
            "cycle_time": 0.12, "range": 4096.0, "range_modifier": 0.75, "penetration": 1,
            "reload_time": 4.5, "automatic": False,
            "recoil_up": 2.1, "recoil_lat": 0.6, "spread_base": 0.014, "spread_move": 0.09,
            "v_model": "v_elite", "w_model": "w_elite", "p_model": "p_elite", "vgui": "640_elite",
            "fire_sounds": ["weapons/elite_fire.wav"],
            "reload_sound": "weapons/elite_rightclipin.wav", "deploy_sound": "weapons/elite_deploy.wav",
        },
        {
            "id": "fiveseven", "cls": "CFiveSeven", "name": "FN Five-SeveN", "slot": 2, "buy_cat": 1, "buy_num": 6,
            "team": "CT", "price": 750, "clip_size": 20, "max_ammo": 100, "ammo_type": "57mm",
            "damage": 25, "armor_ratio": 1.5,
            "cycle_time": 0.15, "range": 4096.0, "range_modifier": 0.885, "penetration": 1,
            "reload_time": 2.7, "automatic": False,
            "recoil_up": 1.8, "recoil_lat": 0.4, "spread_base": 0.01, "spread_move": 0.075,
            "v_model": "v_fiveseven", "w_model": "w_fiveseven", "p_model": "p_fiveseven", "vgui": "640_fiveseven",
            "fire_sounds": ["weapons/fiveseven-1.wav"],
            "reload_sound": "weapons/fiveseven_clipin.wav", "deploy_sound": "weapons/fiveseven_sliderelease.wav",
        },
        # --- SHOTGUNS (Slot 1, Buy Cat 2) ---
        {
            "id": "m3", "cls": "CM3", "name": "Benelli M3 Super 90", "slot": 1, "buy_cat": 2, "buy_num": 1,
            "team": "ANY", "price": 1700, "clip_size": 8, "max_ammo": 32, "ammo_type": "buckshot",
            "damage": 20, "pellets": 9, "armor_ratio": 1.0,
            "cycle_time": 0.875, "range": 3000.0, "range_modifier": 0.70, "penetration": 0,
            "reload_time": 3.2, "automatic": True, "shotgun_reload": True,
            "recoil_up": 5.0, "recoil_lat": 1.2, "spread_base": 0.067, "spread_move": 0.08,
            "v_model": "v_m3", "w_model": "w_m3", "p_model": "p_m3", "vgui": "640_m3",
            "fire_sounds": ["weapons/m3-1.wav"],
            "reload_sound": "weapons/m3_insertshell.wav", "deploy_sound": "weapons/m3_pump.wav",
        },
        {
            "id": "xm1014", "cls": "CXM1014", "name": "Benelli XM1014", "slot": 1, "buy_cat": 2, "buy_num": 2,
            "team": "ANY", "price": 3000, "clip_size": 7, "max_ammo": 32, "ammo_type": "buckshot",
            "damage": 20, "pellets": 6, "armor_ratio": 1.0,
            "cycle_time": 0.25, "range": 3000.0, "range_modifier": 0.70, "penetration": 0,
            "reload_time": 2.8, "automatic": True, "shotgun_reload": True,
            "recoil_up": 3.8, "recoil_lat": 1.0, "spread_base": 0.072, "spread_move": 0.09,
            "v_model": "v_xm1014", "w_model": "w_xm1014", "p_model": "p_xm1014", "vgui": "640_xm1014",
            "fire_sounds": ["weapons/xm1014-1.wav"],
            "reload_sound": "weapons/m3_insertshell.wav", "deploy_sound": "weapons/m3_pump.wav",
        },
        # --- SMGS (Slot 1, Buy Cat 3) ---
        {
            "id": "mp5navy", "cls": "CMP5N", "name": "H&K MP5-Navy", "slot": 1, "buy_cat": 3, "buy_num": 1,
            "team": "ANY", "price": 1500, "clip_size": 30, "max_ammo": 120, "ammo_type": "9mm",
            "damage": 26, "armor_ratio": 1.0,
            "cycle_time": 0.08, "range": 4096.0, "range_modifier": 0.84, "penetration": 1,
            "reload_time": 2.63, "automatic": True,
            "recoil_up": 1.35, "recoil_lat": 0.45, "spread_base": 0.012, "spread_move": 0.045,
            "v_model": "v_mp5", "w_model": "w_mp5", "p_model": "p_mp5", "vgui": "640_mp5",
            "fire_sounds": ["weapons/mp5-1.wav", "weapons/mp5-2.wav"],
            "reload_sound": "weapons/mp5_clipin.wav", "deploy_sound": "weapons/mp5_slideback.wav",
            "class_key": "mp5",
        },
        {
            "id": "tmp", "cls": "CTMP", "name": "Steyr Tactical Machine Pistol", "slot": 1, "buy_cat": 3, "buy_num": 2,
            "team": "CT", "price": 1250, "clip_size": 30, "max_ammo": 120, "ammo_type": "9mm",
            "damage": 20, "armor_ratio": 1.0,
            "cycle_time": 0.07, "range": 4096.0, "range_modifier": 0.85, "penetration": 1,
            "reload_time": 2.12, "automatic": True, "quiet": True,
            "recoil_up": 1.15, "recoil_lat": 0.4, "spread_base": 0.015, "spread_move": 0.04,
            "v_model": "v_tmp", "w_model": "w_tmp", "p_model": "p_tmp", "vgui": "640_tmp",
            "fire_sounds": ["weapons/tmp-1.wav", "weapons/tmp-2.wav"],
            "reload_sound": "weapons/clipin1.wav", "deploy_sound": "weapons/slideback1.wav",
        },
        {
            "id": "p90", "cls": "CP90", "name": "FN P90", "slot": 1, "buy_cat": 3, "buy_num": 3,
            "team": "ANY", "price": 2350, "clip_size": 50, "max_ammo": 100, "ammo_type": "57mm",
            "damage": 21, "armor_ratio": 1.5,
            "cycle_time": 0.066, "range": 4096.0, "range_modifier": 0.885, "penetration": 1,
            "reload_time": 3.4, "automatic": True,
            "recoil_up": 1.3, "recoil_lat": 0.5, "spread_base": 0.013, "spread_move": 0.05,
            "v_model": "v_p90", "w_model": "w_p90", "p_model": "p_p90", "vgui": "640_p90",
            "fire_sounds": ["weapons/p90-1.wav"],
            "reload_sound": "weapons/p90_clipin.wav", "deploy_sound": "weapons/p90_boltpull.wav",
        },
        {
            "id": "mac10", "cls": "CMAC10", "name": "Ingram MAC-10", "slot": 1, "buy_cat": 3, "buy_num": 4,
            "team": "T", "price": 1400, "clip_size": 30, "max_ammo": 100, "ammo_type": "45acp",
            "damage": 29, "armor_ratio": 0.95,
            "cycle_time": 0.07, "range": 4096.0, "range_modifier": 0.82, "penetration": 1,
            "reload_time": 3.15, "automatic": True,
            "recoil_up": 1.55, "recoil_lat": 0.65, "spread_base": 0.018, "spread_move": 0.05,
            "v_model": "v_mac10", "w_model": "w_mac10", "p_model": "p_mac10", "vgui": "640_mac10",
            "fire_sounds": ["weapons/mac10-1.wav"],
            "reload_sound": "weapons/mac10_clipin.wav", "deploy_sound": "weapons/mac10_boltpull.wav",
        },
        {
            "id": "ump45", "cls": "CUMP45", "name": "H&K UMP45", "slot": 1, "buy_cat": 3, "buy_num": 5,
            "team": "ANY", "price": 1700, "clip_size": 25, "max_ammo": 100, "ammo_type": "45acp",
            "damage": 30, "armor_ratio": 1.0,
            "cycle_time": 0.105, "range": 4096.0, "range_modifier": 0.82, "penetration": 1,
            "reload_time": 3.5, "automatic": True,
            "recoil_up": 1.4, "recoil_lat": 0.45, "spread_base": 0.012, "spread_move": 0.045,
            "v_model": "v_ump45", "w_model": "w_ump45", "p_model": "p_ump45", "vgui": "640_ump45",
            "fire_sounds": ["weapons/ump45-1.wav"],
            "reload_sound": "weapons/ump45_clipin.wav", "deploy_sound": "weapons/ump45_boltslap.wav",
        },
        # --- RIFLES (Slot 1, Buy Cat 4) ---
        {
            "id": "ak47", "cls": "CAK47", "name": "CV-47 (AK-47)", "slot": 1, "buy_cat": 4, "buy_num": 1,
            "team": "T", "price": 2500, "clip_size": 30, "max_ammo": 90, "ammo_type": "762nato",
            "damage": 36, "armor_ratio": 1.55,
            "cycle_time": 0.0955, "range": 8192.0, "range_modifier": 0.98, "penetration": 2,
            "reload_time": 2.45, "automatic": True,
            "recoil_up": 2.45, "recoil_lat": 0.75, "spread_base": 0.006, "spread_move": 0.095,
            "v_model": "v_ak47", "w_model": "w_ak47", "p_model": "p_ak47", "vgui": "640_ak47",
            "fire_sounds": ["weapons/ak47-1.wav", "weapons/ak47-2.wav"],
            "reload_sound": "weapons/ak47_clipin.wav", "deploy_sound": "weapons/ak47_boltpull.wav",
        },
        {
            "id": "sg552", "cls": "CSG552", "name": "SIG SG-552 Commando", "slot": 1, "buy_cat": 4, "buy_num": 2,
            "team": "T", "price": 3500, "clip_size": 30, "max_ammo": 90, "ammo_type": "556nato",
            "damage": 33, "armor_ratio": 1.4,
            "cycle_time": 0.0825, "zoomed_cycle_time": 0.135, "range": 8192.0, "range_modifier": 0.955, "penetration": 2,
            "reload_time": 3.0, "automatic": True, "zoom_fovs": [55],
            "recoil_up": 2.0, "recoil_lat": 0.65, "spread_base": 0.006, "spread_move": 0.085,
            "v_model": "v_sg552", "w_model": "w_sg552", "p_model": "p_sg552", "vgui": "640_sg552",
            "fire_sounds": ["weapons/sg552-1.wav", "weapons/sg552-2.wav"],
            "reload_sound": "weapons/sg552_clipin.wav", "deploy_sound": "weapons/sg552_boltpull.wav",
        },
        {
            "id": "m4a1", "cls": "CM4A1", "name": "Colt M4A1 Carbine", "slot": 1, "buy_cat": 4, "buy_num": 3,
            "team": "CT", "price": 3100, "clip_size": 30, "max_ammo": 90, "ammo_type": "556nato",
            "damage": 32, "silenced_damage": 33, "armor_ratio": 1.4,
            "cycle_time": 0.0875, "range": 8192.0, "range_modifier": 0.97, "penetration": 2,
            "reload_time": 3.05, "automatic": True, "silencer": True,
            "recoil_up": 1.85, "recoil_lat": 0.55, "spread_base": 0.005, "spread_move": 0.085,
            "v_model": "v_m4a1", "w_model": "w_m4a1", "p_model": "p_m4a1", "vgui": "640_m4a1",
            "fire_sounds": ["weapons/m4a1_unsil-1.wav", "weapons/m4a1_unsil-2.wav"],
            "silenced_sounds": ["weapons/m4a1-1.wav"],
            "reload_sound": "weapons/m4a1_clipin.wav", "deploy_sound": "weapons/m4a1_deploy.wav",
        },
        {
            "id": "aug", "cls": "CAUG", "name": "Steyr AUG", "slot": 1, "buy_cat": 4, "buy_num": 4,
            "team": "CT", "price": 3500, "clip_size": 30, "max_ammo": 90, "ammo_type": "556nato",
            "damage": 32, "armor_ratio": 1.4,
            "cycle_time": 0.0825, "zoomed_cycle_time": 0.135, "range": 8192.0, "range_modifier": 0.96, "penetration": 2,
            "reload_time": 3.3, "automatic": True, "zoom_fovs": [55],
            "recoil_up": 1.8, "recoil_lat": 0.55, "spread_base": 0.005, "spread_move": 0.08,
            "v_model": "v_aug", "w_model": "w_aug", "p_model": "p_aug", "vgui": "640_aug",
            "fire_sounds": ["weapons/aug-1.wav"],
            "reload_sound": "weapons/aug_clipin.wav", "deploy_sound": "weapons/aug_forearm.wav",
        },
        {
            "id": "scout", "cls": "CSCOUT", "name": "Steyr Scout", "slot": 1, "buy_cat": 4, "buy_num": 5,
            "team": "ANY", "price": 2750, "clip_size": 10, "max_ammo": 90, "ammo_type": "762nato",
            "damage": 75, "armor_ratio": 1.7,
            "cycle_time": 1.25, "range": 8192.0, "range_modifier": 0.98, "penetration": 3,
            "reload_time": 2.0, "automatic": False, "sniper_scope": True, "zoom_fovs": [40, 15],
            "recoil_up": 3.2, "recoil_lat": 0.3, "spread_base": 0.001, "spread_unscoped": 0.05, "spread_move": 0.09,
            "v_model": "v_scout", "w_model": "w_scout", "p_model": "p_scout", "vgui": "640_scout",
            "fire_sounds": ["weapons/scout_fire-1.wav"],
            "reload_sound": "weapons/scout_clipin.wav", "deploy_sound": "weapons/scout_bolt.wav",
        },
        {
            "id": "awp", "cls": "CAWP", "name": "AI Arctic Warfare/Magnum", "slot": 1, "buy_cat": 4, "buy_num": 6,
            "team": "ANY", "price": 4750, "clip_size": 10, "max_ammo": 30, "ammo_type": "338magnum",
            "damage": 115, "armor_ratio": 1.95,
            "cycle_time": 1.45, "range": 8192.0, "range_modifier": 0.99, "penetration": 3,
            "reload_time": 2.9, "automatic": False, "sniper_scope": True, "zoom_fovs": [40, 10],
            "recoil_up": 5.5, "recoil_lat": 0.5, "spread_base": 0.0005, "spread_unscoped": 0.085, "spread_move": 0.14,
            "v_model": "v_awp", "w_model": "w_awp", "p_model": "p_awp", "vgui": "640_awp",
            "fire_sounds": ["weapons/awp1.wav"],
            "reload_sound": "weapons/awp_clipin.wav", "deploy_sound": "weapons/awp_deploy.wav",
        },
        {
            "id": "g3sg1", "cls": "CG3SG1", "name": "H&K G3/SG-1 Sniper Rifle", "slot": 1, "buy_cat": 4, "buy_num": 7,
            "team": "T", "price": 5000, "clip_size": 20, "max_ammo": 90, "ammo_type": "762nato",
            "damage": 80, "armor_ratio": 1.65,
            "cycle_time": 0.25, "range": 8192.0, "range_modifier": 0.98, "penetration": 3,
            "reload_time": 3.5, "automatic": True, "sniper_scope": True, "zoom_fovs": [40, 15],
            "recoil_up": 2.8, "recoil_lat": 0.6, "spread_base": 0.002, "spread_unscoped": 0.055, "spread_move": 0.11,
            "v_model": "v_g3sg1", "w_model": "w_g3sg1", "p_model": "p_g3sg1", "vgui": "640_g3sg1",
            "fire_sounds": ["weapons/g3sg1-1.wav"],
            "reload_sound": "weapons/g3sg1_clipin.wav", "deploy_sound": "weapons/g3sg1_slide.wav",
        },
        {
            "id": "sg550", "cls": "CSG550", "name": "SIG SG-550 Sniper", "slot": 1, "buy_cat": 4, "buy_num": 8,
            "team": "CT", "price": 4200, "clip_size": 30, "max_ammo": 90, "ammo_type": "556nato",
            "damage": 70, "armor_ratio": 1.45,
            "cycle_time": 0.25, "range": 8192.0, "range_modifier": 0.98, "penetration": 2,
            "reload_time": 3.35, "automatic": True, "sniper_scope": True, "zoom_fovs": [40, 15],
            "recoil_up": 2.4, "recoil_lat": 0.5, "spread_base": 0.002, "spread_unscoped": 0.05, "spread_move": 0.10,
            "v_model": "v_sg550", "w_model": "w_sg550", "p_model": "p_sg550", "vgui": "640_sg550",
            "fire_sounds": ["weapons/sg550-1.wav"],
            "reload_sound": "weapons/sg550_clipin.wav", "deploy_sound": "weapons/sg550_boltpull.wav",
        },
        # --- MACHINE GUN (Slot 1, Buy Cat 5) ---
        {
            "id": "m249", "cls": "CM249", "name": "FN M249 Para", "slot": 1, "buy_cat": 5, "buy_num": 1,
            "team": "ANY", "price": 5750, "clip_size": 100, "max_ammo": 200, "ammo_type": "556natobox",
            "damage": 32, "armor_ratio": 1.5,
            "cycle_time": 0.10, "range": 8192.0, "range_modifier": 0.97, "penetration": 2,
            "reload_time": 4.7, "automatic": True,
            "recoil_up": 2.35, "recoil_lat": 0.85, "spread_base": 0.012, "spread_move": 0.095,
            "v_model": "v_m249", "w_model": "w_m249", "p_model": "p_m249", "vgui": "640_m249",
            "fire_sounds": ["weapons/m249-1.wav", "weapons/m249-2.wav"],
            "reload_sound": "weapons/m249_boxin.wav", "deploy_sound": "weapons/m249_chain.wav",
        },
        # --- GRENADES (Slot 4, Buy Cat 8) ---
        {
            "id": "flashbang", "cls": "CFlashbang", "name": "Flashbang", "slot": 4, "buy_cat": 8, "buy_num": 3,
            "team": "ANY", "price": 200, "clip_size": 1, "max_ammo": 2, "ammo_type": "flashbang",
            "damage": 0, "armor_ratio": 1.0, "cycle_time": 1.0, "range": 1500.0,
            "range_modifier": 1.0, "penetration": 0, "reload_time": 0.0, "automatic": False, "grenade": True,
            "v_model": "v_flashbang", "w_model": "w_flashbang", "p_model": "p_flashbang", "vgui": "640_flashbang",
            "fire_sounds": ["weapons/pinpull.wav"],
            "explode_sounds": ["weapons/flashbang-1.wav", "weapons/flashbang-2.wav"],
            "bounce_sounds": ["weapons/grenade_hit1.wav", "weapons/grenade_hit2.wav", "weapons/grenade_hit3.wav"],
        },
        {
            "id": "hegrenade", "cls": "CHEGrenade", "name": "HE Grenade", "slot": 4, "buy_cat": 8, "buy_num": 4,
            "team": "ANY", "price": 300, "clip_size": 1, "max_ammo": 1, "ammo_type": "hegrenade",
            "damage": 98, "armor_ratio": 1.2, "cycle_time": 1.0, "range": 350.0,
            "range_modifier": 1.0, "penetration": 0, "reload_time": 0.0, "automatic": False, "grenade": True,
            "v_model": "v_hegrenade", "w_model": "w_hegrenade", "p_model": "p_hegrenade", "vgui": "640_hegrenade",
            "fire_sounds": ["weapons/pinpull.wav"],
            "explode_sounds": ["weapons/hegrenade-1.wav", "weapons/hegrenade-2.wav"],
            "bounce_sounds": ["weapons/he_bounce-1.wav"],
        },
        {
            "id": "smokegrenade", "cls": "CSmokeGrenade", "name": "Smoke Grenade", "slot": 4, "buy_cat": 8, "buy_num": 5,
            "team": "ANY", "price": 300, "clip_size": 1, "max_ammo": 1, "ammo_type": "smokegrenade",
            "damage": 0, "armor_ratio": 1.0, "cycle_time": 1.0, "range": 280.0,
            "range_modifier": 1.0, "penetration": 0, "reload_time": 0.0, "automatic": False, "grenade": True,
            "v_model": "v_smokegrenade", "w_model": "w_smokegrenade", "p_model": "p_smokegrenade", "vgui": "640_smokegrenade",
            "fire_sounds": ["weapons/pinpull.wav"],
            "explode_sounds": ["weapons/sg_explode.wav"],
            "bounce_sounds": ["weapons/grenade_hit1.wav"],
        },
        # --- C4 EXPLOSIVE (Slot 5) ---
        {
            "id": "c4", "cls": "CC4", "name": "C4 Plastic Explosive", "slot": 5, "buy_cat": 0, "buy_num": 0,
            "team": "T", "price": 0, "clip_size": 1, "max_ammo": 1, "ammo_type": "c4",
            "damage": 500, "armor_ratio": 1.0, "cycle_time": 0.3, "range": 1750.0,
            "range_modifier": 1.0, "penetration": 0, "reload_time": 0.0, "automatic": False,
            "v_model": "v_c4", "w_model": "w_backpack", "planted_model": "w_c4", "p_model": "p_c4", "vgui": "",
            "fire_sounds": ["weapons/c4_click.wav"],
            "plant_sound": "weapons/c4_plant.wav",
            "explode_sounds": ["weapons/c4_explode1.wav"],
            "beep_sounds": [
                "weapons/c4_beep1.wav", "weapons/c4_beep2.wav", "weapons/c4_beep3.wav",
                "weapons/c4_beep4.wav", "weapons/c4_beep5.wav",
            ],
        },
    ]

    weapons_out = {}
    for w in raw_weapons:
        unzoomed, zoomed = ms(w["cls"], 250.0)
        w["max_speed"] = unzoomed
        w["zoomed_speed"] = zoomed
        ckey = w.get("class_key", w["id"])
        w["description"] = descs.get(ckey, "")
        w["hud"] = weapon_hud.get(f"weapon_{w['id']}", {})
        weapons_out[w["id"]] = w

    ammo_types = {
        "9mm": {"name": "9x19mm Parabellum", "clip_amount": 30, "max": 120, "price": 20},
        "45acp": {"name": ".45 ACP", "clip_amount": 12, "max": 100, "price": 25},
        "50ae": {"name": ".50 Action Express", "clip_amount": 7, "max": 35, "price": 40},
        "357sig": {"name": ".357 SIG", "clip_amount": 13, "max": 52, "price": 50},
        "57mm": {"name": "5.7x28mm FN", "clip_amount": 50, "max": 100, "price": 50},
        "buckshot": {"name": "12 Gauge Buckshot", "clip_amount": 8, "max": 32, "price": 65},
        "556nato": {"name": "5.56x45mm NATO", "clip_amount": 30, "max": 90, "price": 60},
        "556natobox": {"name": "5.56mm Belt Box", "clip_amount": 30, "max": 200, "price": 60},
        "762nato": {"name": "7.62x51mm NATO", "clip_amount": 30, "max": 90, "price": 80},
        "338magnum": {"name": ".338 Lapua Magnum", "clip_amount": 10, "max": 30, "price": 125},
    }

    equipment = {
        "kevlar": {
            "id": "kevlar", "name": "Kevlar Vest", "buy_cat": 8, "buy_num": 1,
            "team": "ANY", "price": 650, "description": descs.get("kevlar", ""),
            "sound": "items/kevlar.wav",
        },
        "kevlar_helmet": {
            "id": "kevlar_helmet", "name": "Kevlar + Helmet", "buy_cat": 8, "buy_num": 2,
            "team": "ANY", "price": 1000, "upgrade_price": 350,
            "description": descs.get("kevlar_helmet", ""), "sound": "items/tr_kevlar.wav",
        },
        "defuser": {
            "id": "defuser", "name": "Defusal Kit", "buy_cat": 8, "buy_num": 6,
            "team": "CT", "price": 200, "description": descs.get("defuser", ""),
            "w_model": "w_thighpack",
        },
        "nightvision": {
            "id": "nightvision", "name": "NightVision Goggles", "buy_cat": 8, "buy_num": 7,
            "team": "ANY", "price": 1250, "description": descs.get("nightvision", ""),
            "sound": "items/equip_nvg.wav", "on_sound": "items/nvg_on.wav", "off_sound": "items/nvg_off.wav",
        },
    }

    economy = {
        "start_money": 800,
        "max_money": 16000,
        "kill_reward": 300,
        "teamkill_penalty": -3300,
        "hostage_touch_reward": 150,
        "hostage_rescue_reward": 1000,
        "round_win_elimination": 3250,
        "round_win_bomb_exploded": 3500,
        "round_win_bomb_defused": 3250,
        "round_win_time_ct_de": 3250,
        "round_loss_base": 1400,
        "round_loss_streak_bonus": 500,
        "round_loss_max": 3400,
        "bomb_planted_team_bonus": 800,
    }

    return {"weapons": weapons_out, "ammo": ammo_types, "equipment": equipment, "economy": economy}


def build_classes_database(descs: Dict[str, str]) -> dict:
    return {
        "T": [
            {"id": "terror", "num": 1, "name": "Phoenix Connexion", "vgui": "640_terror", "model": "terror", "description": descs.get("terror", "")},
            {"id": "leet", "num": 2, "name": "L337 Krew", "vgui": "640_leet", "model": "leet", "description": descs.get("leet", "")},
            {"id": "arctic", "num": 3, "name": "Arctic Avengers", "vgui": "640_arctic", "model": "arctic", "description": descs.get("arctic", "")},
            {"id": "guerilla", "num": 4, "name": "Guerilla Warfare", "vgui": "640_guerilla", "model": "guerilla", "description": descs.get("guerilla", "")},
        ],
        "CT": [
            {"id": "urban", "num": 1, "name": "Seal Team 6", "vgui": "640_urban", "model": "urban", "description": descs.get("urban", "")},
            {"id": "gsg9", "num": 2, "name": "GSG-9", "vgui": "640_gsg9", "model": "gsg9", "description": descs.get("gsg9", "")},
            {"id": "sas", "num": 3, "name": "SAS", "vgui": "640_sas", "model": "sas", "description": descs.get("sas", "")},
            {"id": "gign", "num": 4, "name": "GIGN", "vgui": "640_gign", "model": "gign", "description": descs.get("gign", "")},
        ],
        "VIP": {"id": "vip", "name": "VIP", "vgui": "640_vip", "model": "vip"},
    }


def build_radio_database() -> dict:
    return {
        "radio1": {
            "title": "Radio Commands (Z)",
            "items": [
                {"num": 1, "label": "Cover Me", "sound": "radio/ct_coverme.wav", "action": "cover_me"},
                {"num": 2, "label": "You Take the Point", "sound": "radio/takepoint.wav", "action": "take_point"},
                {"num": 3, "label": "Hold This Position", "sound": "radio/position.wav", "action": "hold_position"},
                {"num": 4, "label": "Regroup Team", "sound": "radio/regroup.wav", "action": "regroup"},
                {"num": 5, "label": "Follow Me", "sound": "radio/followme.wav", "action": "follow_me"},
                {"num": 6, "label": "Taking Fire, Need Assistance", "sound": "radio/fireassis.wav", "action": "need_assist"},
            ],
        },
        "radio2": {
            "title": "Group Radio Commands (X)",
            "items": [
                {"num": 1, "label": "Go, Go, Go!", "sound": "radio/com_go.wav", "action": "go"},
                {"num": 2, "label": "Team, Fall Back!", "sound": "radio/fallback.wav", "action": "fallback"},
                {"num": 3, "label": "Stick Together, Team", "sound": "radio/sticktog.wav", "action": "stick_together"},
                {"num": 4, "label": "Get in Position and Wait", "sound": "radio/com_getinpos.wav", "action": "get_in_pos"},
                {"num": 5, "label": "Storm the Front!", "sound": "radio/stormfront.wav", "action": "storm_front"},
                {"num": 6, "label": "Report In, Team", "sound": "radio/com_reportin.wav", "action": "report_in"},
            ],
        },
        "radio3": {
            "title": "Report Radio Commands (C)",
            "items": [
                {"num": 1, "label": "Affirmative / Roger", "sound": "radio/roger.wav", "action": "roger"},
                {"num": 2, "label": "Enemy Spotted", "sound": "radio/ct_enemys.wav", "action": "enemy_spotted"},
                {"num": 3, "label": "Need Backup", "sound": "radio/ct_backup.wav", "action": "need_backup"},
                {"num": 4, "label": "Sector Clear", "sound": "radio/clear.wav", "action": "sector_clear"},
                {"num": 5, "label": "I'm in Position", "sound": "radio/ct_inpos.wav", "action": "in_position"},
                {"num": 6, "label": "Reporting In", "sound": "radio/ct_reportingin.wav", "action": "reporting_in"},
                {"num": 7, "label": "She's Gonna Blow!", "sound": "radio/blow.wav", "action": "gonna_blow"},
                {"num": 8, "label": "Negative", "sound": "radio/negative.wav", "action": "negative"},
                {"num": 9, "label": "Enemy Down", "sound": "radio/enemydown.wav", "action": "enemy_down"},
            ],
        },
    }


def run_binary_stats_extraction(cstrike_dir: str, out_data_dir: str) -> None:
    os.makedirs(out_data_dir, exist_ok=True)
    so_path = os.path.join(cstrike_dir, "dlls", "cs_i386.so")
    maxspeeds = extract_elf_maxspeeds(so_path)
    descs = parse_class_descriptions(os.path.join(cstrike_dir, "classes"))
    hud_data = parse_hud_txt(os.path.join(cstrike_dir, "sprites"))
    materials = parse_materials_txt(os.path.join(cstrike_dir, "sound"))
    titles = parse_titles_txt(cstrike_dir)

    weapons_db = build_weapons_database(maxspeeds, descs, hud_data["weapons"])
    classes_db = build_classes_database(descs)
    radio_db = build_radio_database()

    with open(os.path.join(out_data_dir, "weapons.json"), "w", encoding="utf-8") as f:
        json.dump(weapons_db, f, indent=2)
    with open(os.path.join(out_data_dir, "classes.json"), "w", encoding="utf-8") as f:
        json.dump(classes_db, f, indent=2)
    with open(os.path.join(out_data_dir, "hud_sprites.json"), "w", encoding="utf-8") as f:
        json.dump(hud_data, f, indent=2)
    with open(os.path.join(out_data_dir, "materials.json"), "w", encoding="utf-8") as f:
        json.dump(materials, f, indent=2)
    with open(os.path.join(out_data_dir, "radio.json"), "w", encoding="utf-8") as f:
        json.dump(radio_db, f, indent=2)
    with open(os.path.join(out_data_dir, "titles.json"), "w", encoding="utf-8") as f:
        json.dump(titles, f, indent=2)

    print(
        f"[binary_stats] Extracted {len(weapons_db['weapons'])} weapons "
        f"(ELF GetMaxSpeed matched: {len(maxspeeds)}), "
        f"{len(hud_data['hud'])} HUD rects, {len(materials)} material sounds."
    )
