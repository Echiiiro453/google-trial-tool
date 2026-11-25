@echo off
chcp 65001 >nul
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0auto-trial.ps1" --menu
if errorlevel 1 (
    echo.
    pause
)
