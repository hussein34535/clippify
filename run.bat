@echo off
title ClipAI Studio Starter
echo =========================================
echo Starting ClipAI Studio...
echo =========================================

echo Starting FastAPI Backend Server...
start "ClipAI Backend" cmd /c "python api.py"

echo Starting Flutter Desktop Application...
cd flutter_client
start "ClipAI Frontend" cmd /c "flutter run -d windows"

echo =========================================
echo ClipAI Studio is running!
echo Backend: http://127.0.0.1:8000
echo Frontend: Flutter Desktop
echo =========================================
pause
