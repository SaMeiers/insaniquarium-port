// Print a backtrace on a fatal signal. Desktop/handheld Linux only; on Windows
// SEHCatcher already covers this.
//
// There is no debugger on the target hardware. A segfault otherwise leaves a
// single line of shell output and nothing else -- no function, no file, no
// line.
//
// The shipped binary is stripped, so frames come out as
// "./Insaniquarium(+0x4a1b2c)". Translate the offset with the unstripped build:
//
//   aarch64-linux-gnu-addr2line -f -C -e port/bin/Insaniquarium 0x4a1b2c
//
// The executable is PIE, so if a frame shows an absolute address instead of an
// offset, subtract the load base printed below.
//
// Only async-signal-safe calls are used: backtrace_symbols_fd writes straight
// to the descriptor, unlike backtrace_symbols, which allocates -- and if the
// crash happened inside malloc, that deadlocks instead of reporting.

#if defined(__linux__) && !defined(__ANDROID__)

#include <csignal>
#include <cstring>
#include <cstdlib>
#include <execinfo.h>
#include <link.h>
#include <unistd.h>

namespace
{

void WriteStr(const char *theText)
{
	ssize_t ignored = write(STDERR_FILENO, theText, strlen(theText));
	(void)ignored;
}

void WriteHex(unsigned long theValue)
{
	char aBuf[2 + sizeof(unsigned long) * 2 + 1];
	char *p = aBuf + sizeof(aBuf) - 1;
	*p = '\0';
	do
	{
		*--p = "0123456789abcdef"[theValue & 0xF];
		theValue >>= 4;
	} while (theValue != 0);
	*--p = 'x';
	*--p = '0';
	WriteStr(p);
}

// The first object dl_iterate_phdr reports is always the executable.
int FirstObject(struct dl_phdr_info *theInfo, size_t, void *theOut)
{
	*static_cast<unsigned long *>(theOut) = (unsigned long)theInfo->dlpi_addr;
	return 1; // stop
}

void OnCrash(int theSignal)
{
	WriteStr("\n=== crash, signal ");
	WriteHex((unsigned long)theSignal);
	WriteStr(" ===\nload base: ");

	unsigned long aBase = 0;
	dl_iterate_phdr(FirstObject, &aBase);
	WriteHex(aBase);
	WriteStr("\n");

	void *aFrames[64];
	int aCount = backtrace(aFrames, 64);
	backtrace_symbols_fd(aFrames, aCount, STDERR_FILENO);
	WriteStr("=== end ===\n");

	// Restore the default handler and re-raise, so the process dies with the
	// right status instead of an exit(0) that would tell the launcher all went
	// well.
	signal(theSignal, SIG_DFL);
	raise(theSignal);
}

// A signal that is not fatal, but is worth knowing about. Something outside the
// game -- the firmware's button daemon, a hotkey helper -- can send these, and
// on a handheld there is no terminal to notice it on.
void OnSignal(int theSignal)
{
	WriteStr("[signal ");
	WriteHex((unsigned long)theSignal);
	WriteStr(" received]\n");
	signal(theSignal, SIG_DFL);
	raise(theSignal);
}

struct Installer
{
	Installer()
	{
		signal(SIGSEGV, OnCrash);
		signal(SIGBUS, OnCrash);
		signal(SIGFPE, OnCrash);
		signal(SIGILL, OnCrash);
		signal(SIGABRT, OnCrash);

		// SIGSTOP cannot be caught, but every other way of being suspended or
		// asked to quit can, and any of them would look like a freeze.
		signal(SIGTSTP, OnSignal);
		signal(SIGTTIN, OnSignal);
		signal(SIGTTOU, OnSignal);
		signal(SIGHUP, OnSignal);
		signal(SIGUSR2, OnSignal);

		// Not fatal: this one reports and returns.
	}
};

// Global constructor: installed before main, which is exactly when it is most
// needed -- the game's static objects are built there.
Installer gInstaller;

} // namespace

#endif
