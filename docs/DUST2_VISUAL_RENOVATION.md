# Dust2 visual renovation

This is an additive art pass over the repaired classic Dust2, not a CS2 map port.
Only `de_dust2` enables it. The previous BSP geometry, original texture UVs,
lightmap, collision, spawn/objective data and YaPB graph remain unchanged.

## Art direction

- Sandstone cornices, closed muted-green louvered shutters and shallow sills.
- Upper-facade drain pipes, wall-hugging electrical cables and small brass lamps.
- Flush ceiling trim and decorative fixtures in supported CT underpass ceiling
  rectangles (fixtures are visual, not new realtime lights).
- Eight distant buildings with parapets/cisterns/closed windows, entirely beyond
  the original map bounds. They do not extend the playable area.
- Continuous directional sky gradient, wispy clouds and a restrained warm halo.
  The original six sky textures/mountain artwork are retained. No generated or
  third-party replacement textures are required; existing credits still apply.
- Very light depth haze (density 0.0008), supported by GL Compatibility. No
  volumetrics, screen-space effects, dynamic shadow maps, particles or preload UI.

## Placement and limitations

`tools/build_dust2_renovation.py` reads the pinned original geometry, groups
connected triangles by rectangular facade/ceiling and derives backed anchors.
Details stay on solid upper walls, not across openings, doors or paths. Shutters
are closed decoration, not new enterable windows. Small trim can protrude from
its host plane; it is visual, not new cover. Distant buildings are outside BSP
bounds. There are no new CollisionObject3D nodes or navigation links.

The pass is deliberately not a universal replacement of every facade, nor an
addition of crates, barrels, vegetation, water or NPCs on walkways. Original
crates, bullet penetration, objectives and CT/T characters retain their behavior.

## Cost and verification

The dressing is baked into spatial batches with five shared matte materials,
mipmapped original textures, baked vertex face shading and no shadow pass.
Local detail stops drawing at 110 m; backdrop at 420 m. The static asset budget
is 7,200 triangles. A renovation adds render cost: no FPS gain is promised.

`check_dust2_renovation.py` checks reproducibility, winding, finite coordinates,
texture references, safe anchors, backdrop bounds, budget and unchanged BSP/JSON.
`Dust2RenovationTest.tscn` compares identical cameras against the previously
polished Dust2 without dressing. It checks runtime materials/sky/budgets and
inherits the 756 physical probes, 40 standing spawn clearances, both-site routes,
live-bot simulation and C4/kit checks. Captures include both sites, CT/T areas and
two actual gameplay samples. Full-resolution PNGs are attached to the CI run.

Rebuild with `python tools/build_dust2_renovation.py`; requires repository Git
history and standard Python only. No engine/executables are included in source
ZIPs, and no background loading or capped-cache system was added.
