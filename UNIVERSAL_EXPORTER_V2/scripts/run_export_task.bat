@echo off
setlocal EnableExtensions EnableDelayedExpansion

call :ImportMissingRegistryEnvironment

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
for %%I in ("%SCRIPT_DIR%\..") do set "PROJECT_ROOT=%%~fI"

set "SCRIPTS_DIR=%PROJECT_ROOT%\scripts"
set "LOGS_DIR=%PROJECT_ROOT%\logs"
set "OUTPUT_BASE=%PROJECT_ROOT%\EXPORTED_OBJECTS"
set "DEFAULT_CONFIG=%PROJECT_ROOT%\config\exporter.yaml"

set "TASK_NAME="
set "ENV_NAME="
set "SCHEMA_NAME="
set "CONFIG_FILE=%DEFAULT_CONFIG%"
set "DRY_RUN=0"
set "PREFLIGHT_ONLY=0"

if /I "%~1"=="-h" goto usage
if /I "%~1"=="--help" goto usage
if "%~1"=="" goto usage

if /I "%~1"=="-TaskName" (
    call :ParseNamedArgs %*
) else (
    call :ParsePositionalArgs %*
)
if errorlevel 1 exit /b 1

if not defined TASK_NAME goto usage
if not defined ENV_NAME goto usage

call :ResolveTaskFile "%TASK_NAME%" TASK_FILE TASK_LABEL TASK_DIR
if errorlevel 1 exit /b 1

if not exist "%CONFIG_FILE%" (
    echo Klaida: nerastas config failas "%CONFIG_FILE%".
    exit /b 1
)

call :InitDefaults
call :LoadConfig "%CONFIG_FILE%" "%ENV_NAME%"
if errorlevel 1 exit /b 1

if "%TARGET_ENV_FOUND%"=="0" (
    echo Klaida: aplinka "%ENV_NAME%" nerasta config faile "%CONFIG_FILE%".
    exit /b 1
)

if defined ENV_EXT_PACKAGES set "EXT_PACKAGES=%ENV_EXT_PACKAGES%"
if defined ENV_EXT_PROCEDURES set "EXT_PROCEDURES=%ENV_EXT_PROCEDURES%"
if defined ENV_EXT_FUNCTIONS set "EXT_FUNCTIONS=%ENV_EXT_FUNCTIONS%"
if defined ENV_EXT_TYPES set "EXT_TYPES=%ENV_EXT_TYPES%"
if defined ENV_EXT_TABLES set "EXT_TABLES=%ENV_EXT_TABLES%"
if defined ENV_EXT_VIEWS set "EXT_VIEWS=%ENV_EXT_VIEWS%"

if defined ENV_DDL_SOURCE (
    set "DDL_SOURCE=%ENV_DDL_SOURCE%"
) else (
    set "DDL_SOURCE=%DEFAULT_DDL_SOURCE%"
)
if not defined DDL_SOURCE set "DDL_SOURCE=all"
if /I not "%DDL_SOURCE%"=="dba" set "DDL_SOURCE=all"

if defined TASK_NLS_LANG (
    set "NLS_LANG=%TASK_NLS_LANG%"
) else (
    if defined ENV_NLS_LANG (
        set "NLS_LANG=%ENV_NLS_LANG%"
    ) else (
        if defined DEFAULT_NLS_LANG set "NLS_LANG=%DEFAULT_NLS_LANG%"
    )
)

if defined ENV_CONNECTION_FILE (
    set "CONNECTION_FILE=%ENV_CONNECTION_FILE%"
) else (
    if defined DEFAULT_CONNECTION_FILE (
        set "CONNECTION_FILE=%DEFAULT_CONNECTION_FILE%"
    ) else (
        set "CONNECTION_FILE=%%ORACLE19_CONN%%\conn%ENV_NAME%.conf"
    )
)

call :ExpandEnvPath "!CONNECTION_FILE!" RESOLVED_CONNECTION_FILE
if not exist "%RESOLVED_CONNECTION_FILE%" (
    echo Klaida: nerastas connection failas "%RESOLVED_CONNECTION_FILE%".
    exit /b 1
)

set "CONNECTION_STRING="
set /p CONNECTION_STRING=<"%RESOLVED_CONNECTION_FILE%"
call :Trim "%CONNECTION_STRING%" CONNECTION_STRING
if not defined CONNECTION_STRING (
    echo Klaida: tuscias connection failas "%RESOLVED_CONNECTION_FILE%".
    exit /b 1
)

if not defined SQLPLUS_EXE set "SQLPLUS_EXE=sqlplus"

call :BuildTimestamp RUN_TIMESTAMP
if not exist "%LOGS_DIR%" mkdir "%LOGS_DIR%" >nul 2>&1
set "LOG_FILE=%LOGS_DIR%\bat_export_%RUN_TIMESTAMP%.log"

set /a SUMMARY_TOTAL=0
set /a SUMMARY_EXECUTED=0
set /a SUMMARY_SKIPPED=0

call :WriteLog "RUN START | task=%TASK_LABEL% env=%ENV_NAME% timestamp=%RUN_TIMESTAMP%"
call :WriteLog "CONFIG | %CONFIG_FILE%"
call :WriteLog "TASK FILE | %TASK_FILE%"
call :WriteLog "DDL SOURCE | %DDL_SOURCE%"
if "%DRY_RUN%"=="1" call :WriteLog "MODE | DRY-RUN"
if "%PREFLIGHT_ONLY%"=="1" call :WriteLog "MODE | PREFLIGHT"

if "%PREFLIGHT_ONLY%"=="1" (
    call :RunPreflight
    set "PROCESS_RC=!errorlevel!"
    if not "!PROCESS_RC!"=="0" (
        call :WriteLog "RUN END | mode=preflight status=failed"
        call :WriteLog "LOG FILE | %LOG_FILE%"
        exit /b !PROCESS_RC!
    )

    call :WriteLog "RUN END | mode=preflight status=ok"
    call :WriteLog "LOG FILE | %LOG_FILE%"
    echo Preflight patikra sekminga.
    exit /b 0
)

set "OUTPUT_ROOT=%TASK_DIR%\%ENV_NAME%\%RUN_TIMESTAMP%"
if not exist "%OUTPUT_ROOT%" mkdir "%OUTPUT_ROOT%" >nul 2>&1

pushd "%PROJECT_ROOT%" >nul
if errorlevel 1 (
    echo Klaida: nepavyko pereiti i projekto direktorija "%PROJECT_ROOT%".
    exit /b 1
)

call :ProcessTaskFile "%TASK_FILE%" "%ENV_NAME%" "%SCHEMA_NAME%"
set "PROCESS_RC=%errorlevel%"

popd >nul

if not "%PROCESS_RC%"=="0" exit /b %PROCESS_RC%

call :WriteLog "RUN END | total=%SUMMARY_TOTAL% executed=%SUMMARY_EXECUTED% skipped=%SUMMARY_SKIPPED%"
call :WriteLog "LOG FILE | %LOG_FILE%"
exit /b 0

:ImportMissingRegistryEnvironment
for /f "skip=2 tokens=1,2,*" %%A in ('reg query "HKCU\Environment" 2^>nul') do (
    if not "%%A"=="" (
        if /I not "%%A"=="Path" (
            if not defined %%A set "%%A=%%C"
        )
    )
)

for /f "skip=2 tokens=1,2,*" %%A in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" 2^>nul') do (
    if not "%%A"=="" (
        if /I not "%%A"=="Path" (
            if not defined %%A set "%%A=%%C"
        )
    )
)
exit /b 0

:ParsePositionalArgs
if "%~1"=="" exit /b 1
if "%~2"=="" exit /b 1

set "TASK_NAME=%~1"
set "ENV_NAME=%~2"
set "SCHEMA_NAME="
set "DRY_RUN=0"
set "PREFLIGHT_ONLY=0"

shift
shift

:ParsePositionalArgsLoop
if "%~1"=="" exit /b 0

if /I "%~1"=="--dry-run" (
    set "DRY_RUN=1"
    shift
    goto ParsePositionalArgsLoop
)

if /I "%~1"=="-DryRun" (
    set "DRY_RUN=1"
    shift
    goto ParsePositionalArgsLoop
)

if /I "%~1"=="--preflight" (
    set "PREFLIGHT_ONLY=1"
    shift
    goto ParsePositionalArgsLoop
)

if /I "%~1"=="-Preflight" (
    set "PREFLIGHT_ONLY=1"
    shift
    goto ParsePositionalArgsLoop
)

if /I "%~1"=="--check" (
    set "PREFLIGHT_ONLY=1"
    shift
    goto ParsePositionalArgsLoop
)

if /I "%~1"=="-ConfigPath" (
    if "%~2"=="" (
        echo Klaida: po -ConfigPath turi buti failo kelias.
        exit /b 1
    )
    set "CONFIG_FILE=%~2"
    shift
    shift
    goto ParsePositionalArgsLoop
)

