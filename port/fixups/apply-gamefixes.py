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
              "Fish: precedence broke food accumulation, so fish never grew")

    # --- 2. Cheat code scan runs off the end of the array --------------------
    #
    # Symptom: on a 64-bit build, pressing a key during a game freezes it. Which
    # key depends on the device, and it never happens in the menus.
    #
    # Cause: the element count is computed by dividing by a hardcoded pointer
    # size.
    #
    #     CheatCode* mCheatCodes[8];
    #     for (int i = 0; i < sizeof(mCheatCodes) / 4; i++)
    #
    # A pointer was 4 bytes when this was written, so sizeof was 32 and the loop
    # ran 8 times. A 64-bit pointer makes sizeof 64, so it runs 16 times and
    # reads eight entries past the end of the array, calling a method on
    # whatever happens to follow it in the object. That garbage can report a
    # cheat as activated, and DoCheatCode then runs with an index no case
    # handles.
    #
    # It only bites during a game because Board is what owns these; there is no
    # Board in the menus, which is why the menus are unaffected.
    ok &= sub("Board.cpp",
              b"for (int i = 0; i < sizeof(mCheatCodes) / 4; i++)",
              b"for (int i = 0; i < sizeof(mCheatCodes) / sizeof(mCheatCodes[0]); i++)",
              "Board::KeyChar: cheat code loop ran past the end of the array")

    ok &= sub("Board.cpp",
              b"for (int i = 0; i < (sizeof(mCheatCodes) / 4); i++)",
              b"for (int i = 0; i < (sizeof(mCheatCodes) / sizeof(mCheatCodes[0])); i++)",
              "Board::KeyDown: cheat code loop ran past the end of the array")


    # --- 3. Star potion never turns a big guppy into a star guppy -----------
    #
    # Symptom: a big fish eats a star potion and nothing happens; it never
    # starts producing stars.
    #
    # Cause: the branch already knows the food is type 3, and then asks whether
    # it is type 2:
    #
    #     else if (aFood->mFoodType == 3)     // the potion
    #         ...
    #         if (aFood->mFoodType == 2)      // cannot ever be true
    #             mSize = SIZE_STAR;
    #
    # so the one assignment that makes a star guppy is unreachable. That
    # matters because DropCoin picks the coin with `aCoinType = mSize`, and
    # SIZE_STAR (3) is COIN_STAR (3): the size *is* what produces stars.
    #
    # The condition was `mSize == 2`, that is SIZE_LARGE. The constant 2
    # survived the decompilation but was attached to the wrong variable, and
    # the clamp on mHunger appearing in both branches is the usual sign of a
    # decompiler splitting one `if`. Reading it as SIZE_LARGE also matches what
    # the game itself says -- "Star potions are for BIG guppies only" -- and
    # leaves crowned guppies alone, which a bare `else` would demote.
    ok &= sub("Fish.cpp",
              b"if (aFood->mFoodType == 2)",
              b"if (mSize == SIZE_LARGE)",
              "Fish: star potion could never turn a big guppy into a star guppy")

    # --- 4. Pets spawn with their X and Y ranges swapped --------------------
    #
    # Every other spawn in the game -- thirteen of them -- places an object
    # with X across the tank and Y down it:
    #
    #     new Fish(Next() % 520 + 20, Next() % 265 + 105);
    #
    # SpawnPet is the only one with the two the other way round, so pets appear
    # in a narrow vertical strip in the middle instead of anywhere across the
    # tank, and start at a depth the movement code has to pull back into range.
    ok &= sub("Board.cpp",
              b"\t\ttheX = mApp->mSeed->Next() % 265 + 105;\r\n"
              b"\t\ttheY = mApp->mSeed->Next() % 520 + 20;",
              b"\t\ttheX = mApp->mSeed->Next() % 520 + 20;\r\n"
              b"\t\ttheY = mApp->mSeed->Next() % 265 + 105;",
              "Board::SpawnPet: X and Y spawn ranges were swapped")



    # --- 5. Saved games are written to a path with a Windows separator ------
    #
    # Symptom: on a tester's device nothing bought in the virtual tank was
    # there on the next run, while the profile itself -- unlocks, shells --
    # survived.
    #
    # Cause: GetSaveGameFilePath builds the name with a backslash:
    #
    #     sprintf(aPathBuffer, "userdata\%s%d.dat", aGameModeString, theUserId);
    #
    # so the result is not a file inside userdata but a single file named
    # "userdata\virtualtank0.dat" sitting beside it. WriteBytesToFile calls
    # MkDir(GetFileDir(path)) first, and GetFileDir splits on '/', so it
    # creates the folder above and never notices.
    #
    # On ext4 a backslash is a legal filename character, so the odd name is
    # created and everything works, which is why this never showed up on the
    # devices we test on. FAT is what a handheld's card usually is, and it
    # rejects the name: fopen fails, WriteBytesToFile returns false, and
    # nobody checks the result. The save is lost without a word.
    #
    # The profile survived because its own path, "userdata/user%d.dat", uses
    # the right separator already.
    ok &= sub("ProfileMgr.cpp",
              b'sprintf(aPathBuffer, "userdata\\\\%s%d.dat", aGameModeString, theUserId);',
              b'sprintf(aPathBuffer, "userdata/%s%d.dat", aGameModeString, theUserId);',
              "UserProfile: saved games went to a path with a Windows separator")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
