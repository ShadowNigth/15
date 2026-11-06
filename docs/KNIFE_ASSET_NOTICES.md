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
