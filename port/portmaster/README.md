# Insaniquarium Deluxe

A [PortMaster](https://portmaster.games/) port of Insaniquarium Deluxe
(PopCap, 2004), running natively on aarch64.

Thanks to PopCap Games for making Insaniquarium, to the
[WinFish](https://github.com/vindirect/winfish) project for the decompilation
this is built from, and to [PopLib](https://github.com/teampopwork/poplib) for
the framework that replaces the game's original SexyAppFramework.

**This port does not include the game.** It is the executable only; the assets
come from a copy you own.

## What this is

Not an emulator and not a reimplementation. The decompiled game is compiled
against PopLib, which replaces the original DirectDraw framework with SDL3, so
the binary is native aarch64. Module music is played with
[libopenmpt](https://lib.openmpt.org/libopenmpt/).

## Installation

Copy these folders from your copy of Insaniquarium Deluxe (Steam or GOG) into
`ports/insaniquarium/`:

```
data  images  music  properties  sounds  fishsongs
```

The game will not start without them; it shows a message saying so.

**Watch the letter case.** Windows ignores it and Linux does not, so a retail
copy usually has a few files whose case does not match what the game asks for.
If it complains about an image that clearly exists, that is why. Renaming the
file to the case the game asks for fixes it.

## Controls

The game is played entirely with the pointer, so the gamepad acts as a mouse.

| Button | Action |
| --- | --- |
| Left stick / D-pad | Move the pointer |
| A | Left click — feed, collect coins, shoot |
| B | Right click — release pet, cancel |
| L1 / R1 | Move the pointer slowly, for coins and small fish |
| Start | Enter |
| Select | Escape |

## Saves

Profiles and high scores are kept in `ports/insaniquarium/conf/`, inside the
port folder rather than in the system partition, so deleting the port removes
them and copying the folder to another card keeps them.

## Known issues

- The picture can pause briefly every few minutes. The display driver's pageflip
  event arrives late; it happens below SDL and does not affect play.
- Loading screens run at a reduced frame rate. That is the original engine's own
  behaviour: it deliberately gives two thirds of the CPU to the loading thread.

## Source

<https://github.com/SaMeiers/insaniquarium-port>

Licensed AGPL-3.0, inherited from PopLib. Third-party licences are in
`licenses/`.
