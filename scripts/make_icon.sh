#!/bin/bash
# Genera App/Icon/Biblia-1024.png (concepto «Códice») y Biblia.icns (idempotente).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICON="$ROOT/App/Icon"
SET="$(mktemp -d)/Biblia.iconset"
trap 'rm -rf "$(dirname "$SET")"' EXIT
mkdir -p "$ICON" "$SET"
cd "$ROOT"
swift scripts/make_icon.swift "$ICON/Biblia-1024.png"
for s in 16 32 128 256 512; do
  sips -z $s $s "$ICON/Biblia-1024.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
  d=$((s*2))
  sips -z $d $d "$ICON/Biblia-1024.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o "$ICON/Biblia.icns"
rm -rf "$ICON/Biblia.iconset"
echo "wrote $ICON/Biblia.icns"
