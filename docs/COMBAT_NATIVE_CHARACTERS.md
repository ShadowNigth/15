> Character/resource/chicken decisions below are superseded by [CLASSIC_CHARACTER_ROLLBACK.md](CLASSIC_CHARACTER_ROLLBACK.md).

# Combat, native characters and loading — November 2026

Supersedes the review-only CT/T/hostage decision in NATIVE_WORLD_ASSETS.md.

* Live CTs use native SAS, Ts Phoenix, hostages the native orange-clothed model.
  Team/class/economy/hostage objectives remain unchanged. The VIP retains its
  distinct protected-person model. Native original geometry/textures are unmodified.
* Native gait and weapon-specific hold/reload tracks drive actual Skeleton3D
  bones. GoldSrc bone names are not fed to the native rig. Right-hand sockets
  are calibrated from native muzzle forward/up axes and hold transforms by
  `python -m tools.source.build_native_actor_sockets` (numpy/scipy, development only).
  Baked hold yaw/pitch/roll is removed at the upper spine; the unchanged p_
  barrel must face actor aim, not merely reproduce the old hand orientation.
* Crouching uses two-bone hip/knee IK to keep ankles at their animated ground
  height without shrinking/squashing the mesh. Death is an authored collapse:
  upstream has no native death/crouch clips. It is not a Source 2 ragdoll.
* Bullet-only layer 16 skeletal capsules distinguish head, torso, stomach,
  left/right arms and legs; player navigation still uses its original capsule.
  Gun/knife traces exclude movement hulls when a skeletal rig is present.
  Head regions move with crouching and aim. Standard hitgroups 4/5 are arms,
  6/7 legs; armor protects chest/stomach and helmeted heads, not bare limbs.
* Penetration probes the first forward-facing exit on the entry collider, with
  bounded distance and no entry-backface/unrelated-collider fallback. Material,
  ammunition and actual thickness determine depth/loss. Unbroken bombsite crates
  remain bulletproof; Zeus and zero-penetration weapons cannot wallbang.
* Spray has repeatable weapon-dependent lateral changes and stance attenuation,
  separate from random spread. Recovery is exponential in elapsed time after
  the fire cooldown. Camera and bullet aim use the same punch angles, rather
  than mismatched pitch/yaw multipliers. This is an authored Godot adaptation,
  not a claim to replicate CS2's proprietary spray/ballistic simulation.
* Match creation requests native actors and the chosen map in worker threads,
  shows progress and prevents duplicate starts. Failed loads do not enter a
  half-loaded match. Scene/texture caches are bounded (48/256); native pose
  track lookup tables are shared read-only per team instead of rebuilt per bot.
* The magazine icon and its menu switch are removed from the HUD. Ammo counts
  and low-ammo warnings stay. Original icon files remain for asset compatibility.
* The chicken is 1.85x its upstream size (~0.65 m tall); bullet capsule and model
  use the same scale. Original geometry/animations/texture remain untouched.
* Hostage avoidance handedness uses authored spawn order, not object IDs, so
  importing resources or adding presentation nodes cannot change that choice.

`CombatNativeIntegrationTest.tscn` exercises real production actors, hit regions,
wall geometry/exit thickness, recoil, crouch/ankle alignment, native hostages,
chicken scale and cache bounds. CI captures both standing and crouched native
actors with mounted AKs, the live hostage and the bird beside a human model.
Full existing physical mission, weapon, audio and rendering regressions remain
required. Consult the actual CI result; test existence is not proof of passing.
