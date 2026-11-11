# Sport finish projection correction

The 19 new cs2go Sport paints are re-composited from the same pinned source at
seed 1 / wear .07 and reprojected onto the existing Sport glove UV islands.
The original Sport geometry, original arm surfaces, 43 viewmodel animation rigs
and older Sport finishes are unchanged.

The old importer combined same-named materials from both worldmodel and viewmodel
meshes while always interpreting vertex joints using skin 0. The source has two
different skins. Conversion now selects the viewmodel mesh and its own skin,
uses the matching bind domain, and adds a surface-facing constraint to the
anatomical projection so palm and knuckle candidates are not interchangeable.
Output maps rise from 256 to 512 pixels per existing material island.

This remains a geometric texture adaptation across different meshes, not an exact
Valve-native UV layout. The build report records distance statistics rather than
claiming exact correspondence. Production first-person capture covers Occult,
Red Racer and Superconductor on AK/M4/AWP; catalog checks cover all 19 finishes.
