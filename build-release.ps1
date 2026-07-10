[CmdletBinding()]
param(
    [string]$Version = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSCommandPath
$cleanupScript = Join-Path $root "cleanup-windows.ps1"
if ([string]::IsNullOrWhiteSpace($Version)) {
    $text = Get-Content -LiteralPath $cleanupScript -Raw -Encoding UTF8
    if ($text -match 'WinSweepVersion\s*=\s*"([^"]+)"') {
        $Version = $Matches[1]
    }
    else {
        $Version = "dev"
    }
}

$dist = Join-Path $root "dist"
$stageRoot = Join-Path $root ".release-stage"
$stage = Join-Path $stageRoot "WinSweep-v$Version"

New-Item -ItemType Directory -Path $dist -Force | Out-Null
if (Test-Path -LiteralPath $stageRoot) {
    $stageRootFull = [IO.Path]::GetFullPath($stageRoot)
    $rootFull = [IO.Path]::GetFullPath($root)
    if (-not $stageRootFull.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clear stage outside WinSweep root: $stageRootFull"
    }
    Remove-Item -LiteralPath $stageRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $stage -Force | Out-Null

$files = @(
    "cleanup-windows.ps1",
    "winsweep-config.json",
    "winsweep-menu.bat",
    "winsweep-ui.ps1",
    "winsweep-ui.bat",
    "scan-results.bat",
    "cleanup-safe-now.bat",
    "cleanup-gaming-now.bat",
    "cleanup-smart-now.bat",
    "cleanup-preview.bat",
    "cleanup-now.bat",
    "cleanup-deep-now.bat",
    "cleanup-emergency-now.bat",
    "guard-check-now.bat",
    "disk-space-report.ps1",
    "disk-space-report.bat",
    "disk-analyzer-lite.bat",
    "space-hog-report.ps1",
    "space-hog-report.bat",
    "open-report-in-chrome.ps1",
    "repair-powershell-shortcut.ps1",
    "repair-powershell-shortcut.bat",
    "manage-winsweep-settings.ps1",
    "manage-winsweep-settings.bat",
    "system-maintenance-check.ps1",
    "system-maintenance-check.bat",
    "show-cleanup-history.ps1",
    "show-cleanup-history.bat",
    "open-latest-report.ps1",
    "open-latest-report.bat",
    "open-cleanup-logs.bat",
    "build-release.ps1",
    "build-release.bat",
    "publish-release.ps1",
    "publish-release.bat",
    "save-github-token.ps1",
    "save-github-token.bat",
    "install-scheduled-cleanup.ps1",
    "install-scheduled-cleanup.bat",
    "uninstall-scheduled-cleanup.bat",
    "setup-desktop-folder.ps1",
    "setup-desktop-folder.bat",
    "extra-cache-paths.txt",
    "README.md",
    "CONFIG.md",
    "RELEASES.md"
)

foreach ($file in $files) {
    $source = Join-Path $root $file
    if (Test-Path -LiteralPath $source -PathType Leaf) {
        Copy-Item -LiteralPath $source -Destination (Join-Path $stage $file) -Force
    }
}

$zipPath = Join-Path $dist "WinSweep-v$Version.zip"
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}

Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zipPath -Force
Remove-Item -LiteralPath $stageRoot -Recurse -Force

Write-Host "Release zip created:"
Write-Host $zipPath
