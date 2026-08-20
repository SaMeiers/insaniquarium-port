#!/bin/bash
# Build the PortMaster package from the already-compiled aarch64 binary.
#
#   bash port/package-portmaster.sh            # the port alone (no assets)
#   bash port/package-portmaster.sh --assets   # plus assets, for local testing
#
# The published zip carries no assets: they belong to PopCap and each user
# supplies their own copy. --assets is only for filling a card to test on the
# device without copying by hand.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT/port/bin-linux-aarch64-Insaniquarium"
BASS="$ROOT/poplib/external/bass/linux-aarch64/libbass.so"
PM="$ROOT/port/portmaster"
DIST="$ROOT/port/dist"
GAME="$DIST/insaniquarium"
# Assets come from port/bin, not from the original game folder. Retail copies
# use whatever letter case they please, since Windows ignores it; Linux does
# not. verify-assets.py --fix-case corrects that, and it works on port/bin.
ASSETS_SRC="$ROOT/port/bin"

WITH_ASSETS=0
[ "${1:-}" = "--assets" ] && WITH_ASSETS=1

[ -f "$BIN" ]  || { echo "falta el binario: $BIN  (corre build-linux-arm64.sh en WSL)"; exit 1; }

rm -rf "$DIST"
mkdir -p "$GAME/libs.aarch64"

cp "$BIN"  "$GAME/Insaniquarium"
chmod +x "$GAME/Insaniquarium"

cp "$PM/insaniquarium.gptk" "$GAME/"
cp "$PM/alsoft.conf"          "$GAME/"
cp "$PM/port.json"          "$GAME/"
cp "$PM/Insaniquarium Deluxe.sh" "$DIST/"

# CRLF: the device shell does not forgive it ("bad interpreter: /bin/bash^M").
# A .gptk with CRLF fails worse -- gptokeyb reads "mouse_left\r" as a key name
# that does not exist, ignores it silently, and the A button does nothing.
for f in "$DIST/Insaniquarium Deluxe.sh" "$GAME/insaniquarium.gptk"; do
  sed -i 's/\r$//' "$f"
done
chmod +x "$DIST/Insaniquarium Deluxe.sh"

if [ "$WITH_ASSETS" = "1" ]; then
  echo "== copiando assets desde $ASSETS_SRC"
  [ -d "$ASSETS_SRC/properties" ] || {
    echo "no hay assets en $ASSETS_SRC; corre antes copy-assets.sh"; exit 1; }
  # Only the six game folders: port/bin also holds the .exe, .pdb, bass.dll and
  # logs from the Windows build, none of which belong on the handheld.
  for d in data images music properties sounds fishsongs; do
    [ -d "$ASSETS_SRC/$d" ] && cp -r "$ASSETS_SRC/$d" "$GAME/" && echo "  $d"
  done
fi

echo
echo "== contenido"
(cd "$DIST" && find . -maxdepth 2 -not -path './insaniquarium/images/*' \
                      -not -path './insaniquarium/sounds/*' \
                      -not -path './insaniquarium/data/*' | sort | head -30)
echo
du -sh "$DIST"

# Zipped from $DIST so "Insaniquarium Deluxe.sh" and "insaniquarium/" end up at
# the archive root, which is what PortMaster expects and what port.json lists
# under "items".
ZIP="$ROOT/port/insaniquarium.zip"
rm -f "$ZIP"
if command -v zip >/dev/null 2>&1; then
  (cd "$DIST" && zip -qr "$ZIP" .)
elif command -v powershell.exe >/dev/null 2>&1; then
  # Git Bash has no zip. Compress-Archive does not preserve the execute bit,
  # which does not matter: the launcher chmod +x's the binary before running.
  powershell.exe -NoProfile -Command \
    "Compress-Archive -Path '$(cygpath -w "$DIST")\\*' -DestinationPath '$(cygpath -w "$ZIP")' -Force"
else
  echo "no hay con que comprimir; la carpeta lista esta en $DIST"
  exit 0
fi
echo "zip: $ZIP ($(du -h "$ZIP" | cut -f1))"
