# Cross-compile to Linux aarch64 against a Debian bullseye sysroot.
#
# The sysroot matters as much as the compiler. ArkOS on RK3326 reports glibc
# 2.30, and linking against a newer glibc produces a binary that runs fine on
# the build machine and refuses to start on the handheld.
#
# Bullseye ships 2.31, just above 2.30, and that is fine: glibc symbols are
# versioned by the release that introduced them, so what constrains the result
# is which symbols get used, not the sysroot version. build-linux-arm64.sh
# checks the finished binary.
#
# Going older is not an option: with buster (2.28) the compiler's own libstdc++
# headers fail to build, because they use pthread_cond_clockwait, which is 2.30.
#
# Build the sysroot with mk-sysroot-bullseye.sh.

set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

if(NOT WINFISH_SYSROOT)
	set(WINFISH_SYSROOT "$ENV{HOME}/sysroot-bullseye-winfish")
endif()

# CMake re-includes this file inside every try_compile, where the project cache
# does not exist yet. Without this, WINFISH_SYSROOT arrives empty exactly while
# CMake is testing the compiler, and the reported error is
# "CMAKE_CXX_COMPILER not set", which points nowhere near the cause.
list(APPEND CMAKE_TRY_COMPILE_PLATFORM_VARIABLES WINFISH_SYSROOT)

if(NOT EXISTS "${WINFISH_SYSROOT}/usr/include")
	message(FATAL_ERROR "'${WINFISH_SYSROOT}' is not a sysroot: no usr/include")
endif()

set(CMAKE_C_COMPILER   aarch64-linux-gnu-gcc)
set(CMAKE_CXX_COMPILER aarch64-linux-gnu-g++)
set(CMAKE_SYSROOT "${WINFISH_SYSROOT}")

# ------------------------------------------------------------------- headers
#
# The libc headers must come from the sysroot too, and --sysroot alone does not
# achieve that: the distro's cross gcc puts /usr/aarch64-linux-gnu/include ahead
# of the sysroot, which is its own glibc.
#
# This does not fail loudly. glibc 2.38 redirects strtoul to __isoc23_strtoul
# for C23, so the build emits calls to a function the target's 2.31 does not
# have, and it only surfaces at link time as "undefined reference to
# __isoc23_strtoul".
#
# GCC has no flag to drop a single directory, so -nostdinc turns them all off
# and the correct ones go back: the C++ and compiler-internal ones (those are
# its own and are fine) plus the sysroot's. The list is queried from the
# compiler so no gcc version ends up hardcoded in a path.
function(winfish_include_dirs lang out_var)
	execute_process(
		COMMAND ${CMAKE_CXX_COMPILER} --sysroot=${WINFISH_SYSROOT} -x ${lang} -E -v /dev/null
		ERROR_VARIABLE raw OUTPUT_QUIET ERROR_STRIP_TRAILING_WHITESPACE)
	string(REGEX MATCH "#include <\\.\\.\\.> search starts here:(.*)End of search list\\."
	       _ "${raw}")
	string(REPLACE "\n" ";" lines "${CMAKE_MATCH_1}")
	set(keep "")
	foreach(line IN LISTS lines)
		string(STRIP "${line}" dir)
		if(NOT dir OR NOT IS_DIRECTORY "${dir}")
			continue()
		endif()
		# Normalise before classifying. GCC lists the toolchain's glibc as
		#   /usr/lib/gcc-cross/aarch64-linux-gnu/15/../../../../aarch64-linux-gnu/include
		# which resolves to /usr/aarch64-linux-gnu/include but, as text, contains
		# "/lib/gcc-cross/". Matching the unresolved path would keep exactly the
		# directory this is meant to drop.
		get_filename_component(dir "${dir}" REALPATH)

		if(dir MATCHES "/c\\+\\+/" OR dir MATCHES "/lib/gcc-cross/" OR dir MATCHES "/lib/gcc/")
			list(APPEND keep "-isystem" "${dir}")
		endif()
	endforeach()
	list(APPEND keep "-isystem" "${WINFISH_SYSROOT}/usr/include/aarch64-linux-gnu"
	                 "-isystem" "${WINFISH_SYSROOT}/usr/include")
	list(JOIN keep " " joined)
	set(${out_var} "-nostdinc ${joined}" PARENT_SCOPE)
endfunction()

winfish_include_dirs(c++ WINFISH_CXX_INCLUDES)
winfish_include_dirs(c   WINFISH_C_INCLUDES)
set(CMAKE_CXX_FLAGS_INIT "${WINFISH_CXX_INCLUDES}")
set(CMAKE_C_FLAGS_INIT   "${WINFISH_C_INCLUDES}")

