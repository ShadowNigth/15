# Local agent legs / dedicated first-person arms

The living local player has a lower-body presentation mesh derived from the
selected agent's actual third-person asset. This is intentionally separate from
`AgentViewArms` and `SportGloves`: it does not replace their dedicated first-person
meshes or write glove selection.

`FirstPersonBody` now retains the continuous torso as well as pelvis, legs and
ankles/toes. All three triangle vertices need at least 90% influence from the
accepted body bones. Head and third-person arms remain excluded; dedicated
first-person sleeves and independent gloves are unchanged.

The previous pelvis-only extraction exposed a waist boundary. Its procedural fan
used averaged trouser UVs and could produce the black concentric disk reported
in the user's screenshot. The current mesh path never calls that cap helper:
vertices and UVs are original, only the triangle index selection changes.

A local Skeleton3D copies every actual animated bone pose each render frame.
The continuous local presentation is offset 0.52 m rearward, keeping the neck and
shoulder exclusions behind the first-person camera rather than exposing their
openings at steep downward pitch. This offset is presentation-only. Physics,
bullet hitboxes, world body, locomotion, camera FOV and weapon animations are not
shifted or modified.

Visibility layers:
- 1/2: world and external characters (unchanged for bots).
- 4: existing first-person weapon, dedicated sleeves, independent gloves.
- 8: local lower body, included only in the local world camera, not weapon camera.
- 16: living player's original full body/held model, shadows only.

Respawn and class changes rebuild the filtered copy. Death hides the local copy
and restores the complete corpse on normal character layer 2. Local copies cast
no duplicate shadow. The full body keeps its native gait, strafing, crouch,
jump and turn animation, so the visible legs inherit those same poses.

This is not a full-body first-person camera/recoil simulation. Lower-body material
filtering and look-down framing require real Godot rendering validation, not just
successful scene loading. `FirstPersonBodyTest` exercises all eight agents with
actual movement and crouching, plus respawn/layer/skeleton/death checks.
`first-person-body-qa.yml` also reruns native/legacy wrist inspection captures.
Historical implementation (superseded by the correction below): `644b22046fcb705b14d7aeeab16522b33400a9cf`.

- [Local body + wrist QA](https://github.com/ShadowNigth/15/actions/runs/43119313928):
  **132 lower-body checks + 2153 cosmetic checks, zero failures**. All eight agents
  exercised with real walking, crouching, jumping and respawn/death presentation.
  Checks include exact bone-pose synchronization and waist-cap winding/skinning.
- [Native Godot QA](https://github.com/ShadowNigth/15/actions/runs/43119313861): passed.
- [Independent cosmetic QA](https://github.com/ShadowNigth/15/actions/runs/43119314070): passed.

Real Godot source-of-truth captures were reviewed for SAS/Leet walking, FBI crouch,
and Karambit native/legacy glove inspections at midpoint and native late pose.
Selected final captures are retained in `docs/evidence/`; full captures and logs are
in the local-body workflow artifact. These are isolated rendering regressions, not
a claim to have manually played every map, movement angle or glove combination.
First-person waist caps use interpolated source UVs; they are not new bespoke
first-person torso artwork. Minor pose-dependent intersections remain possible
outside the reviewed combinations.


## Screenshot correction: continuous torso and native glove hands

Current validated implementation: `adf16929`.

- [Local-body and wrist QA 43224355463](https://github.com/ShadowNigth/15/actions/runs/43224355463):
  **151 body checks and 2,153 cosmetic checks, zero failures**. Actual rendered
  stand/walk/crouch/jump, eight agents, 70° and 89° downward pitch with Glock,
  exact pose copying, original vertices/UV preservation and death/respawn layers.
- [Compatible cosmetic QA 43224355565](https://github.com/ShadowNigth/15/actions/runs/43224355565):
  **855 arm checks and 2,153 cosmetic checks, zero failures**. Includes explicit
  source-left → target-right and source-right → target-left native Sport binds,
  including weighted finger joints for each supported rig.

`AgentViewArms._converted` exchanges the new native Sport hand geometry in bind
space using paired original inverse bind transforms, then the existing per-weapon
retargeting. It is not a texture-only swap, a screen mirror or a name change.
UVs and selected artwork are kept with their source glove. Agent sleeves, classic
hands, legacy Sport assets and the original weapon clips/events remain unchanged.
The cache key includes the handedness revision.

Actual renderer captures reviewed for the correction:
- [Phoenix looking 89° down with Glock and blue Amphibious](evidence/body-down-phoenix-blue-fixed.jpg)
- [SAS looking 89° down with Glock](evidence/body-down-sas-blue-fixed.jpg)
- [Native Sport at mid Karambit inspection](evidence/glove-hands-fixed-inspect-mid.jpg)
- [Native Sport at late Karambit inspection](evidence/glove-hands-fixed-inspect-late.jpg)

These are isolated engine scenes, not fabricated images or a claim to have
manually validated every map, wall contact, angle and cosmetic combination.
Import/renderer warning messages still occur in the CI logs; no warning-free
claim is made.
