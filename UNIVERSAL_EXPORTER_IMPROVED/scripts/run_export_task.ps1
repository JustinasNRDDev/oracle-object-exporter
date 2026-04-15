[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$TaskName,
    [Parameter(Mandatory = $true)][string]$EnvironmentName,
    [string]$SchemaName = "",
    [string]$ConfigPath = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$script:ProjectRoot = Split-Path -Parent $PSScriptRoot
$script:Timestamp = Get-Date -Format "yyyyMMddTHHmmss"
$script:LogsDir = Join-Path $script:ProjectRoot "logs"
if (-not (Test-Path -LiteralPath $script:LogsDir)) {
    New-Item -Path $script:LogsDir -ItemType Directory | Out-Null
}
$script:LogFile = Join-Path $script:LogsDir ("bat_export_{0}.log" -f $script:Timestamp)

function Expand-EnvPath {
    param([string]$Value)

    if (-not $Value) { return "" }

    $expanded = [Environment]::ExpandEnvironmentVariables($Value)
    $pattern = [regex]"%([A-Za-z_][A-Za-z0-9_]*)%"

    return $pattern.Replace($expanded, {
        param($match)
        $varName = $match.Groups[1].Value

        $processValue = [Environment]::GetEnvironmentVariable($varName, "Process")
        if ($processValue) { return $processValue }

        foreach ($target in @("User", "Machine")) {
            $val = [Environment]::GetEnvironmentVariable($varName, $target)
            if ($val) { return $val }
        }

        return $match.Value
    })
}

function Write-Log {
    param([string]$Message)
    $line = "{0} | {1}" -f (Get-Date -Format "s"), $Message
    Write-Host $line
    Add-Content -Path $script:LogFile -Value $line
}

function ConvertTo-NormalizedYamlValue {
    param([string]$Raw)

    if ($null -eq $Raw) { return "" }
    $value = $Raw.Trim()

    if ($value.Length -ge 2) {
        if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
            $value = $value.Substring(1, $value.Length - 2)
        }
    }

    return $value.Trim()
}

function Split-ObjectNames {
    param([string]$Raw)

    $names = @()
    foreach ($piece in $Raw -split ",") {
        $name = $piece.Trim()
        if ($name) {
            $names += $name
        }
    }
    return $names
}

function New-StepMap {
    return @{
        packages = @()
        procedures = @()
        functions = @()
        types = @()
        table_ddl = @()
        view_ddl = @()
    }
}

function ConvertTo-StepKey {
    param([string]$Raw)

    $key = $Raw.Trim().ToLowerInvariant()

    switch ($key) {
        "packages" { return "packages" }
        "package" { return "packages" }
        "procedures" { return "procedures" }
        "procedure" { return "procedures" }
        "functions" { return "functions" }
        "function" { return "functions" }
        "types" { return "types" }
        "type" { return "types" }
        "tables" { return "table_ddl" }
        "table" { return "table_ddl" }
        "table_ddl" { return "table_ddl" }
        "views" { return "view_ddl" }
        "view" { return "view_ddl" }
        "view_ddl" { return "view_ddl" }
        default { throw "Nepalaikomas objekto tipas: '$Raw'" }
    }
}

