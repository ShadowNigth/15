# Agent sleeves and independent gloves

Native source pinned to cs2go fb970df0ee8175d9b212d310f6a928f9f61014f2.
No new rights or redistribution permissions are inferred from public availability.

| Agent | Actual arm source |
|---|---|
| SAS | gloves/agents/5600 |
| Phoenix | gloves/agents/5200 |
| ST6 Soldier | gloves/agents/5401 |
| Dragomir | gloves/agents/5500 |
| SAS Officer | gloves/agents/5601 |
| FBI | arm-weighted triangles from its own ctm-fbi body |
| Leet E | arm-weighted triangles from its own tm-leet-variante body |
| Phoenix A | arm-weighted triangles from its own tm-phoenix-varianta body |

The last three are extracted third-person arm geometry, not a falsely labelled
first-person pack from a similar agent. Their original UVs and appearance remain;
they may have less first-person detail than the five dedicated sleeve meshes.

Arsenal → **Brazos del agente** changes weapon preview sleeves independently of
Gloves. Selecting an agent in Arsenal updates the same preview context. In a match,
`PlayerController.set_team_and_class` rebuilds the held viewmodel for the new agent
without writing `selected_glove_id`. Original gloves and older Sport finishes
retain their existing meshes; the 19 new cs2go finishes use native Sport geometry
and native UVs, as explicitly authorized. No geometric paint reprojection is used
for those 19 finishes anymore. Previous projected PNGs are retained for legacy data
compatibility, not used by the new native path.

One canonical mesh per agent is rebound into each weapon's actual bind coordinate
system at equip time. Left and right coordinate conventions are calibrated
separately: fitting them together produces approximately 90-degree errors.
Source geometry, texture UVs and normalized weights are preserved through that
conversion; the weapon skeleton, weapon geometry, animation clips and timing do
not change. Upper-arm helpers absent in a weapon rig collapse to the forearm's
frame. This is a viewmodel compatibility adaptation, not a new animation set.

Installation is transactional: original arm/glove surfaces are removed only after
source mesh, all required target binds and selected finish textures are valid.
Unsupported models retain the original viewmodel surfaces. Native arm/glove
materials bypass the old chrome pass to preserve cloth/leather artwork.

Verification must include real rendered inspection and reload frames, not only
successful resource loading. Existing experimental cs_estate navigation limitation
is unrelated and remains documented in CS2_MOVEMENT_EXPERIMENT.md.
