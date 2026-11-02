#!/usr/bin/env bash
# Gera os PNGs da marca (SPEC-029) a partir dos SVGs em assets/icon/mark/.
# 16–24 px saem do desenho simplificado (mark-small.svg); 32 px em diante, de mark.svg.
# Usa rsvg-convert quando existe; senão, o Inkscape.
set -euo pipefail
cd "$(dirname "$0")/.."
dir=assets/icon/mark
render() { # svg tamanho saída
  if command -v rsvg-convert >/dev/null; then
    rsvg-convert -w "$2" -h "$2" "$1" -o "$3"
  elif command -v inkscape >/dev/null; then
    inkscape "$1" -w "$2" -h "$2" -o "$3" >/dev/null 2>&1
  else
    echo "icons.sh: instale rsvg-convert (librsvg2-bin) ou o Inkscape" >&2
    exit 1
  fi
}
for n in 16 22 24; do render "$dir/mark-small.svg" "$n" "$dir/mark-$n.png"; done
for n in 32 48 64 128 256 512; do render "$dir/mark.svg" "$n" "$dir/mark-$n.png"; done
echo "marca gerada em $dir"
