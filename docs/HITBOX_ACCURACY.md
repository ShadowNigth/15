# Animated head hitboxes and weapon accuracy

Validated implementation/test revision: `20d0edec16b4bf79609fe18b3bfee38476c25be2`.

## Hit regions

The movement capsule is unchanged. Bullet collision still uses eleven skeletal
regions for head, chest, stomach, left/right arms and legs. Shooter movement hulls
and the shooter's own skeletal regions remain excluded from bullet queries.

Head capsules are now fitted separately from each installed agent's actual skinned
mesh: vertices with at least 65% influence from the head or descendant bones are
measured in the head's bind/rest coordinate frame. The fit supplies a centre,
principal axis, radius and segment length, with conservative size limits against
bad geometry. Animation rotates/translates the fit with the head instead of using
a shared world-up offset. Classic rigs and VIP use the same fitting procedure.
A small default remains for unsupported/insufficient source geometry; every tested
modern/classic agent and VIP had sufficient actual geometry and passed fitting.

Existing torso/limb capsule regions and hitgroup metadata remain. Death disables
bullet regions. Damage multipliers and armour rules are unchanged: a head hit is
hitgroup 1 and uses the existing 4x multiplier before armour/range handling.
Capsules approximate anatomy; this is not per-triangle or per-pixel collision.

## Recoil and dispersion

`WeaponAccuracy` separates accuracy from deterministic spray:

- First-shot baseline uses each weapon's existing spread definition.
- Movement penalty rises smoothly with squared normalized horizontal speed,
  rather than suddenly switching on at 15 map units/s.
- Crouching reduces the grounded cone; airborne shots have an explicit penalty.
- Sustained-fire heat increases bloom; shotgun pellet bloom is reduced relative
  to rifle bloom so pellets retain the authored base cone.
- Unscoped sniper and alternate revolver spread remain distinct.
- Dispersion averages two independent uniform disk samples: centred, circular,
  and bounded by the reported cone radius. This intentionally changes the old
  interpretation of base spread as an unbounded Gaussian standard deviation.
- A controller-local RNG separates dispersion from unrelated audio/effects RNG.

`BallisticModel.spray_target` describes repeatable cumulative pitch/yaw. AK and
M4-family weapons have different lateral knots; other weapons retain their own
recoil magnitudes and a common lateral fallback. Each shot applies the difference
between successive targets. Pitch rises progressively towards a bounded plateau;
long bursts continue lateral motion. Crouching reduces recoil increments.

Recovery uses actual elapsed time since the last shot: 0.16 s grace, followed by
exponential punch/heat decay (rates 6.5/s and 5/s). The grace-boundary time slice is
accounted for explicitly, avoiding frame-rate-dependent full-frame recovery.
The shot index resets once heat has settled below 0.10. First-shot ray direction
still uses the actual camera optical basis and recoil is not applied twice.

These are editable game-tuned behaviours, NOT exact Valve/CS2 recoil patterns.
Weapon timing, ammo, damage, zoom handling, silhouettes and animation assets are
not changed. Shot diagnostics now report the cone radius, heat and pre-shot punch.

## Executed evidence

- [Hitbox and accuracy QA](https://github.com/ShadowNigth/15/actions/runs/43129498828):
  3872 checks headless, 3904 with rendering, zero failures. Eight modern and eight
  classic agents: standing/crouched, three yaw angles, head/chest physics rays,
  real headshot damage and disabled dead regions. VIP fitting also checked.
- Per-weapon deterministic spray and stance/movement/air/bloom comparisons;
  12000 seeded samples remain bounded and centred; AK incremental spray sums to
  its target; recovery tested at 30/60/144 updates per second.
- Actual Godot fitted-head overlay captures reviewed for SAS, crouched FBI,
  Leet and Phoenix A. Selected screenshots are in `docs/evidence/`.
- [Native Godot QA](https://github.com/ShadowNigth/15/actions/runs/43129498731): passed.
- [Squad QA](https://github.com/ShadowNigth/15/actions/runs/43128358938): passed.
- [Cosmetic QA](https://github.com/ShadowNigth/15/actions/runs/43128359042): passed.

Not certified: network rewind/lag compensation (this is offline gameplay), exact
Valve patterns, all grazing skull/neck seam angles, or competitive balance from
player playtesting. The head fit does not alter movement collision or local legs.
