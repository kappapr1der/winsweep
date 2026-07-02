[CmdletBinding()]
param(
    [string]$LightNoon = "12:35",
    [string]$LightEvening = "22:45",
    [string]$DeepWeekly = "03:20",
    [ValidateSet("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")]
    [string]$DeepDay = "Sunday",
    [switch]$BrowserCaches,
    [switch]$AppCaches,
    [switch]$SpotifyCache,
    [switch]$Registry,
    [switch]$ExtraPaths,
    [switch]$RecycleBin
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $PSScriptRoot "cleanup-windows.ps1"
if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    throw "cleanup-windows.ps1 was not found next to this installer."
}

$taskPath = "\Codex Windows Cleanup\"
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$powershellPath = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$settings = New-ScheduledTaskSettingsSet `
    -Compatibility Win8 `
    -StartWhenAvailable `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Hours 2)
$principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Highest

function Register-CleanupTask {
    param(
        [string]$Name,
        [Microsoft.Management.Infrastructure.CimInstance]$Trigger,
        [string]$CleanupArgs,
        [string]$Description
    )

    $actionArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" $CleanupArgs"
    $action = New-ScheduledTaskAction -Execute $powershellPath -Argument $actionArgs
    $task = New-ScheduledTask -Action $action -Trigger $Trigger -Settings $settings -Principal $principal -Description $Description
    Register-ScheduledTask -TaskPath $taskPath -TaskName $Name -InputObject $task -Force | Out-Null
    Write-Host "Registered: $taskPath$Name"
}

$optionalArgs = ""
if ($BrowserCaches) {
    $optionalArgs += " -CleanBrowserCaches"
}
if ($AppCaches) {
    $optionalArgs += " -CleanAppCaches"
}
elseif ($SpotifyCache) {
    $optionalArgs += " -CleanSpotifyCache"
}
if ($Registry) {
    $optionalArgs += " -CleanRegistry"
}
if ($ExtraPaths) {
    $optionalArgs += " -CleanExtraPaths"
}
if ($RecycleBin) {
    $optionalArgs += " -ClearRecycleBin"
}

$noonTrigger = New-ScheduledTaskTrigger -Daily -At $LightNoon -RandomDelay (New-TimeSpan -Minutes 20)
$eveningTrigger = New-ScheduledTaskTrigger -Daily -At $LightEvening -RandomDelay (New-TimeSpan -Minutes 20)
$deepTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $DeepDay -At $DeepWeekly -RandomDelay (New-TimeSpan -Minutes 40)

Register-CleanupTask `
    -Name "Light Noon" `
    -Trigger $noonTrigger `
    -CleanupArgs "-TempOlderThanDays 2 -CacheOlderThanDays 7$optionalArgs" `
    -Description "Light cleanup of temp files and safe caches."

Register-CleanupTask `
    -Name "Light Evening" `
    -Trigger $eveningTrigger `
    -CleanupArgs "-TempOlderThanDays 2 -CacheOlderThanDays 7$optionalArgs" `
    -Description "Light cleanup of temp files and safe caches."

Register-CleanupTask `
    -Name "Deep Weekly" `
    -Trigger $deepTrigger `
    -CleanupArgs "-Deep -TempOlderThanDays 2 -CacheOlderThanDays 7$optionalArgs" `
    -Description "Weekly deeper cleanup including Windows component cleanup."

Write-Host ""
Write-Host "Done. Tasks run as: $currentUser"
Write-Host "Task Scheduler path: $taskPath"
Write-Host "Logs: $env:ProgramData\CodexWindowsCleanup\Logs"