if defined SCHEMA_NAME (
    echo Klaida: nepazintas arba perteklinis positional argumentas "%~1".
    exit /b 1
)

set "SCHEMA_NAME=%~1"
shift
goto ParsePositionalArgsLoop

:ParseNamedArgs
:ParseNamedArgsLoop
if "%~1"=="" exit /b 0

if /I "%~1"=="-TaskName" (
    if "%~2"=="" (
        echo Klaida: po -TaskName turi buti TASK reiksme.
        exit /b 1
    )
    set "TASK_NAME=%~2"
    shift
    shift
    goto ParseNamedArgsLoop
)

if /I "%~1"=="-EnvironmentName" (
    if "%~2"=="" (
        echo Klaida: po -EnvironmentName turi buti ENV reiksme.
        exit /b 1
    )
    set "ENV_NAME=%~2"
    shift
    shift
    goto ParseNamedArgsLoop
)

if /I "%~1"=="-SchemaName" (
    if "%~2"=="" (
        echo Klaida: po -SchemaName turi buti SCHEMA reiksme.
        exit /b 1
    )
    set "SCHEMA_NAME=%~2"
    shift
    shift
    goto ParseNamedArgsLoop
)

if /I "%~1"=="-ConfigPath" (
    if "%~2"=="" (
        echo Klaida: po -ConfigPath turi buti failo kelias.
        exit /b 1
    )
    set "CONFIG_FILE=%~2"
    shift
    shift
    goto ParseNamedArgsLoop
)

if /I "%~1"=="-DryRun" (
    set "DRY_RUN=1"
    shift
    goto ParseNamedArgsLoop
)

if /I "%~1"=="-Preflight" (
    set "PREFLIGHT_ONLY=1"
    shift
    goto ParseNamedArgsLoop
)

if /I "%~1"=="--dry-run" (
    set "DRY_RUN=1"
    shift
    goto ParseNamedArgsLoop
)

if /I "%~1"=="--preflight" (
    set "PREFLIGHT_ONLY=1"
    shift
    goto ParseNamedArgsLoop
)

if /I "%~1"=="--check" (
    set "PREFLIGHT_ONLY=1"
    shift
    goto ParseNamedArgsLoop
)

echo Klaida: nepazintas argumentas "%~1".
exit /b 1

:InitDefaults
set "SQLPLUS_EXE=sqlplus"
set "DEFAULT_NLS_LANG="
set "DEFAULT_DDL_SOURCE=all"
set "DEFAULT_CONNECTION_FILE="

set "EXT_PACKAGES=pck"
set "EXT_PROCEDURES=prc"
set "EXT_FUNCTIONS=fnc"
set "EXT_TYPES=typ"
set "EXT_TABLES=sql"
set "EXT_VIEWS=sql"

set "ENV_CONNECTION_FILE="
set "ENV_NLS_LANG="
set "ENV_DDL_SOURCE="
set "ENV_EXT_PACKAGES="
set "ENV_EXT_PROCEDURES="
set "ENV_EXT_FUNCTIONS="
set "ENV_EXT_TYPES="
set "ENV_EXT_TABLES="
set "ENV_EXT_VIEWS="

set "TARGET_ENV_FOUND=0"
set "TASK_NLS_LANG="
set "PREFLIGHT_VALIDATE_ONLY=0"

set "PREFLIGHT_REQUESTED_PACKAGES=0"
set "PREFLIGHT_REQUESTED_PROCEDURES=0"
set "PREFLIGHT_REQUESTED_FUNCTIONS=0"
set "PREFLIGHT_REQUESTED_TYPES=0"
set "PREFLIGHT_REQUESTED_TABLES=0"
set "PREFLIGHT_REQUESTED_VIEWS=0"

set "PREFLIGHT_PRIV_CREATE_SESSION=0"
set "PREFLIGHT_PRIV_SELECT_ANY_DICTIONARY=0"
set "PREFLIGHT_PRIV_DEBUG_ANY_PROCEDURE=0"
set "PREFLIGHT_ROLE_SELECT_CATALOG_ROLE=0"

set "PREFLIGHT_CAN_PACKAGES=0"
set "PREFLIGHT_CAN_PROCEDURES=0"
set "PREFLIGHT_CAN_FUNCTIONS=0"
set "PREFLIGHT_CAN_TYPES=0"
set "PREFLIGHT_CAN_TABLES=0"
set "PREFLIGHT_CAN_VIEWS=0"
exit /b 0

:LoadConfig
set "CFG_PATH=%~1"
set "TARGET_ENV=%~2"

set "SECTION="
set "CURRENT_ENV="
set "IN_DEFAULT_EXT=0"
set "IN_ENV_EXT=0"

for /f "usebackq delims=" %%L in ("%CFG_PATH%") do (
    set "CFG_LINE=%%L"
    call :ProcessConfigLine "%TARGET_ENV%"
)
exit /b 0

:ProcessConfigLine
set "TARGET_ENV=%~1"
set "RAW_LINE=!CFG_LINE!"
call :Trim "!RAW_LINE!" LINE_TRIM

if not defined LINE_TRIM exit /b 0
if "!LINE_TRIM:~0,1!"=="#" exit /b 0

if /I "!LINE_TRIM!"=="defaults:" (
    set "SECTION=defaults"
    set "CURRENT_ENV="
    set "IN_DEFAULT_EXT=0"
    set "IN_ENV_EXT=0"
    exit /b 0
)

if /I "!LINE_TRIM!"=="environments:" (
    set "SECTION=environments"
    set "CURRENT_ENV="
    set "IN_DEFAULT_EXT=0"
    set "IN_ENV_EXT=0"
    exit /b 0
)

if /I "!SECTION!"=="defaults" (
    if "!RAW_LINE:~0,2!"=="  " if not "!RAW_LINE:~2,1!"==" " (
        set "BODY=!RAW_LINE:~2!"
        call :ParseYamlKeyValue "!BODY!" CFG_KEY CFG_VAL
        if /I "!CFG_KEY!"=="export_extensions" (
            set "IN_DEFAULT_EXT=1"
        ) else (
            set "IN_DEFAULT_EXT=0"
            call :StripQuotes "!CFG_VAL!" CFG_VAL

            if /I "!CFG_KEY!"=="sqlplus_executable" if defined CFG_VAL set "SQLPLUS_EXE=!CFG_VAL!"
            if /I "!CFG_KEY!"=="nls_lang" set "DEFAULT_NLS_LANG=!CFG_VAL!"
            if /I "!CFG_KEY!"=="ddl_source" set "DEFAULT_DDL_SOURCE=!CFG_VAL!"
            if /I "!CFG_KEY!"=="connection_file" set "DEFAULT_CONNECTION_FILE=!CFG_VAL!"
        )
        exit /b 0
    )

    if "!IN_DEFAULT_EXT!"=="1" if "!RAW_LINE:~0,4!"=="    " if not "!RAW_LINE:~4,1!"==" " (
        set "BODY=!RAW_LINE:~4!"
        call :ParseYamlKeyValue "!BODY!" CFG_KEY CFG_VAL
        call :NormalizeStep "!CFG_KEY!" CFG_STEP
        call :NormalizeExtension "!CFG_VAL!" CFG_VAL
        if defined CFG_STEP if defined CFG_VAL call :SetExtensionValue "EXT" "!CFG_STEP!" "!CFG_VAL!"
        exit /b 0
    )

    exit /b 0
)

if /I "!SECTION!"=="environments" (
    if "!RAW_LINE:~0,2!"=="  " if not "!RAW_LINE:~2,1!"==" " (
        set "BODY=!RAW_LINE:~2!"
        call :Trim "!BODY!" BODY
        if "!BODY:~-1!"==":" (
            set "CURRENT_ENV=!BODY:~0,-1!"
            call :Trim "!CURRENT_ENV!" CURRENT_ENV
            set "IN_ENV_EXT=0"
            if /I "!CURRENT_ENV!"=="!TARGET_ENV!" set "TARGET_ENV_FOUND=1"
            exit /b 0
        )
    )

    if /I "!CURRENT_ENV!"=="!TARGET_ENV!" (
        if "!RAW_LINE:~0,4!"=="    " if not "!RAW_LINE:~4,1!"==" " (
            set "BODY=!RAW_LINE:~4!"
            call :ParseYamlKeyValue "!BODY!" CFG_KEY CFG_VAL

            if /I "!CFG_KEY!"=="export_extensions" (
                set "IN_ENV_EXT=1"
            ) else (
                set "IN_ENV_EXT=0"
                call :StripQuotes "!CFG_VAL!" CFG_VAL

                if /I "!CFG_KEY!"=="connection_file" set "ENV_CONNECTION_FILE=!CFG_VAL!"
                if /I "!CFG_KEY!"=="nls_lang" set "ENV_NLS_LANG=!CFG_VAL!"
                if /I "!CFG_KEY!"=="ddl_source" set "ENV_DDL_SOURCE=!CFG_VAL!"
            )
            exit /b 0
        )

        if "!IN_ENV_EXT!"=="1" if "!RAW_LINE:~0,6!"=="      " if not "!RAW_LINE:~6,1!"==" " (
            set "BODY=!RAW_LINE:~6!"
            call :ParseYamlKeyValue "!BODY!" CFG_KEY CFG_VAL
            call :NormalizeStep "!CFG_KEY!" CFG_STEP
            call :NormalizeExtension "!CFG_VAL!" CFG_VAL
            if defined CFG_STEP if defined CFG_VAL call :SetExtensionValue "ENV_EXT" "!CFG_STEP!" "!CFG_VAL!"
            exit /b 0
        )
    )
)

