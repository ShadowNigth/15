# Aztec faithful polish

Scope: `de_aztec` only. No new scenery, map redesign, HD texture replacement,
changes to cover or route widths, loading overlay, background preloader or cache
caps. Dust2's existing polish/renovation remains intact.

## Geometry and import

The shared repair pipeline is parameterized without changing Dust2's deterministic
output. `tools/polish_aztec.py` reads the pinned pre-polish Aztec GLB from commit
`babfb0ad6e4f47b33f5a1703c7b77f15be1b354a`. It removes zero-area triangles, repairs
T-junctions with minimal edge splits, and groups static world geometry into 32 m
frustum sectors. Original valid corners, texture UVs, lightmap UVs, bounds, area
per material and all 31 brush submodels are preserved. It does not bridge
intentional gaps in planks, invent missing walls or change gameplay JSON.

Lossy mesh compression, automatic LOD and unused shadow meshes are disabled for
Aztec so repaired boundaries/UVs are not re-quantized. Visible and collision meshes
share the repaired geometry; water primitives remain excluded from solid collision.
Original glass/rope/foliage brush behavior is not indiscriminately removed as an
"invisible wall". One specific gameplay repair restores the missing support of
submodel 1: the visible bridge net was imported as func_illusionary without its
player clip hull. A surface-only collider follows its existing upward-facing net
triangles; no side walls, river-spanning box or new visual geometry is added.
Baseline ray differences are permitted only on this bounded bridge support. Thin triangles that cannot safely split retain
original corners. Report: `data/aztec_polish_report.json`.

## Lighting and material profile

Aztec keeps its original storm sky and baked RGB lightmap. The profile reduces
washed highlights/shadow lifting and over-sharpened relief, while protecting dark
interior visibility. Stone/moss, timber/rope and metal have restrained relief;
original signs/credits stay flat. Character ambient/key/fill are cooler and less
flat, without adding world lights or shadow passes.

All four material families use the Aztec-only lightmap curve. Green water keeps
its original texture, animated waves, transparency, refraction and interactions,
with reduced UV distortion/refraction, higher roughness, zero metallic and lower
specular response. Glass retains its original opacity and collision. Alpha-scissor
foliage keeps its silhouettes; no global texture projection changes are made.
Other maps retain shader defaults and their environment configuration.

## Validation and scope limits

`tests/check_aztec_polish.py` verifies reproducibility, texture references, both UV
sets, bounds, surface area, brush count and unchanged authored gameplay data.
`AztecPolishTest.tscn` compares baseline/repaired physical rays and identical-camera
OpenGL views, validates all 32 standing spawn clearances, routes to both bombsites,
514 authored YaPB nodes, live bot movement, two-way actual standing-player bridge
traversal and C4/kit behavior. It verifies that none of the three river surfaces
becomes an invisible solid floor. `MapSurfaceWaterTest.tscn` additionally exercises
wading, water audio/ripples, actual bullet impacts and grenade splash/resistance.

Aztec is a bomb/defuse map: no hostage rescue or VIP extraction is introduced.
Those objectives remain covered by the project's existing mission regressions.
We do not claim every hypothetical collision defect has been eliminated. No
unverified walls are deleted or intentional holes filled.

Primitive counts from fixed views are a culling diagnostic, not an FPS benchmark.
More sectors can increase draw calls; no universal speedup is promised. Full-size
PNG comparisons and live-gameplay samples are retained in Aztec polish QA.
