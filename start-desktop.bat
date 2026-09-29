@echo off
rem ============================================================
rem  Legacy entry point — تم توحيده على run_clippify.py
rem  This legacy launcher now delegates to run.bat / run_clippify.py
rem  (اكتشاف بايثون + باك إند + واجهة — منجم واحد للمنطق)
rem ============================================================
call "%~dp0run.bat" %*