function Read-ExporterConfig {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Nerastas config failas: $Path"
    }

    $config = @{
        defaults = @{
            sqlplus_executable = "sqlplus"
            nls_lang = ""
            ddl_source = "all"
            connection_file = ""
            export_extensions = @{
                packages = "pck"
                procedures = "prc"
                functions = "fnc"
                types = "typ"
                table_ddl = "sql"
                view_ddl = "sql"
            }
        }
        environments = @{}
    }

    $section = ""
    $inDefaultsExtensions = $false
    $currentEnv = ""
    $inEnvExtensions = $false

    foreach ($raw in Get-Content -LiteralPath $Path) {
        $line = $raw.TrimEnd()

        if ($line -match "^\s*$") { continue }
        if ($line -match "^\s*#") { continue }

        if ($line -match "^defaults:\s*$") {
            $section = "defaults"
            $inDefaultsExtensions = $false
            $currentEnv = ""
            $inEnvExtensions = $false
            continue
        }

        if ($line -match "^environments:\s*$") {
            $section = "environments"
            $inDefaultsExtensions = $false
            $currentEnv = ""
            $inEnvExtensions = $false
            continue
        }

        if ($section -eq "defaults") {
            if ($line -match "^\s{2}export_extensions:\s*$") {
                $inDefaultsExtensions = $true
                continue
            }

            if ($inDefaultsExtensions -and $line -match "^\s{4}([A-Za-z_]+):\s*(.+?)\s*$") {
                $step = ConvertTo-StepKey $matches[1]
                $value = ConvertTo-NormalizedYamlValue $matches[2]
                if ($value) {
                    $config.defaults.export_extensions[$step] = $value.ToLowerInvariant().TrimStart('.')
                }
                continue
            }

            if ($line -match "^\s{2}([A-Za-z_]+):\s*(.+?)\s*$") {
                $key = $matches[1]
                $value = ConvertTo-NormalizedYamlValue $matches[2]
                $inDefaultsExtensions = $false

                switch ($key) {
                    "sqlplus_executable" { $config.defaults.sqlplus_executable = $value }
                    "nls_lang" { $config.defaults.nls_lang = $value }
                    "ddl_source" { $config.defaults.ddl_source = $value.ToLowerInvariant() }
                    "connection_file" { $config.defaults.connection_file = $value }
                    default { }
                }
                continue
            }

            $inDefaultsExtensions = $false
            continue
        }

        if ($section -eq "environments") {
            if ($line -match "^\s{2}([A-Za-z0-9_]+):\s*$") {
                $currentEnv = $matches[1].ToUpperInvariant()
                if (-not $config.environments.ContainsKey($currentEnv)) {
                    $config.environments[$currentEnv] = @{
                        connection_file = ""
                        nls_lang = ""
                        ddl_source = ""
                        export_extensions = @{}
                    }
                }
                $inEnvExtensions = $false
                continue
            }

            if (-not $currentEnv) { continue }

            if ($line -match "^\s{4}export_extensions:\s*$") {
                $inEnvExtensions = $true
                continue
            }

            if ($inEnvExtensions -and $line -match "^\s{6}([A-Za-z_]+):\s*(.+?)\s*$") {
                $step = ConvertTo-StepKey $matches[1]
                $value = ConvertTo-NormalizedYamlValue $matches[2]
                if ($value) {
                    $config.environments[$currentEnv].export_extensions[$step] = $value.ToLowerInvariant().TrimStart('.')
                }
                continue
            }

            if ($line -match "^\s{4}([A-Za-z_]+):\s*(.+?)\s*$") {
                $key = $matches[1]
                $value = ConvertTo-NormalizedYamlValue $matches[2]
                $inEnvExtensions = $false

                switch ($key) {
                    "connection_file" { $config.environments[$currentEnv].connection_file = $value }
                    "nls_lang" { $config.environments[$currentEnv].nls_lang = $value }
                    "ddl_source" { $config.environments[$currentEnv].ddl_source = $value.ToLowerInvariant() }
                    default { }
                }
                continue
            }
        }
    }

    return $config
}

function Read-TaskObjects {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Nerastas task failas: $Path"
    }

    $result = @{}
    $currentEnv = ""
    $currentSchema = ""

    foreach ($raw in Get-Content -LiteralPath $Path) {
        $line = $raw.Trim()

        if (-not $line) { continue }
        if ($line.StartsWith("#") -or $line.StartsWith("--") -or $line.StartsWith(";")) { continue }

        if ($line -match "^\[(.+)\]$") {
            $currentEnv = $matches[1].Trim().ToUpperInvariant()
            $currentSchema = ""

            if (-not $result.ContainsKey($currentEnv)) {
                $result[$currentEnv] = @{
                    nls_lang = ""
                    schemas = @{}
                }
            }
            continue
        }

        if (-not $currentEnv) {
            throw "Task faile aptikta eilute uz [ENV] bloko: $line"
        }

        if ($line -notmatch "^	*([^:]+):\s*(.*)$") {
            throw "Neteisingas task eilutes formatas: $line"
        }

        $key = $matches[1].Trim().ToLowerInvariant()
        $value = $matches[2].Trim()

        if ($key -eq "nls_lang") {
            $result[$currentEnv].nls_lang = $value
            continue
        }

        if ($key -eq "schema") {
            $currentSchema = $value.Trim().ToUpperInvariant()
            if (-not $currentSchema) {
                throw "Task faile schema tuscia."
            }

            if (-not $result[$currentEnv].schemas.ContainsKey($currentSchema)) {
                $result[$currentEnv].schemas[$currentSchema] = New-StepMap
            }
            continue
        }

        if (-not $currentSchema) {
            throw "Task faile objekto eilute pateikta pries schema: $line"
        }

        $step = ConvertTo-StepKey $key
        $names = Split-ObjectNames $value
        if (-not $names) { continue }

        $existing = $result[$currentEnv].schemas[$currentSchema][$step]
        foreach ($name in $names) {
            if (-not ($existing -contains $name)) {
                $existing += $name
            }
        }
        $result[$currentEnv].schemas[$currentSchema][$step] = $existing
    }

    return $result
}

