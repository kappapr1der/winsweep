[CmdletBinding()]
param(
    [int]$Top = 10,
    [string]$LogDir = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

function Resolve-LogDirs {
    param([string]$Preferred)

    $dirs = New-Object System.Collections.ArrayList
    if (-not [string]::IsNullOrWhiteSpace($Preferred)) {
        [void]$dirs.Add($Preferred)
    }
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramData)) {
        [void]$dirs.Add((Join-Path $env:ProgramData "CodexWindowsCleanup\Logs"))
    }
    if (-not [string]::IsNullOrWhiteSpace($env:TEMP)) {
        [void]$dirs.Add((Join-Path $env:TEMP "CodexWindowsCleanup\Logs"))
    }
    return @($dirs | Select-Object -Unique)
}

function Get-FirstMatch {
    param(
        [string[]]$Lines,
        [string]$Pattern
    )

    foreach ($line in $Lines) {
        if ($line -match $Pattern) {
            return $Matches[1]
        }
    }
    return ""
}

function Get-AmountFromLines {
    param([string[]]$Lines)

    foreach ($line in $Lines) {
        if ($line -match "about (.*?), failures") {
            return $Matches[1]
        }
    }
    return ""
}

$logs = New-Object System.Collections.ArrayList
foreach ($dir in (Resolve-LogDirs -Preferred $LogDir)) {
    if (-not (Test-Path -LiteralPath $dir -PathType Container -ErrorAction SilentlyContinue)) {
        continue
    }

    Get-ChildItem -LiteralPath $dir -Filter "cleanup-*.log" -File -ErrorAction SilentlyContinue |
        ForEach-Object { [void]$logs.Add($_) }
}

$logs = @($logs | Sort-Object LastWriteTime -Descending | Select-Object -First $Top)

Write-Host ""
Write-Host "== WinSweep history ==" -ForegroundColor Green
if ($logs.Count -eq 0) {
    Write-Host "No cleanup logs found." -ForegroundColor Yellow
    return
}

$rows = foreach ($log in $logs) {
    $lines = @(Get-Content -LiteralPath $log.FullName -ErrorAction SilentlyContinue)
    $start = @($lines | Where-Object { $_ -match "Windows cleanup started" } | Select-Object -First 1)
    $finish = @($lines | Where-Object { $_ -match "Windows cleanup finished|Analyze finished|Preview finished" } | Select-Object -Last 1)

    $profile = Get-FirstMatch -Lines $start -Pattern "Profile=([^ ]+)"
    $version = Get-FirstMatch -Lines $start -Pattern "Version=([^ ]+)"
    $mode = if ($start -match "Analyze=True") {
        "Analyze"
    }
    elseif ($start -match "DryRun=True") {
        "Preview"
    }
    else {
        "Clean"
    }
    $amount = Get-AmountFromLines -Lines $finish
    $failures = Get-FirstMatch -Lines $finish -Pattern "failures: ([0-9]+)"

    [pscustomobject]@{
        Time = $log.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
        Mode = $mode
        Profile = $profile
        Amount = $amount
        Failures = $failures
        Version = $version
        Log = $log.FullName
    }
}

$rows | Format-Table -AutoSize