exit /b 0

:ResolveTaskFile
set "TASK_INPUT=%~1"
set "TASK_FILE_PATH="
set "TASK_LABEL_VALUE="
set "TASK_DIR_PATH="

call :ExpandEnvPath "!TASK_INPUT!" TASK_INPUT_EXPANDED
if not defined TASK_INPUT_EXPANDED set "TASK_INPUT_EXPANDED=%TASK_INPUT%"
call :StripQuotes "%TASK_INPUT_EXPANDED%" TASK_INPUT_EXPANDED
call :Trim "%TASK_INPUT_EXPANDED%" TASK_INPUT_EXPANDED

if not defined TASK_INPUT_EXPANDED (
    echo Klaida: nenurodytas TASK pavadinimas.
    exit /b 1
)

call :IsAbsolutePath "%TASK_INPUT_EXPANDED%" TASK_INPUT_IS_ABSOLUTE
if "%TASK_INPUT_IS_ABSOLUTE%"=="1" (
    set "TASK_DIR_PATH=%TASK_INPUT_EXPANDED%"
) else (
    set "TASK_DIR_PATH=%OUTPUT_BASE%\%TASK_INPUT_EXPANDED%"
)

for %%I in ("%TASK_DIR_PATH%") do set "TASK_DIR_PATH=%%~fI"
if "%TASK_DIR_PATH:~-1%"=="\" set "TASK_DIR_PATH=%TASK_DIR_PATH:~0,-1%"
set "TASK_FILE_PATH=%TASK_DIR_PATH%\objects.txt"

call :EnsureTaskFolderExists "%TASK_DIR_PATH%" "%TASK_FILE_PATH%"
if errorlevel 1 exit /b 1

if not exist "%TASK_FILE_PATH%" (
    call :EnsureTaskObjectsFile "%TASK_DIR_PATH%" "%TASK_FILE_PATH%"
    if errorlevel 1 exit /b 1
)

for %%I in ("%TASK_FILE_PATH%") do set "TASK_FILE_PATH=%%~fI"
for %%I in ("%TASK_DIR_PATH%") do set "TASK_LABEL_VALUE=%%~nI"

if not defined TASK_LABEL_VALUE (
    echo Klaida: nepavyko nustatyti task aplanko pavadinimo is "%TASK_DIR_PATH%".
    exit /b 1
)

set "%~2=%TASK_FILE_PATH%"
set "%~3=%TASK_LABEL_VALUE%"
if not "%~4"=="" set "%~4=%TASK_DIR_PATH%"
exit /b 0

:EnsureTaskFolderExists
set "TASK_DIR_TO_CHECK=%~1"
set "TASK_FILE_TO_CREATE=%~2"

if exist "%TASK_DIR_TO_CHECK%\." exit /b 0

echo.
echo Nerastas task aplankas "%TASK_DIR_TO_CHECK%".
set "CREATE_TASK_DIR_ANSWER="
set /p CREATE_TASK_DIR_ANSWER="Ar sukurti si aplanka su objects.txt failo sablonu? (Y/N): "

if /I not "%CREATE_TASK_DIR_ANSWER%"=="Y" if /I not "%CREATE_TASK_DIR_ANSWER%"=="YES" (
    echo Vykdymas nutrauktas. Task aplankas nebuvo sukurtas.
    exit /b 1
)

mkdir "%TASK_DIR_TO_CHECK%" >nul 2>&1
if errorlevel 1 (
    echo Klaida: nepavyko sukurti task aplanko "%TASK_DIR_TO_CHECK%".
    exit /b 1
)

call :CreateTaskTemplateOrWizard "%TASK_FILE_TO_CREATE%"
if errorlevel 1 exit /b 1

echo Sukurtas task aplankas ir sablonas: "%TASK_FILE_TO_CREATE%".
exit /b 0

:EnsureTaskObjectsFile
set "TASK_DIR_TO_CHECK=%~1"
set "TASK_FILE_TO_CREATE=%~2"

echo.
echo Nerastas task failas "%TASK_FILE_TO_CREATE%".
set "CREATE_TASK_FILE_ANSWER="
set /p CREATE_TASK_FILE_ANSWER="Ar sukurti objects.txt sablona siame aplanke? (Y/N): "

if /I not "%CREATE_TASK_FILE_ANSWER%"=="Y" if /I not "%CREATE_TASK_FILE_ANSWER%"=="YES" (
    echo Vykdymas nutrauktas. objects.txt failas nebuvo sukurtas.
    exit /b 1
)

if not exist "%TASK_DIR_TO_CHECK%\." mkdir "%TASK_DIR_TO_CHECK%" >nul 2>&1
if errorlevel 1 (
    echo Klaida: nepavyko sukurti task aplanko "%TASK_DIR_TO_CHECK%".
    exit /b 1
)

call :CreateTaskTemplateOrWizard "%TASK_FILE_TO_CREATE%"
if errorlevel 1 exit /b 1

echo Sukurtas sablonas: "%TASK_FILE_TO_CREATE%".
exit /b 0

:CreateTaskTemplateOrWizard
set "TASK_TEMPLATE_PATH=%~1"

echo.
set "INTERACTIVE_TEMPLATE_ANSWER="
set /p INTERACTIVE_TEMPLATE_ANSWER="Ar norite uzpildyti objects.txt interaktyviai dabar? (Y/N, Enter=N): "
call :Trim "%INTERACTIVE_TEMPLATE_ANSWER%" INTERACTIVE_TEMPLATE_ANSWER
if defined INTERACTIVE_TEMPLATE_ANSWER set "INTERACTIVE_TEMPLATE_ANSWER=%INTERACTIVE_TEMPLATE_ANSWER:~0,1%"

if /I "%INTERACTIVE_TEMPLATE_ANSWER%"=="Y" (
    call :WriteObjectsTemplateInteractive "%TASK_TEMPLATE_PATH%"
    exit /b %errorlevel%
)

if /I "%INTERACTIVE_TEMPLATE_ANSWER%"=="YES" (
    call :WriteObjectsTemplateInteractive "%TASK_TEMPLATE_PATH%"
    exit /b %errorlevel%
)

call :WriteObjectsTemplate "%TASK_TEMPLATE_PATH%"
exit /b %errorlevel%

:WriteObjectsTemplate
set "TASK_TEMPLATE_PATH=%~1"

(
echo # Task eksportavimo aprasas.
echo # Atsikomentuokite reikalingas eilutes ir pakeiskite objektu pavadinimus.
echo # Galimi objektu tipai: packages, procedures, functions, tables, views, types.
echo.
echo # [DEV]
echo # nls_lang: Lithuanian_lithuania.utf8
echo # schema:APPUSER19
echo # packages: PKG_SAMPLE
echo # procedures: PR_SAMPLE
echo # functions: FN_SAMPLE
echo # tables: TABLE_ONE,TABLE_TWO
echo # views: VW_SAMPLE
echo # types: TP_SAMPLE
echo.
echo # [TEST]
echo # schema:APPUSER19
echo # packages:
echo # procedures:
echo # functions:
echo # tables:
echo # views:
echo # types:
echo.
echo # [PROD]
echo # schema:APPUSER19
echo # packages:
echo # procedures:
echo # functions:
echo # tables:
echo # views:
echo # types:
) > "%TASK_TEMPLATE_PATH%"

if errorlevel 1 (
    echo Klaida: nepavyko sukurti task sablono "%TASK_TEMPLATE_PATH%".
    exit /b 1
)

exit /b 0

:WriteObjectsTemplateInteractive
set "TASK_TEMPLATE_PATH=%~1"

(
echo # Task eksportavimo aprasas.
echo # Sukurtas interaktyviai per CLI.
echo # Galimi objektu tipai: packages, procedures, functions, tables, views, types.
echo # Visur galima palikti tuscia arba ivesti SKIP.
echo.
) > "%TASK_TEMPLATE_PATH%"

if errorlevel 1 (
    echo Klaida: nepavyko sukurti task failo "%TASK_TEMPLATE_PATH%".
    exit /b 1
)

call :CollectInteractiveEnv "%TASK_TEMPLATE_PATH%" "DEV"
if errorlevel 1 exit /b 1

call :CollectInteractiveEnv "%TASK_TEMPLATE_PATH%" "TEST"
if errorlevel 1 exit /b 1

call :CollectInteractiveEnv "%TASK_TEMPLATE_PATH%" "PROD"
if errorlevel 1 exit /b 1

