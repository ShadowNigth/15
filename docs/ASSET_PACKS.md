# Assets empaquetados (`packs/`) — el «VPK» de este proyecto

Los modelos, mapas, texturas y sonidos ya no se guardan sueltos en Git. Igual que
Source usa `pak01_dir.vpk` + `pak01_000.vpk`, aquí hay un **índice**
(`packs/pak_dir.idx`) y **archivos por categoría** (`packs/<categoría>_NNN.pak`).
La carpeta `assets/` se reconstruye a partir de ellos y **cada archivo queda
idéntico byte a byte al original** (se comprueba su SHA-256): no se recodifica
ninguna textura, malla, animación ni sonido, así que no hay pérdida de calidad.

| | Antes | Ahora |
| :--- | ---: | ---: |
| Assets en el repositorio | 1,24 GB sueltos (6 739 archivos) | **580 MB** en 19 archivos `.pak` |
| Modelos + mapas (`.glb`) | 776 MB | 193 MB |
| Sonidos | 102 MB | 44 MB |
| Texturas, sprites e interfaz | 345 MB | 342 MB (ya eran PNG/JPG/WebP) |

El desglose actualizado está siempre en [`packs/CONTENTS.md`](../packs/CONTENTS.md).

## Uso

| Quiero… | Comando |
| :--- | :--- |
| Preparar el proyecto tras clonar/descargar | `unpack_assets.bat` · `./unpack_assets.sh` · `python tools/pak.py unpack` |
| Guardar cambios hechos en `assets/` | `python tools/pak.py pack` y hacer commit de `packs/` |
| Ver qué cambió y aún no está empaquetado | `python tools/pak.py status` |
| Comprobar la integridad de los archivos | `python tools/pak.py verify` (`--deep` reconstruye todo) |
| Listar el contenido | `python tools/pak.py list [categoría]` |
| Restaurar solo una parte | `python tools/pak.py unpack --only maps sounds/radio/` |

Solo hace falta **Python 3.8+** (biblioteca estándar). Desempaquetar tarda unos
segundos; empaquetar todo, unos 2–4 minutos (usa `-j N` para fijar los procesos;
cada uno necesita ~0,7 GB de RAM).

### Reglas importantes

1. **`assets/` está en `.gitignore`** (salvo `assets/shaders/`, que sigue siendo
   texto normal). Un cambio en `assets/` **no llega a Git hasta ejecutar
   `python tools/pak.py pack`**. `status` avisa de lo pendiente.
2. `unpack` nunca pisa un archivo que hayas modificado: lo deja y te avisa
   (`pack` para conservarlo, `unpack --force` para descartarlo). Tras un
   `git pull`, vuelve a ejecutar `unpack` para actualizar lo que cambió.
3. `pack` ignora lo que genera el importador de Godot dentro de `assets/`
   (`*.import` nuevos y texturas extraídas de los `.glb`). Usa `pack --all`
   si de verdad quieres versionar alguno.
4. `pack` verifica antes de escribir que todos los archivos se reconstruyen
   bit a bit; si algo falla, los `.pak` anteriores no se tocan.
5. Godot no mira `packs/` (`.gdignore`) y los presets de exportación lo
   excluyen: el juego exportado sigue usando el `.pck` normal de Godot.

## Organización

| Archivo | Contenido de `assets/` |
| :--- | :--- |
| `maps` | `maps/` (BSP convertidos + lightmaps) |
| `models_weapons` | `models/weapons/`, `models/props/`, `models/native/` |
| `models_held` | `models/held/` (armas en tercera persona) |
| `models_arms` | `models/native_view/`, `models/agent_arms/`, `models/sport_gloves/` |
| `models_players` | `models/players/`, `models/modern/` |
| `textures_world` | `textures/world/`, `textures/sky/`, `textures/graffiti/` |
| `textures_weapons` | `textures/archi/`, `weapon_skins/`, `cs2_catalog/`, `cs2go/` |
| `textures_gloves` | `textures/native_sport/`, `sport_gloves/`, `moto_smoke_out*/` |
| `sounds_weapons` | `sounds/weapons/` |
| `sounds_native` | `sounds/native/` |
| `sounds_world` | resto de `sounds/` (ambiente, radio, jugador…) |
| `ui` | `ui/`, `sprites/`, `polish/` |
| `models_misc`, `textures_misc`, `misc` | cualquier carpeta nueva que no encaje arriba |

La tabla vive en `ARCHIVES` al principio de `tools/pak.py`. Cada archivo se
parte en trozos de ≤ 48 MB para no superar los límites de GitHub.

## Cómo se reduce sin perder calidad

* **Piezas repetidas una sola vez.** Cada `.glb` se divide por sus fronteras
  internas (JSON, cada `bufferView`, cada imagen incrustada). La misma textura
  de brazos incrustada en decenas de viewmodels, la misma pista de animación o
  la misma malla se guardan una única vez para todo el proyecto (más de 250 MB eran
  repeticiones). Los archivos idénticos también.
* **LZMA2 sólido** para geometría, animación y JSON; **delta + LZMA2** alineado
  a la muestra para los WAV PCM (similar a FLAC, bit a bit exacto).
* PNG, JPG, WebP y OGG **se guardan tal cual**: ya están comprimidos y
  recodificarlos sin pérdida solo ahorraría un 3–5 % a cambio de romper los
  SHA-256 de procedencia de `data/*.json`.

## Qué se eliminó por irrelevante

* `assets/models/native/ct.glb`, `t.glb`, `hostage.glb`, `chicken.glb` (≈ 85 MB):
  modelos de revisión que el juego no carga desde la vuelta a los personajes
  clásicos (`docs/CLASSIC_CHARACTER_ROLLBACK.md`). Se retiraron también sus
  entradas en `data/native_world_manifest.json` y las comprobaciones asociadas.

## Límites honestos

* El editor de Godot necesita los archivos sueltos para importarlos, por eso
  hay que desempaquetar: con `assets/` restaurado la carpeta de trabajo ocupa
  `packs/` (580 MB) + `assets/` (1,1 GB). Lo que se reduce es el repositorio,
  la descarga y cada commit.
* El 60 % de lo que queda son texturas ya comprimidas. Bajar más exigiría
  compresión **con pérdida** o menor resolución (p. ej. los mapas 2K de
  `textures/archi/`), y eso es una decisión artística aparte.
* El historial de Git anterior conserva los assets sueltos; un clon completo
  los sigue descargando hasta que se reescriba/aplaste el historial. `git clone
  --depth 1` y «Download ZIP» ya obtienen solo la versión compacta.