function Resolve-TaskFile {
    param([string]$TaskInput)

    $expanded = Expand-EnvPath $TaskInput
    $candidatePaths = @()

    if ([System.IO.Path]::IsPathRooted($expanded)) {
        $candidatePaths += $expanded
    }
    else {
        $candidatePaths += (Join-Path $script:ProjectRoot $expanded)
        $candidatePaths += (Join-Path $script:ProjectRoot (Join-Path "tasks" $expanded))
    }

    foreach ($candidate in $candidatePaths) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }

        if (Test-Path -LiteralPath $candidate -PathType Container) {
            $file = Join-Path $candidate "objects.txt"
            if (Test-Path -LiteralPath $file -PathType Leaf) {
                return (Resolve-Path -LiteralPath $file).Path
            }
        }
    }

    throw "Task failas nerastas. Patikrinkite TASK pavadinima arba kelia: $TaskInput"
}

function Resolve-ConnectionString {
    param(
        [hashtable]$Config,
        [string]$EnvName
    )

    $connectionFile = ""

    if ($Config.environments.ContainsKey($EnvName)) {
        $connectionFile = $Config.environments[$EnvName].connection_file
    }

    if (-not $connectionFile) {
        $connectionFile = $Config.defaults.connection_file
    }

    if (-not $connectionFile) {
        $connectionFile = "%ORACLE19_CONN%\\conn{0}.conf" -f $EnvName
    }

    $expanded = Expand-EnvPath $connectionFile
    if (-not [System.IO.Path]::IsPathRooted($expanded)) {
        $expanded = Join-Path $script:ProjectRoot $expanded
    }

    if (-not (Test-Path -LiteralPath $expanded)) {
        throw "Nerastas connection failas: $expanded"
    }

    $firstLine = Get-Content -LiteralPath $expanded | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1
    if (-not $firstLine) {
        throw "Tuscias connection failas: $expanded"
    }

    return $firstLine.Trim()
}

$stepOrder = @("packages", "procedures", "functions", "types", "table_ddl", "view_ddl")

if (-not $ConfigPath) {
    $ConfigPath = Join-Path $script:ProjectRoot "config\exporter.yaml"
}

$config = Read-ExporterConfig -Path $ConfigPath
$envName = $EnvironmentName.ToUpperInvariant()

if (-not $config.environments.ContainsKey($envName)) {
    throw "Aplinka '$envName' nerasta config faile: $ConfigPath"
}

$taskFile = Resolve-TaskFile -TaskInput $TaskName
$taskData = Read-TaskObjects -Path $taskFile

if (-not $taskData.ContainsKey($envName)) {
    throw "Task faile nerasta aplinkos sekcija [$envName]: $taskFile"
}

$taskLabel = Split-Path -Leaf (Split-Path -Parent $taskFile)
$taskEnv = $taskData[$envName]

$selectedSchemas = @()
if ($SchemaName) {
    $schemaUpper = $SchemaName.Trim().ToUpperInvariant()
    if (-not $taskEnv.schemas.ContainsKey($schemaUpper)) {
        throw "Schema '$schemaUpper' nerasta task faile [$envName]."
    }
    $selectedSchemas += $schemaUpper
}
else {
    $selectedSchemas += ($taskEnv.schemas.Keys | Sort-Object)
}

$extensions = @{}
foreach ($step in $stepOrder) {
    $extensions[$step] = $config.defaults.export_extensions[$step]
}
foreach ($kv in $config.environments[$envName].export_extensions.GetEnumerator()) {
    $extensions[$kv.Key] = $kv.Value
}

$ddlSource = $config.environments[$envName].ddl_source
if (-not $ddlSource) { $ddlSource = $config.defaults.ddl_source }
if (-not $ddlSource) { $ddlSource = "all" }
$ddlSource = $ddlSource.ToLowerInvariant()
if ($ddlSource -ne "dba") { $ddlSource = "all" }

$nlsLang = $taskEnv.nls_lang
if (-not $nlsLang) { $nlsLang = $config.environments[$envName].nls_lang }
if (-not $nlsLang) { $nlsLang = $config.defaults.nls_lang }
if ($nlsLang) {
    $env:NLS_LANG = $nlsLang
}

$sqlplusExecutable = $config.defaults.sqlplus_executable
if (-not $sqlplusExecutable) { $sqlplusExecutable = "sqlplus" }

$connection = Resolve-ConnectionString -Config $config -EnvName $envName

