# Compatible cs2go cosmetic batch

Approved scope: two new finishes per compatible gun, all 19 Sport finishes in the
pinned catalog, and three additional agents per faction. Not the complete 2,005
weapon / 96 glove catalog, and no new glove geometry families.

Source: 3kh0/cs2go @ fb970df0ee8175d9b212d310f6a928f9f61014f2.

## Included

- **68 gun finishes across 34 weapons**, appended to the existing finishes.
  Olympus/Zeus and unpaintable equipment keep their existing appearances where
  there are not two compatible HD entries. Legacy weapon aliases use the matching
  modern counterpart (P228/P250, M3/Nova, TMP/MP9, Scout/SSG08, etc.).
- **19 Sport finishes**, appended to the 26 existing authored variants: 45 choices
  plus Original. The same 43 native-bind Sport meshes, original arms and animations
  are used. All ten existing left/right sub-material slots receive converted maps.
- **Six additional agents**, for eight distinct CT/T appearances:
  - CT: FBI, Seal Team 6 Soldier / NSWC SEAL, B Squadron Officer / SAS; original SAS retained.
  - T: Elite Crew Variant E, Dragomir / Sabre, Phoenix Variant A; original Phoenix retained.

Class IDs and team rules are unchanged. Selecting a faction still automatically
randomizes its class; there is no manual class screen. The Arsenal previews each
class's actual appearance. Hostages and VIP remain classic.

## Conversion, not thumbnails

The build tool fetches the pinned paint descriptions, texture inputs and WGSL
programs. It runs the upstream compositor only in a development cache using
Node WebGPU / software Vulkan, then writes ordinary image files. Runtime requires
no npm, browser, WebGPU, network, Python or third-party TypeScript.

Paints are baked at seed **1**, wear **0.07**, not dynamically recomposited in game.
Colour output is geometrically reprojected to the installed HD UVs. Registration
uses a fixed 1/32 scale, reflected rigid alignment and part-aware correspondence;
bullet/shell masks retain their original artwork. Existing normal/roughness maps,
scope lenses, chrome balance, weapon geometry, skins and animations remain intact.
This is an offline adaptation, not a claim of exact Valve compositor equivalence.

Sport material names in the old mesh are contralateral to their bone ownership.
The converter follows actual bind ownership and hand/finger frames, not just the
L/R label. Bone-owned surface correspondence prevents cross-finger projection;
local offsets account for Source-inch versus 1/32-unit scale. Wrist regions use
the hand anchor to account for differing forearm lengths. There are no geometry substitutions or runtime vertex rebakes.

Small agent body files share the existing SAS/Phoenix native animation libraries.
Paths and sample tables are rebuilt by bone name and cached per appearance, never
by the source actor's bone indices. Native weapon actions and adapted skeletal
deaths remain available. Appearance-specific sockets are kept in the same catalog.

## Rebuild

```
npm ci --prefix tools/source/modern_agents
npm ci --prefix tools/source/cosmetics
python -m tools.source.expand_cs2go_cosmetics
```

Requires authenticated gh and Python numpy, scipy, Pillow, trimesh and rtree.
Inputs/cached TypeScript and shaders stay in `.cache/cs2go` (not shipped).
`data/cs2go_cosmetics.json` records included finishes, source description hashes,
agent source/output hashes and measured surface-transfer errors. The full source
catalog is deliberately not presented as playable content.

## Verification

`CosmeticExpansionTest` exercises every imported finish/material mode, all Sport
choices on native binds and all eight agents' animation/hitbox/grip compatibility.
Rendered evidence covers the agent lineup and moving poses, plus production
first-person AK, M4 and AWP views with the imported Sport finish after their native
draw animations. Arsenal previews are also retained in the evidence artifact. Existing modern gameplay,
first-person weapons, UI, hostage/VIP and other native QA suites remain active.

Artwork belongs to Valve/its authors. No general root license was identified for
cs2go; public downloadability does not establish redistribution permission. Existing
BDS / CS:GO Ports artwork and credits are preserved separately.

### Executed Godot 4.3 QA

- [Compatible cosmetics](https://github.com/ShadowNigth/15/actions/runs/42895309398):
  **1,277 checks, zero failures**, real OpenGL captures; code revision `90aa512c`.
- [Modern agents gameplay](https://github.com/ShadowNigth/15/actions/runs/42895404306):
  **success**, including 463 movement/combat/death/respawn checks, 723 native import
  checks and 3,261 preserved weapon/knife/glove regression checks; revision `c938d391`.
- [Native Godot QA](https://github.com/ShadowNigth/15/actions/runs/42895404284):
  **success**, including native tests, world assets, gun review and seven rendered
  gun-plate batches; revision `c938d391`.

`c938d391` differs from `90aa512c` only by three additional agent-roster assertions.
The final documentation-only update does not change tested runtime code or assets.
The editable source ZIP contains the Godot project, not an engine or standalone
executable. Physical Rubikon-style ragdoll simulation is not introduced by this batch.
