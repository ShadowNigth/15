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
