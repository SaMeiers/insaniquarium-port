#!/usr/bin/env bash
# Build the SDL3 library this port ships in libs.aarch64.
#
# It is not really SDL3: it is an SDL3 API that forwards to whatever SDL2 the
# firmware already has (https://github.com/bmdhacks/SDL, branch sdl2-backend).
# That is what PortMaster expects a port to use, and it is the reason this one
# does not have to solve video and input again on every device -- the people
# who wrote each firmware already patched their SDL2 for their own hardware.
#
# Built against the same sysroot as the game, on purpose. The copy PortMaster
# distributes needs glibc 2.34; this one needs 2.29, which is the difference
# between running on the older firmwares and not.
set -euo pipefail

SYSROOT="${WINFISH_SYSROOT:-$HOME/sysroot-bullseye-winfish}"
WORK="${WINFISH_SHIM_WORK:-$HOME/shim-build}"
TOOLCHAIN="${WINFISH_TOOLCHAIN:-/mnt/c/proyectos/winfish/port/toolchain-aarch64-linux.cmake}"
OUT="${WINFISH_SHIM_OUT:-/mnt/c/proyectos/winfish/port/bin-linux-aarch64-libSDL3.so.0}"

[ -d "$SYSROOT" ] || { echo "missing sysroot: $SYSROOT"; exit 1; }
[ -f "$TOOLCHAIN" ] || { echo "missing toolchain: $TOOLCHAIN"; exit 1; }

mkdir -p "$WORK"

echo "== sources"
[ -d "$WORK/SDL" ] || git clone -q --depth 1 -b sdl2-backend https://github.com/bmdhacks/SDL.git "$WORK/SDL"
[ -d "$WORK/SPIRV-Cross" ] || git clone -q --depth 1 https://github.com/KhronosGroup/SPIRV-Cross.git "$WORK/SPIRV-Cross"

# Reset first, so a rebuild does not depend on what the last one left behind.
# port/patches/shim holds what this port carries against the shim -- not
# port/patches itself, which is for the SDL the game links. Each one is a fix
# that belongs upstream rather than here.
echo "== patches"
git -C "$WORK/SDL" checkout -q -- .
for aPatch in "$(dirname "$0")"/patches/shim/*.patch; do
  [ -e "$aPatch" ] || continue
  tr -d '' < "$aPatch" | git -C "$WORK/SDL" apply -
  echo "   $(basename "$aPatch")"
done

# The shim pulls in the toolchain's static libstdc++, which is built against a
# much newer glibc than the sysroot has. Same shim the game uses for the same
# reason; without it the link fails on __isoc23_strtoul and
# __libc_single_threaded.
echo "== glibc compatibility object"
INCLUDES=$(aarch64-linux-gnu-g++ -E -Wp,-v -xc++ /dev/null 2>&1 \
           | grep '^ /usr' | grep -E 'c\+\+|gcc-cross' | sed 's|^ |-isystem |' | tr '\n' ' ')
# shellcheck disable=SC2086
aarch64-linux-gnu-g++ -c -fPIC -O2 --sysroot="$SYSROOT" -nostdinc $INCLUDES \
  -isystem "$SYSROOT/usr/include/aarch64-linux-gnu" -isystem "$SYSROOT/usr/include" \
  -o "$WORK/compat-glibc.o" "$(dirname "$0")/compat-glibc.cpp"
aarch64-linux-gnu-ar rcs "$WORK/libcompat.a" "$WORK/compat-glibc.o"

# Passed as a standard library rather than through the linker flags: setting
# CMAKE_SHARED_LINKER_FLAGS on the command line replaces what the toolchain file
# put there, which silently drops the sysroot and links the whole thing against
# the host's glibc instead.
echo "== configure"
rm -rf "$WORK/SDL/build"
cmake -S "$WORK/SDL" -B "$WORK/SDL/build" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_STANDARD_LIBRARIES="$WORK/libcompat.a" \
  -DSDL_SDL2_BACKEND=ON \
  -DSDL_SPIRV_CROSS_DIR="$WORK/SPIRV-Cross" \
  `# Every other backend off, so the sdl2 one is the only way out and SDL` \
  `# picks it even when the firmware names no driver.` \
  -DSDL_X11=OFF -DSDL_WAYLAND=OFF -DSDL_KMSDRM=OFF \
  -DSDL_PIPEWIRE=OFF -DSDL_PULSEAUDIO=OFF -DSDL_ALSA=OFF \
  -DSDL_SNDIO=OFF -DSDL_OSS=OFF -DSDL_JACK=OFF \
  -DSDL_OFFSCREEN=OFF -DSDL_DUMMYVIDEO=OFF \
  -DSDL_DUMMYAUDIO=OFF -DSDL_DISKAUDIO=OFF \
  -DSDL_VULKAN=OFF -DSDL_GPU=ON -DSDL_RENDER_GPU=ON \
  -DSDL_UNIX_CONSOLE_BUILD=ON -DSDL_TESTS=OFF > "$WORK/configure.log" 2>&1

echo "== build"
cmake --build "$WORK/SDL/build" --parallel > "$WORK/build.log" 2>&1

LIB="$WORK/SDL/build/libSDL3.so.0.5.0"
[ -f "$LIB" ] || { echo "no library produced; see $WORK/build.log"; exit 1; }

echo "--- highest glibc version required ---"
aarch64-linux-gnu-objdump -T "$LIB" | grep -o 'GLIBC_[0-9.]*' | sort -uV | tail -4

echo "--- soname (must be libSDL3.so.0) ---"
aarch64-linux-gnu-readelf -d "$LIB" | grep SONAME

echo "--- shared libraries it needs ---"
aarch64-linux-gnu-readelf -d "$LIB" | grep NEEDED

aarch64-linux-gnu-strip -o "$OUT" "$LIB"
echo
echo "copied to: $OUT  ($(stat -c%s "$OUT") bytes)"
