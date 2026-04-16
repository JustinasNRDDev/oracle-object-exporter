@echo off
setlocal

set "BAT_SCRIPT=%~dp0scripts\run_export_task.bat"
if not exist "%BAT_SCRIPT%" (
    echo Klaida: nerastas batch skriptas "%BAT_SCRIPT%".
    exit /b 1
)

call "%BAT_SCRIPT%" %*
exit /b %errorlevel%