echo Interaktyvus task failas sukurtas: "%TASK_TEMPLATE_PATH%".
exit /b 0

:CollectInteractiveEnv
set "TASK_TEMPLATE_PATH=%~1"
set "ENV_LABEL=%~2"

echo.
set "ENV_INCLUDE_ANSWER="
set /p ENV_INCLUDE_ANSWER="AR ENV %ENV_LABEL% ? (Y/N, Enter=skip): "
call :Trim "%ENV_INCLUDE_ANSWER%" ENV_INCLUDE_ANSWER
if defined ENV_INCLUDE_ANSWER set "ENV_INCLUDE_ANSWER=%ENV_INCLUDE_ANSWER:~0,1%"

if /I "%ENV_INCLUDE_ANSWER%"=="Y" goto CollectInteractiveEnvYes
if /I "%ENV_INCLUDE_ANSWER%"=="YES" goto CollectInteractiveEnvYes

call :AppendCommentedEnvTemplate "%TASK_TEMPLATE_PATH%" "%ENV_LABEL%"
exit /b 0

:CollectInteractiveEnvYes
set "ENV_NLS_RAW="
set /p ENV_NLS_RAW="Nurodykite nls_lang %ENV_LABEL% aplinkai (Enter/skip=praleisti): "
call :NormalizeWizardInput "%ENV_NLS_RAW%" ENV_NLS_VALUE

set "ENV_SCHEMA_RAW="
set /p ENV_SCHEMA_RAW="Iveskite schema %ENV_LABEL% aplinkai DIDZIOSIOMIS (Enter/skip=praleisti): "
call :NormalizeWizardInput "%ENV_SCHEMA_RAW%" ENV_SCHEMA_VALUE

if not defined ENV_SCHEMA_VALUE (
    echo Praleista: ENV %ENV_LABEL% - schema nenurodyta.
    call :AppendCommentedEnvTemplate "%TASK_TEMPLATE_PATH%" "%ENV_LABEL%"
    exit /b 0
)

set "ENV_PACKAGES_RAW="
set /p ENV_PACKAGES_RAW="Iveskite packages sarasa %ENV_LABEL% aplinkai (kableliais, Enter/skip=praleisti): "
call :NormalizeWizardInput "%ENV_PACKAGES_RAW%" ENV_PACKAGES_VALUE

set "ENV_PROCEDURES_RAW="
set /p ENV_PROCEDURES_RAW="Iveskite procedures sarasa %ENV_LABEL% aplinkai (kableliais, Enter/skip=praleisti): "
call :NormalizeWizardInput "%ENV_PROCEDURES_RAW%" ENV_PROCEDURES_VALUE

set "ENV_FUNCTIONS_RAW="
set /p ENV_FUNCTIONS_RAW="Iveskite functions sarasa %ENV_LABEL% aplinkai (kableliais, Enter/skip=praleisti): "
call :NormalizeWizardInput "%ENV_FUNCTIONS_RAW%" ENV_FUNCTIONS_VALUE

set "ENV_TABLES_RAW="
set /p ENV_TABLES_RAW="Iveskite tables sarasa %ENV_LABEL% aplinkai (kableliais, Enter/skip=praleisti): "
call :NormalizeWizardInput "%ENV_TABLES_RAW%" ENV_TABLES_VALUE

set "ENV_VIEWS_RAW="
set /p ENV_VIEWS_RAW="Iveskite views sarasa %ENV_LABEL% aplinkai (kableliais, Enter/skip=praleisti): "
call :NormalizeWizardInput "%ENV_VIEWS_RAW%" ENV_VIEWS_VALUE

set "ENV_TYPES_RAW="
set /p ENV_TYPES_RAW="Iveskite types sarasa %ENV_LABEL% aplinkai (kableliais, Enter/skip=praleisti): "
call :NormalizeWizardInput "%ENV_TYPES_RAW%" ENV_TYPES_VALUE

>> "%TASK_TEMPLATE_PATH%" echo [%ENV_LABEL%]
if defined ENV_NLS_VALUE >> "%TASK_TEMPLATE_PATH%" echo nls_lang:%ENV_NLS_VALUE%
>> "%TASK_TEMPLATE_PATH%" echo schema:%ENV_SCHEMA_VALUE%
>> "%TASK_TEMPLATE_PATH%" echo packages:%ENV_PACKAGES_VALUE%
>> "%TASK_TEMPLATE_PATH%" echo procedures:%ENV_PROCEDURES_VALUE%
>> "%TASK_TEMPLATE_PATH%" echo functions:%ENV_FUNCTIONS_VALUE%
>> "%TASK_TEMPLATE_PATH%" echo tables:%ENV_TABLES_VALUE%
>> "%TASK_TEMPLATE_PATH%" echo views:%ENV_VIEWS_VALUE%
>> "%TASK_TEMPLATE_PATH%" echo types:%ENV_TYPES_VALUE%
>> "%TASK_TEMPLATE_PATH%" echo.
exit /b 0

:AppendCommentedEnvTemplate
set "TASK_TEMPLATE_PATH=%~1"
set "ENV_LABEL=%~2"

>> "%TASK_TEMPLATE_PATH%" echo # [%ENV_LABEL%]
>> "%TASK_TEMPLATE_PATH%" echo # schema:APPUSER19
>> "%TASK_TEMPLATE_PATH%" echo # packages:
>> "%TASK_TEMPLATE_PATH%" echo # procedures:
>> "%TASK_TEMPLATE_PATH%" echo # functions:
>> "%TASK_TEMPLATE_PATH%" echo # tables:
>> "%TASK_TEMPLATE_PATH%" echo # views:
>> "%TASK_TEMPLATE_PATH%" echo # types:
>> "%TASK_TEMPLATE_PATH%" echo.
exit /b 0

:NormalizeWizardInput
set "WIZARD_RAW=%~1"
call :StripQuotes "%WIZARD_RAW%" WIZARD_RAW
call :Trim "%WIZARD_RAW%" WIZARD_RAW

if /I "%WIZARD_RAW%"=="SKIP" set "WIZARD_RAW="

set "%~2=%WIZARD_RAW%"
exit /b 0

:ProcessTaskFile
set "TASK_FILE_TO_PROCESS=%~1"
set "TARGET_TASK_ENV=%~2"
set "SCHEMA_FILTER=%~3"

set "TASK_ENV_FOUND=0"
set "SCHEMA_FOUND=0"
set "TASK_ABORT=0"
set "TASK_ABORT_MESSAGE="
set "CURRENT_TASK_ENV="
set "CURRENT_SCHEMA="
set "CURRENT_SCHEMA_ACTIVE=0"

for /f "usebackq tokens=* delims=" %%L in ("%TASK_FILE_TO_PROCESS%") do (
    set "TASK_LINE=%%L"
    call :ProcessTaskLine "%TARGET_TASK_ENV%" "%SCHEMA_FILTER%"
)

if "%TASK_ENV_FOUND%"=="0" (
    echo Klaida: task faile nerasta aplinkos sekcija [%TARGET_TASK_ENV%]: %TASK_FILE_TO_PROCESS%.
    exit /b 1
)

if defined SCHEMA_FILTER if "%SCHEMA_FOUND%"=="0" (
    echo Klaida: schema "%SCHEMA_FILTER%" nerasta task faile sekcijoje [%TARGET_TASK_ENV%].
    exit /b 1
)

if "%TASK_ABORT%"=="1" (
    if defined TASK_ABORT_MESSAGE echo %TASK_ABORT_MESSAGE%
    exit /b 1
)

exit /b 0

:ProcessTaskLine
set "TARGET_TASK_ENV=%~1"
set "SCHEMA_FILTER=%~2"
set "RAW_LINE=!TASK_LINE!"
call :Trim "!RAW_LINE!" LINE_TRIM

if "!TASK_ABORT!"=="1" exit /b 0
if not defined LINE_TRIM exit /b 0
if "!LINE_TRIM:~0,1!"=="#" exit /b 0
if "!LINE_TRIM:~0,2!"=="--" exit /b 0
if "!LINE_TRIM:~0,1!"==";" exit /b 0

if "!LINE_TRIM:~0,1!"=="[" if "!LINE_TRIM:~-1!"=="]" (
    set "CURRENT_TASK_ENV=!LINE_TRIM:~1,-1!"
    call :Trim "!CURRENT_TASK_ENV!" CURRENT_TASK_ENV
    set "CURRENT_SCHEMA="
    set "CURRENT_SCHEMA_ACTIVE=0"
    if /I "!CURRENT_TASK_ENV!"=="!TARGET_TASK_ENV!" set "TASK_ENV_FOUND=1"
    exit /b 0
)

if /I not "!CURRENT_TASK_ENV!"=="!TARGET_TASK_ENV!" exit /b 0

call :ParseYamlKeyValue "!LINE_TRIM!" TASK_KEY TASK_VAL
if not defined TASK_KEY exit /b 0

