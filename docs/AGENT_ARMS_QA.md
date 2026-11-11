# Native Sport / independent agent arms: executed QA

Validated implementation: `e6c3463c007cd32d403c4240fe3fb319046bd409`.

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
claimed as aesthetic approval. FBI, Leet and Phoenix A use their own extracted
third-person arms and retain the lower-detail limitation documented in
AGENT_FIRST_PERSON_ARMS.md.

Legacy regressions that required `ct_arms.bmp` on an actual player or Arsenal
preview now require installed skinned agent arms, while direct original-asset,
weapon geometry, glove selection, animation and gameplay checks remain. The native
workflow's separate release-only export and knife-review jobs were skipped by its
conditions; no new standalone executable is claimed. Godot's dummy renderer still
emits `Parameter "m" is null` warnings in some headless suites despite passing
assertions; this report does not claim warning-free logs.
