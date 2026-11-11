# Local agent legs / dedicated first-person arms

The living local player has a lower-body presentation mesh derived from the
selected agent's actual third-person asset. This is intentionally separate from
`AgentViewArms` and `SportGloves`: it does not replace their dedicated first-person
meshes or write glove selection.

`FirstPersonBody` retains only triangles whose three vertices each have at least
90% lower-body influence (pelvis, base spine, legs, ankles/toes; classic equivalents
supported). Upper torso, head, arms and held weapons are not part of the local
copy. Materials, UVs, weights, bind poses, mesh transform and actual animated
Skeleton3D are shared, not approximated by a second animation clock. No locomotion
collision, camera FOV or weapon animation changes are used to position the legs.

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
At initial implementation these new Godot checks have not executed; no claim of
final visual acceptance is made until they do.
