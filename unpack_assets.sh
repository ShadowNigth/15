#!/bin/sh
# Restores assets/ (models, maps, textures, sounds) from the archives in packs/.
cd "$(dirname "$0")" || exit 1
if command -v python3 >/dev/null 2>&1; then PY=python3; else PY=python; fi
exec "$PY" tools/pak.py unpack "$@"