if /I "!TASK_KEY!"=="nls_lang" (
    call :StripQuotes "!TASK_VAL!" TASK_NLS_LANG
    if defined TASK_NLS_LANG set "NLS_LANG=!TASK_NLS_LANG!"
    exit /b 0
)

if /I "!TASK_KEY!"=="schema" (
    call :StripQuotes "!TASK_VAL!" CURRENT_SCHEMA
    call :Trim "!CURRENT_SCHEMA!" CURRENT_SCHEMA

    if not defined CURRENT_SCHEMA (
        set "TASK_ABORT=1"
        set "TASK_ABORT_MESSAGE=Klaida: task faile schema tuscia."
        exit /b 0
    )

    set "CURRENT_SCHEMA_ACTIVE=1"
    if defined SCHEMA_FILTER if /I not "!CURRENT_SCHEMA!"=="!SCHEMA_FILTER!" set "CURRENT_SCHEMA_ACTIVE=0"

    if "!CURRENT_SCHEMA_ACTIVE!"=="1" (
        set "SCHEMA_FOUND=1"
        if /I not "!PREFLIGHT_VALIDATE_ONLY!"=="1" if not exist "%OUTPUT_ROOT%\!CURRENT_SCHEMA!" mkdir "%OUTPUT_ROOT%\!CURRENT_SCHEMA!" >nul 2>&1
    )
    exit /b 0
)

call :NormalizeStep "!TASK_KEY!" TASK_STEP
if not defined TASK_STEP exit /b 0

if not defined CURRENT_SCHEMA (
    set "TASK_ABORT=1"
    set "TASK_ABORT_MESSAGE=Klaida: task faile objekto eilute pateikta pries schema: !LINE_TRIM!"
    exit /b 0
)

if "!CURRENT_SCHEMA_ACTIVE!"=="0" exit /b 0

call :ProcessStep "!TASK_STEP!" "!CURRENT_SCHEMA!" "!TASK_VAL!"
if errorlevel 1 (
    set "TASK_ABORT=1"
    set "TASK_ABORT_MESSAGE=Klaida vykdant schema !CURRENT_SCHEMA! step !TASK_STEP!."
)

exit /b 0

:ProcessStep
set "STEP_NAME=%~1"
set "STEP_SCHEMA=%~2"
set "STEP_RAW_LIST=%~3"

set /a SUMMARY_TOTAL+=1

call :Trim "%STEP_RAW_LIST%" STEP_RAW_LIST
if not defined STEP_RAW_LIST (
    call :WriteLog "SKIP | %STEP_SCHEMA%.%STEP_NAME% | tuscias objektu sarasas"
    set /a SUMMARY_SKIPPED+=1
    exit /b 0
)

set "STEP_SAVE_DIR=%OUTPUT_ROOT%\%STEP_SCHEMA%"
set "STEP_SCRIPT="
set "STEP_EXTENSION="

if /I "%STEP_NAME%"=="packages" (
    set "STEP_SCRIPT=validate_and_export_package.sql"
    set "STEP_EXTENSION=%EXT_PACKAGES%"
)
if /I "%STEP_NAME%"=="procedures" (
    set "STEP_SCRIPT=validate_and_export_procedure.sql"
    set "STEP_EXTENSION=%EXT_PROCEDURES%"
)
if /I "%STEP_NAME%"=="functions" (
    set "STEP_SCRIPT=validate_and_export_function.sql"
    set "STEP_EXTENSION=%EXT_FUNCTIONS%"
)
if /I "%STEP_NAME%"=="types" (
    set "STEP_SCRIPT=validate_and_export_type.sql"
    set "STEP_EXTENSION=%EXT_TYPES%"
    set "STEP_SAVE_DIR=%OUTPUT_ROOT%\%STEP_SCHEMA%\TYPES"
)
if /I "%STEP_NAME%"=="tables" (
    set "STEP_SCRIPT=generate_tbl_ddl.sql"
    if /I "%DDL_SOURCE%"=="dba" set "STEP_SCRIPT=generate_tbl_ddl_dba.sql"
    set "STEP_EXTENSION=%EXT_TABLES%"
    set "STEP_SAVE_DIR=%OUTPUT_ROOT%\%STEP_SCHEMA%\TABLES"
)
if /I "%STEP_NAME%"=="views" (
    set "STEP_SCRIPT=generate_view_ddl.sql"
    if /I "%DDL_SOURCE%"=="dba" set "STEP_SCRIPT=generate_view_ddl_dba.sql"
    set "STEP_EXTENSION=%EXT_VIEWS%"
    set "STEP_SAVE_DIR=%OUTPUT_ROOT%\%STEP_SCHEMA%\VIEWS"
)

set "STEP_REST=%STEP_RAW_LIST%"
set /a STEP_OBJECT_COUNT=0
:CountObjectsLoop
set "STEP_TOKEN="
set "STEP_NEXT="
for /f "tokens=1* delims=," %%A in ("%STEP_REST%") do (
    set "STEP_TOKEN=%%A"
    set "STEP_NEXT=%%B"
)
call :Trim "%STEP_TOKEN%" STEP_TOKEN
if defined STEP_TOKEN set /a STEP_OBJECT_COUNT+=1
if defined STEP_NEXT (
    set "STEP_REST=%STEP_NEXT%"
    goto CountObjectsLoop
)

if "%STEP_OBJECT_COUNT%"=="0" (
    call :WriteLog "SKIP | %STEP_SCHEMA%.%STEP_NAME% | tuscias objektu sarasas"
    set /a SUMMARY_SKIPPED+=1
    exit /b 0
)

if /I "%PREFLIGHT_VALIDATE_ONLY%"=="1" (
    call :AddPreflightStep "%STEP_NAME%"
    call :WriteLog "CHECK | schema=%STEP_SCHEMA% step=%STEP_NAME% objects=%STEP_OBJECT_COUNT%"
    exit /b 0
)

if not exist "%STEP_SAVE_DIR%" mkdir "%STEP_SAVE_DIR%" >nul 2>&1

call :WriteLog "START | schema=%STEP_SCHEMA% step=%STEP_NAME% objects=%STEP_OBJECT_COUNT%"

set "STEP_REST=%STEP_RAW_LIST%"
:RunObjectsLoop
set "STEP_TOKEN="
set "STEP_NEXT="
for /f "tokens=1* delims=," %%A in ("%STEP_REST%") do (
    set "STEP_TOKEN=%%A"
    set "STEP_NEXT=%%B"
)
call :Trim "%STEP_TOKEN%" STEP_TOKEN

if defined STEP_TOKEN (
    if /I "%STEP_NAME%"=="packages" call :InvokeSqlPlus "%STEP_SCRIPT%" "%STEP_SAVE_DIR%" "%STEP_TOKEN%" "SPEC_AND_BODY" "%STEP_SCHEMA%" "%STEP_EXTENSION%"
    if /I "%STEP_NAME%"=="procedures" call :InvokeSqlPlus "%STEP_SCRIPT%" "%STEP_SAVE_DIR%" "%STEP_TOKEN%" "%STEP_SCHEMA%" "%STEP_EXTENSION%"
    if /I "%STEP_NAME%"=="functions" call :InvokeSqlPlus "%STEP_SCRIPT%" "%STEP_SAVE_DIR%" "%STEP_TOKEN%" "%STEP_SCHEMA%" "%STEP_EXTENSION%"
    if /I "%STEP_NAME%"=="types" call :InvokeSqlPlus "%STEP_SCRIPT%" "%STEP_SAVE_DIR%" "%STEP_TOKEN%" "%STEP_SCHEMA%" "%STEP_EXTENSION%"
    if /I "%STEP_NAME%"=="tables" call :InvokeSqlPlus "%STEP_SCRIPT%" "%STEP_SAVE_DIR%" "%STEP_SCHEMA%" "%STEP_TOKEN%" "%STEP_EXTENSION%"
    if /I "%STEP_NAME%"=="views" call :InvokeSqlPlus "%STEP_SCRIPT%" "%STEP_SAVE_DIR%" "%STEP_SCHEMA%" "%STEP_TOKEN%" "%STEP_EXTENSION%"

    if errorlevel 1 exit /b 1
)

if defined STEP_NEXT (
    set "STEP_REST=%STEP_NEXT%"
    goto RunObjectsLoop
)

set /a SUMMARY_EXECUTED+=1
call :WriteLog "DONE | schema=%STEP_SCHEMA% step=%STEP_NAME%"
exit /b 0

:InvokeSqlPlus
set "SQL_SCRIPT=%~1"
set "SQL_SCRIPT_PATH=%SCRIPTS_DIR%\%SQL_SCRIPT%"

if not exist "%SQL_SCRIPT_PATH%" (
    echo Klaida: nerastas SQL skriptas "%SQL_SCRIPT_PATH%".
    exit /b 1
)

set "SQL_ARGS="
if not "%~2"=="" set "SQL_ARGS=!SQL_ARGS! ^"%~2^""
if not "%~3"=="" set "SQL_ARGS=!SQL_ARGS! ^"%~3^""
if not "%~4"=="" set "SQL_ARGS=!SQL_ARGS! ^"%~4^""
if not "%~5"=="" set "SQL_ARGS=!SQL_ARGS! ^"%~5^""
if not "%~6"=="" set "SQL_ARGS=!SQL_ARGS! ^"%~6^""

