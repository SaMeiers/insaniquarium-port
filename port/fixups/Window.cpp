#include "WinFishApp.h"

// SDL_main.h renames main() to SDL_main() where the platform needs it. On
// Android that is essential: SDLActivity loads libmain.so and calls SDL_main;
// there is no process main(). On desktop it changes nothing.
#include <SDL3/SDL_main.h>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <Windows.h>
#include <DbgHelp.h>
#include <cstdio>
#pragma comment(lib, "dbghelp.lib")
#endif

using namespace PopLib;

#ifdef _WIN32
// Crash handler: without it an access violation exits silently with code
// 0xC0000005 and no hint of where it happened. dbghelp ships with Windows and
// the symbols come from the build's own .pdb.
static LONG WINAPI WinFishCrashHandler(EXCEPTION_POINTERS *theInfo)
{
	FILE *aLog = fopen("crash.txt", "w");
	if (aLog == nullptr)
		aLog = stderr;

	fprintf(aLog, "EXCEPCION 0x%08lX en 0x%p\n\n",
			theInfo->ExceptionRecord->ExceptionCode,
			theInfo->ExceptionRecord->ExceptionAddress);

	HANDLE aProcess = GetCurrentProcess();
	SymSetOptions(SYMOPT_LOAD_LINES | SYMOPT_DEFERRED_LOADS | SYMOPT_UNDNAME);
	SymInitialize(aProcess, nullptr, TRUE);

	char aSymBuffer[sizeof(SYMBOL_INFO) + 256];
	SYMBOL_INFO *aSymbol = (SYMBOL_INFO *)aSymBuffer;
	aSymbol->SizeOfStruct = sizeof(SYMBOL_INFO);
	aSymbol->MaxNameLen = 255;

	// StackWalk64 over the exception CONTEXT, so the stack is the one at the
	// crash site rather than the handler's.
	CONTEXT aContext = *theInfo->ContextRecord;
	STACKFRAME64 aFrame;
	memset(&aFrame, 0, sizeof(aFrame));
	aFrame.AddrPC.Offset = aContext.Rip;
	aFrame.AddrPC.Mode = AddrModeFlat;
	aFrame.AddrFrame.Offset = aContext.Rbp;
	aFrame.AddrFrame.Mode = AddrModeFlat;
	aFrame.AddrStack.Offset = aContext.Rsp;
	aFrame.AddrStack.Mode = AddrModeFlat;

	HANDLE aThread = GetCurrentThread();
	for (int i = 0; i < 62; i++)
	{
		if (!StackWalk64(IMAGE_FILE_MACHINE_AMD64, aProcess, aThread, &aFrame, &aContext,
						 nullptr, SymFunctionTableAccess64, SymGetModuleBase64, nullptr))
			break;
		if (aFrame.AddrPC.Offset == 0)
			break;

		DWORD64 anAddr = aFrame.AddrPC.Offset;
		fprintf(aLog, "  [%2d] 0x%016llX", i, (unsigned long long)anAddr);

		DWORD64 aDisp = 0;
		if (SymFromAddr(aProcess, anAddr, &aDisp, aSymbol))
			fprintf(aLog, "  %s", aSymbol->Name);

		IMAGEHLP_LINE64 aLine;
		aLine.SizeOfStruct = sizeof(IMAGEHLP_LINE64);
		DWORD aLineDisp = 0;
		if (SymGetLineFromAddr64(aProcess, anAddr, &aLineDisp, &aLine))
			fprintf(aLog, "  (%s:%lu)", aLine.FileName, aLine.LineNumber);

		fprintf(aLog, "\n");
	}

	SymCleanup(aProcess);
	if (aLog != stderr)
		fclose(aLog);

	return EXCEPTION_EXECUTE_HANDLER;
}
#endif

// PopLib/SDL3 uses a standard main() on every platform. The original WinMain
// and the dead WndProc (it returned 0 and was never registered) have no
// equivalent and were removed.
int main(int argc, char *argv[])
{
#ifdef _WIN32
	SetUnhandledExceptionFilter(WinFishCrashHandler);
#endif

	WinFishApp *aTheApp = new WinFishApp();

	aTheApp->Init();
	aTheApp->Start();
	aTheApp->Shutdown();

	delete aTheApp;
	return 0;
}
