# Validación con el motor real (Godot 4.3)

Hasta ahora la limpieza se validaba sólo con análisis estático (`gdparse`,
`tools/verify_godot_project.py`, checks de Python). Este documento registra la
primera ejecución **con el motor de verdad**, usando el Godot 4.3 que ahora vive
en [`tools/godot/`](../tools/godot/README.md).

```bash
tools/godot/godot --headless --path . --audio-driver Dummy --import
tools/godot/godot --headless --path . --audio-driver Dummy --fixed-fps 60 res://tests/<Suite>.tscn
```

## Error real que sólo el motor detectó

`gdparse` valida sintaxis, no resolución de identificadores. La retirada del modo
de rehenes había dejado una referencia huérfana en
`CSBot._pick_open_escape_direction()`:

```
SCRIPT ERROR: Parse Error: Identifier "legacy_rescue" not declared in the current scope.
          at: GDScript::reload (res://scripts/ai/CSBot.gd:1734)
```

`legacy_rescue` era `team == "CT" and RoundManager.map_mode == "cs"`. Como
`map_mode` ya sólo puede ser `de` o `dm`, la rama se eliminó y se conservó
únicamente el comportamiento de los mapas de bomba. **Corregido.**

## Resultados de las suites

| Suite | Resultado |
| :--- | :--- |
| `TacticalAIRegressionTest` | **PASS** — 89 comprobaciones (compras y escuadras DE) |
| `NativeAudioTest` | **PASS** — 5 427 comprobaciones, 539 grabaciones, 43 armas, 64 rigs |
| `HitboxAccuracyTest` | **PASS** — 3 871 comprobaciones |
| `UtilityPropagationTest` | **PASS** — 450 comprobaciones |
| `SquadGameplayTest` | **PASS** — 243 comprobaciones |
| `CombatNativeIntegrationTest` | **PASS** — 71 comprobaciones |
| `DeathmatchPolishTest` | **PASS** — 68 comprobaciones |
| `BotResourceMobilityTest` | **PASS** — 23 comprobaciones |
| `SquadInteractionTest` | **PASS** — 9 comprobaciones |
| `ArchiWeaponRuntimeTest` | 2 595 / 2 646 — 51 fallos, todos ambientales o previos (ver abajo) |
| `ModernAgentGameplayTest` | 553 / 577 — 24 fallos de pose/ragdoll, previos |
| `ArchiGameWorldSmokeTest` | 131 / 153 — 22 fallos, todos de materiales en headless |

Ningún fallo afecta a balística, daño, economía, física GoldSrc, navegación,
bomba, granadas ni audio: esas comprobaciones pasan enteras.

## Por qué fallan las comprobaciones restantes

**1. Materiales en modo `--headless` (ambiental).** El renderer `dummy` de Godot
no devuelve materiales por superficie (`mesh_surface_get_material` devuelve
siempre un RID vacío en `servers/rendering/dummy/storage/mesh_storage.h`). Todas
las comprobaciones del tipo *«keeps original arms, ten textured Sport surfaces»*,
*«uses only the original arms and gloves»*, *«render exterior front faces»* o
*«Molotov glass layers refract the scene»* leen esos materiales, así que no pueden
pasar sin un contexto OpenGL real. En CI se ejecutan con `xvfb-run` y
`--rendering-method gl_compatibility` precisamente por eso. Los avisos
`Parameter "m" is null` del log tienen el mismo origen.

**2. Catálogo Sport desfasado (previo a la limpieza).** `ArchiWeaponRuntimeTest`
espera 45 acabados y 320 texturas, pero `data/sport_gloves.json` contiene 27
acabados y 130 texturas, y `tests/check_smoke_out_texture_swap.py` confirma 27.
Ese desajuste ya existía: `git diff` muestra que `data/sport_gloves.json` no se
tocó en la limpieza. Arrastra también los fallos de *«Create Game exposes Original
plus all 45 Sport finishes»* y del acabado *Vice*.

**3. Poses de muerte de agentes modernos (previo).** Las 24 comprobaciones
`death articulates torso …`, `animated corpse pelvis settles` y `headshot radius
follows larger body` dependen de `ModernAgentPose.gd` y de los datos de
animación, que no se modificaron: la comparación campo a campo de
`data/models_meta.json` contra el commit base muestra **0 campos no-audio
modificados** en las entradas conservadas (sólo se borraron 12 entradas de
modelos muertos).

## Inventario de audio actualizado

Al retirar la capa clásica sustituida por el audio nativo, dos comprobaciones de
inventario de `ArchiWeaponRuntimeTest` quedaron obsoletas y se actualizaron a lo
que realmente se envía:

| Constante | Antes | Ahora |
| :--- | ---: | ---: |
| `EXPECTED_ARCHI_WAVS` | 299 | **19** |
| `EXPECTED_CS2_WAVS` | 130 | **3** |

Siguen comprobando que cada WAV presente decodifica en Godot. La integridad de
las rutas la garantiza `tools/verify_godot_project.py`, que verifica las 627
rutas de audio (cues, voces, eventos de animación y literales de código).

## Comprobación de que no se tocó el gameplay

Comparación campo a campo contra el commit base `74e87ba`:

- `data/weapons.json`: 43 armas intactas, **0 campos no-sonido modificados**;
  sólo cambian rutas de sonido y se eliminan `hostage_touch_reward` /
  `hostage_rescue_reward`.
- `data/models_meta.json`: **0 campos no-audio modificados** en las 136 entradas
  conservadas; sólo se eliminan 12 entradas de modelos que ya no se envían.
