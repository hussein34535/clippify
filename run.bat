@echo off
title Clippify Studio Starter
echo =========================================
echo Starting Clippify Studio...
echo =========================================

echo Starting FastAPI Backend Server...
start "Clippify Backend" cmd /c "python api.py"

echo Starting Flutter Desktop Application...
cd flutter_client
start "Clippify Frontend" cmd /c "flutter run -d windows"

echo =========================================
echo Clippify Studio is running!
echo Backend: http://127.0.0.1:8000
echo Frontend: Flutter Desktop
echo =========================================
pause
