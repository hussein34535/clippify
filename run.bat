@echo off
chcp 65001 >nul
title Clippify Studio
setlocal
cd /d "%~dp0"

rem ============================================================
rem  Clippify Studio — one-click launcher
rem  كل المنطق داخل run_clippify.py: اكتشاف بايثون المشروع،
rem  تشغيل الباك إند (api.py)، ثم واجهة Flutter Desktop.
rem  تعمل بأي بايثون متاح — حتى embedded (لا يحتاج fastapi).
rem ============================================================

set "PY=python"
python -c "print(1)" >nul 2>nul
if errorlevel 1 set "PY=py -3"

%PY% run_clippify.py %*
set "EXITCODE=%errorlevel%"

if not "%EXITCODE%"=="0" (
    echo.
    echo [!] Clippify exited with code %EXITCODE%.
    echo     - لو بايثون غير مثبت: ثبت Python 3.10+ أو اضبط CLIPPIFY_PYTHON.
    echo     - لو المتطلبات ناقصة: pip install -r requirements.txt
    echo     - للفحص بدون تشغيل: python run_clippify.py --dry-run
    pause
)
exit /b %EXITCODE%
