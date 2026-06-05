@echo off
chcp 65001 >nul
title ClipAI Studio (Web)
color 0B

echo.
echo ===============================================
echo       ClipAI Studio - Web Browser Mode
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

:: Start Backend
echo [2/3] Starting Backend on port 8000...
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

:: Start Vite
echo [3/3] Starting Vite dev server on port 5174...
cd /d "%~dp0web"
start "ClipAI Vite" /min npm run dev
echo    OK
echo.

:: Wait for Vite
timeout /t 5 /nobreak >nul
echo.
echo ===============================================
echo    ClipAI Studio is running!
echo.
echo    Open your browser to:  http://localhost:5174
echo.
echo    To stop: close this window or press Ctrl+C
echo ===============================================
echo.

:: Open browser
start http://localhost:5174

pause
