#!/bin/bash
# port.sh - transform source/WinFish (SexyAppFramework) into port/winfish (PopLib).
#
# Idempotent: port/winfish is deleted and regenerated on every run, and
# source/WinFish is never modified. Everything the port changes in the game's
# code lives in this script and in fixups/, so the decompilation can be updated
# from upstream and the port re-derived.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${WINFISH_SRC:-$ROOT/source/WinFish}"
DST="$ROOT/port/winfish"
MAP="$ROOT/port/include-map.txt"

[ -d "$SRC" ] || { echo "missing $SRC (set WINFISH_SRC to override)"; exit 1; }
[ -f "$MAP" ] || { echo "missing $MAP"; exit 1; }

echo "== 1. copying sources =="
rm -rf "$DST"
mkdir -p "$DST"
cp "$SRC"/*.cpp "$SRC"/*.h "$DST"/ 2>/dev/null
cp "$SRC"/*.rc "$SRC"/*.ico "$SRC"/*.xml "$DST"/ 2>/dev/null
# the .vcxproj files are replaced by CMake
rm -f "$DST"/*.vcxproj "$DST"/*.filters
echo "   $(ls "$DST" | wc -l) files"

echo "== 2. rewriting framework includes =="
SEDF=$(mktemp)
grep -v '^#' "$MAP" | grep -v '^[[:space:]]*$' | while IFS=$'\t' read -r old new _rest; do
  old=$(echo "$old" | tr -d '[:space:]')
  new=$(echo "$new" | tr -d '[:space:]')
  [ -z "$old" ] && continue
  # covers <> and "", with / and with \
  echo "s|#include[[:space:]]*[<\"]\\(\\.\\./\\)\\?SexyAppFramework[/\\\\]${old}\\.h[>\"]|#include \"PopLib/${new}\"|g"
done > "$SEDF"
echo "   $(wc -l < "$SEDF") include rules"

echo "== 3. namespace and type renames =="
cat >> "$SEDF" <<'RULES'
s/\bnamespace Sexy\b/namespace PopLib/g
s/\busing namespace Sexy\b/using namespace PopLib/g
s/\bSexy::/PopLib::/g
s/\bSexyAppBase\b/AppBase/g
s/\bSexyString\b/PopString/g
s/\bSexyChar\b/PopChar/g
s/\bSexyTransform2D\b/Transform2D/g
s/\bSexyMatrix3\b/Matrix3/g
s/\bDDImage\b/SDLImage/g
s/\bDDInterface\b/SDLInterface/g
s/\bmDDInterface->mD3DInterface\b/mSDLInterface/g
s/\bmDDInterface\b/mSDLInterface/g
s/\bD3DInterface\b/SDLInterface/g
s/StringToSexyStringFast(\(.*\))/\1/g
s/StringToSexyString(\(.*\))/\1/g
s/SexyStringToStringFast(\(.*\))/\1/g
s/SexyStringToString(\(.*\))/\1/g
s/\b_S(/(/g
s|#include *[<"]ImageLib[/\\]ImageLib\.h[>"]|#include "PopLib/imagelib/imagelib.hpp"|g
s/\bgSexyAppBase\b/gAppBase/g
RULES

# sed -b is required: without it sed normalises CRLF to LF and every diff
# against source/WinFish shows 100% of lines changed.
#
# One invocation for all 150 files: process creation is expensive on Windows and
# doing this in a loop cost about 2.5 of the 3 minutes the script used to take.
sed -b -i -f "$SEDF" "$DST"/*.cpp "$DST"/*.h
rm -f "$SEDF"
echo "   applied to $(ls "$DST"/*.cpp "$DST"/*.h 2>/dev/null | wc -l) files"

# DDInterface.h and D3DInterface.h both collapse onto sdlinterface.hpp, so some
# files end up including it twice. Only files that actually have duplicates are
# rewritten, to leave everyone else's CRLF endings alone.
echo "== 3b. de-duplicating PopLib includes =="
dedup=0
dupfiles=$(awk 'FNR==1{delete seen} /^#include "PopLib\//{if(seen[$0]++){print FILENAME; nextfile}}' \
  "$DST"/*.cpp "$DST"/*.h 2>/dev/null)
for f in $dupfiles; do
  if [ -f "$f" ]; then
    # awk normalises CRLF to LF as well, so restore it afterwards with sed -b
    awk '/^#include "PopLib\//{if(seen[$0]++)next}1' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    sed -b -i 's/\r*$/\r/' "$f"
    dedup=$((dedup+1))
    echo "   dedup: $(basename "$f")"
  fi
done
echo "   $dedup files rewritten"

echo "== 3c. fixups (Win32 code with no direct equivalent) =="

# WorkerThread: PopLib has a portable one with the same API (DoTask/WaitForTask);
# the only difference is that its constructor takes a name.
rm -f "$DST/WorkerThread.cpp" "$DST/WorkerThread.h"
sed -b -i \
  -e 's|#include "WorkerThread.h"|#include "PopLib/misc/workerthread.hpp"|' \
  -e 's|new WorkerThread()|new WorkerThread("winfish-worker")|' \
  "$DST/WinFishApp.cpp"
echo "   WorkerThread -> PopLib/misc/workerthread.hpp"

# SEHCatcher: PopLib only has a stub (ErrorHandler) without these fields. They
# were crash-report strings pointing at popcap.com, which no longer exists.
sed -b -i \
  -e '/SEHCatcher::mCrashMessage/,/feedback@popcap\.com\.";/d' \
  -e '/SEHCatcher::mSubmitMessage/,/may be interfering with this program?";/d' \
  -e '/SEHCatcher::mSubmitErrorMessage/,/manually connect to your ISP\.";/d' \
  -e '/SEHCatcher::mSubmitHost/d' \
  "$DST/SexyApp.cpp"
# mShowUI is the body of an if, so the whole if is removed in apply-blocks.py.
# Deleting only the line would leave the if dangling over the next statement.
echo "   SEHCatcher -> removed"

# Demo recording does not exist in PopLib.
sed -b -i -e '/mDemoPrefix/d' -e '/mDemoFileName/d' "$DST/SexyApp.cpp"
sed -b -i '/DemoSyncString/d' "$DST/WinFishApp.cpp"
echo "   demo recording -> removed"

# AppBase signatures that changed in PopLib.
sed -b -i 's/ReadBufferFromFile(\(.*\), false)/ReadBufferFromFile(\1)/' \
  "$DST/Board.cpp" "$DST/HighScoreMgr.cpp" "$DST/ProfileMgr.cpp"
sed -b -i \
  -e 's/CreateMusicInterface(HWND theHWnd)/CreateMusicInterface()/' \
  -e 's/CreateMusicInterface(theHWnd)/CreateMusicInterface()/' \
  "$DST/WinFishApp.cpp"
sed -b -i 's/CreateMusicInterface(HWND theHWnd)/CreateMusicInterface()/' "$DST/WinFishApp.h"
echo "   AppBase signatures (ReadBufferFromFile, CreateMusicInterface)"

# DataSync::SyncLong(ulong&) collides with SyncLong(unsigned int&): ulong was
# 'unsigned long' originally (a distinct type under MSVC), but PopLib defines it
# as uint32_t, which is unsigned int. The overload becomes a redefinition.
sed -b -i '/void SyncLong(ulong& theValue);/d' "$DST/DataSync.h"
DST="$DST" python - <<'PYEOF'
import os, pathlib, re
p = pathlib.Path(os.environ["DST"]) / "DataSync.cpp"
d = p.read_bytes()
pat = re.compile(rb"void DataSync::SyncLong\(ulong& theValue\)\r?\n\{.*?\r?\n\}\r?\n", re.S)
d2, n = pat.subn(b"", d, count=1)
p.write_bytes(d2)
print(f"   DataSync::SyncLong(ulong&) removed ({n} definition)")
PYEOF

# The demo system is gone, so a demo is never playing.
sed -b -i 's/!mPlayingDemoBuffer/true/g' "$DST/SexyApp.cpp"

# HTTPTransfer is non-copyable in PopLib, and the assignment was redundant (the
# member is already default constructed). The header uses it by value, so it
# needs the complete type.
sed -b -i '/mUpdateTransfer = HTTPTransfer();/d' "$DST/InternetManager.cpp"
sed -b -i 's|#define __INTERNETMGR_H__|#define __INTERNETMGR_H__\n\n#include "PopLib/misc/httptransfer.hpp"|' "$DST/InternetManager.h"

# GetBits() returns uint32_t*; DWORD from windows.h is unsigned long.
sed -b -i 's/DWORD\* \(aNewBits\|aMaskBits\) = /uint32_t* \1 = /' "$DST/WinFishApp.cpp"
echo "   DataSync, demos, HTTPTransfer, DWORD*"

# Block replacements (what sed cannot do safely).
if [ -f "$ROOT/port/fixups/apply-blocks.py" ]; then
  python "$ROOT/port/fixups/apply-blocks.py" || echo "   WARNING: a block did not apply"
fi

# Removing Windows-only code for the Android/Linux builds.
if [ -f "$ROOT/port/fixups/apply-portability.py" ]; then
  python "$ROOT/port/fixups/apply-portability.py" || echo "   WARNING: a portability fixup did not apply"
fi

# Bugs in the game itself rather than in the port; see fixups/apply-gamefixes.py.
if [ -f "$ROOT/port/fixups/apply-gamefixes.py" ]; then
  python "$ROOT/port/fixups/apply-gamefixes.py" || echo "   WARNING: a game fix did not apply"
fi

# Entry point: WinMain -> main
if [ -f "$ROOT/port/fixups/Window.cpp" ]; then
  cp "$ROOT/port/fixups/Window.cpp" "$DST/Window.cpp"
  sed -b -i 's/\r*$/\r/' "$DST/Window.cpp"
  echo "   Window.cpp -> main() (from fixups/)"
fi

echo
echo "== 3d. check: if/else/for/while with no body =="
# Deleting a line that was the body of an if leaves the if dangling over the
# next statement, which then only runs conditionally. It compiles cleanly and
# the bug is very hard to spot, so it is checked for explicitly.
danglers=$(grep -nE '^[[:space:]]*(if|else if|for|while)[[:space:]]*\(.*\)[[:space:]]*$' -A1 "$DST"/*.cpp "$DST"/*.h 2>/dev/null \
  | grep -E '^[^:]+-[0-9]+-[[:space:]]*$' | wc -l)
if [ "$danglers" -gt 0 ]; then
  echo "   !! $danglers conditionals followed by a blank line (body possibly deleted):"
  grep -nE '^[[:space:]]*(if|else if|for|while)[[:space:]]*\(.*\)[[:space:]]*$' -A1 "$DST"/*.cpp "$DST"/*.h 2>/dev/null \
    | grep -B1 -E '^[^:]+-[0-9]+-[[:space:]]*$' | grep -E '^[^-]+:[0-9]+:' | sed 's|^.*/winfish/|   |' | head -10
else
  echo "   ok, none"
fi

echo
echo "== 4. LEFT TO DO BY HAND =="
leftover() {
  local pat="$1" desc="$2"
  local hits
  hits=$(grep -rn "$pat" "$DST" 2>/dev/null | grep -v '^Binary')
  if [ -n "$hits" ]; then
    echo
    echo "--- $desc"
    echo "$hits" | sed 's|^.*/port/winfish/|   |' | head -20
  fi
}
leftover 'SexyAppFramework'        'unmapped framework includes'
leftover '\bSexy\b'                'surviving references to Sexy'
leftover 'SEHCatcher'              'SEHCatcher -> no equivalent (remove; ErrorHandler is a stub)'
leftover '#include *<windows'      'Win32 includes'
leftover 'WinMain\|HINSTANCE'      'Win32 entry point -> move to int main()'
leftover '\bHANDLE\b'              'Win32 handles (WorkerThread -> PopLib/misc/workerthread.hpp)'
leftover 'DemoSync\|mDemo'         'demo recording: removed in PopLib'
echo
echo "== done. output in $DST =="
