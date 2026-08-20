@echo off
REM Compile (/c only, no link) every .cpp in the port to get the full list
REM of errors quickly, without waiting for a full build.
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" x64 >nul
if errorlevel 1 exit /b 1

set P=%~dp0..\poplib
set OUT=%TEMP%\winfish-syntax
if not exist "%OUT%" mkdir "%OUT%"

cd /d "%~dp0winfish"

cl /nologo /c /EHsc /std:c++20 /permissive /MP /W0 /D_CRT_SECURE_NO_WARNINGS /DWIN32 /D_WINDOWS ^
  /I"%P%" ^
  /I"%P%\PopLib" ^
  /I"%P%\external\SDL\include" ^
  /I"%P%\external\SDL_ttf\include" ^
  /I"%P%\external\vorbis\include" ^
  /I"%P%\external\ogg\include" ^
  /I"%P%\external\openal" ^
  /I"%P%\external\misc" ^
  /I"%P%\external\stb_image" ^
  /I"%P%\external\curl\include" ^
  /I"." ^
  /Fo"%OUT%\\" ^
  *.cpp
exit /b %errorlevel%
