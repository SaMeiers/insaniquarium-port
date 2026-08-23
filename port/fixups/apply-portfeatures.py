#!/usr/bin/env python3
"""
Anadidos propios del PORT, no correcciones al decomp.

apply-gamefixes.py repara errores del decompilado y apply-portability.py lo
traduce a otra plataforma sin cambiar lo que hace. Este archivo es lo tercero:
funciones que el juego original no tiene y que existen porque se juega en una
consola con mando.

Va aparte para que la lista de "que le agregamos al juego" sea explicita, y
para que nadie confunda un anadido con un arreglo.
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

    # --- Auto Collect --------------------------------------------------------
    #
    # Collecting coins is the one thing this game asks of you constantly, and
    # on a handheld every coin is a press of the same button. Players asked for
    # a way to sweep the tank in one go.
    #
    # It is off by default and warns the first time it is switched on, because
    # it does make the collecting pets less useful and that should be the
    # player's choice rather than something the port decides for them.

    # The option itself, remembered between sessions like the other settings.
    ok &= sub("WinFishApp.h",
              b"\t\tbool\t\t\t\t\t\t\tmScreenSaverEnabled;",
              b"\t\t// Sweep every coin in the tank with one button. Off unless asked for:\r\n"
              b"\t\t// it makes the collecting pets much less useful, so the first time it\r\n"
              b"\t\t// is switched on the player is told as much and can say no.\r\n"
              b"\t\tbool\t\t\t\t\t\t\tmAutoCollectEnabled;\r\n"
              b"\t\tbool\t\t\t\t\t\t\tmAutoCollectWarningShown;\r\n"
              b"\r\n"
              b"\t\tbool\t\t\t\t\t\t\tmScreenSaverEnabled;",
              "WinFishApp: auto collect settings")

    ok &= sub("WinFishApp.h",
              b"\t\tDIALOG_END_ID",
              b"\t\tDIALOG_AUTO_COLLECT,\r\n"
              b"\t\tDIALOG_END_ID",
              "WinFishApp: dialog id for the warning")

    ok &= sub("WinFishApp.cpp",
              b"\tRegistryReadInteger(\"ldaccum\", &mLDAccum);",
              b"\tint anAutoCollect = 0;\r\n"
              b"\tif (RegistryReadInteger(\"AutoCollect\", &anAutoCollect))\r\n"
              b"\t\tmAutoCollectEnabled = anAutoCollect != 0;\r\n"
              b"\tif (RegistryReadInteger(\"AutoCollectWarned\", &anAutoCollect))\r\n"
              b"\t\tmAutoCollectWarningShown = anAutoCollect != 0;\r\n"
              b"\r\n"
              b"\tRegistryReadInteger(\"ldaccum\", &mLDAccum);",
              "WinFishApp: read the setting")

    ok &= sub("WinFishApp.cpp",
              b"\t\tRegistryWriteInteger(\"ldinfo\", mDaysSinceFirstRun);",
              b"\t\tRegistryWriteInteger(\"AutoCollect\", mAutoCollectEnabled ? 1 : 0);\r\n"
              b"\t\tRegistryWriteInteger(\"AutoCollectWarned\", mAutoCollectWarningShown ? 1 : 0);\r\n"
              b"\t\tRegistryWriteInteger(\"ldinfo\", mDaysSinceFirstRun);",
              "WinFishApp: save the setting")

    # Answers to the warning. Yes arrives as 2000 + id, No as 3000 + id.
    ok &= sub("WinFishApp.cpp",
              b"\tcase DIALOG_OPTIONS:\r\n"
              b"\t\tApplyOptionsSettings();\r\n"
              b"\t\tbreak;",
              b"\tcase DIALOG_OPTIONS:\r\n"
              b"\t\tApplyOptionsSettings();\r\n"
              b"\t\tbreak;\r\n"
              b"\tcase DIALOG_AUTO_COLLECT:\r\n"
              b"\t\t// Accepted. Remember the answer so the warning is only ever seen once.\r\n"
              b"\t\tmAutoCollectEnabled = true;\r\n"
              b"\t\tmAutoCollectWarningShown = true;\r\n"
              b"\t\tKillDialog(DIALOG_AUTO_COLLECT);\r\n"
              b"\t\tbreak;",
              "WinFishApp: warning accepted")

    ok &= sub("WinFishApp.cpp",
              b"\t\t\t\tcase 3003:",
              b"\t\t\t\tcase 3000 + DIALOG_AUTO_COLLECT:\r\n"
              b"\t\t\t\t\t// Declined: leave it off, and ask again next time.\r\n"
              b"\t\t\t\t\tmAutoCollectEnabled = false;\r\n"
              b"\t\t\t\t\tKillDialog(DIALOG_AUTO_COLLECT);\r\n"
              b"\t\t\t\t\t{\r\n"
              b"\t\t\t\t\t\tOptionsDialog* aDia = (OptionsDialog*)GetDialog(DIALOG_OPTIONS);\r\n"
              b"\t\t\t\t\t\tif (aDia != NULL)\r\n"
              b"\t\t\t\t\t\t\taDia->SyncAutoCollectCheckbox();\r\n"
              b"\t\t\t\t\t}\r\n"
              b"\t\t\t\t\tbreak;\r\n"
              b"\t\t\t\tcase 3003:",
              "WinFishApp: warning declined")

    # --- the checkbox --------------------------------------------------------
    ok &= sub("OptionsDialog.h",
              b"\t\tCheckbox* m3DCB;",
              b"\t\tCheckbox* m3DCB;\r\n"
              b"\t\tCheckbox* mAutoCollectCB;",
              "OptionsDialog: checkbox member")

    ok &= sub("OptionsDialog.h",
              b"\t\tvirtual void\t\t\tCheckboxChecked(int theId, bool checked);",
              b"\t\tvirtual void\t\t\tCheckboxChecked(int theId, bool checked);\r\n"
              b"\r\n"
              b"\t\t// Put the box back the way the setting is, for when the warning is\r\n"
              b"\t\t// declined after the player has already ticked it.\r\n"
              b"\t\tvoid\t\t\t\t\tSyncAutoCollectCheckbox();",
              "OptionsDialog: sync method")

    ok &= sub("OptionsDialog.cpp",
              b"\tm3DCB = MakeCheckbox(9, this, mApp->Is3DAccelerated());",
              b"\tm3DCB = MakeCheckbox(9, this, mApp->Is3DAccelerated());\r\n"
              b"\tmAutoCollectCB = MakeCheckbox(10, this, mApp->mAutoCollectEnabled);",
              "OptionsDialog: create the checkbox")

    ok &= sub("OptionsDialog.cpp",
              b"\ttheWidgetManager->AddWidget(m3DCB);",
              b"\ttheWidgetManager->AddWidget(m3DCB);\r\n"
              b"\ttheWidgetManager->AddWidget(mAutoCollectCB);",
              "OptionsDialog: show the checkbox")

    ok &= sub("OptionsDialog.cpp",
              b"\ttheWidgetManager->RemoveWidget(m3DCB);",
              b"\ttheWidgetManager->RemoveWidget(m3DCB);\r\n"
              b"\ttheWidgetManager->RemoveWidget(mAutoCollectCB);",
              "OptionsDialog: hide the checkbox")

    ok &= sub("OptionsDialog.cpp",
              b"\tg->DrawString(\"Hardware Acceleration\", m3DCB->mX - mX + 43, m3DCB->mY - mY + 24);",
              b"\tg->DrawString(\"Hardware Acceleration\", m3DCB->mX - mX + 43, m3DCB->mY - mY + 24);\r\n"
              b"\tg->DrawString(\"Auto Collect\", mAutoCollectCB->mX - mX + 43, mAutoCollectCB->mY - mY + 24);",
              "OptionsDialog: label")

    # The second row had only one box on it; this takes the empty half, so the
    # dialog keeps its height and nothing else moves.
    ok &= sub("OptionsDialog.cpp",
              b"\tm3DCB->Resize(mX + 33, mY + 172, 45, 46);",
              b"\tm3DCB->Resize(mX + 33, mY + 172, 45, 46);\r\n"
              b"\tmAutoCollectCB->Resize(mX + 161, mY + 172, 45, 46);",
              "OptionsDialog: layout")

    ok &= sub("OptionsDialog.cpp",
              b"\tif (mFullscreenCB)\r\n"
              b"\t\tdelete mFullscreenCB;",
              b"\tif (mAutoCollectCB)\r\n"
              b"\t\tdelete mAutoCollectCB;\r\n"
              b"\tif (mFullscreenCB)\r\n"
              b"\t\tdelete mFullscreenCB;",
              "OptionsDialog: free the checkbox")

    ok &= sub("OptionsDialog.cpp",
              b"\telse if (theId == 9 && theFlag)",
              b"\telse if (theId == 10)\r\n"
              b"\t{\r\n"
              b"\t\tif (theFlag && !mApp->mAutoCollectWarningShown)\r\n"
              b"\t\t{\r\n"
              b"\t\t\t// Not applied yet: the answer decides. Declining puts the box back.\r\n"
              b"\t\t\tmApp->DoDialog(DIALOG_AUTO_COLLECT, true, \"Auto Collect\",\r\n"
              b"\t\t\t\t\"This may affect the game experience,\\ndo you want to activate it?\",\r\n"
              b"\t\t\t\t\"\", Dialog::BUTTONS_YES_NO);\r\n"
              b"\t\t}\r\n"
              b"\t\telse\r\n"
              b"\t\t{\r\n"
              b"\t\t\tmApp->mAutoCollectEnabled = theFlag;\r\n"
              b"\t\t}\r\n"
              b"\t}\r\n"
              b"\telse if (theId == 9 && theFlag)",
              "OptionsDialog: ask before switching it on")

    ok &= sub("OptionsDialog.cpp",
              b"void PopLib::OptionsDialog::CheckboxChecked(int theId, bool checked)",
              b"void PopLib::OptionsDialog::SyncAutoCollectCheckbox()\r\n"
              b"{\r\n"
              b"\tif (mAutoCollectCB != NULL)\r\n"
              b"\t\tmAutoCollectCB->SetChecked(mApp->mAutoCollectEnabled, false);\r\n"
              b"}\r\n"
              b"\r\n"
              b"void PopLib::OptionsDialog::CheckboxChecked(int theId, bool checked)",
              "OptionsDialog: sync implementation")

    # --- the button ----------------------------------------------------------
    #
    # F1 is what the launcher maps the gamepad's Y to. A letter would be read
    # by the cheat code scanner that shares this handler.
    ok &= sub("Board.cpp",
              b"void Board::KeyDown(KeyCode theKey)\r\n"
              b"{\r\n"
              b"\tif (!mApp->mDebugKeysEnabled)",
              b"void Board::CollectAllCoins()\r\n"
              b"{\r\n"
              b"\t// Coin::MouseDown is what a click does, so going through it keeps the\r\n"
              b"\t// sound, the animation and the counting exactly as they already are.\r\n"
              b"\t// m0x17c is zero until a coin has been taken and counts up while it\r\n"
              b"\t// flies to the total, so it is also the test for one still sitting there.\r\n"
              b"\t//\r\n"
              b"\t// Over a copy: collecting can take a coin out of the list.\r\n"
              b"\tstd::vector<Coin*> aCoins = *mCoinList;\r\n"
              b"\tfor (int i = 0; i < aCoins.size(); i++)\r\n"
              b"\t{\r\n"
              b"\t\tCoin* aCoin = aCoins.at(i);\r\n"
              b"\t\tif (aCoin != NULL && aCoin->m0x17c == 0)\r\n"
              b"\t\t\taCoin->MouseDown(aCoin->mWidth / 2, aCoin->mHeight / 2, 1);\r\n"
              b"\t}\r\n"
              b"}\r\n"
              b"\r\n"
              b"void Board::KeyDown(KeyCode theKey)\r\n"
              b"{\r\n"
              b"\tif (theKey == KEYCODE_F1 && mApp->mAutoCollectEnabled)\r\n"
              b"\t{\r\n"
              b"\t\tCollectAllCoins();\r\n"
              b"\t\treturn;\r\n"
              b"\t}\r\n"
              b"\r\n"
              b"\tif (!mApp->mDebugKeysEnabled)",
              "Board: collect every coin on the button")

    ok &= sub("Board.h",
              b"\t\tvirtual void\t\t\tKeyDown(KeyCode theKey);",
              b"\t\tvoid\t\t\t\t\tCollectAllCoins();\r\n"
              b"\t\tvirtual void\t\t\tKeyDown(KeyCode theKey);",
              "Board: declare CollectAllCoins")

    # Both start off. The registry reads above only assign when the key is
    # already there, so on a first run these would otherwise keep whatever the
    # object was allocated over -- and a non-zero "warning shown" is why the
    # warning never appeared.
    ok &= sub("WinFishApp.cpp",
              b"\tmCurrentProfile = NULL;",
              b"\tmAutoCollectEnabled = false;\r\n"
              b"\tmAutoCollectWarningShown = false;\r\n"
              b"\tmCurrentProfile = NULL;",
              "WinFishApp: auto collect starts off")

    # "Hardware Acceleration" is far wider than the gap to the box beside it and
    # was drawn straight through it. The option does nothing on a handheld --
    # the renderer is chosen before any of this is read -- so the short form
    # costs nothing.
    ok &= sub("OptionsDialog.cpp",
              b'g->DrawString("Hardware Acceleration", m3DCB',
              b'g->DrawString("HA", m3DCB',
              "OptionsDialog: shorten the acceleration label")

    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
