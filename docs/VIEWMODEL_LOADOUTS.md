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

`ViewmodelLoadout.gd` removes only the legacy `ct_arms.bmp` and
`ct_base_glove.bmp` mesh surfaces. It does not hide the weapon mesh. Copies of the
selected glove and sleeve `MeshInstance3D`s point at the active weapon's
`Skeleton3D`; named `Skin` binds let the existing idle, fire, reload, draw and
inspection clips animate the replacements. Rigs without `UpperArm` use their
corresponding `Forearm` bind. Source animation clips are not included.

The source meshes use Source-inch coordinates. The converter scales the upper
three rows of each inverse-bind matrix by `1/32`, converting bone-local geometry
while leaving each target weapon's own joint globals in charge of placement.
This is deliberately not a single rigid rotation/scale fitted to all weapons.

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

Engine tests cover all 43 viewmodel rigs, named-bind resolution, finite CPU-skinned
poses, all eight choices, the real Arsenal selectors, match-start team selection,
M4A1 suppressor state, green Molotov glass and dropped-grenade scale. These checks
do not replace rendered inspection in actual gameplay.
