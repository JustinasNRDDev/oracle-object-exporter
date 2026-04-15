$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Resolve-Path (Join-Path $scriptDir "..\..")

$oracleConnRoot = $env:ORACLE19_CONN
if ([string]::IsNullOrWhiteSpace($oracleConnRoot)) {
    $oracleConnRoot = [Environment]::GetEnvironmentVariable('ORACLE19_CONN', 'User')
}

if ([string]::IsNullOrWhiteSpace($oracleConnRoot)) {
    throw "ORACLE19_CONN nenurodytas nei session, nei User aplinkos kintamuosiuose."
}

$connFile = Join-Path $oracleConnRoot 'connDEV.conf'
if (-not (Test-Path $connFile)) {
    throw "Nerastas connection failas: $connFile"
}

$connection = (Get-Content -Path $connFile -TotalCount 1).Trim()
if ([string]::IsNullOrWhiteSpace($connection)) {
    throw "Tuščias connection string faile: $connFile"
}

Push-Location $projectRoot
try {
    sqlplus $connection @testing/local_oracle19/sql/cleanup_test_objects.sql
    if ($LASTEXITCODE -ne 0) {
        throw "cleanup_test_objects.sql baigėsi su klaida (code=$LASTEXITCODE)."
    }
}
finally {
    Pop-Location
}

Write-Host "Testiniai objektai išvalyti sėkmingai."
