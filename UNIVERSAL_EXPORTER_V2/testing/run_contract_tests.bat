@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
for %%I in ("%SCRIPT_DIR%\..") do set "PROJECT_ROOT=%%~fI"

set "EXPORTER_ENTRY=%PROJECT_ROOT%\oracle_exporter_task.bat"
if not "%~1"=="" set "EXPORTER_ENTRY=%~1"

if not exist "%EXPORTER_ENTRY%" (
    echo Klaida: nerastas exporter entrypoint "%EXPORTER_ENTRY%".
    exit /b 1
)

call :BuildTimestamp RUN_ID
set "TEST_ROOT=%SCRIPT_DIR%\runtime\%RUN_ID%"
set "TEST_OUTPUT_BASE=%PROJECT_ROOT%\EXPORTED_OBJECTS\_CONTRACT_TESTS_%RUN_ID%"
set "LOG_ROOT=%TEST_ROOT%\logs"

mkdir "%TEST_ROOT%" >nul 2>&1
mkdir "%LOG_ROOT%" >nul 2>&1
mkdir "%TEST_OUTPUT_BASE%" >nul 2>&1

set "CONN_FILE=%TEST_ROOT%\connDEV.conf"
> "%CONN_FILE%" echo dummy_user/dummy_password@DUMMY_DB

set "ANSWER_N=%TEST_ROOT%\answer_n.txt"
set "ANSWER_Y=%TEST_ROOT%\answer_y.txt"
> "%ANSWER_N%" echo N
> "%ANSWER_Y%" echo Y

set "CFG_DBA=%TEST_ROOT%\cfg_dba.yaml"
set "CFG_ALL=%TEST_ROOT%\cfg_all.yaml"
set "CFG_CUSTOM=%TEST_ROOT%\cfg_custom_ext.yaml"
set "CFG_MISSING_CONN=%TEST_ROOT%\cfg_missing_conn.yaml"

call :WriteConfig "%CFG_DBA%" "dba" "0" "0"
call :WriteConfig "%CFG_ALL%" "all" "0" "0"
call :WriteConfig "%CFG_CUSTOM%" "dba" "1" "0"
call :WriteConfig "%CFG_MISSING_CONN%" "dba" "0" "1"

set "TASK_VALID=%TEST_OUTPUT_BASE%\VALID_TASK"
set "TASK_ENV_MISSING=%TEST_OUTPUT_BASE%\ENV_MISSING"
set "TASK_BAD_ORDER=%TEST_OUTPUT_BASE%\BAD_ORDER"
set "TASK_AUTO_N=%TEST_OUTPUT_BASE%\AUTO_CREATE_N"
set "TASK_AUTO_Y=%TEST_OUTPUT_BASE%\AUTO_CREATE_Y"
set "TASK_FILE_Y=%TEST_OUTPUT_BASE%\AUTO_FILE_Y"

call :WriteTaskValid "%TASK_VALID%"
call :WriteTaskEnvMissing "%TASK_ENV_MISSING%"
call :WriteTaskBadOrder "%TASK_BAD_ORDER%"
mkdir "%TASK_FILE_Y%" >nul 2>&1

set /a TOTAL=0
set /a PASS=0
set /a FAIL=0

call :CaseStart "CT001_HELP"
call "%EXPORTER_ENTRY%" --help > "%CASE_OUT%" 2>&1
set "RC=%errorlevel%"
call :ExpectExit "%RC%" "1" "help turetu baigtis su kodu 1"
call :ExpectContains "%CASE_OUT%" "Usage:" "nerastas Usage tekstas"
call :CaseEnd

call :CaseStart "CT002_FOLDER_CREATE_DECLINE"
call "%EXPORTER_ENTRY%" "%TASK_AUTO_N%" DEV --dry-run -ConfigPath "%CFG_DBA%" < "%ANSWER_N%" > "%CASE_OUT%" 2>&1
set "RC=%errorlevel%"
call :ExpectExit "%RC%" "1" "turejo nutraukti vykdyma atsisakius kurti aplanka"
call :ExpectContains "%CASE_OUT%" "Task aplankas nebuvo sukurtas" "nera atsisakymo pranesimo"
if exist "%TASK_AUTO_N%\." (
    call :MarkFail "task aplankas neturejo buti sukurtas"
) else (
    call :MarkPass "task aplankas nesukurtas kaip tiketasi"
)
call :CaseEnd

