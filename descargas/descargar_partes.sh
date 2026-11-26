#!/bin/sh
# Descarga las partes una a una; conserva las que ya pasaron la verificación.
set -eu
base='https://raw.githubusercontent.com/ShadowNigth/15/arena/39b11b39-15/descargas'
command -v curl >/dev/null || { echo 'Se necesita curl.' >&2; exit 1; }
curl -fL -o SHA256SUMS.txt "$base/SHA256SUMS.txt"
i=1
while [ "$i" -le 14 ]; do
    part=$(printf 'Proyecto-Godot.zip.%03d' "$i")
    if [ -f "$part" ] && grep "  $part\$" SHA256SUMS.txt | sha256sum -c --status; then
        echo "$part ya está completa."
    else
        # Si un parcial no es válido o no puede reanudarse, se descarga de nuevo.
        curl -fL -o "$part" "$base/$part"
        grep "  $part\$" SHA256SUMS.txt | sha256sum -c -
    fi
    i=$((i + 1))
done
echo 'Descarga completa. Consulta LEEME_PARTES.txt para unir y abrir el proyecto.'
