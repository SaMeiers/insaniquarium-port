#!/usr/bin/env bash
# Cross-compile for Linux aarch64 (PortMaster handhelds: R36S / ArkOS and kin).
#
# Run inside WSL:
#   wsl bash port/build-linux-arm64.sh
#
# Do not launch it with nohup from outside: WSL shuts the VM down when the
# outer command returns and takes the build with it.
set -euo pipefail

WINSRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Local copy of the source tree. Building straight off /mnt/c is very slow: each
# of the ~900 game files, plus every SDL/curl/freetype header, crosses the WSL
# 9p bridge. With a local copy the build drops from tens of minutes to a few.
SRC="$HOME/winfish-src"
BUILD="$HOME/winfish-build-aarch64"
SYSROOT="${WINFISH_SYSROOT:-$HOME/sysroot-bullseye-winfish}"
LOG="$WINSRC/port/build-linux.log"

# Everything goes to the log as well as to stdout. When a build fails the error
# is usually hundreds of lines before the end, followed by warnings from every
# file that did compile, so looking at the tail is useless.
exec > >(tee "$LOG") 2>&1

if [ ! -d "$SYSROOT" ]; then
  echo "missing sysroot: $SYSROOT   (see port/mk-sysroot-bullseye.sh)"
  exit 1
fi

echo "== syncing source to $SRC"
mkdir -p "$SRC"
# .git cannot be excluded: OpenAL's CMake reads .git/modules/.../index to stamp
# its version, and without it ninja fails before compiling anything.
#
# The --include entries come before the --exclude ones on purpose: rsync applies
# the first matching filter. 'build/' is meant for the poplib and port output
# directories, but the pattern matches any directory of that name at any depth,
# including libopenmpt/build/, which holds the svn_version.h its version.cpp
# needs.
rsync -a --delete \
      --include 'external/libopenmpt/build/' \
      --include 'external/libopenmpt/build/**' \
      --exclude 'build/' --exclude 'bin/' --exclude 'android/' \
      --exclude '*.log' \
      "$WINSRC/poplib" "$WINSRC/port" "$SRC/"

# SDL is a submodule of PopLib, so a fork of PopLib does not carry changes made
# inside it. The one change needed lives in patches/ and is applied here, which
# also keeps it visible and reviewable rather than buried in a vendored tree.
#
# --ignore-whitespace is needed for one reason: the patch is stored with LF, as
# a normal checkout has, but this tree was rsynced from a Windows working copy
# where SDL was checked out with CRLF. Without it the context never matches.
SDLDIR="$SRC/poplib/external/SDL"
for p in "$WINSRC"/port/patches/sdl-*.patch; do
  [ -f "$p" ] || continue
  name=$(basename "$p")
  if git -C "$SDLDIR" apply --reverse --check --ignore-whitespace "$p" 2>/dev/null; then
    echo "== $name already applied"
  elif git -C "$SDLDIR" apply --ignore-whitespace "$p" 2>/dev/null; then
    echo "== applied $name"
  else
    echo "== WARNING: $name did not apply"
  fi
done

# CMake stores the source path in its cache and refuses to reuse it if it moves.
if [ -f "$BUILD/CMakeCache.txt" ] && \
   ! grep -q "CMAKE_HOME_DIRECTORY:INTERNAL=$SRC/port" "$BUILD/CMakeCache.txt"; then
  echo "== cache points at a different source tree, discarding it"
  rm -rf "$BUILD"
fi

# The toolchain's CMAKE_*_FLAGS_INIT variables are only read on the first
# configure; after that the values live in the cache and the file is not even
# looked at. Editing the toolchain and reconfiguring would silently do nothing.
if [ -f "$BUILD/CMakeCache.txt" ] && \
   [ "$SRC/port/toolchain-aarch64-linux.cmake" -nt "$BUILD/CMakeCache.txt" ]; then
  echo "== toolchain changed, reconfiguring"
  # Only the cache is removed, not the directory: the object files are still
  # valid if the compile flags did not change.
  rm -f "$BUILD/CMakeCache.txt"
fi

cmake -S "$SRC/port" -B "$BUILD" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$SRC/port/toolchain-aarch64-linux.cmake" \
  -DWINFISH_SYSROOT="$SYSROOT" \
  -DCMAKE_BUILD_TYPE=Release \
  `# On Unix SDL_ttf prefers the system freetype/harfbuzz; the sysroot has` \
  `# neither, and the same version across all platforms is preferable anyway.` \
  -DSDLTTF_VENDORED=ON \
  `# Music goes through libopenmpt. Without turning BASS off the binary still` \
  `# links libbass.so even though nothing uses it.` \
  -DPOPLIB_WITH_BASS=OFF \
  "$@"

cmake --build "$BUILD" --parallel

BIN="$SRC/port/bin/Insaniquarium"
echo
echo "=== binary checks ==="
file "$BIN"

# These two decide whether the binary starts on the device, and the compiler
# catches neither.
echo "--- highest glibc version required (must be <= 2.30 for ArkOS) ---"
aarch64-linux-gnu-objdump -T "$BIN" | grep -o 'GLIBC_[0-9.]*' | sort -uV | tail -5

# glibc 2.34 removed __libc_csu_init and changed how global constructors are
# started. A binary linked against >= 2.34 compiles and links fine but runs no
# static constructors on an older system, and dies before main with no reason
# given.
echo "--- __libc_csu_init (must be present) ---"
aarch64-linux-gnu-nm "$BIN" | grep __libc_csu_init \
  || echo "  *** MISSING: constructors will not run on glibc < 2.34 ***"

echo "--- libraries needed on the device ---"
aarch64-linux-gnu-readelf -d "$BIN" | grep NEEDED

ls -la "$BIN"

# The shipped binary is stripped. The checks above deliberately run on the
# unstripped one, since strip removes the symbol table and __libc_csu_init can
# no longer be verified afterwards.
STRIPPED="$BUILD/Insaniquarium.stripped"
aarch64-linux-gnu-strip -o "$STRIPPED" "$BIN"
echo "--- stripped: $(stat -c%s "$BIN") -> $(stat -c%s "$STRIPPED") bytes ---"

cp "$STRIPPED" "$WINSRC/port/bin-linux-aarch64-Insaniquarium"
echo
echo "copied to: $WINSRC/port/bin-linux-aarch64-Insaniquarium"
