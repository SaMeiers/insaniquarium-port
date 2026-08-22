#!/usr/bin/env python3
"""
Remove Windows-only code from the game for the Android and Linux builds.

Where a portable equivalent exists it is used instead, which is better code and
works just as well on Windows. #ifdef _WIN32 is reserved for what is genuinely
Windows-specific and meaningless elsewhere, such as registering the screensaver
in the registry and in SYSTEM.INI.

As in apply-blocks.py, every replacement is verified: if an expected block is
missing the script says so instead of carrying on.
"""
import sys
import pathlib

DST = pathlib.Path(__file__).resolve().parent.parent / "winfish"


def crlf(b: bytes) -> bytes:
    return b.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")


def sub(path, old, new, label, count=1):
    p = DST / path
    data = p.read_bytes()
    variants = ((crlf(old), crlf(new)), (old, new))
    for o, n in variants:
        if o in data:
            p.write_bytes(data.replace(o, n, count))
            print(f"   [ok] {label}")
            return True
    for _, n in variants:
        if n in data:
            print(f"   [already applied] {label}")
            return True
    print(f"   [FAILED] {label}  ({path})")
    return False


def sub_all(path, old, new, label):
    """Replace every occurrence; fail if there are none."""
    p = DST / path
    data = p.read_bytes()
    o, n = crlf(old), crlf(new)
    hits = data.count(o)
    if hits == 0:
        if data.count(n) > 0:
            print(f"   [already applied] {label}")
            return True
        print(f"   [FAILED] {label}  ({path})")
        return False
    p.write_bytes(data.replace(o, n))
    print(f"   [ok] {label} ({hits}x)")
    return True


def wrap_win32(path, signature, fallback, label):
    """
    Wrap a function body in #ifdef _WIN32 with a fallback for other platforms.
    Finds the closing brace at column 0 rather than using line numbers, which
    drift with every earlier patch.
    """
    p = DST / path
    data = p.read_bytes()
    sig = crlf(signature)

    if crlf(b"#ifdef _WIN32\n") in data and sig in data:
        head = data.index(sig)
        if data.count(crlf(b"#ifdef _WIN32\n"), head, head + 400) > 0:
            print(f"   [already applied] {label}")
            return True

    if sig not in data:
        print(f"   [FAILED] could not find the signature of {label}")
        return False

    start = data.index(sig) + len(sig)
    open_brace = data.index(crlf(b"{\n"), start) + len(crlf(b"{\n"))
    end = data.index(crlf(b"\n}\n"), open_brace)

    body = data[open_brace:end]
    tail = (crlf(b"\n#else\n") + crlf(fallback)) if fallback else crlf(b"\n")
    new_body = crlf(b"#ifdef _WIN32\n") + body + tail + crlf(b"#endif")

    p.write_bytes(data[:open_brace] + new_body + data[end:])
    print(f"   [ok] {label}")
    return True


