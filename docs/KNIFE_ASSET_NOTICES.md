# Additional knife appearances

Source: https://github.com/zh667/ScCsgoKnives
Pinned revision: `1eb8067fd0b7214df5bccf3ac3807fbaa3aee70d`

The first three appearances (historical geometry installer):
- Karambit — Gamma Doppler Phase 4
- M9 Bayonet — Gamma Doppler Phase 1
- Bayonet — Ruby

The initial geometry conversion used `tools/source/add_cs2_knives.py` and an
idle-grip/Kukri-clip adapter. **That animation policy has been superseded** by
the native knife animation correction below. Their third-person/world meshes,
material artwork and UVs remain installed. The original Kukri remains available
and is the default. Other weapon finishes/UVs are untouched.

## Third-party rights

Counter-Strike / CS2 models, material artwork and source animation data are
third-party Valve assets; credit and conversion do not grant additional rights.
The source repository's GPL-3.0 code license does not license Valve's extracted
assets under GPL. No claim of permission from Valve is made. The upstream notices
and legal caveats remain relevant to any further distribution:

- https://github.com/zh667/ScCsgoKnives/blob/1eb8067fd0b7214df5bccf3ac3807fbaa3aee70d/ASSET_SOURCES.md
- https://github.com/zh667/ScCsgoKnives/blob/1eb8067fd0b7214df5bccf3ac3807fbaa3aee70d/THIRD_PARTY_NOTICES.md
- https://github.com/zh667/ScCsgoKnives/blob/1eb8067fd0b7214df5bccf3ac3807fbaa3aee70d/docs/legal-assessment-2026-09-21.md

No upstream C# gameplay code, BF1/EA/DICE audio or other resource packs are included
by this knife conversion. Existing game assets retain their original provenance
and rights; see the project README. This is an unofficial fan project, not a Valve
product or an assertion that cross-game redistribution is authorized.

## Complete shipped catalog expansion

The game additionally includes all 22 knife models shipped at the pinned source
revision (plus the original archi Kukri), all 20 shipped painted knife finishes,
22 matching factory finishes, and all 44 shipped gun finishes. Existing 120
BDS/CS:GO Ports finishes and their accepted UV placement are preserved.

Each knife now uses its own native model-specific clips. Original arm/glove
geometry is retargeted to those poses, including hand and finger motion;
this does not replace the arm mesh with the upstream CS2 arm mesh. Folding
parts keep their original skin weights and native trajectories. Shadow Daggers
uses both source blades and their source motion in first person; third-person/
floor presentation continues to use the right-hand dagger.

Legacy gun artwork is adapted through the existing `nwm1-nearest-surface-v5`
pipeline with bone boundaries and original hardware protection. Current-HD art
keeps its native UV placement. Details/hashes are recorded in
`data/shipped_cs2_uv_report.json`. Knife UVs always use their matching geometry;
materials use the finish's own normal/ORM maps. Subordinate PBR chrome leaves
base-colour artwork unmodified; it does not whiten or recolour the finishes.

This catalog is the resources actually shipped by that repository, NOT every
Valve skin, random seed, wear state, StatTrak variation or Source 2 compositor.
The third-party rights caveats above continue to apply.


## Native knife animation correction

The idle-grip/Kukri animation adapter is superseded by
`tools/source/import_native_knife_animations.py`. Each of the 22 models now uses
its own pinned `.cs2.animation.json` clips, durations and inspection variants.
Knife geometry uses original source skin weights/inverse binds (both Shadow
Daggers included); hand/finger motion is retargeted to the existing arm/glove
geometry using anatomical joint correspondence and per-hand local-axis fits.
Arm/glove vertex data, UVs, original weights, material artwork and original bind
matrices remain unchanged. The original Kukri and all firearm rigs are untouched.
This is native model-specific clip data with **retargeted existing arms**, not a
claim that the original CS2 arm mesh has been installed. Local-axis calibration
residuals and exact source clip names are recorded in
`data/native_knife_animation_report.json`; visual review is still required.

Source camera axes, inch conversion (0.0254), FOV and offsets follow pinned
`Rendering/Cs2Placement.cs` and `Rendering/KnifeTuning.cs`. The native right-hand
rig is not reflected again by the legacy left-authored viewmodel presentation.

Regeneration: after the geometry installer, run
`python -m tools.source.import_native_knife_animations SOURCE_ANIMATION_DIRECTORY`
with numpy/scipy installed and all pinned `.cs2.skin` / `.cs2.animation.json` files.
The earlier fixed-grip installer alone does not reproduce this correction.

The legacy arm mesh was authored through a reflected Source-to-port coordinate
conversion. Its local-axis fit therefore includes **negative parity**, retained
as signed bone scales rather than discarded by quaternion conversion. Only the
retargeted arm/glove surfaces reverse their face-culling mode; the native knife
geometry keeps positive parity and normal back-face culling. Both the match and
Arsenal apply this distinction. Native clips also bypass the legacy equip dip.


## Native firearm and utility motion conversion

The source project also retargets 289 animation clips from the same pinned
ScCsgoKnives commit (`1eb8067fd0b7214df5bccf3ac3807fbaa3aee70d`) onto the 42
existing firearm/utility viewmodels (35 guns, six grenades, C4). The original
archi/BDS geometry, UVs, artwork, arm/glove meshes and inverse binds remain in
place. Per-file SHA-256, original source clip names, native events and pose
checkpoints are in `data/native_gun_animation_report.json`. Native additive
composition and helper-part visibility follow the upstream `Cs2Rig.cs` and
`ScGunPartVisibility.cs` behavior, adapted to Godot and classic action timers.

These conversions do not grant new rights to Valve or other third-party assets.
The existing upstream GPL/code notices and separate asset-rights cautions apply.
