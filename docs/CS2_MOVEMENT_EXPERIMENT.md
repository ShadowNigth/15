# Experimental CS2-style movement — ground and airborne physics

Create Game offers **Estilo CS2 — experimental** (default) and **GoldSrc — clásico**.
The same actor path applies to humans and bots. The selection lasts for the
application session and also controls thrown grenades, dropped equipment and
corpse grounding. Choose it before starting a match.

This is a configurable Source-style approximation, not Valve engine code,
Rubikon, subtick or an exact reproduction of any CS2 build.

## Ground

Acceleration 5.5, friction 5.2, stop speed 80 map units/s. Units remain 1/32 metre.
Weapon speed, walk, crouch and stamina limits remain authoritative. Opposite input
brakes through ordinary acceleration; diagonal input is normalized. Force slices
are at most 1/128 s, not collision/input subticks.

## Added experimental physics

Parameters are isolated in `scripts/actors/CS2ExperimentalPhysics.gd`:

- Jump impulse 301.993/32 m/s; gravity 800/32 m/s². The acceleration of gravity
  matches the classic numerical value deliberately; jump height rises to about
  57 map units. Classic impulse/stamina is retained only in GoldSrc. Existing
  horizontal stamina/landing penalties remain, so this is not unrestricted bhop.
- Air acceleration 12 with a 30/32 m/s projected wish-speed cap, sliced at 1/128 s.
  Perpendicular momentum is preserved; steering does not grant instant full speed.
- Thrown grenade gravity is independently 0.4 of actor gravity. Restitution 0.45;
  contact response separates normal restitution and tangential friction instead of
  damping world X/Y/Z. Existing swept collision, fuses, damage, fire/smoke and audio
  are preserved. Longer arcs intentionally change grenade landing positions.
- Dropped weapons/equipment use actor gravity, restitution 0.25 and tangential
  friction. Existing swept sphere collisions, pickup and angular settling remain.
- Corpses retain existing native skeletal death animations, with experimental
  wall response and exponential ground drag 5/s for longer progressive sliding.
  This is NOT an articulated ragdoll or a general dynamic-prop solver. Map crates
  remain static/destructible and use their existing gameplay rules.

Water, ladders, stairs, hulls, map scale, damage, recoil and accuracy rules are
unchanged. Navigation waypoints are not rebuilt for the higher jump. Bot jump
requests use the new impulse, but route planning remains the existing system.

GoldSrc keeps its original movement, grenade, dropped-item and corpse equations.
The runtime tests exercise both real human/bot jumps and ground paths plus air
projection/rate stability, energy-losing impact response, and profile selection.

## Historical QA (before the trim-support correction)

- Runtime force/real actor, grenade, equipment and corpse checks: **63 passed**,
  zero failures ([run 42952845554](https://github.com/ShadowNigth/15/actions/runs/42952845554)).
- Modern agent animation/gameplay sub-suite: **587 passed**, zero failures;
  full modern workflow is **not green**, because its mission sub-suite fails.
- **Known experimental navigation regression:** full `cs_estate` rescue can stall
  at BSP doorway trim and leave a hostage unrescued. Both the squad workflow and
  full modern workflow report this failure. The old baseline Estate comparison
  passes. A physical retreat/replan attempt does not resolve it reliably.
- Therefore this revision is for experimentation, not a fully certified gameplay
  release. GoldSrc remains selectable before creating a match. Do not interpret
  the 63 force/physics checks as proof that every mission or bot route is valid.

Source parameters remain editable; no claim of Valve-equivalent grenade/object
or corpse simulation is made. Dynamic map props and articulated ragdolls remain
outside this implementation.


## Trim-support correction — validated at e6c3463c

A capsule resting on steep BSP doorway trim can report a wall rather than a
floor. Its centre-foot ray can also miss the supporting edge. The experimental
step fallback now checks the capsule footprint and actual upward-facing contacts
on its lower hemisphere. It still requires nonascending movement and uses the
ordinary bounded 0.54 m step, not a teleport or larger step height. Contacts outside
the current footprint are rejected after relocation. GoldSrc equations are unchanged.

- [Movement QA](https://github.com/ShadowNigth/15/actions/runs/43047962948):
  **75 checks, zero failures**, including no support in free air or beyond the footprint.
- [Squad QA](https://github.com/ShadowNigth/15/actions/runs/43047963208):
  **55 physical mission checks passed**, including Estate, 747 and OilRig.
- [Modern agents QA](https://github.com/ShadowNigth/15/actions/runs/43047963158): passed.
- [Native Godot QA](https://github.com/ShadowNigth/15/actions/runs/43047963211): passed,
  including the separate Estate rescue regression.

The previously documented Estate stall is no longer reproduced by these tests.
This does not certify every possible bot route or make the experimental profile
Valve-equivalent. GoldSrc remains selectable.
