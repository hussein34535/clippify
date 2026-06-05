@echo off
chcp 65001 >nul
title ClipAI Studio Launcher
color 0A

echo.
echo ===============================================
echo       ClipAI Studio - Desktop App Launcher
echo ===============================================
echo.

:: Check Python
echo [1/3] Checking Python...
python --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python not found! Install Python 3.10+ first.
    pause
    exit /b 1
)
echo    OK
echo.

:: Check Node
echo [2/3] Checking Node.js...
node --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Node.js not found! Install Node.js 18+ first.
    pause
    exit /b 1
)
echo    OK
echo.

:: Start Backend
echo [3/3] Starting Backend on port 8000...
cd /d "%~dp0"
start "ClipAI Backend" /min python api.py
echo    OK
echo.

:: Wait for backend
echo Waiting for backend to be ready...
:WAIT_BACKEND
timeout /t 2 /nobreak >nul
curl -s http://localhost:8000/api/health >nul 2>&1
if errorlevel 1 goto WAIT_BACKEND
echo    Backend ready
echo.

:: Start Tauri Desktop
echo Starting ClipAI Desktop App...
echo.
cd /d "%~dp0web"
echo Building and launching... (first time takes 3-5 min)
echo.
npm run tauri:dev

pause
