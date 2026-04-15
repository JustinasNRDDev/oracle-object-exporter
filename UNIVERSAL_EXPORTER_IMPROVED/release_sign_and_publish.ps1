[CmdletBinding()]
param(
    [string]$SourceProjectPath,
    [string]$RuntimeProjectPath,
    [switch]$SkipBuild,
    [switch]$NoSign,
    [switch]$SkipPublishToRuntime,
    [string]$PfxPath,
    [SecureString]$PfxPassword,
    [string]$CertThumbprint,
    [string]$TimestampUrl = "http://timestamp.digicert.com",
    [string]$SignToolPath,
    [switch]$UseMachineStore
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($SourceProjectPath)) {
    if ($PSScriptRoot) {
        $SourceProjectPath = $PSScriptRoot
    }
    elseif ($PSCommandPath) {
        $SourceProjectPath = Split-Path -Parent $PSCommandPath
    }
    else {
        $SourceProjectPath = (Get-Location).Path
    }
}

if ([string]::IsNullOrWhiteSpace($RuntimeProjectPath)) {
    $RuntimeProjectPath = Join-Path (Split-Path -Parent $SourceProjectPath) "UNIVERSAL_EXPORTER_V1"
}

function Write-Step {
    param([string]$Message)
    Write-Host "[release] $Message" -ForegroundColor Cyan
}

function Resolve-SignToolPath {
    param([string]$ExplicitPath)

    if ($ExplicitPath) {
        if (Test-Path -LiteralPath $ExplicitPath) {
            return (Resolve-Path -LiteralPath $ExplicitPath).Path
        }
        throw "SignTool nerastas pagal nurodyta kelia: $ExplicitPath"
    }

    $cmd = Get-Command signtool -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    $candidates = Get-ChildItem "C:\Program Files (x86)\Windows Kits\10\bin\*\x64\signtool.exe" -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending

    if ($candidates) {
        return $candidates[0].FullName
    }

    throw "SignTool nerastas. Irenkite Windows SDK Signing Tools arba naudokite -NoSign."
}

function Convert-SecureStringToPlainText {
    param([SecureString]$SecureValue)

    if ($null -eq $SecureValue) {
        return ""
    }

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureValue)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

$sourcePath = (Resolve-Path -LiteralPath $SourceProjectPath).Path
$sourceExe = Join-Path $sourcePath "oracle_exporter.exe"
$buildScript = Join-Path $sourcePath "build_oracle_exporter_exe.bat"

if (-not $SkipBuild) {
    if (-not (Test-Path -LiteralPath $buildScript)) {
        throw "Build skriptas nerastas: $buildScript"
    }

    Write-Step "Vykdomas build..."
    Push-Location $sourcePath
    try {
        & $buildScript
        if ($LASTEXITCODE -ne 0) {
            throw "Build nepavyko. Exit code: $LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
    }
}
else {
    Write-Step "Build praleistas (-SkipBuild)."
}

if (-not (Test-Path -LiteralPath $sourceExe)) {
    throw "Po build nerastas failas: $sourceExe"
}

$targetExe = $sourceExe
$runtimePath = ""

if (-not $SkipPublishToRuntime) {
    if (-not (Test-Path -LiteralPath $RuntimeProjectPath)) {
        throw "Runtime aplankas nerastas: $RuntimeProjectPath"
    }

    $runtimePath = (Resolve-Path -LiteralPath $RuntimeProjectPath).Path
    $runtimeExe = Join-Path $runtimePath "oracle_exporter.exe"

    Copy-Item -LiteralPath $sourceExe -Destination $runtimeExe -Force
    $targetExe = $runtimeExe

    Write-Step "Exe nukopijuotas i runtime aplanka: $runtimeExe"
}
else {
    Write-Step "Kopijavimas i runtime aplanka praleistas (-SkipPublishToRuntime)."
}

if (-not $NoSign) {
    if ([string]::IsNullOrWhiteSpace($PfxPath) -and [string]::IsNullOrWhiteSpace($CertThumbprint)) {
        throw "Pasirasymui nurodykite -PfxPath arba -CertThumbprint, arba naudokite -NoSign."
    }

    $signTool = Resolve-SignToolPath -ExplicitPath $SignToolPath
    Write-Step "Naudojamas SignTool: $signTool"

    $signArgs = @("sign", "/fd", "SHA256", "/td", "SHA256", "/tr", $TimestampUrl, "/v")

    if (-not [string]::IsNullOrWhiteSpace($PfxPath)) {
        $resolvedPfx = (Resolve-Path -LiteralPath $PfxPath).Path
        $signArgs += @("/f", $resolvedPfx)

        if ($null -ne $PfxPassword) {
            $plainPassword = Convert-SecureStringToPlainText -SecureValue $PfxPassword
            if ($plainPassword) {
                $signArgs += @("/p", $plainPassword)
            }
        }
    }
    else {
        $thumbprint = ($CertThumbprint -replace "\s", "")
        $signArgs += @("/sha1", $thumbprint)
        if ($UseMachineStore) {
            $signArgs += "/sm"
        }
    }

    $signArgs += $targetExe

    Write-Step "Pasirasomas failas..."
    & $signTool @signArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Pasirasymas nepavyko. Exit code: $LASTEXITCODE"
    }

    Write-Step "Tikrinamas parasas..."
    & $signTool verify /pa /v $targetExe
    if ($LASTEXITCODE -ne 0) {
        throw "Paraso verifikacija nepavyko. Exit code: $LASTEXITCODE"
    }
}
else {
    Write-Step "Pasirasymas praleistas (-NoSign)."
}

$signature = Get-AuthenticodeSignature -FilePath $targetExe
$hashValue = (Get-FileHash -LiteralPath $targetExe -Algorithm SHA256).Hash

$releaseDir = Join-Path $sourcePath "release"
if (-not (Test-Path -LiteralPath $releaseDir)) {
    New-Item -Path $releaseDir -ItemType Directory | Out-Null
}

$hashFile = Join-Path $releaseDir "oracle_exporter.sha256.txt"
$reportFile = Join-Path $releaseDir "oracle_exporter.release.json"

Set-Content -Path $hashFile -Value "$hashValue  oracle_exporter.exe"

$report = [ordered]@{
    generatedAt = (Get-Date).ToString("s")
    sourceProjectPath = $sourcePath
    runtimeProjectPath = if ($runtimePath) { $runtimePath } else { "<skipped>" }
    targetExe = $targetExe
    sha256 = $hashValue
    signatureStatus = "$($signature.Status)"
    signatureStatusMessage = "$($signature.StatusMessage)"
    signed = -not $NoSign
}

$report | ConvertTo-Json -Depth 4 | Set-Content -Path $reportFile

Write-Step "Ataskaitos sukurtos:"
Write-Host " - $hashFile"
Write-Host " - $reportFile"
Write-Host ""
Write-Host "SHA256: $hashValue"
Write-Host "Signature status: $($signature.Status)"
Write-Host "Target exe: $targetExe"
