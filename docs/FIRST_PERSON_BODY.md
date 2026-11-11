# Local agent legs / dedicated first-person arms

The living local player has a lower-body presentation mesh derived from the
selected agent's actual third-person asset. This is intentionally separate from
`AgentViewArms` and `SportGloves`: it does not replace their dedicated first-person
meshes or write glove selection.

`FirstPersonBody` retains only triangles whose three vertices each have at least
90% lower-body influence (pelvis, base spine, legs, ankles/toes; classic equivalents
supported). Upper torso, head, arms and held weapons are not part of the local
copy. Materials, UVs, weights, bind poses, mesh transform are preserved. A local Skeleton3D copies every actual animated bone pose each
render frame, not an approximation driven by a second animation clock. The local
copy is offset 0.22 m behind the camera-facing body origin so the camera does not
look directly into the top of the trousers. Physics, bullet hitboxes and the world
body remain at their original positions. No locomotion
collision, camera FOV or weapon animation changes are used to position the legs.
Upper boundary loops are closed with normalized skinned caps using Godot clockwise
front faces; foot/ankle boundaries are not arbitrarily sealed.

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
Validated implementation: `644b22046fcb705b14d7aeeab16522b33400a9cf`.

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
