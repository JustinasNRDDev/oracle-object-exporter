@echo off
setlocal

set "PS_SCRIPT=%~dp0run_export_task.ps1"
if not exist "%PS_SCRIPT%" (
    echo Klaida: nerastas PowerShell skriptas "%PS_SCRIPT%".
    exit /b 1
)

if /I "%~1"=="-h" goto usage
if /I "%~1"=="--help" goto usage

if /I "%~1"=="-TaskName" goto passthrough_named

if "%~1"=="" goto usage
if "%~2"=="" goto usage

set "TASK_NAME=%~1"
set "ENV_NAME=%~2"
set "SCHEMA_NAME="
set "DRYRUN_ARG="

if not "%~3"=="" (
    if /I "%~3"=="--dry-run" (
        set "DRYRUN_ARG=-DryRun"
    ) else (
        set "SCHEMA_NAME=%~3"
    )
)

if /I "%~4"=="--dry-run" set "DRYRUN_ARG=-DryRun"
if /I "%~5"=="--dry-run" set "DRYRUN_ARG=-DryRun"

if defined SCHEMA_NAME (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -TaskName "%TASK_NAME%" -EnvironmentName "%ENV_NAME%" -SchemaName "%SCHEMA_NAME%" %DRYRUN_ARG%
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -TaskName "%TASK_NAME%" -EnvironmentName "%ENV_NAME%" %DRYRUN_ARG%
)

exit /b %errorlevel%

:passthrough_named
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" %*
exit /b %errorlevel%

:usage
echo.
echo Usage:
echo   %~nx0 TASK ENV [SCHEMA] [--dry-run]
echo   %~nx0 -TaskName TASK -EnvironmentName ENV [-SchemaName SCHEMA] [-ConfigPath path] [-DryRun]
echo.
echo Examples:
echo   %~nx0 TASK_123 DEV
echo   %~nx0 TASK_123 DEV APPUSER19
echo   %~nx0 TASK_123 DEV --dry-run
echo   %~nx0 TASK_123 DEV APPUSER19 --dry-run
echo   %~nx0 -TaskName TASK_123 -EnvironmentName DEV -SchemaName APPUSER19 -DryRun
echo.
exit /b 1
