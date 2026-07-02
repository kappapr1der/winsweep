[CmdletBinding()]
param(
    [string]$GuardStart = "00:15",
    [int]$GuardEveryHours = 3,
    [int]$LowFreeGB = 35,
    [int]$LowFreePercent = 18,
    [string]$DeepWeekly = "03:20",
    [ValidateSet("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")]
    [string]$DeepDay = "Sunday",
    [switch]$BrowserCaches,
    [switch]$AppCaches,
    [switch]$SpotifyCache,
    [switch]$Registry,
    [switch]$ExtraPaths,
    [switch]$DeveloperCaches,
    [switch]$GameCaches,
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

try {
    Get-ScheduledTask -TaskPath $taskPath -ErrorAction SilentlyContinue |
        Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue
}
catch {
    Write-Warning "Could not clear old tasks under $taskPath. $($_.Exception.Message)"
}

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
if ($DeveloperCaches) {
    $optionalArgs += " -CleanDeveloperCaches"
}
if ($GameCaches) {
    $optionalArgs += " -CleanGameCaches"
}
if ($RecycleBin) {
    $optionalArgs += " -ClearRecycleBin"
}

$guardTrigger = New-ScheduledTaskTrigger -Daily -At $GuardStart -RandomDelay (New-TimeSpan -Minutes 15)
$guardRepetition = New-CimInstance -ClassName MSFT_TaskRepetitionPattern -Namespace Root/Microsoft/Windows/TaskScheduler -ClientOnly
$guardRepetition.Interval = "PT${GuardEveryHours}H"
$guardRepetition.Duration = "P1D"
$guardTrigger.Repetition = $guardRepetition
$logonTrigger = New-ScheduledTaskTrigger -AtLogOn -RandomDelay (New-TimeSpan -Minutes 5)
$deepTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $DeepDay -At $DeepWeekly -RandomDelay (New-TimeSpan -Minutes 40)

Register-CleanupTask `
    -Name "Pressure Guard" `
    -Trigger $guardTrigger `
    -CleanupArgs "-SmartGuard -AggressiveSafe -MinFreeGB $LowFreeGB -MinFreePercent $LowFreePercent -TempOlderThanDays 0 -CacheOlderThanDays 1$optionalArgs" `
    -Description "Checks disk pressure every few hours and cleans safe caches only when free space is low."

Register-CleanupTask `
    -Name "Startup Guard" `
    -Trigger $logonTrigger `
    -CleanupArgs "-SmartGuard -AggressiveSafe -MinFreeGB $LowFreeGB -MinFreePercent $LowFreePercent -TempOlderThanDays 0 -CacheOlderThanDays 1$optionalArgs" `
    -Description "Checks disk pressure shortly after logon and cleans safe caches only when free space is low."

Register-CleanupTask `
    -Name "Deep Weekly" `
    -Trigger $deepTrigger `
    -CleanupArgs "-Deep -AggressiveSafe -TempOlderThanDays 1 -CacheOlderThanDays 3$optionalArgs" `
    -Description "Weekly deeper cleanup including Windows component cleanup."

Write-Host ""
Write-Host "Done. Tasks run as: $currentUser"
Write-Host "Task Scheduler path: $taskPath"
Write-Host "Pressure guard: every $GuardEveryHours hour(s), starting around $GuardStart, only below $LowFreeGB GB or $LowFreePercent% free."
Write-Host "Deep cleanup: $DeepDay around $DeepWeekly."
Write-Host "Logs: $env:ProgramData\CodexWindowsCleanup\Logs"
