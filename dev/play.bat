@echo off
rem Run the game straight from the source tree (no export). To play the exported build: build\TideAndLine.exe (run dev\export.bat first).
rem Uses the GUI executable (no console window). For print output use the *_console.exe instead.
setlocal
cd /d "%~dp0.."
set GODOT=tools\godot\Godot_v4.7-stable_win64.exe
if not exist "%GODOT%" (
  echo Godot not found. Run first: python dev\setup.py
  exit /b 1
)
"%GODOT%" --path godot --rendering-driver opengl3 %*