$outputRoot = Join-Path $script:ProjectRoot (Join-Path "EXPORTED_OBJECTS" (Join-Path $taskLabel (Join-Path $envName $script:Timestamp)))
New-Item -Path $outputRoot -ItemType Directory -Force | Out-Null

Write-Log ("RUN START | task={0} env={1} timestamp={2}" -f $taskLabel, $envName, $script:Timestamp)
Write-Log ("CONFIG | {0}" -f (Resolve-Path -LiteralPath $ConfigPath).Path)
Write-Log ("TASK FILE | {0}" -f $taskFile)
Write-Log ("DDL SOURCE | {0}" -f $ddlSource)
if ($DryRun) {
    Write-Log "MODE | DRY-RUN"
}

$summaryTotal = 0
$summaryExecuted = 0
$summarySkipped = 0

function Invoke-SqlPlus {
    param(
        [string]$ScriptName,
        [string[]]$Arguments
    )

    $scriptPath = Join-Path $script:ProjectRoot (Join-Path "scripts" $ScriptName)
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        throw "Nerastas SQL skriptas: $scriptPath"
    }

    $display = "{0} <connection-redacted> @{1} {2}" -f $sqlplusExecutable, $scriptPath, ($Arguments -join " ")
    Write-Log ("EXECUTE | {0}" -f $display)

    if ($DryRun) {
        return
    }

    # Ensure sqlplus terminates after script execution instead of staying interactive.
    $output = "exit" | & $sqlplusExecutable -L $connection ("@{0}" -f $scriptPath) @Arguments 2>&1
    foreach ($line in $output) {
        $text = [string]$line
        Write-Host $text
        Add-Content -Path $script:LogFile -Value $text
    }

    if ($LASTEXITCODE -ne 0) {
        throw "sqlplus baigesi su klaida ($LASTEXITCODE) vykdant $ScriptName"
    }
}

foreach ($schema in $selectedSchemas) {
    $schemaMap = $taskEnv.schemas[$schema]
    $schemaRoot = Join-Path $outputRoot $schema

    foreach ($step in $stepOrder) {
        $summaryTotal += 1
        $objects = $schemaMap[$step]

        if (-not $objects -or $objects.Count -eq 0) {
            Write-Log ("SKIP | {0}.{1} | tuscias objektu sarasas" -f $schema, $step)
            $summarySkipped += 1
            continue
        }

        $saveDir = $schemaRoot
        if ($step -eq "types") {
            $saveDir = Join-Path $schemaRoot "TYPES"
        }
        elseif ($step -eq "table_ddl") {
            $saveDir = Join-Path $schemaRoot "TABLES"
        }
        elseif ($step -eq "view_ddl") {
            $saveDir = Join-Path $schemaRoot "VIEWS"
        }

        New-Item -Path $saveDir -ItemType Directory -Force | Out-Null

        Write-Log ("START | schema={0} step={1} objects={2}" -f $schema, $step, $objects.Count)

        foreach ($obj in $objects) {
            switch ($step) {
                "packages" {
                    Invoke-SqlPlus -ScriptName "validate_and_export_package.sql" -Arguments @($saveDir, $obj, "SPEC_AND_BODY", $schema, $extensions[$step])
                }
                "procedures" {
                    Invoke-SqlPlus -ScriptName "validate_and_export_procedure.sql" -Arguments @($saveDir, $obj, $schema, $extensions[$step])
                }
                "functions" {
                    Invoke-SqlPlus -ScriptName "validate_and_export_function.sql" -Arguments @($saveDir, $obj, $schema, $extensions[$step])
                }
                "types" {
                    Invoke-SqlPlus -ScriptName "validate_and_export_type.sql" -Arguments @($saveDir, $obj, $schema, $extensions[$step])
                }
                "table_ddl" {
                    $ddlScript = if ($ddlSource -eq "dba") { "generate_tbl_ddl_dba.sql" } else { "generate_tbl_ddl.sql" }
                    Invoke-SqlPlus -ScriptName $ddlScript -Arguments @($saveDir, $schema, $obj, $extensions[$step])
                }
                "view_ddl" {
                    $ddlScript = if ($ddlSource -eq "dba") { "generate_view_ddl_dba.sql" } else { "generate_view_ddl.sql" }
                    Invoke-SqlPlus -ScriptName $ddlScript -Arguments @($saveDir, $schema, $obj, $extensions[$step])
                }
            }
        }

        $summaryExecuted += 1
        Write-Log ("DONE | schema={0} step={1}" -f $schema, $step)
    }
}

Write-Log ("RUN END | total={0} executed={1} skipped={2}" -f $summaryTotal, $summaryExecuted, $summarySkipped)
Write-Log ("LOG FILE | {0}" -f $script:LogFile)