call :CaseStart "CT003_FOLDER_CREATE_ACCEPT"
call "%EXPORTER_ENTRY%" "%TASK_AUTO_Y%" DEV --dry-run -ConfigPath "%CFG_DBA%" < "%ANSWER_Y%" > "%CASE_OUT%" 2>&1
set "RC=%errorlevel%"
call :ExpectExit "%RC%" "1" "sablono sukurimas turetu baigtis klaida del tuscio sablono"
call :ExpectContains "%CASE_OUT%" "Sukurtas task aplankas ir sablonas" "nera aplanko sukurimo patvirtinimo"
call :ExpectFileExists "%TASK_AUTO_Y%\objects.txt" "po patvirtinimo turi atsirasti objects.txt"
call :CaseEnd

call :CaseStart "CT004_OBJECTS_FILE_CREATE_ACCEPT"
call "%EXPORTER_ENTRY%" "%TASK_FILE_Y%" DEV --dry-run -ConfigPath "%CFG_DBA%" < "%ANSWER_Y%" > "%CASE_OUT%" 2>&1
set "RC=%errorlevel%"
call :ExpectExit "%RC%" "1" "sablono sukurimas turetu baigtis klaida del tuscio sablono"
call :ExpectContains "%CASE_OUT%" "Nerastas task failas" "nera missing objects failo pranesimo"
call :ExpectContains "%CASE_OUT%" "Sukurtas sablonas" "nera sablono sukurimo patvirtinimo"
call :ExpectFileExists "%TASK_FILE_Y%\objects.txt" "objects.txt failas nebuvo sukurtas"
call :CaseEnd

call :CaseStart "CT005_TEMPLATE_STRUCTURE"
call :ExpectContains "%TASK_AUTO_Y%\objects.txt" "# [DEV]" "sablone nerasta DEV sekcija"
call :ExpectContains "%TASK_AUTO_Y%\objects.txt" "# [TEST]" "sablone nerasta TEST sekcija"
call :ExpectContains "%TASK_AUTO_Y%\objects.txt" "# [PROD]" "sablone nerasta PROD sekcija"
call :ExpectContains "%TASK_AUTO_Y%\objects.txt" "# packages:" "sablone nerastas packages laukas"
call :ExpectContains "%TASK_AUTO_Y%\objects.txt" "# types:" "sablone nerastas types laukas"
call :CaseEnd

call :CaseStart "CT006_ENV_SECTION_MISSING"
call "%EXPORTER_ENTRY%" "%TASK_ENV_MISSING%" DEV --dry-run -ConfigPath "%CFG_DBA%" > "%CASE_OUT%" 2>&1
set "RC=%errorlevel%"
call :ExpectExit "%RC%" "1" "turejo grazinti klaida del nerastos ENV sekcijos"
call :ExpectContains "%CASE_OUT%" "nerasta aplinkos sekcija [DEV]" "nera ENV klaidos teksto"
call :CaseEnd

call :CaseStart "CT007_OBJECT_BEFORE_SCHEMA"
call "%EXPORTER_ENTRY%" "%TASK_BAD_ORDER%" DEV --dry-run -ConfigPath "%CFG_DBA%" > "%CASE_OUT%" 2>&1
set "RC=%errorlevel%"
call :ExpectExit "%RC%" "1" "turejo grazinti klaida del object eilutes pries schema"
call :ExpectContains "%CASE_OUT%" "objekto eilute pateikta pries schema" "nera tvarkos klaidos teksto"
call :CaseEnd

call :CaseStart "CT008_SCHEMA_FILTER_MISSING"
call "%EXPORTER_ENTRY%" "%TASK_VALID%" DEV UNKNOWN_SCHEMA --dry-run -ConfigPath "%CFG_DBA%" > "%CASE_OUT%" 2>&1
set "RC=%errorlevel%"
call :ExpectExit "%RC%" "1" "turejo grazinti klaida del nerastos schemos"
call :ExpectContains "%CASE_OUT%" "schema \"UNKNOWN_SCHEMA\" nerasta" "nera schema filtro klaidos"
call :CaseEnd

call :CaseStart "CT009_MISSING_CONNECTION_FILE"
call "%EXPORTER_ENTRY%" -TaskName "%TASK_VALID%" -EnvironmentName DEV -SchemaName APPSCHEMA -DryRun -ConfigPath "%CFG_MISSING_CONN%" > "%CASE_OUT%" 2>&1
set "RC=%errorlevel%"
call :ExpectExit "%RC%" "1" "turejo grazinti klaida del connection failo"
call :ExpectContains "%CASE_OUT%" "nerastas connection failas" "nera connection failo klaidos"
call :CaseEnd

