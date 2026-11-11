# Native Sport / independent agent arms: executed QA

Historical validation before the dedicated-substitute revision: `e6c3463c007cd32d403c4240fe3fb319046bd409`.

| Workflow | Result | Evidence |
|---|---|---|
| Native Godot | Passed: weapon/runtime/knife/catalog/world tests and seven rendered gun plate jobs | https://github.com/ShadowNigth/15/actions/runs/43047963211 |
| Compatible cosmetics | 2011 checks; arms 530 checks; zero failures | https://github.com/ShadowNigth/15/actions/runs/43047962886 |
| Modern agents gameplay | Passed | https://github.com/ShadowNigth/15/actions/runs/43047963158 |
| Squad / interaction | Passed, including all 55 physical mission checks | https://github.com/ShadowNigth/15/actions/runs/43047963208 |
| Experimental movement | 75 checks; zero failures | https://github.com/ShadowNigth/15/actions/runs/43047962948 |
| Crosshair / HUD | Passed | https://github.com/ShadowNigth/15/actions/runs/43047963036 |
| Menu / Arsenal | 203 checks, including independent preview agent/glove selection | https://github.com/ShadowNigth/15/actions/runs/43036284980 |

Rendered cosmetic evidence includes eight actual player agent swaps, inspection,
SAS and Leet reload frames, and native-UV gloves on AK/M4/AWP. Source annotations
and downloadable render artifacts are attached to the workflows. Earlier rendered
frames were inspected during integration; numerical pass counts alone are not
claimed as aesthetic approval. The later dedicated-substitute revision replaces FBI, Leet and Phoenix A with
first-person packs 5308, 5105 and 5200; the table above does not validate that
new revision. See AGENT_FIRST_PERSON_ARMS.md for current source assignments.

Legacy regressions that required `ct_arms.bmp` on an actual player or Arsenal
preview now require installed skinned agent arms, while direct original-asset,
weapon geometry, glove selection, animation and gameplay checks remain. The native
workflow's separate release-only export and knife-review jobs were skipped by its
conditions; no new standalone executable is claimed. Godot's dummy renderer still
emits `Parameter "m" is null` warnings in some headless suites despite passing
assertions; this report does not claim warning-free logs.

## Dedicated substitutes — validated at 4ee88d39

FBI now uses dedicated first-person package 5308 (FBI variant B), Leet uses
5105 (Leet variant G), and Phoenix A uses 5200 (base Phoenix). No third-person
body is used as an arm source. Exposed forearms in a dedicated package's hands
meshgroup are retained by arm weights; bundled fingers/default gloves are omitted.
The selected Arsenal glove remains independent. The generator also preserves
source cloth RGB tint and rejects full-body source paths.

- [Cosmetics and arm QA](https://github.com/ShadowNigth/15/actions/runs/43054516223):
  **2011 cosmetic checks + 554 arm checks passed**, zero failures. Includes explicit
  dedicated-source assertions, independent glove selection, eight player swaps,
  inspection and reload evidence. Rendered FBI, Leet and Phoenix A frames reviewed.
- [Native Godot QA](https://github.com/ShadowNigth/15/actions/runs/43054516361):
  passed, including weapon/knife/catalog and physical mission regressions.

These are intentionally similar first-person substitutes, not claimed exact
first-person copies of FBI base, Leet E or Phoenix A. Phoenix A and base Phoenix
now share their dedicated first-person sleeves/forearms.

## Inspection regression correction — implementation 6b30ab7b

User gameplay screenshots invalidated the earlier static-fit acceptance. Two actual
retargeting faults were found and corrected:

- `Forearm` and `ForeTwist` were collapsed into the same native semantic key;
  insertion order selected the twist helper instead of the animated forearm.
  They now remain distinct in source geometry and all target transforms.
- Knife skins omit canonical upper-arm joints. Their weighted sleeve vertices
  previously fell through to an identity bind on bone zero. They now explicitly
  collapse to the appropriate animated forearm, using that forearm's canonical
  reference. Runtime conversion rejects any still-unmapped weighted bind.

All nine canonical assets were regenerated. Exposed dedicated forearms are included
for Leet/Phoenix/Phoenix A; long closed sleeves do not receive an unnecessary hidden
skin shell. Sleeve/skin wrist endpoints are compressed only within the final 8 cm
to stay behind the glove wrist plane, retaining source UVs and weights.

[Executed runtime regression](https://github.com/ShadowNigth/15/actions/runs/43091598151):
726 arm checks and 2153 cosmetic checks passed, including nine sampled points per
inspection clip for AK/M4/AWP and Karambit with native and legacy Sport finishes,
SAS and Leet, plus explicit no-root-weight checks. A separate numerical source audit
confirmed complete weighted-bind coverage for all 387 canonical-asset/weapon pairs.
These are sampled timelines, not exhaustive continuous collision detection.

The rendered initial native Karambit pose was reviewed. Mid/late native, legacy,
and bare-forearm captures were generated and retained in the successful workflow's
`compatible-cosmetics-evidence` artifact. Their first annotation publication was
truncated by GitHub's per-step limit. A separate publication workflow retrieves that
same artifact; its run 43097312462 was still queued when this note was written.
A later full workflow (43093596116) passed the import and runtime steps but failed
its artifact upload and had not finalized. Consequently this correction is NOT
claimed to have completed visual acceptance of every inspection/wrist join yet.

## Follow-up while rendered evidence remains queued

Added `tools/source/audit_wrist_motion.py`, an independent offline evaluator of
the shipped GLB animation channels, canonical conversion and weighted skinning.
Run with the existing source-tool dependencies:

```
python -m tools.source.audit_wrist_motion --output /tmp/wrist-audit
# Optional flat-color diagnostic images/GIFs, explicitly not engine captures:
python -m tools.source.audit_wrist_motion --output /tmp/wrist-audit --render
```

Executed: **32 animation/agent combinations, 31 samples each (992 poses)** across
Karambit/AK/M4/AWP and SAS/FBI/Leet/Phoenix A. Evaluations were finite and the
combined glove/sleeve extent stayed below the 3 m catastrophic-deformation bound.
Missing weighted mappings fail evaluation rather than silently using a root.
The rendered source-geometry midpoint diagnostics for SAS/Leet were reviewed;
these are flat-color, depth-sorted source diagnostics, NOT Godot framebuffers and
not evidence of texture correctness, per-pixel occlusion or absence of small
cloth/glove intersections. No new acceptance claim is inferred from them.

GitHub run 43097312462 remained queued; downloading the earlier workflow artifact
also returned HTTP 502. Actual mid/late engine capture acceptance remains open.


## Engine visual follow-up completed for the reported Karambit cases

The old blocked publication was superseded by
[run 43119313928](https://github.com/ShadowNigth/15/actions/runs/43119313928).
Import, 132 local-body checks and 2153 cosmetic checks passed. Actual Godot
midpoint captures were inspected for native Sport/SAS, native Sport/Leet and
legacy Sport/SAS, plus the late native Sport/SAS inspection pose. The large
forearm detachment/root-binding failure is absent in those reviewed frames.
Selected engine captures are retained in `docs/evidence/`. Independent cosmetic
and complete native Godot workflows passed for implementation `644b2204`.

This closes the earlier inability to inspect actual engine wrist evidence; it
does not certify continuous triangle collision freedom for every agent/weapon/
glove combination. The dedicated first-person source policy and independent
Arsenal glove selection are unchanged. See FIRST_PERSON_BODY.md for local legs.
