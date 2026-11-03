# Counter-Strike 1.5 Retail — Remake en Godot 4 (GDScript)

Remake jugable de **Counter-Strike 1.5 Retail** construido íntegramente en **Godot 4.x (GDScript)**. Los mapas, texturas de mundo, personajes, HUD, radio y constantes clásicas proceden de [`Ch0wW/counterstrike-betas` (`cs15_retail`)](https://github.com/Ch0wW/counterstrike-betas/tree/cs15_retail). Los **43 slots de armas** usan modelos, texturas, iconos y sonidos convertidos desde [`ShadowNigth/archi`](https://github.com/ShadowNigth/archi), con sus animaciones y eventos.

---

## Cómo abrir y jugar en Godot 4

1. Abre **Godot Engine 4.3+** (compatible con Godot 4.3, 4.4, 4.5, 4.6+ en Windows, Linux, macOS y exportación HTML5/Web gracias al renderer `GL Compatibility`).
2. Haz clic en **Import** y selecciona el archivo `project.godot` en la raíz del repositorio (en la primera apertura Godot importará automáticamente las texturas y los `.glb`).
3. Pulsa **F5 (Run Project)**:
   - Se abrirá el **Menú Clásico WON de Counter-Strike 1.5** (`splash.png` original + sonidos `launch_glow1.wav` / `launch_select1.wav`).
   - Elige **Quick Launch: de_dust2** o **Play CS 1.5 (LAN / Bots)** para escoger cualquiera de los **26 mapas originales**, cantidad de **Bots IA**, nivel de habilidad y dinero inicial (`$800` / `$3500` / `$16000`).
   - También puedes abrir el **3D Arsenal & Model Viewer** desde el menú principal para inspeccionar en 3D los modelos `.glb` de armas y personajes convertidos desde `.mdl` junto con sus estadísticas extraídas de `cs_i386.so`.

---

## Contenido extraído e incluido en el proyecto

Todo el contenido de `cstrike/` fue procesado mediante la suite de ingeniería inversa GoldSrc en `tools/goldsrc/`:

| Categoría | Origen en `cs15_retail` | Formato en Godot 4 | Cantidad |
| :--- | :--- | :--- | :--- |
| **Mapas 3D + Lightmaps** | `maps/*.bsp` (GoldSrc BSP v30 + 23 WAD3) | `assets/maps/*.glb` + `*_lm.png` + `data/maps/*.json` | **26 / 26 mapas** |
| **Grafo de Navegación IA** | Hull 1 (`CLIPNODES`) de cada `.bsp` | `waypoints` A* en `data/maps/*.json` | **26 grafos** (230–340 nodos/mapa) |
| **Texturas de Mundo + Cielos** | `*.wad` (`de_aztec`, `cs_dust`, `halflife`…) + `gfx/env/*.tga` | `assets/textures/world/*.png` (`{` alpha Fence) + `sky/*.png` | **2,346 texturas + 109 caras skybox** |
| **Modelos 3D Animados** | StudioMDL GoldSrc + MDL/VTF de `ShadowNigth/archi` | `assets/models/**/*.glb` (esqueleto + animaciones + winding CCW) | **184 modelos `.glb`** |
| **Arsenal** | 27 slots clásicos reemplazados + 16 armas/utilidades de archi | `data/weapons.json` | **43 slots + equipamiento** |
| **Audio Espacial & Radio** | `cs15_retail` + 299 WAV originales de archi | `assets/sounds/**/*.wav` (PCM 16-bit limpio) | **843 archivos `.wav`** |
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
  - **Nuevas utilidades**: Zeus x27 de una carga, Decoy con señuelo sonoro y explosión final, Molotov e Incendiaria con fuego persistente. Todos los slots incluyen sus GLB V/P/W, iconos y animaciones/sonidos de archi.
  - **Fuego con propagación física**: Molotov e Incendiaria encienden focos escalonados sobre el piso, se expanden alrededor de obstáculos y aplican daño sólo dentro de las llamas activas. Incluyen llamas por capas, brasas, humo, quemaduras y luz parpadeante.
  - **Materiales y granadas corregidos**: las máscaras de tinte CS2 se conservan en los modelos V/P/W, las lentes mantienen su color negro también en los drops y todas las granadas lanzadas/soltadas usan una escala visual moderada y consistente (`0.90`).
- **Economía, Rondas y Objetivos (`RoundManager.gd`, `BuyMenu.gd`)**:
  - Freeze time, Buy time en `func_buyzone`, menú VGUI clásico con previsualización de armas y **atajos rápidos clásicos** (ej. `B-4-1` AK-47, `B-4-3` M4A1, `B-4-6` AWP, `B-8-2` Kevlar+Casco, `,` y `.` para munición primaria/secundaria).
  - Plantado y desactivación del **C4** (`de_*`, 5s con Defuse Kit / 10s sin Kit), rescate de **Rehenes** (`cs_*` con `E`) y escolta de **VIP** (`as_*`).
- **HUD Ámbar Original y VGUI (`CSHud.gd`, `TeamSelectMenu.gd`, `Scoreboard.gd`, `RadioMenu.gd`)**:
  - Números ámbar recortados del atlas original `640hud7.spr`, radar giratorio con puntos de aliados/bomba/rehenes, killfeed con iconos `d_*` de `hud.txt`, indicador de zona de compra/C4/Kit, linterna (`F`) y **Visión Nocturna verde (`N`)**.
- **Bots IA estilo PodBot (`CSBot.gd`, `BotNavigator.gd`)**:
  - Compra automática según presupuesto y equipo, navegación A* sobre el grafo del BSP, plantado/desactivación de C4, rescate de rehenes, escolta VIP, reacción a sonidos de disparos, ceguera por Flashbang, bloqueo visual por humo y órdenes de radio (`Z` / `X` / `C`).

---

## Controles Clásicos

| Tecla | Acción |
| :--- | :--- |
| `W A S D` | Movimiento |
| `Espacio` / `Ctrl` / `Shift` | Saltar / Agacharse / Caminar en silencio |
| `Click Izquierdo` | Disparar / Plantar C4 en Bombsite |
| `Click Derecho` | Zoom (AWP/Scout/AUG/SG552) / Silenciador (M4A1, USP) / Ráfaga (Glock) / Puñalada |
| `R` / `G` / `Q` | Recargar / Soltar arma al suelo / Última arma usada |
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
```
