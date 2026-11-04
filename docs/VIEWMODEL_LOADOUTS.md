# First-person gloves and sleeves

Open **3D Arsenal & Models** in the main menu. The four selectors independently
choose CT gloves, CT sleeves, T gloves and T sleeves. Changing a selector rebuilds
the animated weapon preview. `GameData` keeps the choices for the current session
and `PlayerController` applies the pair for the player's team whenever a
first-person weapon is built, including the initial match spawn.

| Team | Kind | Options |
| --- | --- | --- |
| CT | Gloves | Hard Knuckle, Hard Knuckle Black |
| CT | Sleeves | SAS, FBI |
| T | Gloves | Fingerless, Fullfinger |
| T | Sleeves | Professional, Balkan |

The database is `data/viewmodel_loadouts.json`. The eight self-contained GLBs are
in `assets/models/loadouts/`; base colour, normal and ORM textures are embedded,
so no external CS2 installation is needed at runtime.

## Runtime attachment

`ViewmodelLoadout.gd` preserves the original `ct_arms.bmp` geometry and skinning,
and removes only the legacy `ct_base_glove.bmp` surface. It does not hide the weapon
mesh. MultiRig glove GLBs also contain a `bare_arm_133` surface; that surface is
always discarded, so the repository contributes **only gloves and sleeves**.
Before replacing the legacy glove, it converts those retained surfaces into the
active weapon's own rest space. Vertices, normals and tangents are baked once per
weapon/variant and cached; UVs, joint indices, weights and materials are
preserved. Rigs without `UpperArm` use their corresponding `Forearm` during this
mapping.

The intermediate source meshes use Source-inch coordinates and inverse binds
with `1/32` scale. They are not attached directly to the renderer. The baked
mesh is in metres and receives a new Skin containing native target-bone indices
and rigid target-rest inverse binds (`1.0` scale). Its transform is identical to
the target `Skeleton3D`. Existing idle, fire, reload, draw and inspection clips
then animate the additions alongside the untouched original arms. If conversion
fails, both original arm/glove surfaces remain untouched.

## Source and rebuild

Source: `goribby/CS2-MultiRig`, reviewed at commit
`026058b2a70a55257d6b85563f27b3c31e558f26`. The upstream repository does not
declare a licence; this project does not claim a redistribution grant.

With NumPy and Pillow installed, and a sparse checkout of the required `Arms`
paths, rebuild from the repository root:

```sh
python3 tools/source/build_viewmodel_loadouts.py /path/to/CS2-MultiRig .
```

The converter preserves positions, UVs, joint indices and weights exactly,
renames the 38 hand/arm joints to the installed Bip01 names, embeds and optimizes
PBR images, removes animation clips, and prunes unused accessors. Base colour is
capped at 2048 px; normal and ORM images are capped at 1024 px.

Engine tests cover all 43 viewmodel rigs, exact preservation of original arm
vertex/UV/skinning/index arrays, exclusion of repository bare-arm surfaces, native glove/sleeve binds
and finite CPU-skinned rest/draw/idle poses. They also cover all eight choices,
the real Arsenal selectors, match-start team selection and T + Glock. They also
cover M4A1 suppressor state, green Molotov glass and dropped-grenade scale. These
checks do not replace rendered inspection in actual gameplay.
