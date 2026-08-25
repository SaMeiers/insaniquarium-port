#!/bin/bash
# Build the PortMaster package from the already-compiled aarch64 binary.
#
#   bash port/package-portmaster.sh            # the port alone (no assets)
#   bash port/package-portmaster.sh --assets   # plus assets, for local testing
#   bash port/package-portmaster.sh --pr       # the layout PortMaster-New wants
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
#   screenshot.jpg
#   insaniquarium/          <- launcher-side files, licenses, and the binary
#
# The zip this makes puts the metadata inside the port directory, matching the
# packages handed round for testing rather than whatever tools/build_release.py
# emits -- that one builds from the repository and is the authority for the
# pull request, which is what --pr is for.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT/port/bin-linux-aarch64-Insaniquarium"
PM="$ROOT/port/portmaster"
DIST="$ROOT/port/dist"
SHIM="${WINFISH_SDL3_SHIM:-$ROOT/port/bin-linux-aarch64-libSDL3.so.0}"
PORTDIR="insaniquarium"
GAME="$DIST/$PORTDIR"

# Assets come from port/bin, not from the original game folder. Retail copies
# use whatever letter case they please, since Windows ignores it; Linux does
# not. verify-assets.py --fix-case corrects that, and it works on port/bin.
ASSETS_SRC="$ROOT/port/bin"

WITH_ASSETS=0
WITH_PR=0
case "${1:-}" in
  --assets) WITH_ASSETS=1 ;;
  --pr)     WITH_PR=1 ;;
esac

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
mkdir -p "$GAME"

cp "$BIN" "$GAME/Insaniquarium"
chmod +x "$GAME/Insaniquarium"

cp -r "$PM/$PORTDIR/." "$GAME/"

mkdir -p "$GAME/libs.aarch64"
if [ -f "$SHIM" ]; then
  cp "$SHIM" "$GAME/libs.aarch64/libSDL3.so.0"
  chmod +x "$GAME/libs.aarch64/libSDL3.so.0"
else
  echo "missing the SDL3 shim: $SHIM"
  echo "  build it with port/build-sdl3-shim.sh"
  exit 1
fi
cp "$PM/Insaniquarium Deluxe.sh" "$DIST/"

# The same moves build_release.py makes.
cp "$PM/port.json"     "$GAME/port.json"
cp "$PM/gameinfo.xml"  "$GAME/gameinfo.xml"
cp "$PM/README.md"     "$GAME/README.md"
for s in "$PM"/screenshot.png "$PM"/screenshot.jpg; do
  [ -f "$s" ] && cp "$s" "$GAME/"
done

# CRLF: the device shell does not forgive it ("bad interpreter: /bin/bash^M").
# The gamepad config fails worse -- gptokeyb reads "mouse_left\r" as a key name
# that does not exist, ignores it silently, and the A button does nothing.
for f in "$DIST/Insaniquarium Deluxe.sh" "$GAME/insaniquarium.ini"; do
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
# The port script has to come out of the zip executable. Compress-Archive
# records DOS attributes only, so everything it writes extracts without the
# execute bit and the port will not launch after an automatic install. zip
# stores real Unix permissions, so use it even when it only exists in WSL.
chmod +x "$DIST/Insaniquarium Deluxe.sh" "$DIST/insaniquarium/Insaniquarium"

if command -v zip >/dev/null 2>&1; then
  (cd "$DIST" && zip -qr "$ZIP" .)
elif command -v wsl.exe >/dev/null 2>&1; then
  WSL_DIST=$(wsl.exe -e wslpath "$(cygpath -w "$DIST")" | tr -d "\r")
  WSL_ZIP=$(wsl.exe -e wslpath "$(cygpath -w "$ZIP")" | tr -d "\r")
  wsl.exe -e sh -c "cd '$WSL_DIST' && zip -qr '$WSL_ZIP' ."
else
  echo "no zip available; it stores the execute bit Compress-Archive drops"
  echo "the unpacked port is in $DIST"
  exit 1
fi
echo "zip: $ZIP ($(du -h "$ZIP" | cut -f1))"

# A PR to PortMaster-New is not the zip: the metadata sits beside the port
# directory rather than inside it, and the binaries are committed as files.
# Built from the same DIST the zip came from so the two cannot disagree.
if [ "$WITH_PR" = "1" ]; then
  PR="$ROOT/port/pr/ports/$PORTDIR"
  rm -rf "$ROOT/port/pr"
  mkdir -p "$PR/$PORTDIR"
  cp -r "$GAME/." "$PR/$PORTDIR/"
  cp "$DIST/Insaniquarium Deluxe.sh" "$PR/"
  for f in port.json gameinfo.xml README.md screenshot.png screenshot.jpg; do
    [ -f "$PR/$PORTDIR/$f" ] && mv "$PR/$PORTDIR/$f" "$PR/"
  done
  echo
  echo "== ports/$PORTDIR (copy this into the fork)"
  (cd "$ROOT/port/pr" && find . -type f | sort)
  echo
  echo "  90MB is the limit before tools/build_data.py has to split a file:"
  find "$PR" -type f -size +85M -printf '  *** %s bytes: %p
' 2>/dev/null
  du -sh "$ROOT/port/pr"
  echo
  echo "  Commit these 644. PortMaster-New's AGENTS.md asks for it, and the"
  echo "  launch script chmods the binary itself because zip extraction drops"
  echo "  the bit however it was committed."
fi
