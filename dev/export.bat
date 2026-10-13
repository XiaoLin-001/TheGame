@echo off
rem 匯出 Windows exe 到 build\TideAndLine.exe（CLAUDE.md「每批工作的收尾」第 5 步）。
rem 匯出完在 exe 上再驗一次：
rem   set TL_CLICKTEST=1& set TL_PANEL=title& set TL_MUTE=1& build\TideAndLine.exe --rendering-driver opengl3
setlocal
cd /d "%~dp0.."
set GODOT=tools\godot\Godot_v4.7-stable_win64_console.exe
if not exist "%GODOT%" (
  echo 找不到 Godot。先跑：python dev\setup.py
  exit /b 1
)
if not exist build mkdir build
"%GODOT%" --headless --path godot --import || exit /b 1
"%GODOT%" --headless --path godot --export-release "Windows Desktop" || exit /b 1
echo.
echo 已匯出：build\TideAndLine.exe
