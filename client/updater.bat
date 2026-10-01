@echo off
title KONMAI Game Auto Updater
chcp 65001 > nul
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0updater.ps1"
exit /b 0