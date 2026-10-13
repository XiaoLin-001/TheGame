@echo off
rem 直接從原始碼樹開遊戲（不經匯出）。要玩匯出版：build\TideAndLine.exe（先跑 dev\export.bat）。
rem 用 GUI 版執行檔（沒有黑色的 console 視窗）；要看 print 輸出請改用 *_console.exe。
setlocal
cd /d "%~dp0.."
set GODOT=tools\godot\Godot_v4.7-stable_win64.exe
if not exist "%GODOT%" (
  echo 找不到 Godot。先跑：python dev\setup.py
  exit /b 1
)
"%GODOT%" --path godot --rendering-driver opengl3 %*
