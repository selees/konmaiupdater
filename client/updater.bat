@echo off
title KONMAI Game Auto Updater
chcp 65001 > nul
cd /d "%~dp0"

REM 1. Read ServerUrl from config.ini (default: http://localhost:8080)
set "SERVER_URL="
if exist config.ini (
    for /f "tokens=1,* delims==" %%A in ('findstr /i "^ServerUrl" config.ini 2^>nul') do (
        set "SERVER_URL=%%B"
    )
)
if not defined SERVER_URL set "SERVER_URL=http://localhost:8080"
for /f "tokens=* delims= " %%A in ("%SERVER_URL%") do set "SERVER_URL=%%A"
if "%SERVER_URL:~-1%"=="/" set "SERVER_URL=%SERVER_URL:~0,-1%"

REM 2. Check for latest client_updater.ps1 from server (silently skips if server is offline or timeout after 2s)
curl.exe -fsSL --connect-timeout 2 --max-time 4 -o "%~dp0updater.ps1.tmp" "%SERVER_URL%/client_updater.ps1" 2>nul
if errorlevel 1 (
    curl.exe -fsSL --connect-timeout 2 --max-time 4 -o "%~dp0updater.ps1.tmp" "%SERVER_URL%/updater.ps1" 2>nul
)
if %ERRORLEVEL% equ 0 if exist "%~dp0updater.ps1.tmp" (
    fc /b "%~dp0updater.ps1" "%~dp0updater.ps1.tmp" >nul 2>nul
    if errorlevel 1 (
        move /y "%~dp0updater.ps1.tmp" "%~dp0updater.ps1" >nul
        echo [Auto-Update] updater.ps1 updated to latest version from server.
    ) else (
        del /f "%~dp0updater.ps1.tmp" >nul 2>nul
    )
) else (
    if exist "%~dp0updater.ps1.tmp" del /f "%~dp0updater.ps1.tmp" >nul 2>nul
)

REM 3. Launch PowerShell updater
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0updater.ps1"
exit /b 0