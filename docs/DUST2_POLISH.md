# Dust2: faithful geometry and lighting pass

Scope: `de_dust2` only. No HD texture replacements, new props, altered routes,
spawn points, bombsite volumes, prices, navigation links, or loading systems.

## Geometry, UVs and collision

`tools/polish_dust2.py` reads the pinned pre-polish GLB from commit
`511be65e61447fd5801e00898a76a369b8d043ff`. It removes zero-area triangles,
splits affected world triangles at T-junctions, and groups the world into 48 m
sectors for ordinary renderer frustum culling. It does not move the exterior
boundary or add invisible collision hulls. Render and collision use the same
repaired mesh. Extremely thin triangles retain their original corners.

Dust2 import explicitly disables lossy attribute compression, automatic LOD
simplification and unused shadow meshes. This avoids re-quantizing the repaired
sector boundaries/UVs and avoids generating shadow data for an unshadowed BSP.

Original albedo UVs and lightmap UVs are retained; new edge/center vertices
interpolate those coordinates. Texture alignment/scale is not globally changed:
blind reprojection would destroy authored wall/door alignment. The static test
checks reproducibility, both UV sets, map extents, area per material, texture
references, all 38 interactive submodels and unchanged gameplay JSON. Report:
`data/dust2_polish_report.json`.

## Lighting and materials

A map-specific profile retains the authored RGB lightmap and original textures.
It reduces excessive shadow lifting/highlight boost, softens the height-from-
albedo relief and sharpening, distinguishes wood/stone/metal relief, and keeps
signs/credits flat. Character ambient and fill light are reduced moderately;
world geometry is still not double-lit by the character light rig. Other maps
retain shader default values and their environment setup.

Dust2 has no authored water volume or glass material. We do not invent a river,
windows or unrequested decorations. Existing other-map water/glass paths stay
unchanged, as do original credits, relief and texture provenance.

## Runtime validation

`Dust2PolishTest.tscn` compares baseline and repaired physics with dense floor and
horizontal wall rays, checks all 40 authored spawns and directed routes from
each spawn to both bombsites, simulates live bots through the actual game world,
and exercises C4 kit defusal at both sites. The graph remains the authored 1,238
YaPB nodes. Dust2 is bomb/defuse: hostage rescue and VIP escort belong to other
maps and remain covered by the existing mission regressions.

Four identical-camera before/after OpenGL captures cover both sites and the two
spawn environments. Their primitive counts are logged as a culling diagnostic,
not an FPS benchmark. More sectors can increase draw calls; no blanket speedup
or universal removal of every collision problem is claimed. We do not delete
unverified walls or seal intentionally open map boundaries.

No loading overlay, background preloader or capped resource cache was added.
