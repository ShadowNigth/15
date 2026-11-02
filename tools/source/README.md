# CS:GO M.A.T. weapon models → Godot

Source: <https://github.com/ilunp/CSGO-M.A.T> (Crowbar-decompiled SMD/QC + VTF textures).
These scripts produced every `v_*/p_*/w_*` gun model in `assets/models/weapons/`. The C4, the
grenades, shells and gear models are not part of the pack, so they stay as they were.

```bash
# 1. sparse checkout of the pack (V/W model decompiles + textures only)
git clone --filter=blob:none --no-checkout --depth 1 https://github.com/ilunp/CSGO-M.A.T.git /tmp/mat
cd /tmp/mat && git sparse-checkout set --no-cone '*/V_Models/Decompile/' \
    '*/W_Models/Decompile/*/*.qc' '*/W_Models/Decompile/*/*.smd' '*/Texture/' && git checkout
# 2. references from the previous (task-24) GoldSrc ports: arms mesh + in-hand placement
mkdir -p /tmp/ref && for m in v_ak47 $(cd assets/models/weapons && ls p_*.glb | sed 's/.glb//'); do
    git show 479e009:assets/models/weapons/$m.glb > /tmp/ref/$m.glb; done
# 3. build + install (needs numpy, pillow, srctools, scipy)
python -m tools.source.build_csgo_viewmodels /tmp/mat/Source /tmp/ref/v_ak47.glb /tmp/vm
python -m tools.source.install_csgo_viewmodels /tmp/vm .
python -m tools.source.build_csgo_worldmodels /tmp/mat/Source /tmp/ref /tmp/wm   # then copy p_/w_
```

* **Viewmodels**: Source→Godot transforms are in `smd_converter.py` (1/32 scale, Source
  `(x,y,z)→(-y,z,x)` plus a +90° yaw on the roots, and the ports' 2-unit pull-back). CS:GO
  viewmodels have no arms, so the CS:GO glove/sleeve mesh is bone-merged by bone name from a port.
  The QC `event 5004` sound events become `seq_events` in `data/models_meta.json`, resolved
  against the installed CS:GO foley in `assets/sounds/weapons/csgo/`.
* **Reload timing**: `WeaponController` uses the clip length as the reload time, so every reload
  clip (and its sound events, scaled the same way) is retimed to the CS 1.5 `reload_time` in
  `data/weapons.json`.
* **Silencer** (USP-S / M4A1-S): the silencer bone gets a scale track in every clip (shown in the
  default clips, hidden in `*_unsil`, and toggled at the QC SHOW/HIDE frames in add/detach).
* **World models**: `p_` comes from the third-person `w_<x>.smd`, rigidly fitted (ICP) onto the
  previous p_ model so it keeps the grip the GoldSrc player animations expect. `w_` comes from
  `w_<x>_dropped.smd`, laid on its side.
