#!/usr/bin/env python3
"""
Reemplazos de bloque que sed no puede hacer con seguridad.
Se ejecuta sobre port/winfish/ despues de las reglas de sed.
Preserves CRLF (opened in binary mode and handled as bytes).
Idempotente y verificable: si un bloque esperado no aparece, avisa y sale != 0.
"""
import sys, pathlib

DST = pathlib.Path(__file__).resolve().parent.parent / "winfish"

# --- fishsongs: FindFirstFileA -> std::filesystem -------------------------
# The original enumerates "fishsongs\*.txt", parses each one and sorts them by
# the _long.txt / _short.txt suffix, splitting the name at the first underscore.
# directory_iterator gives no ordering guarantee, so the list is sorted
# alphabetically to keep the order stable (FindFirstFile is alphabetical in
# practice on NTFS, so this stays closer to the original than not sorting).
FISHSONGS_OLD = b'''	WIN32_FIND_DATAA aFindFileData;
	HANDLE hFind = FindFirstFileA("fishsongs\\\\*.txt", &aFindFileData);

	if (hFind == INVALID_HANDLE_VALUE)
		return;
'''

FISHSONGS_NEW = b'''	std::vector<std::string> aSongFiles;
	{
		std::error_code anEC;
		for (const auto &anEntry : std::filesystem::directory_iterator("fishsongs", anEC))
		{
			if (!anEntry.is_regular_file())
				continue;
			std::string anExt = anEntry.path().extension().string();
			for (char &c : anExt)
				c = (char)tolower((unsigned char)c);
			if (anExt == ".txt")
				aSongFiles.push_back(anEntry.path().filename().string());
		}
		if (anEC || aSongFiles.empty())
			return;
		std::sort(aSongFiles.begin(), aSongFiles.end());
	}
'''

# The loop body: do/while(FindNextFileA) becomes a range-for over aSongFiles.
# The original semantics are preserved, including the name split and the
# long/short classification.
LOOP_OLD = b'''	do \n	{
		FishSongData* aNewSong = new FishSongData();
		gSongsVector1.push_back(aNewSong);

		PopString aFilePath = "fishsongs\\\\";
		aFilePath.append(aFindFileData.cFileName);
'''

LOOP_NEW = b'''	for (const std::string &aFileName : aSongFiles)
	{
		FishSongData* aNewSong = new FishSongData();
		gSongsVector1.push_back(aNewSong);

		PopString aFilePath = "fishsongs\\\\";
		aFilePath.append(aFileName);
'''

ERRLINE_OLD = b'''				fprintf(anErrorFile, "%s - %s\\n", aFindFileData.cFileName, gFishSongParseError.c_str());'''
ERRLINE_NEW = b'''				fprintf(anErrorFile, "%s - %s\\n", aFileName.c_str(), gFishSongParseError.c_str());'''

SPLIT_OLD = b'''			char* aProperty = strchr(aFindFileData.cFileName, '_');
			if (aProperty != 0)
			{
				*aProperty = '\\0';
				if (stricmp(aProperty + 1, "long.txt") == 0)
					aNewSong->mProperties["long"] = aFindFileData.cFileName;
				else if(stricmp(aProperty + 1, "short.txt") == 0)
					aNewSong->mProperties["short"] = aFindFileData.cFileName;
			}
'''

SPLIT_NEW = b'''			std::string::size_type anUnderscore = aFileName.find('_');
			if (anUnderscore != std::string::npos)
			{
				std::string aPrefix = aFileName.substr(0, anUnderscore);
				std::string aSuffix = aFileName.substr(anUnderscore + 1);
				if (stricmp(aSuffix.c_str(), "long.txt") == 0)
					aNewSong->mProperties["long"] = aPrefix;
				else if(stricmp(aSuffix.c_str(), "short.txt") == 0)
					aNewSong->mProperties["short"] = aPrefix;
			}
'''

TAIL_OLD = b'''	} while (FindNextFileA(hFind, &aFindFileData) != 0);

	FindClose(hFind);
	if(anErrorFile != nullptr)
'''

TAIL_NEW = b'''	}

	if(anErrorFile != nullptr)
'''

# Si falla la carga de recursos, imprimir el motivo antes de intentar el popup.
# PopLib crashes inside MakeSimpleMessageBox when there is no window yet, so
# without this the game dies with 0xC0000005 and no clue as to why.
RESERR_OLD = b'''	if (!aSuccessfulResLoad)
		WFAShowResourceError();
'''

RESERR_NEW = b'''	if (!aSuccessfulResLoad)
	{
		fprintf(stderr, "ERROR DE RECURSOS: %s\\n",
				mResourceManager->GetErrorText().c_str());
		fflush(stderr);
		WFAShowResourceError();
	}
'''

# SEHCatcher::mShowUI is the body of an if. Deleting only that line left the if
# dangling over SexyApp::Init(), so AppBase::Init() -- and with it the creation
# of mSDLInterface -- only ran in screensaver mode. The whole if is removed.
SHOWUI_OLD = b'''	if (anIsScreenSaver)
		SEHCatcher::mShowUI = false;

	SexyApp::Init();
'''

SHOWUI_NEW = b'''	SexyApp::Init();
'''

# <filesystem> no viene por common.hpp
INC_OLD = b'''#include "PopLib/debug/errorhandler.hpp"'''
INC_NEW = b'''#include <filesystem>
#include "PopLib/debug/errorhandler.hpp"'''


def crlf(b: bytes) -> bytes:
    """Sources are CRLF; the literals above are written with \\n."""
    return b.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")


def replace_once(path, old, new, label):
    p = DST / path
    data = p.read_bytes()
    # Buscar SIEMPRE el patron viejo primero. Al reves da falsos positivos:
    # if NEW is a substring of the untransformed text (for instance NEW keeps a
    # line OLD already had), it reports "already applied" without doing anything.
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
    print(f"   [FAILED] no encontre el bloque de {label} en {path}")
    return False

def main():
    ok = True
    for old, new, label in (
        (INC_OLD, INC_NEW, "include <filesystem>"),
        (FISHSONGS_OLD, FISHSONGS_NEW, "fishsongs: enumeracion"),
        (LOOP_OLD, LOOP_NEW, "fishsongs: cabecera del loop"),
        (ERRLINE_OLD, ERRLINE_NEW, "fishsongs: linea de error"),
        (SPLIT_OLD, SPLIT_NEW, "fishsongs: split del nombre"),
        (TAIL_OLD, TAIL_NEW, "fishsongs: cierre del loop"),
        (RESERR_OLD, RESERR_NEW, "log del error de recursos"),
        (SHOWUI_OLD, SHOWUI_NEW, "if de SEHCatcher::mShowUI"),
    ):
        ok &= replace_once("WinFishApp.cpp", old, new, label)
    return 0 if ok else 1

if __name__ == "__main__":
    sys.exit(main())
