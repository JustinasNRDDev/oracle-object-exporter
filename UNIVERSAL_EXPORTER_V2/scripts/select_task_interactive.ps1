[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$OutputBase,
    [Parameter(Mandatory = $true)][string]$SelectionFile
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $OutputBase -PathType Container)) {
    exit 2
}

$tasks = @(
    Get-ChildItem -LiteralPath $OutputBase -Directory |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "objects.txt") } |
        Sort-Object Name |
        Select-Object -ExpandProperty Name
)

if (-not $tasks -or $tasks.Count -eq 0) {
    exit 2
}

if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
    exit 4
}

$index = 0

while ($true) {
    Clear-Host
    Write-Host ""
    Write-Host ("Pasiekiami task aplanke: {0}" -f $OutputBase)
    Write-Host "Naudokite Up/Down rodykles ir Enter pasirinkimui. Esc - atsaukti."
    Write-Host ""

    for ($i = 0; $i -lt $tasks.Count; $i++) {
        if ($i -eq $index) {
            Write-Host (" [*] " + $tasks[$i]) -ForegroundColor Cyan
        }
        else {
            Write-Host (" [ ] " + $tasks[$i])
        }
    }

    $key = [Console]::ReadKey($true)

    if ($key.Key -eq [ConsoleKey]::UpArrow) {
        if ($index -gt 0) {
            $index--
        }
        continue
    }

    if ($key.Key -eq [ConsoleKey]::DownArrow) {
        if ($index -lt ($tasks.Count - 1)) {
            $index++
        }
        continue
    }

    if ($key.Key -eq [ConsoleKey]::Enter) {
        $selected = $tasks[$index]
        Set-Content -LiteralPath $SelectionFile -Value $selected -Encoding ASCII
        exit 0
    }

    if ($key.Key -eq [ConsoleKey]::Escape) {
        exit 3
    }
}
