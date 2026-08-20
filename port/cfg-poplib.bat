@echo off
REM Configure PopLib with MSVC x64. Output in poplib\build.
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" x64 >nul
if errorlevel 1 exit /b 1
cd /d "%~dp0..\poplib"
cmake -S . -B build -G "Visual Studio 17 2022" -A x64 -DBUILD_EXAMPLES=ON -DBUILD_TOOLS=OFF -DFEATURE_DISCORD_RPC=OFF
exit /b %errorlevel%
