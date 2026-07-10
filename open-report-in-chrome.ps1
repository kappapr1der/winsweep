[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Report file was not found: $Path"
}

$resolvedPath = (Resolve-Path -LiteralPath $Path).ProviderPath
$candidates = New-Object System.Collections.ArrayList

function Add-ChromeCandidate {
    param(
        [string]$BasePath,
        [string]$RelativePath
    )

    if ([string]::IsNullOrWhiteSpace($BasePath)) {
        return
    }

    [void]$candidates.Add((Join-Path $BasePath $RelativePath))
}

Add-ChromeCandidate -BasePath ${env:ProgramFiles} -RelativePath "Google\Chrome\Application\chrome.exe"
Add-ChromeCandidate -BasePath ${env:ProgramFiles(x86)} -RelativePath "Google\Chrome\Application\chrome.exe"
Add-ChromeCandidate -BasePath $env:LOCALAPPDATA -RelativePath "Google\Chrome\Application\chrome.exe"

$command = Get-Command chrome.exe -ErrorAction SilentlyContinue
if ($null -ne $command) {
    [void]$candidates.Add($command.Source)
}

$chromePath = @($candidates | Where-Object {
    -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_ -PathType Leaf)
} | Select-Object -Unique | Select-Object -First 1)

if ($chromePath.Count -gt 0) {
    Start-Process -FilePath $chromePath[0] -ArgumentList @("--new-window", ('"{0}"' -f $resolvedPath))
    Write-Host "Открываю HTML-отчёт в Google Chrome: $resolvedPath"
    return
}

Write-Warning "Google Chrome не найден. Открываю отчёт через браузер Windows по умолчанию."
Start-Process -FilePath $resolvedPath
