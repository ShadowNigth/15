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
