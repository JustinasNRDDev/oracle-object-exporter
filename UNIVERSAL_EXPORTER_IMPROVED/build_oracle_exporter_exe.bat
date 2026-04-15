@echo off
setlocal

where python >nul 2>nul
if %errorlevel% neq 0 (
    echo Python nerastas PATH. Instaliuokite Python 3.10+ ir bandykite dar karta.
    exit /b 1
)

python -m pip show pyinstaller >nul 2>nul
if errorlevel 1 (
    echo Diegiamas PyInstaller...
    python -m pip install -r requirements-build.txt
    if errorlevel 1 (
        echo Nepavyko idiegti build priklausomybiu.
        exit /b 1
    )
)

python -m PyInstaller --onefile --name oracle_exporter --clean run_export.py
if %errorlevel% neq 0 (
    echo .exe surinkimas nepavyko.
    exit /b 1
)

copy /Y dist\oracle_exporter.exe . >nul
if %errorlevel% neq 0 (
    echo Nepavyko nukopijuoti oracle_exporter.exe i projekto kataloga.
    exit /b 1
)

echo Sukurta: oracle_exporter.exe
echo Originalas: dist\oracle_exporter.exe
exit /b 0