call :WriteLog "EXECUTE | %SQLPLUS_EXE% <connection-redacted> @%SQL_SCRIPT_PATH%%SQL_ARGS%"
if "%DRY_RUN%"=="1" exit /b 0

set "SQL_TMP_OUT=%LOGS_DIR%\sqlplus_%RUN_TIMESTAMP%_%RANDOM%%RANDOM%.tmp"

(
    echo exit
) | "%SQLPLUS_EXE%" -L "%CONNECTION_STRING%" @"%SQL_SCRIPT_PATH%"%SQL_ARGS% > "%SQL_TMP_OUT%" 2>&1

set "SQL_RC=%errorlevel%"

if exist "%SQL_TMP_OUT%" (
    type "%SQL_TMP_OUT%"
    >> "%LOG_FILE%" type "%SQL_TMP_OUT%"
    del /q "%SQL_TMP_OUT%" >nul 2>&1
)

if not "%SQL_RC%"=="0" (
    call :WriteLog "ERROR | sqlplus baigesi su klaida (%SQL_RC%) vykdant %SQL_SCRIPT%"
    exit /b %SQL_RC%
)

exit /b 0

:RunPreflight
set "PREFLIGHT_SQL_SCRIPT=%SCRIPTS_DIR%\preflight_check.sql"
set "PREFLIGHT_TMP_OUT=%LOGS_DIR%\preflight_%RUN_TIMESTAMP%_%RANDOM%%RANDOM%.tmp"

call :WriteLog "PREFLIGHT | validating sqlplus executable"
call :CheckSqlPlusExecutable
if errorlevel 1 exit /b 1

call :WriteLog "PREFLIGHT | validating required sql scripts"
call :CheckRequiredSqlScripts
if errorlevel 1 exit /b 1

if not exist "%PREFLIGHT_SQL_SCRIPT%" (
    echo Klaida: nerastas preflight SQL skriptas "%PREFLIGHT_SQL_SCRIPT%".
    call :WriteLog "ERROR | nerastas preflight SQL skriptas %PREFLIGHT_SQL_SCRIPT%"
    exit /b 1
)

set "PREFLIGHT_OLD_DRY_RUN=%DRY_RUN%"
set "PREFLIGHT_VALIDATE_ONLY=1"
set "DRY_RUN=1"
set "OUTPUT_ROOT=%TASK_DIR%\%ENV_NAME%\%RUN_TIMESTAMP%_PREFLIGHT"

set "PREFLIGHT_REQUESTED_PACKAGES=0"
set "PREFLIGHT_REQUESTED_PROCEDURES=0"
set "PREFLIGHT_REQUESTED_FUNCTIONS=0"
set "PREFLIGHT_REQUESTED_TYPES=0"
set "PREFLIGHT_REQUESTED_TABLES=0"
set "PREFLIGHT_REQUESTED_VIEWS=0"

call :WriteLog "PREFLIGHT | validating task file structure"
call :ProcessTaskFile "%TASK_FILE%" "%ENV_NAME%" "%SCHEMA_NAME%"
set "PREFLIGHT_TASK_RC=%errorlevel%"

set "DRY_RUN=%PREFLIGHT_OLD_DRY_RUN%"
set "PREFLIGHT_VALIDATE_ONLY=0"

if not "%PREFLIGHT_TASK_RC%"=="0" exit /b %PREFLIGHT_TASK_RC%

call :WriteLog "PREFLIGHT | checking Oracle connection and privileges"
"%SQLPLUS_EXE%" -L -S "%CONNECTION_STRING%" @"%PREFLIGHT_SQL_SCRIPT%" > "%PREFLIGHT_TMP_OUT%" 2>&1
set "PREFLIGHT_SQL_RC=%errorlevel%"

if exist "%PREFLIGHT_TMP_OUT%" (
    type "%PREFLIGHT_TMP_OUT%"
    >> "%LOG_FILE%" type "%PREFLIGHT_TMP_OUT%"
)

if not "%PREFLIGHT_SQL_RC%"=="0" (
    call :WriteLog "ERROR | preflight SQL patikra baigesi su klaida code=%PREFLIGHT_SQL_RC%"
    if exist "%PREFLIGHT_TMP_OUT%" del /q "%PREFLIGHT_TMP_OUT%" >nul 2>&1
    exit /b %PREFLIGHT_SQL_RC%
)

findstr /x /c:"PREFLIGHT_CONN_OK" "%PREFLIGHT_TMP_OUT%" >nul 2>&1
if errorlevel 1 (
    echo Klaida: preflight negavo DB prisijungimo patvirtinimo.
    call :WriteLog "ERROR | preflight negavo DB prisijungimo patvirtinimo"
    if exist "%PREFLIGHT_TMP_OUT%" del /q "%PREFLIGHT_TMP_OUT%" >nul 2>&1
    exit /b 1
)

findstr /x /c:"PREFLIGHT_DONE" "%PREFLIGHT_TMP_OUT%" >nul 2>&1
if errorlevel 1 (
    echo Klaida: preflight SQL atsakymas nebaigtas - nera PREFLIGHT_DONE zymos.
    call :WriteLog "ERROR | preflight SQL atsakymas nebaigtas"
    if exist "%PREFLIGHT_TMP_OUT%" del /q "%PREFLIGHT_TMP_OUT%" >nul 2>&1
    exit /b 1
)

findstr /b /c:"PREFLIGHT_CAPABILITY:PROCEDURES:" "%PREFLIGHT_TMP_OUT%" >nul 2>&1
if errorlevel 1 (
    echo Klaida: preflight SQL negrazino capability informacijos.
    call :WriteLog "ERROR | preflight SQL negrazino capability informacijos"
    if exist "%PREFLIGHT_TMP_OUT%" del /q "%PREFLIGHT_TMP_OUT%" >nul 2>&1
    exit /b 1
)

call :ParsePreflightCapabilities "%PREFLIGHT_TMP_OUT%"
call :PrintPreflightSummary
call :ValidatePreflightCapabilities
set "PREFLIGHT_CAP_RC=%errorlevel%"

if not "%PREFLIGHT_CAP_RC%"=="0" (
    if exist "%PREFLIGHT_TMP_OUT%" del /q "%PREFLIGHT_TMP_OUT%" >nul 2>&1
    exit /b %PREFLIGHT_CAP_RC%
)

if exist "%PREFLIGHT_TMP_OUT%" del /q "%PREFLIGHT_TMP_OUT%" >nul 2>&1

call :WriteLog "PREFLIGHT | all checks passed"
exit /b 0

:AddPreflightStep
set "PRE_STEP=%~1"
if /I "%PRE_STEP%"=="packages" set "PREFLIGHT_REQUESTED_PACKAGES=1"
if /I "%PRE_STEP%"=="procedures" set "PREFLIGHT_REQUESTED_PROCEDURES=1"
if /I "%PRE_STEP%"=="functions" set "PREFLIGHT_REQUESTED_FUNCTIONS=1"
if /I "%PRE_STEP%"=="types" set "PREFLIGHT_REQUESTED_TYPES=1"
if /I "%PRE_STEP%"=="tables" set "PREFLIGHT_REQUESTED_TABLES=1"
if /I "%PRE_STEP%"=="views" set "PREFLIGHT_REQUESTED_VIEWS=1"
exit /b 0

:ParsePreflightCapabilities
set "REPORT_FILE=%~1"
set "PREFLIGHT_PRIV_CREATE_SESSION=0"
set "PREFLIGHT_PRIV_SELECT_ANY_DICTIONARY=0"
set "PREFLIGHT_PRIV_DEBUG_ANY_PROCEDURE=0"
set "PREFLIGHT_ROLE_SELECT_CATALOG_ROLE=0"

set "PREFLIGHT_CAN_PACKAGES=0"
set "PREFLIGHT_CAN_PROCEDURES=0"
set "PREFLIGHT_CAN_FUNCTIONS=0"
set "PREFLIGHT_CAN_TYPES=0"
set "PREFLIGHT_CAN_TABLES=0"
set "PREFLIGHT_CAN_VIEWS=0"

for /f "usebackq tokens=1,2,3 delims=:" %%A in (`findstr /b /c:"PREFLIGHT_PRIV:" "%REPORT_FILE%"`) do (
    if /I "%%B"=="CREATE_SESSION" set "PREFLIGHT_PRIV_CREATE_SESSION=%%C"
    if /I "%%B"=="SELECT_ANY_DICTIONARY" set "PREFLIGHT_PRIV_SELECT_ANY_DICTIONARY=%%C"
    if /I "%%B"=="DEBUG_ANY_PROCEDURE" set "PREFLIGHT_PRIV_DEBUG_ANY_PROCEDURE=%%C"
)

