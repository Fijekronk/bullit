@echo off
rem BULLIT launcher: проверить обновление и запустить игру.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0launcher.ps1"
if errorlevel 1 pause
