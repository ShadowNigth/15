# Source weapon assets → Godot

## Current archi build (43 slots)

Primary model, texture, inventory-icon and animation-foley source:
<https://github.com/ShadowNigth/archi> (extracted CS2GO Director's Cut MDL/VTF/WAV).
Dedicated weapon audio is supplemented from Source2Sounds/cs2 as documented below.
The installed set replaces all 27 classic slots and adds P2000, CZ75, R8, Tec-9,
FAMAS, Galil, M4A4, MAG-7, Sawed-Off, Negev, PP-Bizon, MP7, Zeus, Decoy, Molotov
and Incendiary. All 129 shipped weapon GLBs are self-contained; neither archi nor
SourceIO is needed by Godot.

```bash
# External source and build-time dependencies (numpy, pillow, scipy, srctools, SourceIO).
git clone --filter=blob:none --no-checkout --depth 1 \
    https://github.com/ShadowNigth/archi.git /tmp/archi
git -C /tmp/archi sparse-checkout set --no-cone \
    '/*/EXTRAIDOS/' '/*/*/EXTRAIDOS/' '/*/*/*/EXTRAIDOS/' '/sound/'
git -C /tmp/archi checkout
git clone --depth 1 https://github.com/REDxEYE/SourceIO.git /tmp/SourceIO

# Keep the previous weapon directory as the rigid world-placement reference and
# as the source of the existing CT arms. Build into a separate inspection directory.
PYTHONPATH=/tmp:. python -m tools.source.build_archi_weapons \
    /tmp/archi /path/to/previous/weapons /path/to/previous/v_ak47.glb /tmp/archi_build

# Validate finite geometry/animations and render every corrected idle pose.
PYTHONPATH=/tmp:. python -m tools.source.validate_archi_build \
    /tmp/archi_build /tmp/archi_preview

# Choose ONE installation route. Full roster installation (for new slots/audio):
python -m tools.source.install_archi_weapons /tmp/archi_build /tmp/archi

# OR material-only repair (run INSTEAD of the full installer above). This preserves
# every non-image bufferView (geometry, skins and all animation clips) byte-for-byte.
python -m tools.source.patch_archi_materials /tmp/archi_build/weapons
```

`ArchiSounds` preserves the original PCM samples while normalizing malformed RIFF
container sizes and word alignment. Animation events retain their source timing;
C4 cycles through the seven real key-press takes. The elite P/W conversion filters
out the intentionally distant left pistol from the source buy-menu pose.

### Dedicated CS2 audio, normal sizing and presentation refinements

Archi does not ship a distinct firing recording for every added weapon. The current
installation supplements it with 130 authentic 16-bit WAVs from
<https://github.com/Source2Sounds/cs2>; no firing sample is shared by two weapon IDs.
In particular, M4A4 uses `m4a1_01..04`, while unsuppressed M4A1-S uses the distinct
`m4a1_us_01..04` family. The installer also replaces the knife/Zeus and incendiary
placeholders and 41 draw/reload/pump/pin events with dedicated recordings. Source
MP3 foley is decoded to PCM16 WAV with the build-only `miniaudio` dependency.

```bash
git clone --filter=blob:none --no-checkout --depth 1 \
    https://github.com/Source2Sounds/cs2.git /tmp/cs2
git -C /tmp/cs2 sparse-checkout set /sounds/weapons/
git -C /tmp/cs2 checkout
python -m pip install miniaudio
python -m tools.source.install_cs2_weapon_sounds /tmp/cs2 /home/user/15
python -m tools.source.calibrate_weapon_world_scale /home/user/15
```

Normal `world_scale` is `1.0` for the 37 firearms/tools and `0.90` for the six
grenades, shared by hand, dropped, thrown and planted presentations. The default
calibration command restores those accepted values. Its optional `--calibrate`
mode retains the experimental length-fitting table, but that pass made weapons
too small and is not the shipping configuration. View/world material styling is
separate from matte character cloth. Weapons use a glossier metallic response;
the Molotov treats both textured glass surfaces and its inner liquid as ordered
translucent layers, while bright label/rag texels retain their opacity.

#### Targeted animation repair

```bash
python -m tools.source.refine_weapon_animations /home/user/15
python -m tools.source.refine_weapon_animations --check /home/user/15
```

This appends animation accessors only in `v_m4a1.glb`, `v_usp.glb` and
`v_glock18.glb`. It stabilises the M4A1/USP gun attachment relative to the right
hand during both inspection variants, without freezing the arms. Glock firing
clips reuse the measured 47.6 mm rearward slide axis from `reload`; normal shots
return to battery and `shoot_empty` stays locked open. Semi/burst clip routing is
unchanged. Meshes, UVs, textures, materials, skins and unrelated animations are
not rebuilt; never substitute the historical one-way UV migration for this tool.

#### CS2-MultiRig review

<https://github.com/goribby/CS2-MultiRig> was reviewed at commit
`026058b2a70a55257d6b85563f27b3c31e558f26`. Its bare arms and glove exports are
potential mesh sources and include `a_idle`, inspection and icon-pose clips, but
they are not drop-in replacements: the 38-joint Source 2 rig (`hand_r`,
`finger_index_0_l`, twist bones, etc.) differs from the installed `Bip01` weapon
rig. Reuse requires bone mapping, bind-pose alignment and per-weapon inspection/
reload calibration. No MultiRig assets are installed. The repository declares no
license or redistribution grant, so permission and asset terms should be confirmed
before shipping those meshes or textures in this project's archive.

