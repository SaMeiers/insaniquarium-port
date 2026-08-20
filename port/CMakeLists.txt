# Insaniquarium Deluxe (WinFish decomp) on PopLib.
# Replaces the original WinFish.sln (MSVC v143, x86, DirectDraw).
#
# One CMakeLists for desktop and Android. On Android the game is not an
# executable but a shared library named libmain.so, which is what SDLActivity
# loads; everything else is identical.
cmake_minimum_required(VERSION 3.26 FATAL_ERROR)

project(WinFishPort LANGUAGES C CXX ASM)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# PopLib as a subproject. No examples or tools: we only want the library.
set(BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(BUILD_TOOLS    OFF CACHE BOOL "" FORCE)
set(FEATURE_DISCORD_RPC OFF CACHE BOOL "" FORCE)
add_subdirectory(${CMAKE_CURRENT_LIST_DIR}/../poplib poplib_build)

# --- game sources ------------------------------------------------------------
file(GLOB WINFISH_SOURCES ${CMAKE_CURRENT_LIST_DIR}/winfish/*.cpp)
file(GLOB WINFISH_HEADERS ${CMAKE_CURRENT_LIST_DIR}/winfish/*.h)

# Beetlemuncher.cpp and ColorUtils.cpp exist on disk but the original
# WinFish.vcxproj does not build them. Excluded to keep the binary equivalent.
list(REMOVE_ITEM WINFISH_SOURCES
	${CMAKE_CURRENT_LIST_DIR}/winfish/Beetlemuncher.cpp
	${CMAKE_CURRENT_LIST_DIR}/winfish/ColorUtils.cpp
)

if(WIN32)
	list(APPEND WINFISH_SOURCES ${CMAKE_CURRENT_LIST_DIR}/winfish/Insaniquarium.rc)
endif()

# --- target ------------------------------------------------------------------
# SDLActivity calls System.loadLibrary("main"), so on Android the target must be
# named exactly "main" and be SHARED.
if(ANDROID)
	set(GAME_TARGET main)
	add_library(${GAME_TARGET} SHARED ${WINFISH_SOURCES} ${WINFISH_HEADERS})
else()
	set(GAME_TARGET WinFish)
	add_executable(${GAME_TARGET} ${WINFISH_SOURCES} ${WINFISH_HEADERS})
endif()

target_include_directories(${GAME_TARGET} PRIVATE
	${CMAKE_CURRENT_LIST_DIR}/winfish
)

# The original WinFish.vcxproj sets ConformanceMode=false, i.e. /permissive.
# Without it 24 sites fail: ambiguous conversions to ButtonListener (the class
# appears more than once in the dialog hierarchy) and temporaries bound to
# non-const references (Color&, Rect&). This is how the game originally built.
if(MSVC)
	target_compile_options(${GAME_TARGET} PRIVATE /permissive /wd4996)
	target_compile_definitions(${GAME_TARGET} PRIVATE _CRT_SECURE_NO_WARNINGS)
	# Symbols in Release too: the crash handler in Window.cpp uses them to print
	# a stack with file and line.
	target_compile_options(${GAME_TARGET} PRIVATE /Zi)
	target_link_options(${GAME_TARGET} PRIVATE /DEBUG /OPT:REF /OPT:ICF)
else()
	# Clang/GCC are stricter than MSVC's /permissive on the decomp's code; these
	# two cases are the ones MSVC accepts with /permissive.
	target_compile_options(${GAME_TARGET} PRIVATE
		-fpermissive
		-Wno-writable-strings
		-Wno-invalid-offsetof
	)
endif()

target_link_libraries(${GAME_TARGET} PRIVATE PopLib)

# --- cross-compiling against an old glibc (PortMaster / R36S) ----------------
if(CMAKE_CROSSCOMPILING AND CMAKE_SYSTEM_NAME STREQUAL "Linux")
	# The toolchain's SHARED libstdc++ references symbols the target does not
	# have (pthread_create@GLIBC_2.34, arc4random@GLIBC_2.36), so it goes into
	# the executable. glibc is NOT linked statically: that breaks dlopen, which
	# SDL uses to load its video and audio drivers.
	#
	# libgcc, on the other hand, is deliberately dynamic -- the opposite of the
	# obvious choice. Its static form (libgcc_eh.a) carries an exception
	# unwinder built against a current glibc, which uses _dl_find_object
	# (glibc 2.35). That one cannot be stubbed out: when the symbol exists the
	# unwinder has no fallback path, so a stub returning "not found" turns every
	# throw into std::terminate. Bullseye's shared libgcc does not use it, and
	# libgcc_s.so.1 is present on any Linux, so it need not be shipped.
	target_link_options(${GAME_TARGET} PRIVATE -static-libstdc++)

	# That static libstdc++ leaves references to symbols the target's glibc does
	# not provide. compat-glibc.cpp supplies them and explains each one. It is
	# added to the executable's sources rather than to a library; the reason is
	# in the file header.
	target_sources(${GAME_TARGET} PRIVATE ${CMAKE_CURRENT_LIST_DIR}/compat-glibc.cpp)

	# Without this a segfault on the handheld is one line of shell output and
	# nothing else. The file explains how to decode what it prints.
	target_sources(${GAME_TARGET} PRIVATE ${CMAKE_CURRENT_LIST_DIR}/crash-backtrace.cpp)

	# The static libstdc++ has pthread_once in its locale.o, and distro linkers
	# default to --as-needed: libpthread is dropped when first seen -- nothing
	# needs it yet -- and later, when libstdc++.a asks for it, the linker
	# reports "DSO missing from command line" naming a library that was on the
	# command line. Re-enabled straight after so nothing else gains needless
	# dependencies.
	target_link_libraries(${GAME_TARGET} PRIVATE
		"-Wl,--no-as-needed" "-lpthread" "-Wl,--as-needed")
endif()

if(NOT ANDROID)
	set_target_properties(${GAME_TARGET} PROPERTIES
		RUNTIME_OUTPUT_DIRECTORY         "${CMAKE_CURRENT_LIST_DIR}/bin"
		RUNTIME_OUTPUT_DIRECTORY_DEBUG   "${CMAKE_CURRENT_LIST_DIR}/bin"
		RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_CURRENT_LIST_DIR}/bin"
		RUNTIME_OUTPUT_NAME              Insaniquarium
	)

	# bass.dll next to the executable (needed for .mo3 music on Windows).
	# Not applicable on Android: Gradle packages the .so files itself.
	if(POPLIB_WITH_BASS)
		include(${CMAKE_CURRENT_LIST_DIR}/../poplib/cmake/CopyDLLPost.cmake)
		copy_dll_post(${GAME_TARGET} ${BASS_PATH})
	endif()
endif()
