@echo off
rem Export the Windows exe to build\TideAndLine.exe (CLAUDE.md: end-of-batch step 5).
rem Then verify ON THE EXE (the export packs resources; the source tree being green does not prove the exe is complete):
rem   set TL_CLICKTEST=1& set TL_PANEL=title& set TL_MUTE=1& build\TideAndLine.exe --rendering-driver opengl3
setlocal
cd /d "%~dp0.."
set GODOT=tools\godot\Godot_v4.7-stable_win64_console.exe
if not exist "%GODOT%" (
  echo Godot not found. Run first: python dev\setup.py
  exit /b 1
)
if not exist build mkdir build
"%GODOT%" --headless --path godot --import || exit /b 1
"%GODOT%" --headless --path godot --export-release "Windows Desktop" || exit /b 1
echo.
echo Exported: build\TideAndLine.exe
