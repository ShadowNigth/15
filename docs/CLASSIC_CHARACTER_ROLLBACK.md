# Classic characters restored — 2026-11-07

This request supersedes COMBAT_NATIVE_CHARACTERS.md for character presentation,
ambient chickens, and resource warmup/cache limits.

* Live CT/T class selections again instantiate the original players/<class>
  models, original skeleton blending, hand sockets, crouch/death animations,
  and original circular buy-menu character preview. VIP stays distinct.
* Hostages again use players/hostage and its original idle/walk/scared/run/
  crouch/gutshot clips. Authored-spawn-order obstacle avoidance is preserved.
* Native CT/T/hostage entries are no longer offered in the animated Arsenal.
  Classic player/class reviews and all weapon/knife reviews remain available.
* The chicken model included in this repository has exactly idle, walk and run.
  It has no authored skeletal death clip. Consequently all ambient chicken
  spawns, its Arsenal entry and its cosmetic option are removed. A rotated
  corpse is not presented as a native death animation. Source assets remain
  archived for provenance; none of these removed models is loaded by match
  warmup (which itself has been removed).
* Match launch directly changes scene again: no threaded resource requests,
  progress blocker or 48/256-entry cache eviction. Original ordinary Godot
  resource caching is retained, without these added application limits.
* Bullet skeletal regions remain, now using explicit classic Bip01 aliases.
  Material/thickness penetration, repeatable recoil, source weapon animation
  and audio, shell ejection, numeric ammunition and the icon-free HUD remain.
* Human attacks use the actual rendered Camera3D origin and orthonormal basis,
  including eye interpolation, damage/shake and visible recoil. Previously
  generic actor eyes were 1.85/1.08 m while the actual camera used 1.66/0.96 m:
  shots started 19/12 cm above the reticle's optical ray, especially visible
  against nearby walls. The camera ray fixes this, rather than moving the HUD
  by an arbitrary pixel offset or eliminating legitimate weapon spread.

CombatNativeIntegrationTest retains its historical scene name but now tests
classic rigs and head regions, real wall penetration, repeatable recoil, and
standing/crouched/scoped optical rays. Physical wall hit positions must project
onto the reticle within half a pixel, with nonzero recoil and camera roll.

> **Update (asset packs):** the unused review models `assets/models/native/ct.glb`,
> `t.glb`, `hostage.glb` and `chicken.glb` (≈85 MB, never loaded by the game)
> were removed from the project when assets moved to `packs/`. See
> [ASSET_PACKS.md](ASSET_PACKS.md). They can be regenerated with
> `tools/source/fetch_native_world_assets.py` + `build_native_world_assets.py`.
