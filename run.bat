@echo off
title ClipAI Studio Starter
echo =========================================
echo 🎬 Starting ClipAI Studio...
echo =========================================

echo 🚀 Starting FastAPI Backend Server...
start "ClipAI Backend" cmd /c "python api.py"

echo 💻 Starting Tauri Frontend Application...
cd web
start "ClipAI Frontend" cmd /c "npm run dev"

echo =========================================
echo 🎉 ClipAI Studio is running!
echo Backend: http://127.0.0.1:8000
echo Frontend: http://localhost:5174
echo =========================================
pause
