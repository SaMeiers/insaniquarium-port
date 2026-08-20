#!/usr/bin/env python3
"""
Correcciones a BUGS DEL JUEGO encontrados en el decomp.

Esto es distinto de apply-blocks.py y apply-portability.py: aquellos traducen el
codigo a otra plataforma sin cambiar comportamiento; este SI cambia lo que hace
el juego, porque el decomp tiene errores respecto del original.

Se mantiene aparte a proposito, para que la lista de "que le arreglamos al
decomp" sea explicita y revisable -- y eventualmente mandable upstream.

Cada arreglo lleva: sintoma observado, causa, y por que la correccion es la
correcta.
"""
import sys
import pathlib

DST = pathlib.Path(__file__).resolve().parent.parent / "winfish"


def crlf(b: bytes) -> bytes:
    return b.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")


def sub(path, old, new, label):
    p = DST / path
    data = p.read_bytes()
    variants = ((crlf(old), crlf(new)), (old, new))
    for o, n in variants:
        if o in data:
            p.write_bytes(data.replace(o, n, 1))
            print(f"   [ok] {label}")
            return True
    for _, n in variants:
        if n in data:
            print(f"   [already applied] {label}")
            return True
    print(f"   [FAILED] {label}  ({path})")
    return False


def main():
    ok = True

    # --- 1. Fish do not grow -----------------------------------------------
    #
    # Symptom: fish eat indefinitely but almost never leave their first
    # stage. Only one or two in the tank ever grow.
    #
    # Cause: a missing pair of parentheses. In C++ '+' binds tighter than
    # '!=', so
    #
    #     mFoodAte = mFoodAte + 2 + mApp->mGameMode != GAMEMODE_VIRTUAL_TANK;
    #
    # parses as
    #
    #     mFoodAte = ((mFoodAte + 2 + mGameMode) != GAMEMODE_VIRTUAL_TANK);
    #
    # which assigns a boolean: every time a fish eats the counter resets to
    # 0 or 1 instead of accumulating. Since mFoodNeededToGrow ranges from 4
    # to 20, the threshold is never reached this way.
    #
    # The intent is to add 2 in the virtual tank and 3 elsewhere, which is
    # what correctly placed parentheses produce.
    ok &= sub("Fish.cpp",
              b"mFoodAte = mFoodAte + 2 + mApp->mGameMode != GAMEMODE_VIRTUAL_TANK;",
              b"mFoodAte = mFoodAte + 2 + (mApp->mGameMode != GAMEMODE_VIRTUAL_TANK);",
              "Fish: precedencia rompia la acumulacion de comida (no crecian)")

    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
