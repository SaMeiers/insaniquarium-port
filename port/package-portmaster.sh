#!/bin/bash
# Build the PortMaster package from the already-compiled aarch64 binary.
#
#   bash port/package-portmaster.sh            # the port alone (no assets)
#   bash port/package-portmaster.sh --assets   # plus assets, for local testing
#
# The published zip carries no assets: they belong to PopCap and each user
# supplies their own copy. --assets is only for filling a card to test on the
# device without copying by hand.
#
# port/portmaster/ is laid out exactly like a port directory in the PortMaster
# repository, so it can be submitted as-is:
#
#   Insaniquarium Deluxe.sh
#   README.md
#   gameinfo.xml
#   port.json
#   screenshot.png
#   insaniquarium/          <- launcher-side files, licenses, and the binary
#
# The official builder (tools/build_release.py) moves the metadata INTO the port
# directory when it makes the zip, and renames README.md after the port. This
# script does the same, so what is tested here is what the repository produces.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT/port/bin-linux-aarch64-Insaniquarium"
PM="$ROOT/port/portmaster"
DIST="$ROOT/port/dist"
PORTDIR="insaniquarium"
GAME="$DIST/$PORTDIR"

# Assets come from port/bin, not from the original game folder. Retail copies
# use whatever letter case they please, since Windows ignores it; Linux does
# not. verify-assets.py --fix-case corrects that, and it works on port/bin.
ASSETS_SRC="$ROOT/port/bin"

WITH_ASSETS=0
[ "${1:-}" = "--assets" ] && WITH_ASSETS=1

[ -f "$BIN" ] || { echo "missing binary: $BIN  (run build-linux-arm64.sh in WSL)"; exit 1; }

# These are what tools/build_release.py enforces; a port missing any of them is
# rejected before it is looked at.
missing=0
for f in "Insaniquarium Deluxe.sh" README.md gameinfo.xml port.json; do
  [ -f "$PM/$f" ] || { echo "missing required file: portmaster/$f"; missing=1; }
done
if [ ! -f "$PM/screenshot.png" ] && [ ! -f "$PM/screenshot.jpg" ]; then
  echo "missing required file: portmaster/screenshot.png (4:3, at least 640x480,"
  echo "  gameplay rather than the title screen, captured as shown on the device)"
  missing=1
fi
[ "$missing" = "0" ] || exit 1

rm -rf "$DIST"
mkdir -p "$GAME/libs.aarch64"

cp "$BIN" "$GAME/Insaniquarium"
chmod +x "$GAME/Insaniquarium"

cp -r "$PM/$PORTDIR/." "$GAME/"
cp "$PM/Insaniquarium Deluxe.sh" "$DIST/"

# The same moves build_release.py makes.
cp "$PM/port.json"     "$GAME/port.json"
cp "$PM/gameinfo.xml"  "$GAME/gameinfo.xml"
cp "$PM/README.md"     "$GAME/$PORTDIR.md"
for s in "$PM"/screenshot.png "$PM"/screenshot.jpg "$PM"/cover.png "$PM"/cover.jpg; do
  [ -f "$s" ] && cp "$s" "$GAME/"
done

# CRLF: the device shell does not forgive it ("bad interpreter: /bin/bash^M").
# A .gptk with CRLF fails worse -- gptokeyb reads "mouse_left\r" as a key name
# that does not exist, ignores it silently, and the A button does nothing.
for f in "$DIST/Insaniquarium Deluxe.sh" "$GAME/insaniquarium.gptk"; do
  sed -i 's/\r$//' "$f"
done
chmod +x "$DIST/Insaniquarium Deluxe.sh"

if [ "$WITH_ASSETS" = "1" ]; then
  echo "== copying assets from $ASSETS_SRC"
  [ -d "$ASSETS_SRC/properties" ] || {
    echo "no assets in $ASSETS_SRC; run copy-assets.sh first"; exit 1; }
  # Only the six game folders: port/bin also holds the .exe, .pdb and logs from
  # the Windows build, none of which belong on the handheld.
  for d in data images music properties sounds fishsongs; do
    [ -d "$ASSETS_SRC/$d" ] && cp -r "$ASSETS_SRC/$d" "$GAME/" && echo "  $d"
  done
fi

echo
echo "== contents"
(cd "$DIST" && find . -maxdepth 2 \
      -not -path './insaniquarium/images/*' \
      -not -path './insaniquarium/sounds/*' \
      -not -path './insaniquarium/data/*' | sort)
echo
du -sh "$DIST"

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
  echo "nothing available to compress with; the folder is in $DIST"
  exit 0
fi
echo "zip: $ZIP ($(du -h "$ZIP" | cut -f1))"
