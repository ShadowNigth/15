# Experimental CS2-style movement — phase one

The Create Game screen now offers **Estilo CS2 — experimental** (initial default)
and **GoldSrc — clásico**. The choice applies to both the human and bots through
the same actor movement path. It lasts for the current application session.

This is a tunable Source-style approximation, not Valve engine code, Rubikon,
subtick, or a verified exact reproduction of a particular CS2 build.

## What changes

Ground acceleration 5.5, friction 5.2, stop speed 80 map units/second; map units
remain 1/32 metre. Weapon speed, walk, crouch and stamina limits remain authoritative.
Opposite directional input applies normal acceleration against momentum, allowing
counter-strafing faster than simply releasing the movement key. No instant stop,
velocity snapping or automatic accuracy bonus is added. Diagonal input is normalized.
Force integration uses slices no larger than 1/128 second; collision and input
processing still use Godot's ordinary physics ticks, not CS2 subtick.

The GoldSrc branch retains its original equations and constants unchanged. Select
it before launching a match to restore the previous feel.

## Deliberately unchanged

Air acceleration, jump impulse/stamina, gravity, ladders, swimming, stairs, hulls,
map scale, navigation, weapon recoil/spread rules, grenades, dropped items and
skeletal deaths. This is not a complete physics replacement. Bot navigation was
not retuned to a new jumping model because jumping has not changed yet.

`MovementProfileTest` checks deterministic force behavior, release vs opposite-input
braking, diagonals, vertical independence, weapon speed caps, timestep sensitivity,
and real CT/T actor movement on a physical floor under both profiles.