for /f "usebackq tokens=1,2,3 delims=:" %%A in (`findstr /b /c:"PREFLIGHT_ROLE:" "%REPORT_FILE%"`) do (
    if /I "%%B"=="SELECT_CATALOG_ROLE" set "PREFLIGHT_ROLE_SELECT_CATALOG_ROLE=%%C"
)

for /f "usebackq tokens=1,2,3 delims=:" %%A in (`findstr /b /c:"PREFLIGHT_CAPABILITY:" "%REPORT_FILE%"`) do (
    if /I "%%B"=="PACKAGES" set "PREFLIGHT_CAN_PACKAGES=%%C"
    if /I "%%B"=="PROCEDURES" set "PREFLIGHT_CAN_PROCEDURES=%%C"
    if /I "%%B"=="FUNCTIONS" set "PREFLIGHT_CAN_FUNCTIONS=%%C"
    if /I "%%B"=="TYPES" set "PREFLIGHT_CAN_TYPES=%%C"
    if /I "%%B"=="TABLES" set "PREFLIGHT_CAN_TABLES=%%C"
    if /I "%%B"=="VIEWS" set "PREFLIGHT_CAN_VIEWS=%%C"
)

exit /b 0

:PrintPreflightSummary
call :BoolToYesNo "%PREFLIGHT_PRIV_CREATE_SESSION%" TXT_CREATE_SESSION
call :BoolToYesNo "%PREFLIGHT_PRIV_SELECT_ANY_DICTIONARY%" TXT_SELECT_ANY_DICTIONARY
call :BoolToYesNo "%PREFLIGHT_PRIV_DEBUG_ANY_PROCEDURE%" TXT_DEBUG_ANY_PROCEDURE
call :BoolToYesNo "%PREFLIGHT_ROLE_SELECT_CATALOG_ROLE%" TXT_SELECT_CATALOG_ROLE

call :BoolToYesNo "%PREFLIGHT_CAN_PACKAGES%" TXT_CAN_PACKAGES
call :BoolToYesNo "%PREFLIGHT_CAN_PROCEDURES%" TXT_CAN_PROCEDURES
call :BoolToYesNo "%PREFLIGHT_CAN_FUNCTIONS%" TXT_CAN_FUNCTIONS
call :BoolToYesNo "%PREFLIGHT_CAN_TYPES%" TXT_CAN_TYPES
call :BoolToYesNo "%PREFLIGHT_CAN_TABLES%" TXT_CAN_TABLES
call :BoolToYesNo "%PREFLIGHT_CAN_VIEWS%" TXT_CAN_VIEWS

echo.
echo Oracle teisiu suvestine:
echo   CREATE SESSION: %TXT_CREATE_SESSION%
echo   SELECT ANY DICTIONARY: %TXT_SELECT_ANY_DICTIONARY%
echo   DEBUG ANY PROCEDURE: %TXT_DEBUG_ANY_PROCEDURE%
echo   SELECT_CATALOG_ROLE: %TXT_SELECT_CATALOG_ROLE%
echo.
echo Oracle eksporto galimybes:
echo   packages: %TXT_CAN_PACKAGES%
echo   procedures: %TXT_CAN_PROCEDURES%
echo   functions: %TXT_CAN_FUNCTIONS%
echo   types: %TXT_CAN_TYPES%
echo   tables: %TXT_CAN_TABLES%
echo   views: %TXT_CAN_VIEWS%

call :WriteLog "PREFLIGHT RIGHTS | CREATE_SESSION=%TXT_CREATE_SESSION% SELECT_ANY_DICTIONARY=%TXT_SELECT_ANY_DICTIONARY% DEBUG_ANY_PROCEDURE=%TXT_DEBUG_ANY_PROCEDURE% SELECT_CATALOG_ROLE=%TXT_SELECT_CATALOG_ROLE%"
call :WriteLog "PREFLIGHT CAPABILITIES | packages=%TXT_CAN_PACKAGES% procedures=%TXT_CAN_PROCEDURES% functions=%TXT_CAN_FUNCTIONS% types=%TXT_CAN_TYPES% tables=%TXT_CAN_TABLES% views=%TXT_CAN_VIEWS%"
exit /b 0

:ValidatePreflightCapabilities
set "PREFLIGHT_MISSING_STEPS="

if "%PREFLIGHT_REQUESTED_PACKAGES%"=="1" if not "%PREFLIGHT_CAN_PACKAGES%"=="1" call :AddMissingPreflightStep "packages"
if "%PREFLIGHT_REQUESTED_PROCEDURES%"=="1" if not "%PREFLIGHT_CAN_PROCEDURES%"=="1" call :AddMissingPreflightStep "procedures"
if "%PREFLIGHT_REQUESTED_FUNCTIONS%"=="1" if not "%PREFLIGHT_CAN_FUNCTIONS%"=="1" call :AddMissingPreflightStep "functions"
if "%PREFLIGHT_REQUESTED_TYPES%"=="1" if not "%PREFLIGHT_CAN_TYPES%"=="1" call :AddMissingPreflightStep "types"
if "%PREFLIGHT_REQUESTED_TABLES%"=="1" if not "%PREFLIGHT_CAN_TABLES%"=="1" call :AddMissingPreflightStep "tables"
if "%PREFLIGHT_REQUESTED_VIEWS%"=="1" if not "%PREFLIGHT_CAN_VIEWS%"=="1" call :AddMissingPreflightStep "views"

if defined PREFLIGHT_MISSING_STEPS (
    echo Klaida: pagal naudotojo teises siame task negalimas eksportas siu tipams: %PREFLIGHT_MISSING_STEPS%
    call :WriteLog "ERROR | preflight truksta teisiu task tipams: %PREFLIGHT_MISSING_STEPS%"
    exit /b 1
)

echo Preflight: pagal esamas teises galima eksportuoti visus task'e nurodytus objektu tipus.
call :WriteLog "PREFLIGHT | task objektu tipams teisiu pakanka"
exit /b 0

:AddMissingPreflightStep
if defined PREFLIGHT_MISSING_STEPS (
    set "PREFLIGHT_MISSING_STEPS=%PREFLIGHT_MISSING_STEPS%, %~1"
) else (
    set "PREFLIGHT_MISSING_STEPS=%~1"
)
exit /b 0

:BoolToYesNo
set "BOOL_INPUT=%~1"
if "%BOOL_INPUT%"=="1" (
    set "%~2=YES"
) else (
    set "%~2=NO"
)
exit /b 0

:CheckSqlPlusExecutable
set "SQLPLUS_CHECK=%SQLPLUS_EXE%"
call :ExpandEnvPath "!SQLPLUS_CHECK!" SQLPLUS_CHECK
call :StripQuotes "%SQLPLUS_CHECK%" SQLPLUS_CHECK
call :Trim "%SQLPLUS_CHECK%" SQLPLUS_CHECK
if not defined SQLPLUS_CHECK set "SQLPLUS_CHECK=sqlplus"

call :IsAbsolutePath "%SQLPLUS_CHECK%" SQLPLUS_IS_ABSOLUTE
if "%SQLPLUS_IS_ABSOLUTE%"=="1" (
    if not exist "%SQLPLUS_CHECK%" (
        echo Klaida: sqlplus executable nerastas "%SQLPLUS_CHECK%".
        call :WriteLog "ERROR | sqlplus executable nerastas %SQLPLUS_CHECK%"
        exit /b 1
    )
    exit /b 0
)

where "%SQLPLUS_CHECK%" >nul 2>&1
if errorlevel 1 (
    echo Klaida: sqlplus nerastas PATH. Patikrinkite sqlplus_executable config reiksme.
    call :WriteLog "ERROR | sqlplus nerastas PATH, sqlplus_executable=%SQLPLUS_CHECK%"
    exit /b 1
)

exit /b 0

:CheckRequiredSqlScripts
set "MISSING_SQL_SCRIPTS="

for %%S in (
    validate_and_export_package.sql
    validate_and_export_procedure.sql
    validate_and_export_function.sql
    validate_and_export_type.sql
    generate_tbl_ddl.sql
    generate_tbl_ddl_dba.sql
    generate_view_ddl.sql
    generate_view_ddl_dba.sql
    preflight_check.sql
) do (
    if not exist "%SCRIPTS_DIR%\%%S" (
        if defined MISSING_SQL_SCRIPTS (
            set "MISSING_SQL_SCRIPTS=!MISSING_SQL_SCRIPTS!, %%S"
        ) else (
            set "MISSING_SQL_SCRIPTS=%%S"
        )
    )
)

if defined MISSING_SQL_SCRIPTS (
    echo Klaida: nerasti privalomi SQL skriptai: %MISSING_SQL_SCRIPTS%
    call :WriteLog "ERROR | nerasti privalomi SQL skriptai: %MISSING_SQL_SCRIPTS%"
    exit /b 1
)

exit /b 0

:IsAbsolutePath
set "INPUT_PATH=%~1"
set "IS_ABSOLUTE=0"
if "%INPUT_PATH:~1,1%"==":" set "IS_ABSOLUTE=1"
if "%INPUT_PATH:~0,2%"=="\\" set "IS_ABSOLUTE=1"
set "%~2=%IS_ABSOLUTE%"
exit /b 0

