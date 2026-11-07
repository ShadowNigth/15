# Additional knife appearances

Source: https://github.com/zh667/ScCsgoKnives
Pinned revision: `1eb8067fd0b7214df5bccf3ac3807fbaa3aee70d`

Three fixed-blade models and their matching UV-mapped finish textures:
- Karambit — Gamma Doppler Phase 4
- M9 Bayonet — Gamma Doppler Phase 1
- Bayonet — Ruby

The source `.cs2.skin` meshes and PNG finish/normal/ORM images were converted to
Godot-compatible GLBs with `tools/source/add_cs2_knives.py`. Source animation JSON
is used offline only to recover the idle grip. **The installed archi knife's nine
animations, original arm/glove geometry, Sport Glove choices and classic melee
rules are retained**, not replaced by Survivalcraft code or CS2 animation clips.
The three new models also have matching third-person/world meshes. The original
Kukri remains available and is the default. Other weapon finishes/UVs are untouched.

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

Original arm, glove and hand animation tracks are retained. Folding knives append
source-derived mechanical blade/hinge tracks to those clips: this is not a claim
of complete native CS2 hand choreography. Shadow Daggers bind one blade to each
first-person hand; third-person/floor presentation uses the right-hand dagger.

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
