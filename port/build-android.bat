@echo off
REM Build the Android APK (arm64-v8a).
REM La primera corrida baja Gradle 8.12 (~130 MB) y compila SDL, curl, OpenAL,
REM vorbis and zlib for ARM, so it takes a while.
cd /d "%~dp0android"

REM Gradle's asset merger keeps incremental state keyed on file names. When an
REM asset changes case (which is exactly what verify-assets.py --fix-case does),
REM the old and new state collide on a case-insensitive filesystem and the build
REM fails with "Duplicate resources". Clearing that cache is cheap.
if exist "app\build\intermediates\merged_assets"    rmdir /s /q "app\build\intermediates\merged_assets"
if exist "app\build\intermediates\compressed_assets" rmdir /s /q "app\build\intermediates\compressed_assets"
if exist "app\build\intermediates\assets"            rmdir /s /q "app\build\intermediates\assets"
if exist "app\build\intermediates\incremental"       rmdir /s /q "app\build\intermediates\incremental"

call "%~dp0android\gradlew.bat" assembleDebug --no-daemon
exit /b %errorlevel%
