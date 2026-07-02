[CmdletBinding()]
param(
    [string]$FolderName = "WinSweep",
    [switch]$InstallSchedule,
    [switch]$BrowserCaches,
    [switch]$AppCaches,
    [switch]$SpotifyCache,
    [switch]$Registry,
    [switch]$ExtraPaths,
    [switch]$RecycleBin
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$sourceRoot = Split-Path -Parent $PSCommandPath
$desktop = [Environment]::GetFolderPath("DesktopDirectory")
if ([string]::IsNullOrWhiteSpace($desktop)) {
    $desktop = Join-Path $env:USERPROFILE "Desktop"
}

$targetRoot = Join-Path $desktop $FolderName
New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null

$files = @(
    "cleanup-windows.ps1",
    "install-scheduled-cleanup.ps1",
    "cleanup-now.bat",
    "cleanup-smart-now.bat",
    "cleanup-deep-now.bat",
    "cleanup-preview.bat",
    "open-cleanup-logs.bat",
    "install-scheduled-cleanup.bat",
    "uninstall-scheduled-cleanup.bat",
    "setup-desktop-folder.ps1",
    "setup-desktop-folder.bat",
    "extra-cache-paths.txt",
    "README.md"
)

foreach ($file in $files) {
    $source = Join-Path $sourceRoot $file
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        continue
    }

    $destination = Join-Path $targetRoot $file
    $sourceFull = (Resolve-Path -LiteralPath $source).ProviderPath
    $destinationFull = [IO.Path]::GetFullPath($destination)

    if ($sourceFull -ieq $destinationFull) {
        continue
    }

    Copy-Item -LiteralPath $source -Destination $destination -Force
}

Write-Host "Desktop folder is ready:"
Write-Host $targetRoot

if (-not $InstallSchedule) {
    Write-Host ""
    Write-Host "Schedule was not installed. Run install-scheduled-cleanup.bat from that folder when ready."
    return
}

$installer = Join-Path $targetRoot "install-scheduled-cleanup.ps1"
if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
    throw "Installer was not copied to the desktop folder."
}

$scheduleArgs = @{}
if ($BrowserCaches) {
    $scheduleArgs.BrowserCaches = $true
}
if ($AppCaches) {
    $scheduleArgs.AppCaches = $true
}
elseif ($SpotifyCache) {
    $scheduleArgs.SpotifyCache = $true
}
if ($Registry) {
    $scheduleArgs.Registry = $true
}
if ($ExtraPaths) {
    $scheduleArgs.ExtraPaths = $true
}
if ($RecycleBin) {
    $scheduleArgs.RecycleBin = $true
}

Write-Host ""
Write-Host "Installing scheduled tasks from the desktop folder..."
& $installer @scheduleArgs