call :CaseStart "CT010_DDL_SOURCE_DBA"
call "%EXPORTER_ENTRY%" -TaskName "%TASK_VALID%" -EnvironmentName DEV -SchemaName APPSCHEMA -DryRun -ConfigPath "%CFG_DBA%" > "%CASE_OUT%" 2>&1
set "RC=%errorlevel%"
call :ExpectExit "%RC%" "0" "dba dry-run turetu buti sekmingas"
call :ExpectContains "%CASE_OUT%" "generate_tbl_ddl_dba.sql" "nera dba table ddl skripto"
call :ExpectContains "%CASE_OUT%" "generate_view_ddl_dba.sql" "nera dba view ddl skripto"
call :ExpectContains "%CASE_OUT%" "VALID_TASK\objects.txt" "task failas turi buti skaitomas is EXPORTED_OBJECTS"
call :CaseEnd

call :CaseStart "CT011_DDL_SOURCE_ALL"
call "%EXPORTER_ENTRY%" -TaskName "%TASK_VALID%" -EnvironmentName DEV -SchemaName APPSCHEMA -DryRun -ConfigPath "%CFG_ALL%" > "%CASE_OUT%" 2>&1
set "RC=%errorlevel%"
call :ExpectExit "%RC%" "0" "all dry-run turetu buti sekmingas"
call :ExpectContains "%CASE_OUT%" "generate_tbl_ddl.sql" "nera all table ddl skripto"
call :ExpectContains "%CASE_OUT%" "generate_view_ddl.sql" "nera all view ddl skripto"
call :ExpectNotContains "%CASE_OUT%" "generate_tbl_ddl_dba.sql" "all neturi naudoti dba table ddl"
call :ExpectNotContains "%CASE_OUT%" "generate_view_ddl_dba.sql" "all neturi naudoti dba view ddl"
call :CaseEnd

call :CaseStart "CT012_CUSTOM_EXTENSIONS"
call "%EXPORTER_ENTRY%" -TaskName "%TASK_VALID%" -EnvironmentName DEV -SchemaName APPSCHEMA -DryRun -ConfigPath "%CFG_CUSTOM%" > "%CASE_OUT%" 2>&1
set "RC=%errorlevel%"
call :ExpectExit "%RC%" "0" "custom ext dry-run turetu buti sekmingas"
call :ExpectContains "%CASE_OUT%" "PkgX123" "nerasta custom package extension"
call :ExpectContains "%CASE_OUT%" "PrX123" "nerasta custom procedure extension"
call :ExpectContains "%CASE_OUT%" "FcX123" "nerasta custom function extension"
call :ExpectContains "%CASE_OUT%" "TbX123" "nerasta custom table extension"
call :ExpectContains "%CASE_OUT%" "VwX123" "nerasta custom view extension"
call :ExpectContains "%CASE_OUT%" "TyX123" "nerasta custom type extension"
call :CaseEnd

call :CaseStart "CT013_NAMED_ARGUMENTS"
call "%EXPORTER_ENTRY%" -TaskName "%TASK_VALID%" -EnvironmentName DEV -SchemaName APPSCHEMA -DryRun -ConfigPath "%CFG_CUSTOM%" > "%CASE_OUT%" 2>&1
set "RC=%errorlevel%"
call :ExpectExit "%RC%" "0" "named arguments dry-run turetu buti sekmingas"
call :ExpectContains "%CASE_OUT%" "MODE" "nera dry-run indikatoriaus"
call :CaseEnd

call :CaseStart "CT014_PATH_INDEPENDENCE"
pushd "%PROJECT_ROOT%\.." >nul
call "%EXPORTER_ENTRY%" "%TASK_VALID%" DEV APPSCHEMA --dry-run -ConfigPath "%CFG_DBA%" > "%CASE_OUT%" 2>&1
set "RC=%errorlevel%"
popd >nul
call :ExpectExit "%RC%" "0" "paleidimas is kito CWD turetu buti sekmingas"
call :ExpectContains "%CASE_OUT%" "RUN END" "nera sekmingo pabaigos iraso"
call :CaseEnd

echo.
echo ========================================
echo CONTRACT TEST SUMMARY
echo TOTAL: %TOTAL%
echo PASS : %PASS%
echo FAIL : %FAIL%
echo ROOT : %TEST_ROOT%
echo ========================================

if not "%FAIL%"=="0" exit /b 1
exit /b 0

:CaseStart
set /a TOTAL+=1
set "CASE_ID=%~1"
set "CASE_FAILED=0"
set "CASE_OUT=%LOG_ROOT%\%CASE_ID%.out.txt"
if exist "%CASE_OUT%" del /q "%CASE_OUT%" >nul 2>&1

echo.
echo [CASE] %CASE_ID%
exit /b 0

