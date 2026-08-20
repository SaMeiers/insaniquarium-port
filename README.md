# Insaniquarium Deluxe — native port

Insaniquarium Deluxe (PopCap, 2004) built from the [WinFish][winfish]
decompilation and running natively on Windows, Android and Linux aarch64
(PortMaster handhelds).

This is not an emulator. The game's original framework, SexyAppFramework
(x86, DirectDraw), is replaced by [PopLib][poplib], a community rewrite on
SDL3. Module music is played with [libopenmpt][libopenmpt].

**The game's assets are not included.** They belong to PopCap and come from your
own copy (Steam or GOG).

## Credits

The decompilation is the [WinFish][winfish] project's work and the framework is
[PopLib][poplib]'s. This repository is only the port built on top of them.

PopLib is archived upstream, so the changes it needed for this port could not be
offered back; they live in the fork referenced as the `poplib` submodule and are
listed in its `PORT-CHANGES.md`. Several of them are framework bugs rather than
port-specific work and would affect any game built on PopLib.

Insaniquarium Deluxe is © PopCap Games. No game content is distributed here.

[winfish]: https://github.com/vindirect/winfish
[poplib]: https://github.com/teampopwork/poplib
[libopenmpt]: https://lib.openmpt.org/libopenmpt/

## Licence

AGPL-3.0, inherited from PopLib. See `LICENSE`.

## Layout

```
port/           the port: build files, scripts, fixups, PortMaster packaging
poplib/         submodule, the framework (fork, with this port's fixes)
source/WinFish/ submodule, the decompilation (unmodified)
```

## How the port works

`source/WinFish/` is never modified. `port/port.sh` regenerates `port/winfish/`
from it on every run: it rewrites includes, renames the framework's types, and
applies the fixups in `port/fixups/`. The decompilation can therefore be updated
upstream and the port re-derived on top.

The fixups are split by intent:

| Script | Contents |
| --- | --- |
| `apply-blocks.py` | verified block replacements sed cannot do safely |
| `apply-portability.py` | removing Windows-only code for Android and Linux |
| `apply-gamefixes.py` | bugs in the game itself, not in the port |

`port/patches/` holds changes to third-party code that lives inside PopLib's own
submodules, applied by the build script rather than vendored.

## Building

```bash
git clone --recurse-submodules <this repo>
bash port/port.sh          # source/WinFish -> port/winfish
bash port/copy-assets.sh   # your game's assets -> port/bin
```

Windows (MSVC x64):

```
port\build-game.bat
```

Android (arm64-v8a):

```
port\build-android.bat
port\install-android.bat
```

Linux aarch64, for PortMaster. Runs inside WSL and needs a Debian bullseye
sysroot; the header of `port/toolchain-aarch64-linux.cmake` explains why:

```bash
bash port/build-linux-arm64.sh
bash port/package-portmaster.sh     # -> port/insaniquarium.zip
```

## Controls on a handheld

The game is played entirely with the pointer, so the gamepad acts as a mouse
through gptokeyb.

| Button | Action |
| --- | --- |
| Left stick / d-pad | move the pointer |
| A | left click |
| B | right click |
| L1 / R1 | slow the pointer for small targets |
| Start / Select | Enter / Escape |

## Known issues

- On the R36S, using the hardware volume buttons during a game can briefly
  freeze the picture. Reports from other devices are welcome.
- Loading screens run at a reduced frame rate. This is the engine's own
  behaviour: it deliberately yields two thirds of the CPU to the loading thread.

## Notes on the assets

The loader is case-sensitive on Linux and Android and Windows is not, so a
retail copy will usually have a handful of files whose case does not match
`resources.xml`. `verify-assets.py` checks every resource the game references
and `--fix-case` renames the mismatches, including the alpha-channel companion
files that `resources.xml` never mentions by name.
