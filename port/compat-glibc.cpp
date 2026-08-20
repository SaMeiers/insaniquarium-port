// Symbols a modern libstdc++ expects but an old glibc does not provide.
// Only built when cross-compiling to Linux (see CMakeLists.txt).
//
// The aarch64 PortMaster build targets glibc 2.31 (Debian bullseye) because the
// handhelds ship 2.30 and glibc is not backwards compatible. The compiler,
// however, is the host distro's, and its libstdc++ assumes a recent glibc.
// Linking it statically -- which is required, since the shared one directly
// references symbols that do not exist on the target -- leaves these dangling.
//
// The alternative is a toolchain built against glibc 2.31 (crosstool-NG). That
// is considerably more to set up and maintain than this file.
//
// This must be compiled into the executable, not into a static library: the
// linker only pulls an object out of an archive to resolve an undefined symbol,
// and a weak definition does not count, so it would never be extracted.

#if defined(__linux__) && !defined(__ANDROID__)

#include <cstdlib>
#include <cstddef>
#include <cstdint>

// getrandom() is glibc 2.25, so it is already present on the target.
#include <sys/random.h>

extern "C" {

// glibc 2.32. A char that is 1 while the process is single threaded; libstdc++
// reads it to skip atomics in local-static guards and shared_ptr counters.
// Defining it as 0 means "assume more than one thread", i.e. always take the
// atomic path: correct in every case, just without the shortcut. There is in
// fact more than one thread here, since SDL runs its own for audio.
//
// Everything is weak so that a future build against a glibc that provides these
// picks the real ones instead of colliding.
__attribute__((weak)) char __libc_single_threaded = 0;

// glibc 2.38. C23 allows a "0b" prefix in strtol and friends, and glibc handled
// the behaviour change with new symbols: the headers redirect strtoul to
// __isoc23_strtoul. We compile against the older sysroot headers, which do not
// redirect, but the toolchain's libstdc++.a was built against the new ones.
//
// Delegating to the classic versions is correct in practice: the only
// difference is the "0b" prefix, and libstdc++ uses these to parse decimal
// environment variables (GLIBCXX_TUNABLES).
__attribute__((weak)) long __isoc23_strtol(const char *s, char **end, int base)
{
	return std::strtol(s, end, base);
}
__attribute__((weak)) unsigned long __isoc23_strtoul(const char *s, char **end, int base)
{
	return std::strtoul(s, end, base);
}
__attribute__((weak)) long long __isoc23_strtoll(const char *s, char **end, int base)
{
	return std::strtoll(s, end, base);
}
__attribute__((weak)) unsigned long long __isoc23_strtoull(const char *s, char **end, int base)
{
	return std::strtoull(s, end, base);
}

// glibc 2.36. GCC 13+ implements std::random_device with these, and something
// in the dependency graph pulls std::random_device in, so libstdc++.a
// references them even though no game code does.
//
// arc4random is specified as never-failing cryptographic randomness.
// getrandom() with no flags reads the same kernel CSPRNG as /dev/urandom and
// can only come up short if interrupted, hence the loop.
__attribute__((weak)) void arc4random_buf(void *buf, size_t n)
{
	unsigned char *p = static_cast<unsigned char *>(buf);
	while (n > 0)
	{
		ssize_t got = getrandom(p, n, 0);
		if (got < 0)
			continue; // EINTR, or the pool is not seeded yet; retry
		p += got;
		n -= static_cast<size_t>(got);
	}
}

__attribute__((weak)) uint32_t arc4random(void)
{
	uint32_t v;
	arc4random_buf(&v, sizeof v);
	return v;
}
}

#endif
