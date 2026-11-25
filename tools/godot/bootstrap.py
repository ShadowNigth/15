#!/usr/bin/env python3
"""Instala (o reconstruye) el Godot 4.3 estable que usa este proyecto.

Por qué existe este script
--------------------------
El entorno de agente sólo tiene salida de red a github.com, codeload.github.com,
api.github.com, registry.npmjs.org, pypi.org y files.pythonhosted.org. Los
binarios oficiales de Godot viven en GitHub Releases, que redirige a
`release-assets.githubusercontent.com`: ese host NO está permitido, así que la
descarga directa del editor falla siempre (SSL_ERROR_SYSCALL).

La ruta que sí funciona es compiling desde el código fuente oficial:
  * codeload.github.com  -> tarball del tag `4.3-stable` (permitido)
  * pypi.org             -> `scons` (permitido)
Godot 4.3 en Linux usa `use_sowrap=yes`, es decir carga X11/ALSA/Pulse/udev con
dlopen en tiempo de ejecución, y todas sus dependencias de terceros van
`builtin`. Por eso NO hacen falta headers de desarrollo: basta g++ y scons.

Uso
---
    python3 tools/godot/bootstrap.py            # descomprime el motor incluido
    python3 tools/godot/bootstrap.py --rebuild  # recompila desde la fuente

El resultado queda en `tools/godot/godot-4.3-stable-linux-x86_64.xz` (versionado)
y el lanzador `tools/godot/godot` lo descomprime en `.cache/godot/` al usarlo.
"""

from __future__ import annotations

import argparse
import lzma
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
NAME = "godot-4.3-stable-linux-x86_64"
ARCHIVE = HERE / f"{NAME}.xz"
CACHE = ROOT / ".cache" / "godot"
TAG = "4.3-stable"
TARBALL = f"https://codeload.github.com/godotengine/godot/tar.gz/refs/tags/{TAG}"
# `pkg-config --version` es lo único que exige detect.py cuando se usa sowrap
# con todas las dependencias builtin; el resto de consultas no se llegan a hacer.
PKG_CONFIG_STUB = '#!/bin/sh\ncase "$1" in\n  --version) echo "1.8.1"; exit 0;;\n  *) exit 1;;\nesac\n'


def extract() -> Path:
    """Descomprime el motor archivado en el repositorio y devuelve su ruta."""
    if not ARCHIVE.is_file():
        sys.exit(f"No existe {ARCHIVE}. Ejecuta: python3 tools/godot/bootstrap.py --rebuild")
    CACHE.mkdir(parents=True, exist_ok=True)
    target = CACHE / NAME
    if not target.is_file() or target.stat().st_size == 0:
        print(f"[godot] descomprimiendo {ARCHIVE.name} -> {target}")
        with lzma.open(ARCHIVE, "rb") as src, open(target, "wb") as dst:
            shutil.copyfileobj(src, dst, 1 << 20)
        target.chmod(0o755)
    return target


def _run(cmd: list[str], **kw) -> None:
    print("+", " ".join(str(c) for c in cmd), flush=True)
    subprocess.run([str(c) for c in cmd], check=True, **kw)


def rebuild(jobs: int) -> Path:
    work = Path(tempfile.mkdtemp(prefix="godot_build_"))
    print(f"[godot] directorio de compilación: {work}")
    bindir = work / "bin"
    bindir.mkdir()
    stub = bindir / "pkg-config"
    stub.write_text(PKG_CONFIG_STUB)
    stub.chmod(0o755)

    tarball = work / "godot.tar.gz"
    print(f"[godot] descargando {TARBALL}")
    with urllib.request.urlopen(TARBALL, timeout=600) as resp, open(tarball, "wb") as out:
        shutil.copyfileobj(resp, out, 1 << 20)
    with tarfile.open(tarball) as tf:
        tf.extractall(work)
    src = work / f"godot-{TAG}"
    if not src.is_dir():
        sys.exit(f"No se encontró el árbol de fuente en {src}")

    scons = shutil.which("scons")
    if not scons:
        venv = work / "venv"
        _run([sys.executable, "-m", "venv", venv])
        pip = venv / "bin" / "pip"
        _run([pip, "install", "--quiet", "scons==4.8.1"])
        scons = str(venv / "bin" / "scons")

    env = dict(os.environ)
    env["PATH"] = f"{bindir}{os.pathsep}{env.get('PATH', '')}"
    _run(
        [scons, "platform=linuxbsd", "target=editor", "debug_symbols=no",
         "module_openxr_enabled=no", f"-j{jobs}"],
        cwd=src, env=env,
    )

    built = src / "bin" / "godot.linuxbsd.editor.x86_64"
    if not built.is_file():
        sys.exit(f"La compilación no produjo {built}")
    if shutil.which("strip"):
        _run(["strip", "--strip-unneeded", built])

    HERE.mkdir(parents=True, exist_ok=True)
    print(f"[godot] comprimiendo -> {ARCHIVE}")
    with open(built, "rb") as raw, lzma.open(ARCHIVE, "wb", preset=6) as dst:
        shutil.copyfileobj(raw, dst, 1 << 20)
    shutil.copy2(src / "LICENSE.txt", HERE / "LICENSE.txt")
    print(f"[godot] listo: {ARCHIVE.stat().st_size / 1e6:.1f} MB comprimidos")
    shutil.rmtree(work, ignore_errors=True)
    return extract()


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--rebuild", action="store_true", help="recompila desde el código fuente oficial")
    ap.add_argument("-j", "--jobs", type=int, default=max(1, min(os.cpu_count() or 1, 4)))
    ap.add_argument("--version", action="store_true", help="ejecuta `godot --version` al terminar")
    args = ap.parse_args()
    binary = rebuild(args.jobs) if args.rebuild else extract()
    print(f"[godot] motor disponible en: {binary}")
    if args.version:
        _run([binary, "--version"])


if __name__ == "__main__":
    main()
