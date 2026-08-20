#!/bin/bash
# Copy the original game assets next to the ported executable.
# The decompilation ships no assets: they come from your own copy of the game.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Pass the folder holding your copy of the game, or drop it in ./game.
SRC="${1:-$ROOT/game}"
DST="$ROOT/port/bin"

[ -d "$SRC" ] || { echo "cannot find the original game at: $SRC"; exit 1; }
mkdir -p "$DST"

# Retail releases keep everything loose (no main.pak), so it is copied as is.
for d in data images music properties sounds fishsongs; do
  if [ -d "$SRC/$d" ]; then
    cp -r "$SRC/$d" "$DST/" && echo "  $d"
  else
    echo "  MISSING: $d"
  fi
done

echo "assets in $DST ($(du -sh "$DST" | cut -f1))"

# --- check everything resources.xml references is actually there -------------
echo
echo "verifying resources referenced by resources.xml..."
python "$ROOT/port/verify-assets.py" || exit 1
