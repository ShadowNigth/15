# Counter-Strike 1.5 Retail — Remake en Godot 4 (GDScript)

Remake jugable de **Counter-Strike 1.5 Retail** construido íntegramente en **Godot 4.x (GDScript)**. Los mapas, texturas de mundo, personajes, HUD, radio y constantes clásicas proceden de [`Ch0wW/counterstrike-betas` (`cs15_retail`)](https://github.com/Ch0wW/counterstrike-betas/tree/cs15_retail). Los **43 slots de armas** conservan modelos, texturas e iconos convertidos desde [`ShadowNigth/archi`](https://github.com/ShadowNigth/archi), con audio específico complementado por [`Source2Sounds/cs2`](https://github.com/Source2Sounds/cs2). Las armas/utilidades y los 22 cuchillos añadidos usan ahora animaciones nativas por modelo de [`zh667/ScCsgoKnives`](https://github.com/zh667/ScCsgoKnives), adaptadas a nuestros modelos y brazos originales.

---

## Cómo abrir y jugar en Godot 4

1. Abre **Godot Engine 4.3+** (compatible con Godot 4.3, 4.4, 4.5, 4.6+ en Windows, Linux, macOS y exportación HTML5/Web gracias al renderer `GL Compatibility`).
2. Haz clic en **Import** y selecciona el archivo `project.godot` en la raíz del repositorio (en la primera apertura Godot importará automáticamente las texturas y los `.glb`).
3. Pulsa **F5 (Run Project)**:
   - Se abrirá el **Menú Clásico WON de Counter-Strike 1.5** (`splash.png` original + sonidos `launch_glow1.wav` / `launch_select1.wav`).
   - Elige **Quick Launch: de_dust2** o **Play CS 1.5 (LAN / Bots)** para escoger cualquiera de los **26 mapas originales**, cantidad de **Bots IA**, nivel de habilidad y dinero inicial (`$800` / `$3500` / `$16000`).
   - También puedes abrir **3D Arsenal, Skins & Models** para inspeccionar los modelos y animaciones, elegir los **120 acabados anteriores más 44 incorporados al catálogo de armas**, además de los acabados de cuchillo y previsualizar los guantes para la próxima partida. **Original HD** siempre permanece disponible.

---

## Animaciones nativas de armas y utilidades

- **42 conjuntos / 289 clips originales:** 35 armas de fuego, seis granadas y C4.
- Desenfunde, disparo, recarga, inspecciones y variantes disponibles de cada modelo; **52 inspecciones** de armas/utilidades. T recorre las inspecciones de ese modelo.
- Se conservan todos los vértices, normales, UV, pesos, índices, materiales y matrices de enlace originales. Los cargadores, correderas, cerrojos y silenciadores siguen sus curvas nativas mediante calibración de sus pivotes.
- El R8 compone correctamente su animación aditiva sobre idle; se ocultan los accesorios de recarga cuando no corresponden. La CZ75 recuerda la retirada de su cargador delantero y pasa a las variantes posteriores.
- Se mantienen los tiempos de acción existentes: las recargas y sus sonidos se reproducen a la velocidad necesaria para terminar junto con el temporizador de juego. Las escopetas conservan la recarga interrumpible por cartucho y muestran la primera inserción antes de acreditarlo.
- Los 22 cuchillos añadidos conservan sus **235 clips / 33 inspecciones nativas** ya corregidos. El cuchillo original no se sustituye.
- Los clips auxiliares de transición y miras también están incluidos en los GLB; no se inventan estados de CS2 incompatibles con las reglas clásicas de este juego.

El selector **Preview animation** del Arsenal permite reproducir cualquier clip importado, incluidas las variantes y transiciones auxiliares.

Más detalles y reproducción de pruebas: [`docs/NATIVE_WEAPON_ANIMATIONS.md`](docs/NATIVE_WEAPON_ANIMATIONS.md). El ZIP de código es el proyecto editable: **no incluye Godot ni ejecutables**. Las publicaciones ejecutables anteriores no contienen necesariamente estas animaciones.

---

## Contenido extraído e incluido en el proyecto

Todo el contenido de `cstrike/` fue procesado mediante la suite de ingeniería inversa GoldSrc en `tools/goldsrc/`:

| Categoría | Origen en `cs15_retail` | Formato en Godot 4 | Cantidad |
| :--- | :--- | :--- | :--- |
| **Mapas 3D + Lightmaps** | `maps/*.bsp` (GoldSrc BSP v30 + 23 WAD3) | `assets/maps/*.glb` + `*_lm.png` + `data/maps/*.json` | **26 / 26 mapas** |
| **Grafo de Navegación IA** | Hull 1 (`CLIPNODES`) de cada `.bsp` | `waypoints` A* en `data/maps/*.json` | **26 grafos** (230–340 nodos/mapa) |
| **Texturas de Mundo + Cielos** | `*.wad` (`de_aztec`, `cs_dust`, `halflife`…) + `gfx/env/*.tga` | PNG originales con mipmaps, sin overrides reescalados | **2,346 texturas originales + 109 caras skybox** |
| **Materiales HD de armas** | VMT/VTF de `ShadowNigth/archi` | `assets/textures/archi/` + `data/archi_materials.json` | **54 materiales + 136 mapas compartidos de hasta 2K** |
| **Skins UV auténticas** | Valve / CS:GO Ports / BDS, vía `cs16-skin-inventory` | `assets/textures/weapon_skins/` + `data/weapon_skins.json` | **120 acabados / 20 familias + Original HD** |
| **Modelos 3D Animados** | StudioMDL GoldSrc + MDL/VTF de `ShadowNigth/archi` | `assets/models/**/*.glb` (esqueleto + animaciones + winding CCW) | **293 modelos `.glb`** |
| **Arsenal** | 27 slots clásicos reemplazados + 16 armas/utilidades de archi | `data/weapons.json` | **43 slots + equipamiento** |
| **Audio Espacial & Radio** | `cs15_retail` + 299 WAV de archi + 130 WAV específicos de CS2 | `assets/sounds/**/*.wav` (PCM 16-bit limpio) | **973 archivos `.wav`** |
| **Sprites HUD & VGUI** | `sprites/*.spr`, `hud.txt`, `gfx/vgui/*.tga`, `overviews/*.bmp` | `assets/sprites/*.png`, `assets/ui/**`, `data/hud_sprites.json` | **88 sprites + 42 VGUI + 26 radares** |

### Los 26 Mapas Clásicos Incluidos
- **Bomb / Defuse (`de_*`)**: `de_aztec`, `de_cbble`, `de_chateau`, `de_dust`, `de_dust2`, `de_inferno`, `de_nuke`, `de_piranesi`, `de_prodigy`, `de_storm`, `de_survivor`, `de_torn`, `de_train`, `de_vegas`, `de_vertigo`.
- **Hostage Rescue (`cs_*`)**: `cs_747`, `cs_assault`, `cs_backalley`, `cs_estate`, `cs_havana`, `cs_italy`, `cs_militia`, `cs_office`, `cs_siege`.
- **VIP Assassination (`as_*`)**: `as_oilrig`, `as_tundra`.

---

## Mecánicas de Juego Implementadas

- **Física GoldSrc Auténtica (`CSActor.gd`)**: Aceleración terrestre y strafe aéreo estilo GoldSrc, velocidades máximas por arma extraídas de `cs_i386.so` (`260` Scout, `250` Cuchillo/Pistolas, `221` AK-47, `210` AWP), agachado (`Ctrl`), caminata silenciosa (`Shift`), escaleras (`func_ladder`) y sonidos de pisadas por tipo de superficie (`materials.txt`).
- **Arsenal clásico reemplazado por archi + 16 adiciones (`WeaponController.gd`)**:
  - **Pistolas**: USP `.45` (con silenciador desmontable `Mouse2`), Glock 18 (modo ráfaga de 3 disparos `Mouse2`), Desert Eagle, P228, Dual Berettas, Five-Seven.
  - **Escopetas**: M3 Super 90 y XM1014 (recarga cartucho por cartucho interrumpible al disparar).
  - **SMGs**: MP5 Navy, TMP silenciada, P90, MAC-10, UMP-45.
  - **Rifles y Francotiradores**: AK-47, Colt M4A1 Carbine (con silenciador desmontable `Mouse2`), SG-552, Steyr AUG, Scout, **AWP Magnum** (mira telescópica doble zoom), G3SG1, SG-550.
  - **Pesadas / Tácticas**: M249 Para, Cuchillo (corte rápido y **puñalada por la espalda de 195 de daño**), C4 Plastic Explosive, HE Grenade, Flashbang (ceguera direccional en pantalla y a Bots), Smoke Grenade (bloquea visión de Bots IA) y Wallbanging en paredes delgadas.
  - **Nuevas armas de archi**: P2000, CZ75-Auto, R8 Revolver (martillo y fuego alternativo), Tec-9, FAMAS (ráfaga), Galil AR, M4A4, MAG-7 (cargador), Sawed-Off (cartuchos), Negev, PP-Bizon y MP7.
  - **Nuevas utilidades**: Zeus x27 de una carga, Decoy con señuelo sonoro y explosión final, Molotov e Incendiaria con fuego persistente. Todos los slots incluyen sus GLB V/P/W, iconos, animaciones de archi y audio específico de archi/CS2.
  - **Fuego con propagación física**: Molotov e Incendiaria encienden focos escalonados sobre el piso, se expanden alrededor de obstáculos y aplican daño sólo dentro de las llamas activas. La Molotov usa ahora 30–68 parches conectados, ramas y una envolvente irregular más amplia, con semilla independiente por lanzamiento; no es un círculo prefabricado. Incluyen llamas por capas, brasas, humo, quemaduras y luz parpadeante.
  - **Presentación y materiales corregidos**: las armas conservan tamaño normal (`1.0`), las granadas en mano/proyectil usan `0.90` y las soltadas en el piso `1.0`. M4A1/USP mantienen el acople con las manos al inspeccionar, la corredera de Glock se mueve al disparar y el silenciador permanece visible durante su animación de montaje/desmontaje, ocultándose únicamente en estado desmontado. Las máscaras de tinte y lentes negras se conservan, el acabado de primera persona es más brillante/metálico y el Molotov combina vidrio verde y líquido translúcidos con etiqueta y trapo legibles.
  - **Inspecciones alternativas y materiales HD**: `T` rota las inspecciones auténticas disponibles. Deagle añade su secuencia larga con nueve eventos de foley, C4 añade dos variantes y las seis granadas añaden una segunda; recarga y plantado siguen bloqueando la inspección. 54 materiales comparten 136 texturas de color, normales y rugosidad derivada de Phong, con resolución de hasta 2K y sin alterar los brazos, guantes, tintes ni acabados ya calibrados.
  - **Selector de skins auténticas**: el 3D Arsenal ofrece seis acabados identificados para cada una de 20 familias (120 en total), con vista previa inmediata y selección independiente por arma para la próxima partida. Los PNG conservan los mapas UV originales de 512px, no son recolores procedurales; se aplican al viewmodel, tercera persona y drops sin reemplazar geometría, normales, roughness, miras, animaciones ni audio. Cada opción registra su paint-kit oficial, cotejado con `items_game.txt` y `csgo_english.txt` de GameTracking-CS2. Los créditos y términos de Valve/CS:GO Ports/BDS se conservan en `data/weapon_skins.json` y `tools/source/README.md`.
  - **Brazos originales y Sport Gloves opcionales**: los 43 viewmodels conservan sus brazos originales `ct_arms.bmp`. Se puede elegir el guante clásico o uno de 26 acabados Sport con binds nativos y winding exterior corregido; no se utiliza MultiRig ni retargeting híbrido.
- **Economía, Rondas y Objetivos (`RoundManager.gd`, `BuyMenu.gd`)**:
  - Freeze time, Buy time en `func_buyzone`, menú VGUI clásico con previsualización de armas y **atajos rápidos clásicos** (ej. `B-4-1` AK-47, `B-4-3` M4A1, `B-4-6` AWP, `B-8-2` Kevlar+Casco, `,` y `.` para munición primaria/secundaria).
  - Plantado y desactivación del **C4** (`de_*`, 5s con Defuse Kit / 10s sin Kit), rescate de **Rehenes** (`cs_*` con `E`) y escolta de **VIP** (`as_*`).
- **HUD Ámbar Original y VGUI (`CSHud.gd`, `TeamSelectMenu.gd`, `Scoreboard.gd`, `RadioMenu.gd`)**:
  - Números ámbar recortados del atlas original `640hud7.spr`, radar giratorio con puntos de aliados/bomba/rehenes, killfeed con iconos `d_*` de `hud.txt`, indicador de zona de compra/C4/Kit, linterna (`F`) y **Visión Nocturna verde (`N`)**.
- **Bots IA estilo PodBot (`CSBot.gd`, `BotNavigator.gd`)**:
  - Compras legales variadas según presupuesto, personalidad y composición de escuadra; navegación A* compartida sobre el grafo del BSP con costes de contactos y fuego, cobertura física al recargar, plantado/desactivación de C4 y rescate de rehenes. En `as_*`, el VIP bot navega activamente hasta las zonas auténticas `func_vip_safetyzone`, los CT mantienen una escolta móvil sin acampar al quedar asignados y los T cazan o preparan emboscadas. En `cs_*`, los rescatadores reparten objetivos, recorren los últimos metros hasta cada rehén, vuelven a por seguidores bloqueados y escoltan hacia volúmenes reales de rescate. Conservan reacción a sonidos, Flashbang, humo y órdenes de radio (`Z` / `X` / `C`).

---

## Controles Clásicos

| Tecla | Acción |
| :--- | :--- |
| `W A S D` | Movimiento |
| `Espacio` / `Ctrl` / `Shift` | Saltar / Agacharse / Caminar en silencio |
| `Click Izquierdo` | Disparar / Plantar C4 en Bombsite |
| `Click Derecho` | Zoom (AWP/Scout/AUG/SG552) / Silenciador (M4A1, USP) / Ráfaga (Glock) / Puñalada |
| `R` / `G` / `Q` | Recargar / Soltar arma al suelo / Última arma usada |
| `T` | Inspeccionar / alternar las inspecciones auténticas disponibles |
| `1` `2` `3` `4` `5` | Primaria / Pistola / Cuchillo / Granadas / C4 |
| `B` | Menú de Compra VGUI (soporta combinaciones numéricas como `B-4-3`, `B-8-2`) |
| `,` (Coma) / `.` (Punto) | Comprar munición primaria / secundaria |
| `E` | Desactivar C4 / Guiar Rehén / Abrir Puerta |
| `F` / `N` | Linterna / Gafas de Visión Nocturna |
| `M` | Cambiar de Equipo / Clase (Terrorist / Counter-Terrorist) |
| `Z` / `X` / `C` | Menús de Radio Táctica |
| `Tab` / `Esc` | Tabla de Puntuaciones / Menú de Pausa (añadir Bots, reiniciar ronda) |

---

## Estructura del Proyecto y Herramientas de Extracción

```text
├── project.godot                # Configuración de Godot 4 (GL Compatibility, Autoloads)
├── scenes/
│   ├── MainMenu.tscn            # Escena inicial (Menú WON + Selector de 26 mapas + Visor 3D)
│   └── GameWorld.tscn           # Escena principal de partida
├── scripts/
│   ├── core/                    # GameData.gd, AudioManager.gd, RoundManager.gd
│   ├── actors/                  # CSActor.gd (física GoldSrc), PlayerController.gd
│   ├── weapons/                 # WeaponController.gd (balística, retroceso, recarga, C4)
│   ├── ai/                      # BotNavigator.gd (AStar3D), CSBot.gd (IA táctica)
│   ├── world/                   # MapLoader.gd, SkyBuilder.gd, PlantedC4.gd, HostageNPC.gd...
│   └── ui/                      # MainMenu.gd, CSHud.gd, BuyMenu.gd, TeamSelectMenu.gd...
├── assets/                      # Mapas .glb, lightmaps, modelos .glb, sonidos .wav, sprites, shaders
├── data/                        # JSONs de armas, clases, mapas, waypoints, HUD, overviews y radio
└── tools/
    ├── extract_cs15.py          # Pipeline completo para regenerar todos los assets desde cs15_retail
    ├── verify_godot_project.py  # Verificador AST GDScript + integridad binaria GLB/JSON/WAV
    └── goldsrc/                 # Convertidores Python de BSP v30, StudioMDL v10, WAD3, SPR y cs_i386.so
```

Para volver a ejecutar la extracción desde un clon local de `cs15_retail` o validar la integridad completa del proyecto:
```bash
python3 tools/extract_cs15.py --src /ruta/a/counterstrike-betas/cstrike --out .
python3 tools/verify_godot_project.py

# Después de la primera importación, pruebas reales de recursos y mecánicas:
godot --headless --path . res://tests/ArchiWeaponRuntimeTest.tscn
godot --headless --path . --fixed-fps 60 res://tests/ArchiGameWorldSmokeTest.tscn
godot --headless --path . --fixed-fps 60 res://tests/IncendiaryProceduralTest.tscn
godot --headless --path . --fixed-fps 60 res://tests/MapSurfaceWaterTest.tscn
godot --headless --path . --fixed-fps 60 res://tests/TacticalAIRegressionTest.tscn
godot --headless --path . --fixed-fps 60 res://tests/MissionObjectiveRegressionTest.tscn
```

## Cuchillos y proyecto para Godot

En **Create Game → Knife model** y en el Arsenal 3D se elige entre el Kukri
original y los 22 modelos CS2. Los tres acabados integrados inicialmente
(Karambit Gamma Doppler Phase 4, M9 Gamma Doppler Phase 1 y Bayonet Ruby)
continúan disponibles, ahora con los clips propios de sus respectivos modelos.
Ranura `3`: cuchillo; clic izquierdo: ataque ligero; clic derecho: puñalada;
`T`: inspección y rotación de las variantes disponibles para ese modelo.

El proyecto se abre importando `project.godot` con Godot 4.3 y se ejecuta con
**F5**. No requiere los ejecutables ni `.pck` de las descargas independientes.
La primera importación de recursos puede tardar varios minutos.

### Catálogo completo de cuchillos y acabados

**Create Game → Knife model** y el Arsenal 3D ofrecen los **22 cuchillos del
repositorio fuente**, además del Kukri original. El selector **Weapon finish**
se adapta al cuchillo seleccionado, conserva una elección independiente por
modelo y ofrece sus acabados de fábrica y pintados compatibles: **22 de fábrica
+ 20 pintados**. Las armas conservan las **120 skins BDS** anteriores y añaden
los **44 acabados de armas** disponibles en el mismo catálogo fuente.

El chrome PBR de los cuchillos es discreto y queda subordinado a la textura;
normal/ORM cambian junto al acabado. Las poses de manos, dedos, hojas y bisagras
proceden de los clips propios de cada modelo. Se conserva y retargetea la
geometría de brazos y guantes existente; no se instala la malla de brazos nativa
del port. Los Shadow Daggers tienen geometría y movimiento separados para ambas
manos en primera persona.
Se conserva el daño, velocidad, ranura y economía del cuchillo clásico.


### Corrección de animaciones de los cuchillos

Los 22 cuchillos CS2 usan ahora sus propios clips de equipar, reposo, ataques e
inspección, incluidas variantes disponibles en el catálogo. Ya no comparten las
poses del Kukri. Las poses nativas se retargetean a la geometría de brazos y
Sport Gloves existente; no se reemplazan sus texturas ni los rigs de armas de
fuego. Se corrige la inversión doble de mano y se conserva el encuadre del origen.
Los datos y limitaciones de conversión figuran en `docs/KNIFE_ASSET_NOTICES.md`
y `data/native_knife_animation_report.json`.

Validación de esta corrección: **3.185 comprobaciones headless y 3.782 con OpenGL**,
235 clips importados, 33 variantes de inspección y 199 capturas del catálogo
(reposo, múltiples fases de todas las inspecciones y acabados de armas).
[QA completa y capturas](https://github.com/ShadowNigth/15/actions/runs/42323185698).
Las compilaciones ejecutables anteriores no contienen esta corrección; el
proyecto actualizado sí. Las advertencias del renderer dummy en headless no
sustituyen la revisión de las capturas reales.