:ExpandEnvPath
setlocal EnableDelayedExpansion
set "EXPAND_VALUE=%~1"

if not defined EXPAND_VALUE (
    endlocal & set "%~2=" & exit /b 0
)
set /a EXPAND_GUARD=0

:ExpandLoop
set /a EXPAND_GUARD+=1
if !EXPAND_GUARD! gtr 20 goto ExpandDone

set "EXPAND_PRE="
set "EXPAND_VAR="
set "EXPAND_POST="
set "EXPAND_PARSE=#!EXPAND_VALUE!"
for /f "tokens=1,2* delims=%%" %%A in ("!EXPAND_PARSE!") do (
    set "EXPAND_PRE=%%A"
    set "EXPAND_VAR=%%B"
    set "EXPAND_POST=%%C"
)

if defined EXPAND_PRE set "EXPAND_PRE=!EXPAND_PRE:~1!"

if not defined EXPAND_VAR goto ExpandDone

set "EXPAND_VAR_VALUE="
call set "EXPAND_VAR_VALUE=%%%EXPAND_VAR%%%"
if "!EXPAND_VAR_VALUE!"=="%%%EXPAND_VAR%%%" set "EXPAND_VAR_VALUE="
if not defined EXPAND_VAR_VALUE call :GetRegistryEnv "!EXPAND_VAR!" EXPAND_VAR_VALUE
if not defined EXPAND_VAR_VALUE goto ExpandDone

set "EXPAND_VALUE=!EXPAND_PRE!!EXPAND_VAR_VALUE!!EXPAND_POST!"
goto ExpandLoop

:ExpandDone
endlocal & set "%~2=%EXPAND_VALUE%"
exit /b 0

:GetRegistryEnv
setlocal
set "REG_NAME=%~1"
set "REG_VALUE="

for /f "skip=2 tokens=1,2,*" %%A in ('reg query "HKCU\Environment" /v "%REG_NAME%" 2^>nul') do (
    if /I "%%A"=="%REG_NAME%" set "REG_VALUE=%%C"
)

if not defined REG_VALUE (
    for /f "skip=2 tokens=1,2,*" %%A in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v "%REG_NAME%" 2^>nul') do (
        if /I "%%A"=="%REG_NAME%" set "REG_VALUE=%%C"
    )
)

endlocal & set "%~2=%REG_VALUE%"
exit /b 0

:NormalizeStep
set "STEP_RAW=%~1"
call :Trim "%STEP_RAW%" STEP_RAW
set "STEP_NORMALIZED="

if /I "%STEP_RAW%"=="package" set "STEP_NORMALIZED=packages"
if /I "%STEP_RAW%"=="packages" set "STEP_NORMALIZED=packages"

if /I "%STEP_RAW%"=="procedure" set "STEP_NORMALIZED=procedures"
if /I "%STEP_RAW%"=="procedures" set "STEP_NORMALIZED=procedures"

if /I "%STEP_RAW%"=="function" set "STEP_NORMALIZED=functions"
if /I "%STEP_RAW%"=="functions" set "STEP_NORMALIZED=functions"

if /I "%STEP_RAW%"=="type" set "STEP_NORMALIZED=types"
if /I "%STEP_RAW%"=="types" set "STEP_NORMALIZED=types"

if /I "%STEP_RAW%"=="table" set "STEP_NORMALIZED=tables"
if /I "%STEP_RAW%"=="tables" set "STEP_NORMALIZED=tables"
if /I "%STEP_RAW%"=="table_ddl" set "STEP_NORMALIZED=tables"

if /I "%STEP_RAW%"=="view" set "STEP_NORMALIZED=views"
if /I "%STEP_RAW%"=="views" set "STEP_NORMALIZED=views"
if /I "%STEP_RAW%"=="view_ddl" set "STEP_NORMALIZED=views"

set "%~2=%STEP_NORMALIZED%"
exit /b 0

:SetExtensionValue
set "EXT_PREFIX=%~1"
set "EXT_STEP=%~2"
set "EXT_VALUE=%~3"

if /I "%EXT_STEP%"=="packages" set "%EXT_PREFIX%_PACKAGES=%EXT_VALUE%"
if /I "%EXT_STEP%"=="procedures" set "%EXT_PREFIX%_PROCEDURES=%EXT_VALUE%"
if /I "%EXT_STEP%"=="functions" set "%EXT_PREFIX%_FUNCTIONS=%EXT_VALUE%"
if /I "%EXT_STEP%"=="types" set "%EXT_PREFIX%_TYPES=%EXT_VALUE%"
if /I "%EXT_STEP%"=="tables" set "%EXT_PREFIX%_TABLES=%EXT_VALUE%"
if /I "%EXT_STEP%"=="views" set "%EXT_PREFIX%_VIEWS=%EXT_VALUE%"
exit /b 0

:NormalizeExtension
set "EXT_INPUT=%~1"
call :StripQuotes "%EXT_INPUT%" EXT_INPUT
if defined EXT_INPUT if "%EXT_INPUT:~0,1%"=="." set "EXT_INPUT=%EXT_INPUT:~1%"
call :Trim "%EXT_INPUT%" EXT_INPUT
set "%~2=%EXT_INPUT%"
exit /b 0

:ParseYamlKeyValue
set "KV_LINE=%~1"
set "KV_KEY="
set "KV_VALUE="

for /f "tokens=1* delims=:" %%A in ("%KV_LINE%") do (
    set "KV_KEY=%%A"
    set "KV_VALUE=%%B"
)

call :Trim "%KV_KEY%" KV_KEY
call :Trim "%KV_VALUE%" KV_VALUE
set "%~2=%KV_KEY%"
set "%~3=%KV_VALUE%"
exit /b 0

:StripQuotes
setlocal EnableDelayedExpansion
set "SQ_VALUE=%~1"
call :Trim "!SQ_VALUE!" SQ_VALUE

set "SQ_VALUE=!SQ_VALUE:"=!"
set "SQ_VALUE=!SQ_VALUE:'=!"

call :Trim "!SQ_VALUE!" SQ_VALUE
endlocal & set "%~2=%SQ_VALUE%"
exit /b 0

:Trim
setlocal EnableDelayedExpansion
set "TRIM_VALUE=%~1"

if not defined TRIM_VALUE (
    endlocal & set "%~2=" & exit /b 0
)

:TrimLeading
if defined TRIM_VALUE if "!TRIM_VALUE:~0,1!"==" " set "TRIM_VALUE=!TRIM_VALUE:~1!" & goto TrimLeading

:TrimTrailing
if defined TRIM_VALUE if "!TRIM_VALUE:~-1!"==" " set "TRIM_VALUE=!TRIM_VALUE:~0,-1!" & goto TrimTrailing

endlocal & set "%~2=%TRIM_VALUE%"
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

:WriteLog
setlocal EnableDelayedExpansion
set "LOG_MESSAGE=%~1"
call :BuildLogTimestamp LOG_TS
set "LOG_LINE=!LOG_TS! | !LOG_MESSAGE!"
echo(!LOG_LINE!
>> "%LOG_FILE%" echo(!LOG_LINE!
endlocal
exit /b 0

:BuildLogTimestamp
set "LOCAL_DT="
for /f "tokens=2 delims==" %%I in ('wmic os get LocalDateTime /value 2^>nul ^| find "="') do if not defined LOCAL_DT set "LOCAL_DT=%%I"

if defined LOCAL_DT (
    set "%~1=%LOCAL_DT:~0,4%-%LOCAL_DT:~4,2%-%LOCAL_DT:~6,2%T%LOCAL_DT:~8,2%:%LOCAL_DT:~10,2%:%LOCAL_DT:~12,2%"
    exit /b 0
)

set "%~1=%DATE% %TIME%"
exit /b 0

:usage
echo.
echo Usage:
echo   %~nx0 TASK ENV [SCHEMA] [--dry-run] [--preflight] [-ConfigPath path]
echo   %~nx0 -TaskName TASK -EnvironmentName ENV [-SchemaName SCHEMA] [-ConfigPath path] [-DryRun] [-Preflight]
echo.
echo Examples:
echo   %~nx0 TASK_123 DEV
echo   %~nx0 TASK_123 DEV APPUSER19
echo   %~nx0 TASK_123 DEV --dry-run
echo   %~nx0 TASK_123 DEV APPUSER19 --dry-run
echo   %~nx0 TASK_123 DEV --preflight
echo   %~nx0 TASK_123 DEV APPUSER19 --preflight
echo   %~nx0 TASK_123 DEV --preflight -ConfigPath .\config\exporter.yaml
echo   %~nx0 -TaskName TASK_123 -EnvironmentName DEV -SchemaName APPUSER19 -DryRun
echo   %~nx0 -TaskName TASK_123 -EnvironmentName DEV -SchemaName APPUSER19 -Preflight
echo.
exit /b 1
