# Bot animation / third-person grip polish

Works on the existing eight modern CT/T appearances, preserving body size +8%,
movement profiles, native meshes, original first-person arms/animations and skins.

Corrections:
- Compose aimed upper-body clips in their calibrated pelvis reference frame while
  preserving the locomotion/crouch lower body. This fixes downward-pointing guns
  caused by mixing low-ready crouch holds with standing weapon socket calibration.
- Apply the current body yaw before world-space spine aiming and support-hand IK,
  removing the previous-frame reference-frame error during turns.
- Walk/run hysteresis (enter run above 4.3 m/s, return below 3.7 m/s) and diagonal
  direction hysteresis reduce animation switching around speed/direction boundaries.
- Ladder and airborne states take priority over grounded crouch locomotion;
  crouched jumps use the available native crouched airborne clips.
- Magazine reload clips are time-mapped to the weapon controller's actual reload
  duration, instead of ending early/late relative to the magazine refill. Staged
  shotgun reloads retain their native timing path rather than squeezing a full
  reload animation into every shell-insertion timer.
- Support-arm and wrist corrections blend in/out over roughly 83 ms; release during
  draw/reload, suppressor operations and ladder movement. Rifles/SMGs/shotguns/LMGs
  retain the per-weapon foregrip target. Pistols, dual pistols, knives, C4 and grenades
  retain their authored grips rather than forcing a rifle-style two-handed IK pose.

Existing per-weapon socket calibrations and weapon scale remain authoritative.
No arbitrary universal gun offset, mesh edits, finger retargeting or new animation
assets are introduced. Verification expands native held-weapon/foregrip checks
from five weapons to all 43 slots, audits socket frames across all eight appearances,
and checks sharp aimed turns and real reload timing. Rendered gameplay captures
continue to cover idle, running, crouching, shooting, reloading and death.