def main():
    ok = True

    # --- 1. GetTickCount -> SDL_GetTicks -------------------------------------
    ok &= sub("FishSongMgr.cpp", b'#include "PopLib/common.hpp"',
              b'#include <SDL3/SDL.h>\n#include "PopLib/common.hpp"',
              "FishSongMgr: include SDL")
    ok &= sub_all("FishSongMgr.cpp", b"GetTickCount()", b"(DWORD)SDL_GetTicks()",
                  "GetTickCount -> SDL_GetTicks")

    # --- 2. OutputDebugString -> SDL_Log -------------------------------------
    # SDL_Log also reaches logcat on Android, which is what is wanted.
    ok &= sub_all("SexyApp.cpp", b"OutputDebugString(", b'SDL_Log("%s", ',
                  "SexyApp: OutputDebugString -> SDL_Log")
    ok &= sub_all("InternetManager.cpp", b"OutputDebugStringA(", b'SDL_Log("%s", ',
                  "InternetManager: OutputDebugStringA -> SDL_Log")

    # --- 3. CreateDirectoryA -> MkDir (helper portable de PopLib) ------------
    ok &= sub("InternetManager.cpp",
              b"\t\t\t\tCreateDirectoryA(aDirToCreate.c_str(), NULL);",
              b"\t\t\t\tMkDir(aDirToCreate);",
              "CreateDirectoryA -> MkDir")

    # --- 4. <direct.h> y mkdir() ---------------------------------------------
    ok &= sub("SexyApp.cpp", b"#include <direct.h>",
              b"#include <filesystem>",
              "SexyApp: <direct.h> -> <filesystem>")
    ok &= sub("SexyApp.cpp", b'\tmkdir("temp");', b'\tMkDir("temp");',
              "mkdir -> MkDir")

    # --- 5. MessageBox -> SDL_ShowSimpleMessageBox ---------------------------
    ok &= sub("SexyApp.cpp",
              b'\t\tMessageBox(NULL, aVersionString.c_str(), "Version Info", MB_ICONINFORMATION | MB_OK);',
              b'\t\tSDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_INFORMATION, "Version Info",\n'
              b'\t\t\t\t\t\t\t\t aVersionString.c_str(), nullptr);',
              "MessageBox -> SDL_ShowSimpleMessageBox")

    # --- 6. limpieza de temp\\tpl*.html -> std::filesystem -------------------
    ok &= sub("SexyApp.cpp", b'''	WIN32_FIND_DATA aFindData;
	HANDLE aHandle = FindFirstFile("temp\\\\tpl*.html", &aFindData);
	if (aHandle != NULL)
	{
		do
		{
			std::string aFilePath = std::string("temp\\\\") + aFindData.cFileName;
			DeleteFile(aFilePath.c_str());
		} while (FindNextFile(aHandle, &aFindData));

		FindClose(aHandle);
	}
''', b'''	{
		std::error_code anEC;
		for (const auto &anEntry : std::filesystem::directory_iterator("temp", anEC))
		{
			const std::string aName = anEntry.path().filename().string();
			if (aName.rfind("tpl", 0) == 0 && anEntry.path().extension() == ".html")
				std::filesystem::remove(anEntry.path(), anEC);
		}
	}
''', "limpieza de temp/tpl*.html -> std::filesystem")

    # --- 7. GetFileLastWriteTime -> std::filesystem --------------------------
    ok &= sub("WinFishApp.cpp", b'''bool GetFileLastWriteTime(const char* path, FILETIME* outTime)
{
	HANDLE hFile = CreateFileA(
		path,
		GENERIC_READ,
		0,
		nullptr,
		OPEN_EXISTING,
		0,
		nullptr
	);

	if (hFile == INVALID_HANDLE_VALUE)
		return false;

	BOOL ok = GetFileTime(hFile, nullptr, nullptr, outTime);
	CloseHandle(hFile);

	return ok != 0;
}''', b'''bool GetFileLastWriteTime(const char* path, std::filesystem::file_time_type* outTime)
{
	std::error_code anEC;
	auto aTime = std::filesystem::last_write_time(path, anEC);
	if (anEC)
		return false;
	if (outTime != nullptr)
		*outTime = aTime;
	return true;
}''', "GetFileLastWriteTime -> std::filesystem")

    ok &= sub("WinFishApp.cpp", b'''	FILETIME ft1;
	FILETIME ft2;''', b'''	std::filesystem::file_time_type ft1;
	std::filesystem::file_time_type ft2;''',
              "DoScrCopy: FILETIME -> file_time_type")

    # --- 7b. tipos y funciones de tiempo de MSVC -----------------------------
    # __time64_t, _time64 and _localtime64 are MSVC extensions. Under MSVC
    # x64 time_t is __time64_t, and on 64-bit Android time_t is 64-bit too,
    # so the substitution is exact and does not change Windows behaviour.
    #
    # It matters more than it looks: mTimeBought is a GameObject member, and
    # with an unknown type clang cannot complete the class. That produced
    # "GameObject does not derive from Widget" and a cascade of conversion
    # errors across the whole game.
    for f in ("GameObject.h", "GameObject.cpp", "Board.cpp", "WinFishCommon.cpp"):
        p = DST / f
        d = p.read_bytes()
        n = d.count(b"__time64_t") + d.count(b"_time64(") + d.count(b"_localtime64(")
        if n == 0:
            continue
        d = d.replace(b"__time64_t", b"time_t")
        d = d.replace(b"_localtime64(", b"localtime(")
        # order matters: __time64_t has already been replaced, so the remaining
        # "_time64(" is only the function
        d = d.replace(b"_time64(", b"time(")
        p.write_bytes(d)
        print(f"   [ok] tiempo MSVC -> portable en {f} ({n}x)")

    ok &= sub("GameObject.h", b'#include "DataSync.h"',
              b'#include <ctime>\n#include "DataSync.h"',
              "GameObject.h: include <ctime>")

    # --- 7c. herencia redundante de ButtonListener ---------------------------
    # PopLib::Dialog already inherits ButtonListener, so game classes that
    # derive from Dialog/MoneyDialog and ButtonListener as well end up with
    # two copies and every conversion becomes ambiguous. Dropping the
    # explicit base keeps the behaviour (they still are ButtonListeners via
    # Dialog) and satisfies both compilers.
    #
    # Classes deriving from Widget do need ButtonListener explicitly: Widget
    # does not provide it.
    dialog_classes = {
        "MoneyDialog.h": b"class MoneyDialog : public Dialog, public ButtonListener",
        "UpdateCheckDialog.h": b"class UpdateCheckDialog : public Dialog, public ButtonListener",
        "ContinueDialog.h": b"class ContinueDialog : public MoneyDialog, public ButtonListener",
        "PetDialog.h": b"class PetDialog : public MoneyDialog, public ButtonListener",
        "VirtualDialog.h": b"class VirtualDialog : public MoneyDialog, public ButtonListener",
        "NewUserDialog.h": b"class NewUserDialog : public MoneyDialog, public ButtonListener, public EditListener",
        "RegisterDialog.h": b"class RegisterDialog : public MoneyDialog, public ButtonListener, public EditListener",
        "OptionsDialog.h": b"class OptionsDialog : public MoneyDialog, public ButtonListener, public SliderListener, public CheckboxListener",
        "ScreenSaverDialog.h": b"class ScreenSaverDialog : public MoneyDialog, public ButtonListener, public CheckboxListener",
        "UserDialog.h": b"class UserDialog : public MoneyDialog, public ButtonListener, public ListListener, public EditListener",
    }
    for fname, decl in dialog_classes.items():
        new_decl = decl.replace(b", public ButtonListener", b"", 1)
        ok &= sub(fname, decl, new_decl, f"ButtonListener redundante en {fname}")

    # --- 7d. temporales atados a referencia no-const -------------------------
    # SetColorHelper only reads the colour, so const& is correct. It is
    # called with Color(...) temporaries, which cannot bind to a non-const
    # reference (MSVC allowed it under /permissive).
    ok &= sub("GameObject.h", b"SetColorHelper(Graphics* g, Color& theColor);",
              b"SetColorHelper(Graphics* g, const Color& theColor);",
              "SetColorHelper: const& (declaracion)")
    ok &= sub("GameObject.cpp", b"SetColorHelper(Graphics* g, Color& theColor)",
              b"SetColorHelper(Graphics* g, const Color& theColor)",
              "SetColorHelper: const& (definicion)")

    # All three DrawInstr*Part take Rect(...) temporaries and only read the
    # rect (verified: no assignments to theRect in any of the three).
    for fn in ("DrawInstrLeftPart", "DrawInstrMiddlePart", "DrawInstrRightPart"):
        ok &= sub("HelpScreen.h",
                  f"{fn}(Graphics* g, Rect& theRect);".encode(),
                  f"{fn}(Graphics* g, const Rect& theRect);".encode(),
                  f"{fn}: const& (declaracion)")
        ok &= sub("HelpScreen.cpp",
                  f"{fn}(Graphics* g, Rect& theRect)".encode(),
                  f"{fn}(Graphics* g, const Rect& theRect)".encode(),
                  f"{fn}: const& (definicion)")

    # DrawInstrText receives the now-const theRect from the three above and
    # does not modify it either, so const propagates.
    ok &= sub("HelpScreen.h",
              b"DrawInstrText(Graphics* g, Rect& theRect, PopString& theTitle,",
              b"DrawInstrText(Graphics* g, const Rect& theRect, PopString& theTitle,",
              "DrawInstrText: const& (declaracion)")
    ok &= sub("HelpScreen.cpp",
              b"DrawInstrText(Graphics* g, Rect& theRect, PopString& theTitle,",
              b"DrawInstrText(Graphics* g, const Rect& theRect, PopString& theTitle,",
              "DrawInstrText: const& (definicion)")

    # int -> float in an initialiser list (same reason as SDL_FRect)
    ok &= sub("Missle.cpp", b"float aVec[3] = { aDiffX, aDiffY , 0};",
              b"float aVec[3] = { (float)aDiffX, (float)aDiffY, 0.0f };",
              "Missle: narrowing en aVec")

    # --- 7e. asuncion de 32 bits en Res.cpp ----------------------------------
    # gResources[] stores the addresses of the resource variables, and this
    # map keys on the value held there: a pointer for images and fonts, an
    # int for sounds. The original treated all of them as int, which worked
    # on 32-bit Windows.
    #
    # On 64-bit both sides truncate to the low 32 bits (4 bytes are read on
    # construction and the pointer is cast on lookup), so it works today by
    # coincidence -- but clang rejects the pointer-to-int cast. The map is
    # left as uint32_t and the cast goes through uintptr_t to truncate
    # legally.
    #
    # Not switched to full uintptr_t on purpose: for sounds the stored value
    # really is an int.
    # variable apuntada es un int de 4 bytes, y leer 8 traeria basura.
    ok &= sub("Res.cpp", b"\ttypedef std::map<int, int> MyMap;",
              b"\ttypedef std::map<uint32_t, int> MyMap;",
              "Res: clave del mapa a uint32_t")
    ok &= sub("Res.cpp", b"\t\t\taMap[*(int*)gResources[i]] = i;",
              b"\t\t\taMap[*(uint32_t*)gResources[i]] = i;",
              "Res: lectura de la clave a uint32_t")
    ok &= sub("Res.cpp", b"aMap.find((int)theVariable);",
              b"aMap.find((uint32_t)(uintptr_t)theVariable);",
              "Res: busqueda sin cast puntero->int")
    ok &= sub("Res.cpp", b"return GetIdByVariable((void*)theSound);",
              b"return GetIdByVariable((void*)(uintptr_t)theSound);",
              "Res: int->void* via uintptr_t")

    # --- 7f. referencia no-const a un retorno por valor ----------------------
    # GetPetName returns PopString by value, so it cannot bind to a
    # non-const reference. A copy is taken, which is what MSVC did anyway.
    ok &= sub("PetsScreen.cpp", b"PopString& aPetName = GetPetName(thePetId);",
              b"PopString aPetName = GetPetName(thePetId);",
              "PetsScreen: copia en vez de referencia")

    # --- 7g. more screensaver Win32 -------------------------------------------
    # The user name is only used to build the screensaver registry key,
    # which does not exist outside Windows.
    ok &= sub("WinFishApp.cpp", b'''	char aUserNameBuffer[1024];
	DWORD aUserNameSize = sizeof(aUserNameBuffer);
	if (GetUserNameA(aUserNameBuffer, &aUserNameSize))
	{
		mScreenSaverRegPath.append(aUserNameBuffer, strlen(aUserNameBuffer));
		mScreenSaverRegPath += '\\\\';
	}''', b'''#ifdef _WIN32
	char aUserNameBuffer[1024];
	DWORD aUserNameSize = sizeof(aUserNameBuffer);
	if (GetUserNameA(aUserNameBuffer, &aUserNameSize))
	{
		mScreenSaverRegPath.append(aUserNameBuffer, strlen(aUserNameBuffer));
		mScreenSaverRegPath += '\\\\';
	}
#endif''', "GetUserNameA -> #ifdef _WIN32")

    # Enabling the system screensaver: pure Windows, no equivalent.
    ok &= sub("WinFishApp.cpp", b'''				PVOID aParam = 0;
				SystemParametersInfoA(SPI_GETSCREENSAVEACTIVE, 0, &aParam, 0);
				if(aParam == 0)
					SystemParametersInfoA(SPI_SETSCREENSAVEACTIVE, 1, &aParam, 1);''',
              b'''#ifdef _WIN32
				PVOID aParam = 0;
				SystemParametersInfoA(SPI_GETSCREENSAVEACTIVE, 0, &aParam, 0);
				if(aParam == 0)
					SystemParametersInfoA(SPI_SETSCREENSAVEACTIVE, 1, &aParam, 1);
#endif''', "SystemParametersInfo -> #ifdef _WIN32")

    # chdir si tiene equivalente portable.
    ok &= sub("WinFishApp.cpp",
              b"\t\tif (SetCurrentDirectoryA(aDirectoryPath.c_str()) != 0)\n\t\t\treturn true;",
              b"\t{\n"
              b"\t\tstd::error_code anEC;\n"
              b"\t\tstd::filesystem::current_path(aDirectoryPath, anEC);\n"
              b"\t\tif (!anEC)\n"
              b"\t\t\treturn true;\n"
              b"\t}",
              "SetCurrentDirectoryA -> std::filesystem::current_path")

    # --- 8. bloque salvapantallas: #ifdef _WIN32 -----------------------------
    # Registering the game as the system screensaver goes through the
    # registry and SYSTEM.INI, which only exist on Windows.
    # en Android ni en Linux: el concepto no existe. Se conserva intacto el
    # comportamiento en Windows y se deja un no-op en el resto.
    ok &= wrap_win32("WinFishApp.cpp",
                     b"void PopLib::WinFishApp::SetScreenSaver(const char* thePath)",
                     b"\t(void)thePath; // no hay salvapantallas del sistema fuera de Windows\n",
                     "SetScreenSaver -> #ifdef _WIN32")

    ok &= wrap_win32("WinFishApp.cpp",
                     b"PopString PopLib::WinFishApp::GetScreenSaverFilePath()",
                     b"\treturn \"\";\n",
                     "GetScreenSaverFilePath -> #ifdef _WIN32")

    ok &= wrap_win32("WinFishApp.cpp",
                     b"void PopLib::WinFishApp::GetSystemScreenSaverPath(PopString& theDest)",
                     b"\ttheDest = \"\";\n",
                     "GetSystemScreenSaverPath -> #ifdef _WIN32")

    # --- 9. executable path: GetModuleFileNameA -> SDL_GetBasePath ------------
    # SDL_GetBasePath is portable and resolves the app directory on every
    # platform (it returns null on Android, which is correct: there is no
    # "exe directory" there and this block is screensaver code anyway).
    ok &= sub("WinFishApp.cpp", b'''		char aModuleFileName[260];
		GetModuleFileNameA(NULL, aModuleFileName, sizeof(aModuleFileName));
		PopString aModulePath = aModuleFileName;''',
              b'''		const char* aBasePath = SDL_GetBasePath();
		PopString aModuleFileName = (aBasePath != nullptr) ? aBasePath : "";
		PopString aModulePath = aModuleFileName;''',
              "GetModuleFileNameA -> SDL_GetBasePath")

    ok &= sub("WinFishApp.cpp", b"\t\t\tstd::string aFileName = GetFileName(aModuleFileName);",
              b"\t\t\tstd::string aFileName = GetFileName(aModuleFileName.c_str());",
              "ajuste de tipo tras SDL_GetBasePath")

    # --- 10. BetaSupport: interfaz igual, implementacion no-op fuera de Win32 -
    # This is PopCap beta-program telemetry: it creates a Win32 window and
    # pumps messages. Rather than deleting it and touching all 8 call sites,
    # only the implementation is guarded, so Windows behaviour is untouched
    # and every other platform gets stubs. Members are left alone so the
    # class layout on Windows does not change.
    # so the class layout on Windows does not change.
    ok &= sub("BetaSupport.h", b"#include <windows.h>",
              b"#ifdef _WIN32\n#define WIN32_LEAN_AND_MEAN\n#include <windows.h>\n#endif",
              "BetaSupport.h: guardar windows.h")

    ok &= sub("BetaSupport.h", b'''		HFONT mTahomaFont;
		HFONT mArialFont;
		HFONT mTahomaBoldFont;
		int m0x14;
		HWND mHWND1;''', b'''#ifdef _WIN32
		HFONT mTahomaFont;
		HFONT mArialFont;
		HFONT mTahomaBoldFont;
#endif
		int m0x14;
#ifdef _WIN32
		HWND mHWND1;
#endif''', "BetaSupport.h: guardar miembros Win32")

    ok &= sub("BetaSupport.cpp", b'''	mHWND1 = 0;

	HWND hWnd = GetDesktopWindow();''', b'''#ifdef _WIN32
	mHWND1 = 0;

	HWND hWnd = GetDesktopWindow();''', "BetaSupport: abrir guard del constructor")

    ok &= sub("BetaSupport.cpp", b'''	ReleaseDC(hWnd, hDC);
}''', b'''	ReleaseDC(hWnd, hDC);
#endif
}''', "BetaSupport: cerrar guard del constructor")

    ok &= wrap_win32("BetaSupport.cpp", b"PopLib::BetaSupport::~BetaSupport()",
                     b"", "BetaSupport: destructor")
    ok &= wrap_win32("BetaSupport.cpp", b"void PopLib::BetaSupport::DoMessageLoop()",
                     b"", "BetaSupport: DoMessageLoop")

    # --- default profile name -------------------------------------------------
    # A handheld has no keyboard, so the game got stuck on the "enter your
    # name" screen with no way past it. The field is pre-filled with a name
    # from the game itself (its pets and aliens); confirming is enough.
    # y alcanza con aceptar.
    #
    # Uses the standard library rand() and not PopLib Rand() on purpose:
    # that one is the game Mersenne Twister, and drawing from it every time
    # this dialog opens would shift the sequence gameplay depends on.
    ok &= sub("NewUserDialog.cpp",
              b"""	mEditWidget = MakeEditWidget(0, this);
	mEditWidget->mMaxChars = 12;""",
              b"""	mEditWidget = MakeEditWidget(0, this);
	mEditWidget->mMaxChars = 12;

	if (!theRename)
	{
		static const char *aDefaultNames[] = {
			"Stinky", "Niko", "Prego", "Vert", "Rufus", "Meryl",
			"Zorf", "Clyde", "Gumbo", "Blip", "Rhubarb", "Nimbus",
			"Presto", "Seymour", "Shrapnel", "Brinkley", "Angie", "Walter",
		};
		mEditWidget->mString =
			aDefaultNames[rand() % (sizeof(aDefaultNames) / sizeof(aDefaultNames[0]))];
	}""",
              "NewUserDialog: nombre por defecto (no hay teclado en la consola)")

    ok &= sub("NewUserDialog.cpp",
              b'#include "PopLib/widget/widgetmanager.hpp"',
              b'''#include "PopLib/widget/widgetmanager.hpp"

#include <cstdlib>''',
              "NewUserDialog: cstdlib para rand()")


    # --- the last Windows path separators -----------------------------------
    #
    # partner.xml has never been read. It is opened as "properties\\partner.xml",
    # which on Linux names a file that does not exist, and it is optional so
    # nothing complains. The file is real and ships with the game's data: it
    # carries NoReg, which is what tells the game this copy is registered, so
    # without it the game believes it is not and offers to sell itself.
    #
    # The signature check has to go with it. PopLib's CheckSignature is a stub
    # returning false whatever it is handed, so a file that now loads would be
    # met with a popup refusing it -- worse than the silence it replaces. There
    # is nothing to protect either: the data comes from the player's own copy.
    aBS = chr(92)
    aSep = (aBS + aBS).encode()

    ok &= sub("SexyApp.cpp",
              b"bool checkSig = !IsScreenSaver();",
              b"bool checkSig = false; // PopLib has no signature implementation",
              "SexyApp: partner.xml was asked for a signature that cannot pass")

    ok &= sub("SexyApp.cpp",
              b'"properties' + aSep + b'partner.xml"',
              b'"properties/partner.xml"',
              "SexyApp: partner.xml was opened with a Windows separator")

    # Unreachable in practice -- it needs a Windows screensaver path to exist
    # first -- but it is the same mistake and cheap to correct.
    ok &= sub("WinFishApp.cpp",
              b'GetAppDataFolder() + "' + aSep + b'screensaver.dat"',
              b'GetAppDataFolder() + "screensaver.dat"',
              "WinFishApp: screensaver.dat under the data folder")

    ok &= sub("WinFishApp.cpp",
              b'GetFileDir(theScrSvrPath) + "' + aSep + b'screensaver.dat"',
              b'GetFileDir(theScrSvrPath) + "/screensaver.dat"',
              "WinFishApp: screensaver.dat beside the screensaver")

    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
