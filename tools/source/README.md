# Classic-Offensive / CS:GO weapon models → Godot

Current model source: <https://github.com/ixof/Classic-Offensive> (CSCO MDL/VVD/VTX + VTF).
Animation/reference source: <https://github.com/ilunp/CSGO-M.A.T> (Crowbar SMD/QC + VTF).
All shipped GLBs are self-contained; neither source repository nor SourceIO is needed by Godot.

## CSCO build

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
  `(x,y,z)→(-y,z,x)`, +90° yaw on roots, UV vertical flip, and the ports' 2-unit pull-back).
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
