[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$folder = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Windows PowerShell"
$powershellPath = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"

if (-not (Test-Path -LiteralPath $powershellPath -PathType Leaf)) {
    throw "Windows PowerShell executable was not found: $powershellPath"
}

New-Item -ItemType Directory -Path $folder -Force | Out-Null
$shell = New-Object -ComObject WScript.Shell

function New-PowerShellShortcut {
    param(
        [string]$Name,
        [string]$Arguments,
        [string]$Description
    )

    $path = Join-Path $folder $Name
    $shortcut = $shell.CreateShortcut($path)
    $shortcut.TargetPath = $powershellPath
    $shortcut.Arguments = $Arguments
    $shortcut.WorkingDirectory = $env:USERPROFILE
    $shortcut.IconLocation = "$powershellPath,0"
    $shortcut.Description = $Description
    $shortcut.Save()
    return $path
}

$standard = New-PowerShellShortcut `
    -Name "Windows PowerShell 5.1.lnk" `
    -Arguments "-NoLogo" `
    -Description "Windows PowerShell 5.1"

$admin = New-PowerShellShortcut `
    -Name "Windows PowerShell 5.1 (Admin).lnk" `
    -Arguments ("-NoLogo -NoProfile -Command `"Start-Process -FilePath '{0}' -Verb RunAs`"" -f $powershellPath) `
    -Description "Windows PowerShell 5.1 with administrator rights"

Write-Host "Ярлыки Windows PowerShell восстановлены:" -ForegroundColor Green
Write-Host $standard
Write-Host $admin
