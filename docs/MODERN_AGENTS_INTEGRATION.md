# Modern agent integration — NOT activated

Requested source: 3kh0/cs2go, pinned fb970df0ee8175d9b212d310f6a928f9f61014f2.
Target bodies: roster/ctm-sas.glb and roster/tm-phoenix.glb. Both have embedded
images and skinned meshes but NO animation tracks. They require Meshopt,
KHR_mesh_quantization and KHR_texture_basisu. Ground Rebel native has six rifle
locomotion clips; the base animation pack contains 18 mostly preview/idle clips.
Neither constitutes a validated complete combat/death animation controller.

Conversion attempted outside Git using glTF Transform 4.5.1 ktxdecompress. Meshopt
was decoded, but KTX conversion stopped because the external `ktx` executable is
not installed. No partial GLB or bind-pose replacement was shipped. Source downloads
and tooling are development scratch files, not game dependencies.

Remaining gates before replacing defaults:
- Decode textures/geometry to formats importable by Godot 4.3 Compatibility.
- Map separate animation packs to both skeletons; validate rest/bind transforms,
  scale, native axes, root-motion removal and missing helper bones.
- Implement/test idle, locomotion/strafe, crouch, airborne, reload/fire and death.
- Calibrate weapon grip, muzzle origin, head aim, animated bullet hitboxes.
- Apply same appearances to faction chooser/buy/menu previews without class menu.
- Render moving gameplay and validate no T-poses, sliding, floating weapons,
  clipping or regressions to first-person weapons/hands and VIP/hostage missions.
- Review rights: roster/source.json attributes assets to Valve; no general root
  licence was identified. Public availability is not redistribution permission.

Classic characters are deliberately still active. GoldSrc physics untouched.

## Original AI changes, independently implemented
Actual bullets now govern burst length independently of the recoil counter.
Rifles use finite distance-based bursts; ranged rifles and snipers must settle
before firing. Empty/reload/cooldown triggers are not counted. A live urgent
objective follows its existing safe route rather than repeatedly strafing at a
visible target beyond 16 metres; close threats and reload cover still interrupt.
No upstream source code copied and no unseen opponent locations used.

## Compatibility conversion resolved

`tools/source/import_modern_agents.py` now downloads pinned models and the default
rifle animation pack, decodes Meshopt and BasisU to ordinary geometry/embedded PNG,
and transfers 21 named source animation clips to each native rig. Non-root local
translation keys are converted from metres to the rig's inch coordinates; root
movement is suppressed so it cannot displace gameplay physics. No source TS code
is copied. The animation conversion is original tooling.

Rebuild: `npm ci --prefix tools/source/modern_agents`, then
`python tools/source/import_modern_agents.py` (requires authenticated gh). Runtime
requires neither npm, gh, ktx, network access nor WASM. Provenance and SHA256 hashes
are in `data/modern_agents_import.json`. Source artwork rights remain unchanged.

Open `tests/ModernAgentImportTest.tscn` to inspect SAS/Phoenix with real native
idle, run and crouch clips. This isolated import test does NOT activate them as
match defaults. Weapon-specific actions/grip calibration, death controller,
preview integration and moving gameplay QA remain required before replacement.
The earlier missing `ktx` executable is no longer a blocker.

## Runtime activation

Combat class aliases now resolve to SAS (CT) / Phoenix (T) everywhere, including
team chooser, buy preview and Arsenal. Random internal class selection remains;
there is still no manual class-selection step. VIP and hostages stay classic.
Original classic files remain on disk as research/reference, not default combatants.

ModernAgentPose selects native directional walk/run/crouch/air poses, weapon holds,
draw/reload/fire upper layers, resets sparse tracks on transitions, applies aim
pitch/recoil, and disables root displacement. The importer adds common rifle,
pistol, knife/grenade and weapon-specific action packs. Legacy firearm aliases
(e.g. P228/P250, M3/Nova, SG550/SCAR) use the corresponding available modern pack.
Weapon sockets are calibrated per appearance and weapon from the modern hold pose
against the established p_ mesh orientation. Inch-root scale is cancelled at the
socket, preserving unchanged weapon geometry and world scale.

Deaths are an original bounded procedural fall from the current live pose, combined
with existing world corpse grounding and normal weapon drops. They are NOT native
CS2 death clips or a full joint-by-joint physics ragdoll. No death GLB clips exist
in the inspected source pack. Resurrection rebuilds the rig and resets this state.
Animated skeletal bullet regions follow modern bone names. GoldSrc movement,
first-person models/animations/gloves/skins, mission logic and AI remain unchanged.
