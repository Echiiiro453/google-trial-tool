@echo off
chcp 65001 >nul
cd /d "%~dp0"

echo ============================================
echo   Google One / AI Trial Tool
echo ============================================
echo   [1] Portugues (Brasil)
echo   [2] English
echo   [3] 简体中文 (Chinese)
echo.
set "LANG_CHOICE="
set /p LANG_CHOICE="Idioma / Language / 语言 (1-3, default 1): "

set "UI_LANG=pt"
if "%LANG_CHOICE%"=="2" set "UI_LANG=en"
if "%LANG_CHOICE%"=="3" set "UI_LANG=zh"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0auto-trial.ps1" --menu --lang %UI_LANG%
if errorlevel 1 (
    echo.
    pause
)