# ------------------------------------------------------------------- lookups
#
# Headers and libraries from the sysroot only, programs from the host only.
#
# NEVER for PROGRAM is required: the sysroot contains an aarch64 pkg-config
# binary, and if CMake finds it first it tries to run it on x86_64 and fails
# with 'Syntax error: "(" unexpected' -- the shell trying to interpret an ELF.
set(CMAKE_FIND_ROOT_PATH "${WINFISH_SYSROOT}")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# Debian packages put libraries in per-triplet subdirectories; without this the
# linker cannot find libX11, libasound and so on.
set(CMAKE_LIBRARY_ARCHITECTURE aarch64-linux-gnu)

# ------------------------------------------------------------------- linking
#
# The -L flags are not optional, and they are the main trap here.
#
# --sysroot does not cover glibc. The distro's cross gcc carries its own copy in
# /usr/aarch64-linux-gnu/lib, an absolute host path and therefore outside the
# sysroot; its libc.so is an ld script with absolute paths that are not prefixed
# either. The result is libpthread.so.0 from the sysroot (2.31) and libc.so.6
# from the toolchain.
#
# That shows up in the worst possible way: a list of
# "undefined reference to `__libc_longjmp@GLIBC_PRIVATE'", which looks like a
# broken glibc. It is not -- it is two different glibcs in one link, and
# GLIBC_PRIVATE symbols only match within the same version.
#
# The dangerous case is when it does not fail: a program that never touches
# pthread links happily against the toolchain's glibc, and the binary requests
# symbols the target does not have. Without these -L flags the "glibc 2.31"
# target is silently lost. To verify:
#
#   aarch64-linux-gnu-g++ ... -Wl,-t   # must show <sysroot>/.../libc.so.6
#
# -L is searched before the compiler's own directories, so listing the sysroot
# first is enough.
set(CMAKE_EXE_LINKER_FLAGS_INIT
    "-L${WINFISH_SYSROOT}/usr/lib/aarch64-linux-gnu -L${WINFISH_SYSROOT}/lib/aarch64-linux-gnu")

# -B matters even more than -L, though it does not look like it.
#
# The startup files (Scrt1.o, crti.o, crtn.o) are not found through -L: the gcc
# driver keeps its own list for those, and its own wins. -B prepends to that
# list. The trailing slash is required.
#
# Why it matters: since glibc 2.34, Scrt1.o passes NULL to __libc_start_main
# instead of __libc_csu_init, because from that release the loader walks
# .init_array itself. An older loader does not -- it expects to be handed the
# pointer.
#
# So with the new toolchain's Scrt1.o on a 2.30 system the program starts,
# reaches main and appears to work, but no static constructor ever runs, with no
# error of any kind. Here that would be fatal and silent, since Res.cpp's
# resource tables and PopLib's registries are built that way.
#
# Verified on the finished binary:
#   aarch64-linux-gnu-nm Insaniquarium | grep __libc_csu_init
string(APPEND CMAKE_EXE_LINKER_FLAGS_INIT " -B${WINFISH_SYSROOT}/usr/lib/aarch64-linux-gnu/")

# When the linker takes a shared library from the sysroot it must be able to
# open that library's own DT_NEEDED entries to know which symbols are resolved.
# That is what -rpath-link provides.
string(APPEND CMAKE_EXE_LINKER_FLAGS_INIT
       " -Wl,-rpath-link,${WINFISH_SYSROOT}/lib:${WINFISH_SYSROOT}/lib/aarch64-linux-gnu:${WINFISH_SYSROOT}/usr/lib/aarch64-linux-gnu")

# -static-libstdc++ lives in the game's CMakeLists, next to the compat shim it
# depends on; separately they are useless and the resulting error looks nothing
# like the cause.
#
# -static-libgcc is deliberately never used: libgcc_eh.a carries an exception
# unwinder built against a current glibc, which uses _dl_find_object (2.35).

set(CMAKE_SHARED_LINKER_FLAGS_INIT "${CMAKE_EXE_LINKER_FLAGS_INIT}")

set(ENV{PKG_CONFIG_DIR} "")
set(ENV{PKG_CONFIG_SYSROOT_DIR} "${WINFISH_SYSROOT}")
set(ENV{PKG_CONFIG_LIBDIR}
	"${WINFISH_SYSROOT}/usr/lib/pkgconfig:${WINFISH_SYSROOT}/usr/lib/aarch64-linux-gnu/pkgconfig:${WINFISH_SYSROOT}/usr/share/pkgconfig")

# PortMaster keeps a port's private libraries in libs.aarch64/ next to the
# binary.
set(CMAKE_INSTALL_RPATH "$ORIGIN/libs.aarch64")
set(CMAKE_BUILD_WITH_INSTALL_RPATH ON)
