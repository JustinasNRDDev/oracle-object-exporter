@echo off
setlocal

where python >nul 2>nul
if %errorlevel% neq 0 (
    echo Python nerastas PATH. Instaliuokite Python 3.10+ ir bandykite dar karta.
    exit /b 1
)

python run_export.py %*
exit /b %errorlevel%
