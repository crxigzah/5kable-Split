@echo off
title 5kable Split - build
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1"
if errorlevel 1 (
    echo.
    echo Build failed - see the error above.
    pause
    exit /b 1
)
start "" "%~dp0dist"
pause