CS2 weapon VMTs commonly use `$blendtintbybasealpha` with `$color2`. The converter
bakes Source's `base * lerp(1, color2, base_alpha)` operation in linear colour space
(the pack uses the default `$blendtintcoloroverbase 0`) before opaque JPEG encoding
discards the tint mask. Unmasked `$color2` values remain
glTF base-colour factors; `GameData.get_styled_model_material()` multiplies those
factors when adjusting brightness instead of replacing them, preserving black scope
lenses and other material-specific colours on view, player and dropped world models.

Direct VVD texture coordinates and the decoded VTF pixels already use glTF's texture
orientation; applying the old SMD/Blender V inversion to these meshes mixes adjacent
atlas islands. The separate SMD arm conversion retains its own V transform. To compare
all 43 V and 86 P/W installed models directly with the original VVD coordinates:

```bash
PYTHONPATH=/tmp:. python -m tools.source.verify_archi_uvs /tmp/archi /home/user/15
```

The older CSCO/M.A.T. pipeline below is retained only for historical builds.

## Legacy CSCO build

Legacy model source: <https://github.com/ixof/Classic-Offensive> (CSCO MDL/VVD/VTX + VTF).
Legacy animation/reference source: <https://github.com/ilunp/CSGO-M.A.T> (Crowbar SMD/QC + VTF).

`mdl_reader.py` uses SourceIO only as an external build-time MDL parser. It reads the MDL
sequences/events directly and does not import SourceIO's Blender or native content-manager
modules. `build_csco_viewmodels.py` writes the v_ models and metadata;
`build_csco_worldmodels.py` writes the p_/w_ models.

```bash
# External sources and Python build dependencies (numpy, pillow, srctools, scipy).
git clone --filter=blob:none --no-checkout --depth 1 \
    https://github.com/ixof/Classic-Offensive.git /tmp/csco
cd /tmp/csco && git sparse-checkout set models/weapons materials/models/weapons scripts/items && git checkout
git clone --depth 1 https://github.com/REDxEYE/SourceIO.git /tmp/sio
mkdir -p /tmp/siopkg && ln -s /tmp/sio/library /tmp/siopkg/SourceIO
cd /home/user/15

# /tmp/ref/v_ak47.glb is a CT-armed reference; the installed weapon directory supplies
# the previous C4/grenade clips and calibrated p_/w_ placement references.
PYTHONPATH=/tmp/siopkg:. python -m tools.source.build_csco_viewmodels \
    /tmp/csco /tmp/mat/Source /tmp/ref/v_ak47.glb /tmp/csco_vm assets/models/weapons
PYTHONPATH=/tmp/siopkg:. python -m tools.source.build_csco_worldmodels \
    /tmp/csco /tmp/mat/Source assets/models/weapons /tmp/csco_world
PYTHONPATH=/tmp/siopkg:. python -m tools.source.install_csgo_viewmodels /tmp/csco_vm .
cp /tmp/csco_world/p_*.glb /tmp/csco_world/w_*.glb assets/models/weapons/
```

CSCO does **not** contain the game's weapon WAV files (they are excluded by its `.gitignore`).
Accordingly, animation sound events resolve to audio already installed in the game; no silent
placeholder sounds are generated.

### Conversion notes

* **Viewmodels**: Source→Godot transforms are in `smd_converter.py` (1/32 scale, Source
  `(x,y,z)→(-y,z,x)`, +90° yaw on roots, V inversion only on the SMD arm path, and the
  ports' 2-unit pull-back). Direct VVD coordinates remain unflipped.
  CSCO meshes/materials are combined with the CT arms and validated stock animations. CSCO's
  custom per-bone animation staging is not compatible with those stock clips; include events
  are used only when they describe the same stock animation.
* **Missing meshes**: CSCO has no elite, G3SG1 or M249 v_ mesh. Those three use M.A.T. geometry
  with CSCO textures. The MP5 uses a Galil-derived CSCO rig, so its mesh is rigidly fitted and
  rebound to the validated MP7 rig instead of copying incompatible local bone transforms.
* **World models**: each CSCO v_ mesh contains no arms and is used as a static p_/w_ mesh. A
  24-axis ICP fit preserves the existing hand grip and dropped-weapon placement without scaling.
* **Reload timing**: `WeaponController` uses the clip length as the reload time, so reload clips
  and their sound events are retimed to the CS 1.5 `reload_time` in `data/weapons.json`.
* **Silencer** (USP-S / M4A1-S): the silencer bone gets a scale track in every clip (shown in
  default clips, hidden in `*_unsil`, and toggled at the normalized SHOW/HIDE event times).
* **Attachments/events**: muzzle/eject attachments are averaged over the actual output clips.
  QC/type-1024 events become `seq_events` in `data/models_meta.json` and resolve to installed WAVs.

## Legacy M.A.T.-only build

The previous build remains available as `build_csgo_viewmodels.py`,
`build_csgo_worldmodels.py`, and `install_csgo_viewmodels.py`. Both world-model builders accept
`texture_override`, and the installer updates metadata per model without discarding unrelated
keys or attachment points.
