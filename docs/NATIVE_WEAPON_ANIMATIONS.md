# Native per-weapon motion on the original models

## Scope and provenance

Pinned upstream: `zh667/ScCsgoKnives`, commit
`1eb8067fd0b7214df5bccf3ac3807fbaa3aee70d`.

- 35 firearm animation sets + six grenades + C4 = **42 sets, 289 source clips**.
- **52 inspection variants** for these weapons/utilities.
- Existing 22 added knives retain their separate 235 native clips / 33 inspections.
- The original knife, all weapon statistics, skins, world models and map assets are unchanged.

Every upstream clip is represented, including empty-slide states, subsequent CZ
reloads, alternate draws, grenade high/low holds and throws, C4 inspections/plant,
R8 hammer preparation/alternate fire, and auxiliary inspect/ironsight clips.
Compatibility names may share a native clip; they are not counted as additional
source animations. Auxiliary graph clips remain accessible but do not introduce
new firing rules or CS2 networking/animation-graph behavior into classic gameplay.

## Conversion

`tools/source/import_native_gun_animations.py` consumes the pinned
`*.cs2.animation.json` files. The importer verifies byte-equivalent original
positions, normals, UVs, weights, indices and inverse binds. Existing material
assignments remain intact. Arms and Sport Glove geometry are not replaced.

Native camera coordinates are converted from inches with
`(x forward, y left, z up) -> (-z, -x, +y)` and 0.0254 metre/inch.
The old archi geometry's reflected X, 1/32-unit scale and +2-unit camera-Z
placement are calibrated, not copied onto native quaternions.

For each mechanical joint, transfer uses the complete global transforms:

```
G_old_joint(t) = C N_native_joint(t) N_native_joint(idle)^-1 C^-1 D O_old_joint(idle)
```

This preserves the installed part's own mesh/pivot/axes while moving it around
the native pivot. Unmapped helper joints inherit their mapped ancestor's motion.
Original arm/finger joint axes are fitted anatomically; the R8 ring-finger and
MP5 thumb phalange outliers get individual axis calibration. Signed scales
retain reflected mesh parity. Native knives keep their arm-only front culling;
retained firearm geometry requires front culling on every viewmodel surface.
Molotov glass/liquid have corresponding front-cull shader variants; world props
retain the original shaders.

The R8 `RelativeToFrame / FirstFrame` layer is composed over animated idle, with
frame-zero rotations subtracted, following upstream `Cs2Rig.SampleAdditive`.
It must never be sampled as an absolute pose. Native graph helper visibility is
baked for the R8 loader and Sawed-Off shell. The CZ front spare disappears at
`Weapon_CZ.Clipout2`, remains removed for that loadout, and subsequent reloads
use the native follow-up variants. Resetting weapons resets the cosmetic state.

## Playback and gameplay

The GLBs retain source duration. `gameplay_seq_durations` preserves the previous
per-action durations separately. `WeaponController` reads the gameplay duration;
`PlayerController` applies the corresponding animation speed and identical sound
event time scale. Source ID/particle events are not misrouted as sounds or used
to grant ammunition twice. Only existing recordings are resolved; the dedicated M4A4 and MAG-7 CS2 foley
is preserved at native event times. Visibility scale changes use STEP keys.

Shotgun source INTRO / LOOP / OUTRO event boundaries drive the derived stages.
Because the classic controller credits its first shell at the end of start_reload,
that derived clip includes the native intro and first insertion; later shells
repeat the native loop. Existing timers, ammunition credit cadence and reload
interrupt rules remain unchanged. The complete uncut native reload is also kept.
C4 plant follows the classic three-second timer; grenade pin/hold follows the
existing high/low timings; R8 preparation follows the existing primary delay.

Committed `.glb.import` settings disable lossy animation optimization, retain
constant tracks needed by visibility overrides, and import animation at 60 fps.
These are editable source settings, not engine binaries or generated scene caches.

## Reports and regression tests

- `data/native_gun_animation_report.json`: upstream file hashes, exact source
  names, aliases, durations, mechanical mappings, graph events and expected
  global hand/part matrices at several phases of all 289 source clips plus derived shotgun stages.
- `tests/check_native_gun_animations.py`: compares every mesh primitive and skin
  against the pre-conversion commit, verifies all 289 source clips, sound paths,
  existing action timers, and the R8 additive layer's idle starting pose.
- `tests/NativeGunAnimationTest.tscn`: instantiates all 42 rigs through production
  PlayerController, checks imported source poses, handedness, action speed and
  Sport compatibility. With `--capture`, renders idle/fire/reload/inspection,
  utility actions and mechanically difficult transitions in real OpenGL gameplay.
- Existing knife/cosmetic, weapon runtime, map/mission, fire and AI regressions
  remain in `.github/workflows/native-qa.yml`.
- The native review job uploads full PNG framebuffers and seven review checks
  publish real, labelled frame batches plus selected full-frame close-ups.

Run static validation with Python, then import with Godot 4.3:

```
python tests/check_native_gun_animations.py
godot --headless --path . --import
godot --headless --path . --fixed-fps 60 res://tests/NativeGunAnimationTest.tscn
```

For real framebuffer captures, run the same scene with an OpenGL display,
`--rendering-method gl_compatibility --resolution 960x540 -- --capture`.
Upstream code/asset notices remain in `KNIFE_ASSET_NOTICES.md`; conversion is not
a claim of permission to redistribute third-party game assets.

### Rebuilding the conversion (optional)

The project ZIP already contains the animated GLBs, so no downloads or Python
packages are needed to play. For conversion development, install NumPy/SciPy,
use `python -m tools.source.fetch_native_gun_animations [OUTPUT_DIRECTORY]`
(with GitHub CLI installed), then run the importer module against that directory.
The downloader verifies both pinned Git blob IDs and report SHA-256 values.
Start with the original gun GLBs and `models_meta.json` from pre-conversion commit
`e0360c636ab40cb36761dc0ef2189030f922fa33`; the importer deliberately refuses to
stack a second conversion on an already retargeted model. Do not restore knives,
skin artwork, weapon statistics or unrelated game files for this operation.
