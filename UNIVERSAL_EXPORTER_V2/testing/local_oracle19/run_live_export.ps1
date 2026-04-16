$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Resolve-Path (Join-Path $scriptDir "..\..")

$oracleConnRoot = $env:ORACLE19_CONN
if ([string]::IsNullOrWhiteSpace($oracleConnRoot)) {
    $oracleConnRoot = [Environment]::GetEnvironmentVariable('ORACLE19_CONN', 'User')
}

if ([string]::IsNullOrWhiteSpace($oracleConnRoot)) {
    throw "ORACLE19_CONN is not set in session or User environment variables."
}

$connFile = Join-Path $oracleConnRoot 'connDEV.conf'
if (-not (Test-Path $connFile)) {
    throw "Connection file not found: $connFile"
}

$env:ORACLE19_CONN = $oracleConnRoot

Push-Location $projectRoot
try {
    $entry = Join-Path $projectRoot 'oracle_exporter_task.bat'
    if (-not (Test-Path $entry)) {
        throw "Nerastas entrypoint: $entry"
    }

    $taskDir = Resolve-Path (Join-Path $scriptDir 'TASK_LOCAL19')
    $taskDirPath = $taskDir.Path

    & $entry -TaskName "$taskDirPath" -EnvironmentName LOCAL19 -ConfigPath config/exporter.yaml
    if ($LASTEXITCODE -ne 0) {
        throw "oracle_exporter_task.bat LOCAL19 baigesi su klaida (code=$LASTEXITCODE)."
    }
}
finally {
    Pop-Location
}

Write-Host "LOCAL19 eksportas įvykdytas sėkmingai."
