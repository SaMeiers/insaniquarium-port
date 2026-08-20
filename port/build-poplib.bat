@echo off
REM Compila PopLib + demos en Release x64.
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" x64 >nul
if errorlevel 1 exit /b 1
cd /d "%~dp0..\poplib"
cmake --build build --config Release --parallel
exit /b %errorlevel%
