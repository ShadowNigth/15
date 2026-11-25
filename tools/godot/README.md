# Godot 4.3 incluido en el repositorio

Este proyecto necesita **Godot 4.3 estable** (`config/features` de
`project.godot`). Aquí queda una copia permanente del motor para poder importar
el proyecto y ejecutar las pruebas sin depender de descargas externas.

```bash
tools/godot/godot --version
tools/godot/godot --headless --path . --import
tools/godot/godot --headless --path . --fixed-fps 60 res://tests/TacticalAIRegressionTest.tscn
```

El lanzador descomprime el motor la primera vez en `.cache/godot/` (fuera de Git)
y a partir de ahí lo ejecuta directamente.

## Qué hay aquí

| Archivo | Qué es |
| :--- | :--- |
| `godot` | Lanzador POSIX; descomprime si hace falta y ejecuta el motor. |
| `godot-4.3-stable-linux-x86_64.xz` | Editor de Godot 4.3 estable para Linux x86_64, comprimido con xz. |
| `bootstrap.py` | Descomprime el motor, o lo recompila desde la fuente con `--rebuild`. |
| `LICENSE.txt` | Licencia MIT del motor (Godot Engine). |

## Por qué no se descarga de GitHub Releases

El entorno de agente sólo tiene salida de red a `github.com`,
`codeload.github.com`, `api.github.com`, `registry.npmjs.org`, `pypi.org` y
`files.pythonhosted.org`. Los binarios oficiales de Godot están en GitHub
Releases, y esa URL redirige a **`release-assets.githubusercontent.com`**, que no
está en la lista: la descarga falla siempre con `SSL_ERROR_SYSCALL`.

Rutas comprobadas y descartadas:

- `github.com/.../releases/download/...` → 302 a `release-assets.githubusercontent.com` (bloqueado).
- `api.github.com/.../releases/assets/<id>` → misma redirección.
- PyPI y npm: ningún paquete publica el editor de Godot 4.3 para Linux (los
  paquetes `godot*` son MCP/herramientas, no el motor).
- Binarios de Godot commiteados en otros repositorios (se pueden leer con la API
  de blobs de `api.github.com`): sólo hay 4.1, 4.2.2-mono, 4.7 y builds propios;
  ningún 4.3 estable para Linux.

## Ruta que sí funciona: compilar la fuente oficial

`codeload.github.com` **sí** está permitido, así que se descarga el tarball del
tag `4.3-stable` del repositorio oficial y se compila:

```bash
python3 tools/godot/bootstrap.py --rebuild -j2
```

Detalles que hacen viable la compilación en un entorno mínimo:

- Godot 4.3 en Linux usa `use_sowrap=yes`: X11, Xcursor, Xrandr, ALSA, PulseAudio,
  D-Bus y udev se cargan con `dlopen` en tiempo de ejecución. **No hacen falta
  headers de desarrollo** (`libx11-dev`, `libasound2-dev`, etc.).
- Todas las dependencias de terceros van `builtin` (freetype, harfbuzz, ICU,
  libpng, zlib, vorbis, webp, pcre2…), así que tampoco se consultan con
  `pkg-config`.
- `detect.py` sólo exige que `pkg-config --version` responda; `bootstrap.py`
  crea un stub temporal para esa única comprobación.
- Wayland se desactiva solo si falta `wayland-scanner`.
- `use_static_cpp=yes` (por defecto) enlaza libgcc/libstdc++ estáticamente, así
  que el binario es portable entre distribuciones.
- `scons` se instala desde PyPI, que sí está permitido.

Requisitos: `g++` (probado con GCC 12), `python3`, `make`, `ar`, `strip`.
Tiempo aproximado: ~50 minutos con 2 núcleos.

El binario resultante se comprime con xz y se versiona aquí, de modo que las
siguientes sesiones no necesiten volver a compilar nada.

## Licencia

Godot Engine se distribuye bajo licencia MIT; el texto completo está en
`LICENSE.txt`, tal como viene en el árbol de fuente oficial del tag `4.3-stable`.
El binario se construye sin modificar el código fuente.