:CaseEnd
if "%CASE_FAILED%"=="0" (
    set /a PASS+=1
    echo [PASS] %CASE_ID%
) else (
    set /a FAIL+=1
    echo [FAIL] %CASE_ID%
)
exit /b 0

:MarkFail
set "CASE_FAILED=1"
echo   [FAIL] %~1
exit /b 0

:MarkPass
echo   [OK] %~1
exit /b 0

:ExpectExit
if "%~1"=="%~2" (
    call :MarkPass "exit code %~1"
) else (
    call :MarkFail "%~3 (gauta %~1, tiketasi %~2)"
)
exit /b 0

:ExpectFileExists
if exist "%~1" (
    call :MarkPass "%~1 egzistuoja"
) else (
    call :MarkFail "%~2"
)
exit /b 0

:ExpectContains
if not exist "%~1" (
    call :MarkFail "failas nerastas: %~1"
    exit /b 0
)

findstr /l /c:"%~2" "%~1" >nul 2>&1
if errorlevel 1 (
    call :MarkFail "%~3"
) else (
    call :MarkPass "rasta: %~2"
)
exit /b 0

:ExpectNotContains
if not exist "%~1" (
    call :MarkFail "failas nerastas: %~1"
    exit /b 0
)

findstr /l /c:"%~2" "%~1" >nul 2>&1
if errorlevel 1 (
    call :MarkPass "nera: %~2"
) else (
    call :MarkFail "%~3"
)
exit /b 0

:WriteConfig
setlocal EnableDelayedExpansion
set "WC_CFG_PATH=%~1"
set "WC_DDL=%~2"
set "WC_CUSTOM_EXT=%~3"
set "WC_MISSING_CONN=%~4"

if "!WC_MISSING_CONN!"=="1" (
    set "WC_CONN_FILE=%TEST_ROOT%\missing_conn.conf"
) else (
    set "WC_CONN_FILE=%CONN_FILE%"
)

(
echo version: 1
echo.
echo defaults:
echo   sqlplus_executable: sqlplus
echo   nls_lang: LITHUANIAN_LITHUANIA.UTF8
echo   ddl_source: !WC_DDL!
echo   export_extensions:
if "!WC_CUSTOM_EXT!"=="1" (
    echo     packages: PkgX123
    echo     procedures: PrX123
    echo     functions: FcX123
    echo     tables: TbX123
    echo     views: VwX123
    echo     types: TyX123
) else (
    echo     packages: pck
    echo     procedures: prc
    echo     functions: fnc
    echo     tables: sql
    echo     views: sql
    echo     types: typ
)
echo.
echo environments:
echo   DEV:
echo     connection_file: "!WC_CONN_FILE!"
echo     ddl_source: !WC_DDL!
echo     nls_lang: Lithuanian_lithuania.utf8
) > "!WC_CFG_PATH!"

endlocal
exit /b 0

:WriteTaskValid
set "TASK_DIR=%~1"
mkdir "%TASK_DIR%" >nul 2>&1
(
echo [DEV]
echo schema:APPSCHEMA
echo packages: PKG_ONE
echo procedures: PR_ONE
echo functions: FN_ONE
echo tables: TBL_ONE
echo views: VW_ONE
echo types: TP_ONE
) > "%TASK_DIR%\objects.txt"
exit /b 0

:WriteTaskEnvMissing
set "TASK_DIR=%~1"
mkdir "%TASK_DIR%" >nul 2>&1
(
echo [TEST]
echo schema:APPSCHEMA
echo packages: PKG_ONE
) > "%TASK_DIR%\objects.txt"
exit /b 0

:WriteTaskBadOrder
set "TASK_DIR=%~1"
mkdir "%TASK_DIR%" >nul 2>&1
(
echo [DEV]
echo packages: PKG_ONE
echo schema:APPSCHEMA
) > "%TASK_DIR%\objects.txt"
exit /b 0

:BuildTimestamp
set "LOCAL_DT="
for /f "tokens=2 delims==" %%I in ('wmic os get LocalDateTime /value 2^>nul ^| find "="') do if not defined LOCAL_DT set "LOCAL_DT=%%I"

if defined LOCAL_DT (
    set "%~1=%LOCAL_DT:~0,8%T%LOCAL_DT:~8,6%"
    exit /b 0
)

set "D=%DATE:~0,4%%DATE:~5,2%%DATE:~8,2%"
set "HOUR=%TIME:~0,2%"
if "%HOUR:~0,1%"==" " set "HOUR=0%HOUR:~1,1%"
set "MINUTE=%TIME:~3,2%"
set "SECOND=%TIME:~6,2%"
set "%~1=%D%T%HOUR%%MINUTE%%SECOND%"
exit /b 0