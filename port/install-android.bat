@echo off
REM Install the APK on a connected device, launch it and show the log.
REM
REM Before running: enable USB debugging on the phone
REM (Settings > Developer options) and accept the authorisation prompt.
setlocal
set ADB=C:\Dev\Android\Sdk\platform-tools\adb.exe
set APK=%~dp0android\app\build\outputs\apk\debug\app-debug.apk

"%ADB%" devices
echo.

if not exist "%APK%" (
    echo No existe el APK. Compilalo primero con build-android.bat
    exit /b 1
)

echo Instalando...
"%ADB%" install -r "%APK%"
if errorlevel 1 exit /b 1

echo.
echo Lanzando...
"%ADB%" shell am start -n org.winfish.insaniquarium/.InsaniquariumActivity
if errorlevel 1 exit /b 1

echo.
echo === log (Ctrl+C para salir) ===
REM SDL_Log comes out under the SDL tag; native errors under DEBUG/AndroidRuntime.
"%ADB%" logcat -c
"%ADB%" logcat SDL:V DEBUG:V AndroidRuntime:E libc:V *:S
