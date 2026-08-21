#!/bin/bash
# Copy only what changes between debug iterations to the SD card.
#
#   bash port/deploy-r36s.sh            # to E:/ports
#   bash port/deploy-r36s.sh /x/ports   # somewhere else
#
# The game assets (24 MB) are left alone: they never change and copying them to
# an SD card every time costs minutes for nothing. conf/ is left alone too,
# since that holds the save games.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${1:-/e/ports}"
GAME="$DEST/insaniquarium"

BIN="$ROOT/port/bin-linux-aarch64-Insaniquarium"
PM="$ROOT/port/portmaster"

[ -d "$DEST" ] || { echo "cannot find $DEST (is the card inserted?)"; exit 1; }
[ -f "$BIN" ]  || { echo "missing binary: $BIN"; exit 1; }


mkdir -p "$GAME"
cp "$BIN" "$GAME/Insaniquarium"
cp -r "$PM/insaniquarium/." "$GAME/"
cp "$PM/Insaniquarium Deluxe.sh" "$DEST/"

# The same moves the official builder makes when it zips a port.
cp "$PM/port.json"    "$GAME/port.json"
cp "$PM/gameinfo.xml" "$GAME/gameinfo.xml"
cp "$PM/README.md"    "$GAME/insaniquarium.md"
for s in "$PM"/screenshot.png "$PM"/cover.png; do
  [ -f "$s" ] && cp "$s" "$GAME/"
done

# CRLF: the device shell does not forgive it ("bad interpreter: /bin/bash^M"),
# and a .gptk with CRLF fails worse than that -- gptokeyb reads "mouse_left\r"
# as a key name that does not exist, ignores it silently, and the A button
# simply does nothing.
sed -i 's/\r$//' "$DEST/Insaniquarium Deluxe.sh" "$GAME/insaniquarium.gptk"

rm -f "$GAME/log.txt"

echo "copied to $GAME:"
ls -la "$GAME/Insaniquarium" "$GAME/insaniquarium.gptk"
ls -la "$DEST/Insaniquarium Deluxe.sh"
echo
echo "assets and conf/ left untouched."
