[CmdletBinding()]
param(
    [switch]$Deep,
    [switch]$DryRun,
    [switch]$Analyze,
    [switch]$SmartGuard,
    [switch]$AggressiveSafe,
    [switch]$CleanBrowserCaches,
    [switch]$CleanAppCaches,
    [switch]$CleanSpotifyCache,
    [switch]$CleanRegistry,
    [switch]$CleanExtraPaths,
    [switch]$CleanDeveloperCaches,
    [switch]$CleanGameCaches,
    [switch]$ClearRecycleBin,
    [switch]$Detailed,
    [switch]$Quiet,
    [switch]$OpenReport,
    [int]$MinFreeGB = 35,
    [int]$MinFreePercent = 18,
    [string]$GuardDrive = "",
    [int]$TempOlderThanDays = 2,
    [int]$CacheOlderThanDays = 7,
    [int]$LogRetentionDays = 30,
    [ValidateSet("", "Safe", "Gaming", "Deep", "Emergency")]
    [string]$Profile = "",
    [string]$ExtraPathsFile = "",
    [string]$LogDir = "",
    [string]$ConfigPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$script:WinSweepVersion = "0.4.3"
$script:DeletedBytes = [int64]0
$script:DeletedItems = 0
$script:PotentialBytes = [int64]0
$script:PotentialItems = 0
$script:FailedItems = 0
$script:TargetResults = New-Object System.Collections.ArrayList
$script:CloseHints = @{}
$script:PreflightResults = New-Object System.Collections.ArrayList
$script:HtmlReportPath = ""
$script:ConfigSource = ""
$script:ConfigLoadWarning = ""
$script:CliParameters = @{}
foreach ($key in $PSBoundParameters.Keys) {
    $script:CliParameters[$key] = $true
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ConfigProperty {
    param(
        $Object,
        [string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Resolve-WinSweepPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ""
    }

    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    if ([IO.Path]::IsPathRooted($expanded)) {
        return $expanded
    }

    return (Join-Path $PSScriptRoot $expanded)
}

function Set-StringFromConfig {
    param(
        [string]$Name,
        $Value
    )

    if ($null -eq $Value -or $script:CliParameters.ContainsKey($Name)) {
        return
    }

    Set-Variable -Name $Name -Value ([string]$Value) -Scope Script
}

function Set-IntFromConfig {
    param(
        [string]$Name,
        $Value
    )

    if ($null -eq $Value -or $script:CliParameters.ContainsKey($Name)) {
        return
    }

    Set-Variable -Name $Name -Value ([int]$Value) -Scope Script
}

function Set-SwitchFromConfig {
    param(
        [string]$Name,
        $Value
    )

    if ($null -eq $Value -or $script:CliParameters.ContainsKey($Name)) {
        return
    }

    Set-Variable -Name $Name -Value ([bool]$Value) -Scope Script
}

function New-LogFolder {
    param([string]$PreferredLogDir)

    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($PreferredLogDir)) {
        $candidates += $PreferredLogDir
    }
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramData)) {
        $candidates += (Join-Path $env:ProgramData "CodexWindowsCleanup\Logs")
    }
    if (-not [string]::IsNullOrWhiteSpace($env:TEMP)) {
        $candidates += (Join-Path $env:TEMP "CodexWindowsCleanup\Logs")
    }

    foreach ($candidate in $candidates) {
        try {
            New-Item -ItemType Directory -Path $candidate -Force -ErrorAction Stop | Out-Null
            $testPath = Join-Path $candidate ".winsweep-write-test"
            Set-Content -LiteralPath $testPath -Value "ok" -Encoding ASCII -ErrorAction Stop
            Remove-Item -LiteralPath $testPath -Force -ErrorAction SilentlyContinue
            return $candidate
        }
        catch {
            continue
        }
    }

    throw "Could not create a log directory."
}

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $defaultConfigPath = Join-Path $PSScriptRoot "winsweep-config.json"
    if (Test-Path -LiteralPath $defaultConfigPath -PathType Leaf -ErrorAction SilentlyContinue) {
        $ConfigPath = $defaultConfigPath
    }
}
else {
    $ConfigPath = Resolve-WinSweepPath -Path $ConfigPath
}

$config = $null
if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
    try {
        if (Test-Path -LiteralPath $ConfigPath -PathType Leaf -ErrorAction Stop) {
            $configFullPath = (Resolve-Path -LiteralPath $ConfigPath -ErrorAction Stop).ProviderPath
            $config = Get-Content -LiteralPath $configFullPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $script:ConfigSource = $configFullPath
        }
        elseif ($script:CliParameters.ContainsKey("ConfigPath")) {
            $script:ConfigLoadWarning = "Config file was not found: $ConfigPath"
        }
    }
    catch {
        $script:ConfigLoadWarning = "Could not read config file: $ConfigPath. $($_.Exception.Message)"
    }
}

if ($null -ne $config) {
    $configuredProfile = Get-ConfigProperty -Object $config -Name "defaultProfile"
    if ($null -ne $configuredProfile -and -not $script:CliParameters.ContainsKey("Profile")) {
        $validProfiles = @("", "Safe", "Gaming", "Deep", "Emergency")
        if ($validProfiles -contains ([string]$configuredProfile)) {
            $Profile = [string]$configuredProfile
        }
        else {
            $script:ConfigLoadWarning = "Config defaultProfile is invalid: $configuredProfile"
        }
    }

    $thresholds = Get-ConfigProperty -Object $config -Name "thresholds"
    Set-IntFromConfig -Name "MinFreeGB" -Value (Get-ConfigProperty -Object $thresholds -Name "minFreeGB")
    Set-IntFromConfig -Name "MinFreePercent" -Value (Get-ConfigProperty -Object $thresholds -Name "minFreePercent")
    Set-IntFromConfig -Name "TempOlderThanDays" -Value (Get-ConfigProperty -Object $thresholds -Name "tempOlderThanDays")
    Set-IntFromConfig -Name "CacheOlderThanDays" -Value (Get-ConfigProperty -Object $thresholds -Name "cacheOlderThanDays")
    Set-IntFromConfig -Name "LogRetentionDays" -Value (Get-ConfigProperty -Object $thresholds -Name "logRetentionDays")

    $features = Get-ConfigProperty -Object $config -Name "features"
    Set-SwitchFromConfig -Name "AggressiveSafe" -Value (Get-ConfigProperty -Object $features -Name "aggressiveSafe")
    Set-SwitchFromConfig -Name "CleanBrowserCaches" -Value (Get-ConfigProperty -Object $features -Name "browserCaches")
    Set-SwitchFromConfig -Name "CleanAppCaches" -Value (Get-ConfigProperty -Object $features -Name "appCaches")
    Set-SwitchFromConfig -Name "CleanSpotifyCache" -Value (Get-ConfigProperty -Object $features -Name "spotifyCache")
    Set-SwitchFromConfig -Name "CleanRegistry" -Value (Get-ConfigProperty -Object $features -Name "registry")
    Set-SwitchFromConfig -Name "CleanExtraPaths" -Value (Get-ConfigProperty -Object $features -Name "extraPaths")
    Set-SwitchFromConfig -Name "CleanDeveloperCaches" -Value (Get-ConfigProperty -Object $features -Name "developerCaches")
    Set-SwitchFromConfig -Name "CleanGameCaches" -Value (Get-ConfigProperty -Object $features -Name "gameCaches")
    Set-SwitchFromConfig -Name "ClearRecycleBin" -Value (Get-ConfigProperty -Object $features -Name "clearRecycleBin")

    $paths = Get-ConfigProperty -Object $config -Name "paths"
    $configuredGuardDrive = Get-ConfigProperty -Object $paths -Name "guardDrive"
    if ($null -ne $configuredGuardDrive -and -not $script:CliParameters.ContainsKey("GuardDrive")) {
        $GuardDrive = [string]$configuredGuardDrive
    }

    $configuredExtraPathsFile = Get-ConfigProperty -Object $paths -Name "extraPathsFile"
    if ($null -ne $configuredExtraPathsFile -and -not $script:CliParameters.ContainsKey("ExtraPathsFile")) {
        $ExtraPathsFile = Resolve-WinSweepPath -Path ([string]$configuredExtraPathsFile)
    }

    $configuredLogDir = Get-ConfigProperty -Object $paths -Name "logDir"
    if ($null -ne $configuredLogDir -and -not $script:CliParameters.ContainsKey("LogDir")) {
        $LogDir = Resolve-WinSweepPath -Path ([string]$configuredLogDir)
    }
}

$LogDir = New-LogFolder -PreferredLogDir $LogDir
$LogStamp = "{0:yyyy-MM-dd-HHmmss-fff}-pid{1}" -f (Get-Date), $PID
$LogFile = Join-Path $LogDir ("cleanup-$LogStamp.log")

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO",
        [switch]$Detail
    )

    $line = "{0:u} [{1}] {2}" -f (Get-Date), $Level, $Message
    try {
        Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        if (-not $Quiet) {
            Write-Host "Could not write to log file: $LogFile"
        }
    }

    if ($Quiet) {
        return
    }

    if ($Detail -and -not $Detailed) {
        return
    }

    if ($Level -eq "INFO" -and -not $Detailed) {
        if ($Message.StartsWith("Skipped missing path")) {
            return
        }
        if ($Message.StartsWith("[dry-run] Would remove")) {
            return
        }
        if ($Message.StartsWith("[dry-run] Would export")) {
            return
        }
    }

    $prefix = switch ($Level) {
        "WARN" { "!" }
        "ERROR" { "x" }
        default { ">" }
    }
    $color = switch ($Level) {
        "WARN" { "Yellow" }
        "ERROR" { "Red" }
        default { "Cyan" }
    }

    Write-Host ("{0} {1}" -f $prefix, $Message) -ForegroundColor $color
}

function Write-Panel {
    param(
        [string]$Title,
        [string[]]$Lines = @()
    )

    if ($Quiet) {
        return
    }

    Write-Host ""
    Write-Host ("== {0} ==" -f $Title) -ForegroundColor Green
    foreach ($line in $Lines) {
        Write-Host ("   {0}" -f $line) -ForegroundColor Gray
    }
}

function Format-ByteSize {
    param([int64]$Bytes)

    if ($Bytes -ge 1GB) {
        return "{0:N2} GB" -f ($Bytes / 1GB)
    }
    if ($Bytes -ge 1MB) {
        return "{0:N2} MB" -f ($Bytes / 1MB)
    }
    if ($Bytes -ge 1KB) {
        return "{0:N2} KB" -f ($Bytes / 1KB)
    }
    return "$Bytes bytes"
}

function Get-TargetCategory {
    param([string]$Label)

    $text = $Label.ToLowerInvariant()
    if ($text -match "chrome|edge|brave|firefox|browser") {
        return "browser"
    }
    if ($text -match "spotify|discord|telegram|slack|teams|zoom") {
        return "app"
    }
    if ($text -match "steam|epic|battle\.net|ea desktop|ubisoft|riot|rockstar|game") {
        return "game"
    }
    if ($text -match "npm|yarn|pnpm|pip|poetry|nuget|gradle") {
        return "developer"
    }
    if ($text -match "nvidia|amd|directx|opengl|shader") {
        return "graphics"
    }
    if ($text -match "windows|prefetch|explorer|crash|temp|delivery|update") {
        return "windows"
    }
    if ($text -match "extra") {
        return "extra"
    }
    return "cache"
}

function Get-TargetRisk {
    param([string]$Category)

    switch ($Category) {
        "developer" { return "medium" }
        "game" { return "medium" }
        "extra" { return "custom" }
        default { return "safe" }
    }
}

function Add-CleanupResult {
    param(
        [string]$Label,
        [string]$Path,
        [int]$Days,
        [int64]$Bytes,
        [int]$Items,
        [int]$Failures,
        [string]$Status
    )

    $category = Get-TargetCategory -Label $Label
    [void]$script:TargetResults.Add([pscustomobject]@{
        Label = $Label
        Path = $Path
        Days = $Days
        Bytes = $Bytes
        Items = $Items
        Failures = $Failures
        Status = $Status
        Category = $category
        Risk = (Get-TargetRisk -Category $category)
    })
}

function Get-CloseHint {
    param([string]$Label)

    $text = $Label.ToLowerInvariant()
    if ($text -match "spotify") {
        return "Close Spotify and run the same WinSweep action again."
    }
    if ($text -match "telegram") {
        return "Close Telegram Desktop and run the same WinSweep action again."
    }
    if ($text -match "chrome|edge|brave|firefox|browser") {
        return "Close browsers before browser-cache cleanup."
    }
    if ($text -match "discord|slack|teams|zoom") {
        return "Close chat/meeting apps before app-cache cleanup."
    }
    if ($text -match "steam|epic|battle\.net|ea desktop|ubisoft|riot|rockstar") {
        return "Close game launchers before gaming-cache cleanup."
    }
    if ($text -match "nvidia|amd|directx|opengl|shader") {
        return "Close games and GPU-heavy apps before graphics-cache cleanup."
    }
    return ""
}

function Add-CloseHint {
    param([string]$Label)

    $hint = Get-CloseHint -Label $Label
    if (-not [string]::IsNullOrWhiteSpace($hint)) {
        $script:CloseHints[$hint] = $true
    }
}

function Add-AdminRetryHint {
    $script:CloseHints["Run WinSweep as administrator if protected Windows or Store app caches are skipped."] = $true
}

function Get-ProfileName {
    if ([string]::IsNullOrWhiteSpace($Profile)) {
        return "custom"
    }
    return $Profile
}

function Show-ScanResults {
    param([string]$Mode)

    $rows = @($script:TargetResults | Where-Object { $_.Bytes -gt 0 } | Sort-Object Bytes -Descending)
    $totalBytes = [int64]0
    $totalItems = 0
    foreach ($row in $rows) {
        $totalBytes += [int64]$row.Bytes
        $totalItems += [int]$row.Items
    }

    $title = if ($Mode -eq "clean") { "Cleaned Results" } else { "Scan Results" }
    $lines = @(
        ("profile: {0}" -f (Get-ProfileName)),
        ("selected: {0} item(s), {1}" -f $totalItems, (Format-ByteSize $totalBytes))
    )

    if ($rows.Count -eq 0) {
        $lines += "no sizeable removable cache found for this profile."
        Write-Panel -Title $title -Lines $lines
        return
    }

    $lines += "top categories:"
    foreach ($row in ($rows | Select-Object -First 12)) {
        $lines += ("{0} | {1} | {2} item(s) | {3}/{4}" -f (Format-ByteSize ([int64]$row.Bytes)), $row.Label, $row.Items, $row.Category, $row.Risk)
        Write-Log ("Result: {0} | {1} | {2} item(s) | {3}/{4} | {5}" -f (Format-ByteSize ([int64]$row.Bytes)), $row.Label, $row.Items, $row.Category, $row.Risk, $row.Path) -Detail
    }

    Write-Panel -Title $title -Lines $lines
}

function Get-DiskSummaryLines {
    param(
        $Before,
        $After
    )

    if ($null -eq $Before -or $null -eq $After) {
        return @()
    }

    if ($DryRun) {
        return @(
            ("disk free: {0} ({1}%)" -f (Format-ByteSize ([int64]$After.FreeBytes)), $After.FreePercent)
        )
    }

    $delta = [int64]$After.FreeBytes - [int64]$Before.FreeBytes
    $deltaText = Format-ByteSize ([Math]::Abs($delta))
    if ($delta -ge 0) {
        $deltaText = "+$deltaText"
    }
    else {
        $deltaText = "-$deltaText"
    }

    return @(
        ("disk before: {0} free ({1}%)" -f (Format-ByteSize ([int64]$Before.FreeBytes)), $Before.FreePercent),
        ("disk after: {0} free ({1}%)" -f (Format-ByteSize ([int64]$After.FreeBytes)), $After.FreePercent),
        ("disk delta: {0}" -f $deltaText)
    )
}

function Show-CloseHints {
    if ($script:CloseHints.Count -eq 0) {
        return
    }

    $lines = @($script:CloseHints.Keys | Sort-Object)
    Write-Panel -Title "Retry Tips" -Lines $lines
}

function Add-PreflightResult {
    param(
        [string]$App,
        [string[]]$Processes,
        [string]$Reason
    )

    $running = @()
    foreach ($processName in $Processes) {
        $found = @(Get-Process -Name $processName -ErrorAction SilentlyContinue)
        foreach ($process in $found) {
            $running += $process.ProcessName
        }
    }

    $running = @($running | Sort-Object -Unique)
    if ($running.Count -eq 0) {
        return
    }

    [void]$script:PreflightResults.Add([pscustomobject]@{
        App = $App
        Processes = ($running -join ", ")
        Reason = $Reason
    })

    $script:CloseHints["Close $App before cleanup to free more cache files."] = $true
}

function Invoke-PreflightCheck {
    if ($Quiet) {
        return
    }

    if ($CleanSpotifyCache -or $CleanAppCaches -or $AggressiveSafe) {
        Add-PreflightResult -App "Spotify" -Processes @("Spotify") -Reason "Spotify Store/classic cache can be locked while it is running."
    }
    if ($CleanAppCaches -or $AggressiveSafe) {
        Add-PreflightResult -App "Telegram Desktop" -Processes @("Telegram") -Reason "Telegram media cache may stay locked while Telegram is open."
        Add-PreflightResult -App "Discord" -Processes @("Discord") -Reason "Discord cache and GPU cache may stay locked."
        Add-PreflightResult -App "Slack" -Processes @("Slack") -Reason "Slack cache may stay locked."
        Add-PreflightResult -App "Microsoft Teams" -Processes @("Teams", "ms-teams") -Reason "Teams cache may stay locked."
    }
    if ($CleanBrowserCaches -or $AggressiveSafe) {
        Add-PreflightResult -App "browsers" -Processes @("chrome", "msedge", "brave", "firefox") -Reason "Browser cache cleanup is cleaner when browsers are closed."
    }
    if ($CleanGameCaches -or $AggressiveSafe) {
        Add-PreflightResult -App "Steam" -Processes @("steam", "steamwebhelper") -Reason "Steam shader/http cache may be active."
        Add-PreflightResult -App "Epic Games Launcher" -Processes @("EpicGamesLauncher") -Reason "Epic webcache may be active."
        Add-PreflightResult -App "Battle.net" -Processes @("Battle.net", "Agent") -Reason "Battle.net cache may be active."
        Add-PreflightResult -App "Riot Client" -Processes @("RiotClientServices", "RiotClientUx", "RiotClientUxRender") -Reason "Riot client cache/logs may be active."
        Add-PreflightResult -App "Ubisoft Connect" -Processes @("UbisoftConnect", "upc") -Reason "Ubisoft launcher cache/logs may be active."
        Add-PreflightResult -App "Rockstar Launcher" -Processes @("Launcher", "RockstarService") -Reason "Rockstar launcher cache/logs may be active."
    }

    if ($script:PreflightResults.Count -eq 0) {
        Write-Log "Preflight: no tracked cache-heavy apps appear to be open." -Detail
        return
    }

    $lines = @()
    foreach ($item in $script:PreflightResults) {
        $lines += ("{0}: {1}" -f $item.App, $item.Reason)
        Write-Log ("Preflight open app: {0}; processes: {1}; reason: {2}" -f $item.App, $item.Processes, $item.Reason) -Detail
    }

    Write-Panel -Title "Preflight" -Lines $lines
}

function ConvertTo-HtmlText {
    param([string]$Text)

    if ($null -eq $Text) {
        return ""
    }

    return [System.Net.WebUtility]::HtmlEncode($Text)
}

function Get-HtmlRows {
    param($Rows)

    $html = New-Object System.Text.StringBuilder
    foreach ($row in $Rows) {
        [void]$html.AppendLine("<tr><td>$(ConvertTo-HtmlText $row.Label)</td><td>$(ConvertTo-HtmlText (Format-ByteSize ([int64]$row.Bytes)))</td><td>$($row.Items)</td><td>$(ConvertTo-HtmlText $row.Category)</td><td>$(ConvertTo-HtmlText $row.Risk)</td><td>$(ConvertTo-HtmlText $row.Status)</td><td>$(ConvertTo-HtmlText $row.Path)</td></tr>")
    }
    return $html.ToString()
}

function Write-HtmlReport {
    param(
        [string]$Mode,
        $Before,
        $After,
        [string[]]$SummaryLines
    )

    try {
        $reportDir = Join-Path $LogDir "Reports"
        New-Item -ItemType Directory -Path $reportDir -Force -ErrorAction Stop | Out-Null
        $reportPath = Join-Path $reportDir ("report-$LogStamp.html")
        $latestPath = Join-Path $reportDir "latest.html"

        $rows = @($script:TargetResults | Where-Object { $_.Bytes -gt 0 } | Sort-Object Bytes -Descending)
        $allRows = @($script:TargetResults | Sort-Object Bytes -Descending)
        $totalBytes = [int64]0
        $totalItems = 0
        foreach ($row in $rows) {
            $totalBytes += [int64]$row.Bytes
            $totalItems += [int]$row.Items
        }

        $preflightHtml = if ($script:PreflightResults.Count -gt 0) {
            (($script:PreflightResults | ForEach-Object { "<li><strong>$(ConvertTo-HtmlText $_.App)</strong>: $(ConvertTo-HtmlText $_.Reason) <span>$(ConvertTo-HtmlText $_.Processes)</span></li>" }) -join "`n")
        }
        else {
            "<li>No tracked cache-heavy apps were detected as open.</li>"
        }

        $tipsHtml = if ($script:CloseHints.Count -gt 0) {
            (($script:CloseHints.Keys | Sort-Object | ForEach-Object { "<li>$(ConvertTo-HtmlText $_)</li>" }) -join "`n")
        }
        else {
            "<li>No retry tips for this run.</li>"
        }

        $summaryHtml = (($SummaryLines | ForEach-Object { "<li>$(ConvertTo-HtmlText $_)</li>" }) -join "`n")
        $topRowsHtml = Get-HtmlRows -Rows ($rows | Select-Object -First 15)
        $allRowsHtml = Get-HtmlRows -Rows $allRows
        $generated = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        $diskBefore = if ($null -ne $Before) { "{0} ({1}%)" -f (Format-ByteSize ([int64]$Before.FreeBytes)), $Before.FreePercent } else { "unknown" }
        $diskAfter = if ($null -ne $After) { "{0} ({1}%)" -f (Format-ByteSize ([int64]$After.FreeBytes)), $After.FreePercent } else { "unknown" }

        $html = @"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>WinSweep Report</title>
  <style>
    :root { color-scheme: light; font-family: Segoe UI, Arial, sans-serif; }
    body { margin: 0; background: #f4f6f8; color: #17212b; }
    main { max-width: 1180px; margin: 0 auto; padding: 28px; }
    header { background: #0f1720; color: white; padding: 24px 28px; border-radius: 8px; }
    h1 { margin: 0 0 8px; font-size: 30px; }
    h2 { margin: 28px 0 12px; font-size: 19px; }
    .meta { color: #c7d1dc; }
    .grid { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 12px; margin-top: 18px; }
    .metric { background: white; border: 1px solid #d9e0e7; border-radius: 8px; padding: 14px; }
    .metric b { display: block; font-size: 22px; margin-top: 5px; }
    section { background: white; border: 1px solid #d9e0e7; border-radius: 8px; padding: 18px; margin-top: 16px; }
    table { width: 100%; border-collapse: collapse; font-size: 13px; }
    th, td { text-align: left; padding: 8px 10px; border-bottom: 1px solid #edf0f3; vertical-align: top; }
    th { background: #f8fafc; color: #3b4652; position: sticky; top: 0; }
    code { background: #edf2f7; padding: 2px 5px; border-radius: 4px; }
    ul { margin: 8px 0 0; padding-left: 20px; }
    li { margin: 5px 0; }
    span { color: #657282; }
    .empty { color: #657282; }
  </style>
</head>
<body>
<main>
  <header>
    <h1>WinSweep Report</h1>
    <div class="meta">Generated $generated | mode: $(ConvertTo-HtmlText $Mode) | profile: $(ConvertTo-HtmlText (Get-ProfileName)) | version: $script:WinSweepVersion</div>
  </header>
  <div class="grid">
    <div class="metric">Selected reclaim<b>$(ConvertTo-HtmlText (Format-ByteSize $totalBytes))</b></div>
    <div class="metric">Selected items<b>$totalItems</b></div>
    <div class="metric">Disk before<b>$(ConvertTo-HtmlText $diskBefore)</b></div>
    <div class="metric">Disk after<b>$(ConvertTo-HtmlText $diskAfter)</b></div>
  </div>
  <section>
    <h2>Summary</h2>
    <ul>$summaryHtml</ul>
    <p>Log file: <code>$(ConvertTo-HtmlText $LogFile)</code></p>
  </section>
  <section>
    <h2>Preflight</h2>
    <ul>$preflightHtml</ul>
  </section>
  <section>
    <h2>Top Results</h2>
    <table>
      <thead><tr><th>Target</th><th>Size</th><th>Items</th><th>Category</th><th>Risk</th><th>Status</th><th>Path</th></tr></thead>
      <tbody>$topRowsHtml</tbody>
    </table>
  </section>
  <section>
    <h2>Retry Tips</h2>
    <ul>$tipsHtml</ul>
  </section>
  <section>
    <h2>All Targets</h2>
    <table>
      <thead><tr><th>Target</th><th>Size</th><th>Items</th><th>Category</th><th>Risk</th><th>Status</th><th>Path</th></tr></thead>
      <tbody>$allRowsHtml</tbody>
    </table>
  </section>
</main>
</body>
</html>
"@

        Set-Content -LiteralPath $reportPath -Value $html -Encoding UTF8 -ErrorAction Stop
        Copy-Item -LiteralPath $reportPath -Destination $latestPath -Force -ErrorAction Stop
        $script:HtmlReportPath = $reportPath
        Write-Log "HTML report saved: $reportPath"

        if ($OpenReport -and -not $Quiet) {
            Start-Process -FilePath $reportPath -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-Log "Could not write HTML report. $($_.Exception.Message)" "WARN"
    }
}

function Get-DriveSnapshot {
    param([string]$Drive)

    if ([string]::IsNullOrWhiteSpace($Drive)) {
        $Drive = $env:SystemDrive
    }

    if ([string]::IsNullOrWhiteSpace($Drive)) {
        return $null
    }

    $driveName = $Drive.TrimEnd("\")
    if ($driveName.Length -eq 1) {
        $driveName = "$driveName`:"
    }

    try {
        $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $driveName) -ErrorAction Stop
        if ($null -ne $disk -and [int64]$disk.Size -gt 0) {
            $freeBytes = [int64]$disk.FreeSpace
            $totalBytes = [int64]$disk.Size
            $freePercent = [Math]::Round(($freeBytes / $totalBytes) * 100, 1)

            return [pscustomobject]@{
                Drive = $driveName
                FreeBytes = $freeBytes
                TotalBytes = $totalBytes
                FreePercent = $freePercent
            }
        }
    }
    catch {
        Write-Log "CIM drive lookup failed for $Drive. Trying PSDrive fallback. $($_.Exception.Message)" "WARN" -Detail
    }

    try {
        $psDriveName = $driveName.TrimEnd(":")
        $psDrive = Get-PSDrive -Name $psDriveName -PSProvider FileSystem -ErrorAction Stop
        $freeBytes = [int64]$psDrive.Free
        $usedBytes = [int64]$psDrive.Used
        $totalBytes = $freeBytes + $usedBytes
        if ($totalBytes -gt 0) {
            $freePercent = [Math]::Round(($freeBytes / $totalBytes) * 100, 1)

            return [pscustomobject]@{
                Drive = $driveName
                FreeBytes = $freeBytes
                TotalBytes = $totalBytes
                FreePercent = $freePercent
            }
        }

        Write-Log "PSDrive lookup returned an empty disk size for $Drive. Trying DriveInfo fallback." "WARN" -Detail
    }
    catch {
        Write-Log "PSDrive lookup failed for $Drive. Trying DriveInfo fallback. $($_.Exception.Message)" "WARN" -Detail
    }

    try {
        $root = "$($driveName.TrimEnd(':')):\"
        $driveInfo = New-Object -TypeName System.IO.DriveInfo -ArgumentList $root
        if (-not $driveInfo.IsReady -or $driveInfo.TotalSize -le 0) {
            return $null
        }

        $freeBytes = [int64]$driveInfo.AvailableFreeSpace
        $totalBytes = [int64]$driveInfo.TotalSize
        $freePercent = [Math]::Round(($freeBytes / $totalBytes) * 100, 1)

        return [pscustomobject]@{
            Drive = $driveName
            FreeBytes = $freeBytes
            TotalBytes = $totalBytes
            FreePercent = $freePercent
        }
    }
    catch {
        Write-Log "Could not read drive information for $Drive. $($_.Exception.Message)" "WARN"
        return $null
    }
}

function Test-ShouldRunSmartGuard {
    param(
        [string]$Drive,
        [int]$MinimumFreeGB,
        [int]$MinimumFreePercent
    )

    $snapshot = Get-DriveSnapshot -Drive $Drive
    if ($null -eq $snapshot) {
        Write-Log "Smart guard could not read disk state, continuing with cleanup." "WARN"
        return $true
    }

    $freeGB = [Math]::Round($snapshot.FreeBytes / 1GB, 2)
    Write-Panel -Title "Disk Pressure" -Lines @(
        ("{0}: {1} free of {2} ({3}%)" -f $snapshot.Drive, (Format-ByteSize $snapshot.FreeBytes), (Format-ByteSize $snapshot.TotalBytes), $snapshot.FreePercent),
        ("threshold: below {0} GB or below {1}%" -f $MinimumFreeGB, $MinimumFreePercent)
    )

    if ($freeGB -lt $MinimumFreeGB) {
        Write-Log ("Smart guard triggered: {0} has only {1} GB free." -f $snapshot.Drive, $freeGB)
        return $true
    }

    if ($snapshot.FreePercent -lt $MinimumFreePercent) {
        Write-Log ("Smart guard triggered: {0} has only {1}% free." -f $snapshot.Drive, $snapshot.FreePercent)
        return $true
    }

    Write-Log ("Smart guard skipped cleanup: {0} still has {1} free ({2}%)." -f $snapshot.Drive, (Format-ByteSize $snapshot.FreeBytes), $snapshot.FreePercent)
    return $false
}

function Test-SafeCleanupDirectory {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }

    try {
        $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd("\")
        $rootPath = [IO.Path]::GetPathRoot($fullPath).TrimEnd("\")
    }
    catch {
        return $false
    }

    if ([string]::IsNullOrWhiteSpace($fullPath) -or [string]::IsNullOrWhiteSpace($rootPath)) {
        return $false
    }

    if ($fullPath -ieq $rootPath) {
        return $false
    }

    if ($fullPath.Length -lt ($rootPath.Length + 4)) {
        return $false
    }

    $forbidden = New-Object System.Collections.ArrayList
    if (-not [string]::IsNullOrWhiteSpace($env:SystemDrive)) {
        [void]$forbidden.Add("$($env:SystemDrive)\")
        [void]$forbidden.Add((Join-Path "$($env:SystemDrive)\" "Users"))
    }
    foreach ($candidate in @($env:USERPROFILE, $env:PUBLIC, $env:SystemRoot, $env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            [void]$forbidden.Add($candidate)
        }
    }

    foreach ($candidate in $forbidden) {
        try {
            $candidateFull = [IO.Path]::GetFullPath($candidate).TrimEnd("\")
            if ($fullPath -ieq $candidateFull) {
                return $false
            }
        }
        catch {
            continue
        }
    }

    return $true
}

function Remove-OldContents {
    param(
        [string]$Label,
        [string]$Path,
        [int]$OlderThanDays
    )

    if (-not (Test-SafeCleanupDirectory -Path $Path)) {
        Write-Log "Skipped unsafe or empty path for ${Label}: $Path" "WARN"
        Add-CleanupResult -Label $Label -Path $Path -Days $OlderThanDays -Bytes 0 -Items 0 -Failures 0 -Status "unsafe"
        return
    }

    try {
        $pathExists = Test-Path -LiteralPath $Path -PathType Container -ErrorAction Stop
    }
    catch {
        Write-Log "Skipped inaccessible path for ${Label}: $Path. $($_.Exception.Message)" "WARN"
        Add-AdminRetryHint
        Add-CleanupResult -Label $Label -Path $Path -Days $OlderThanDays -Bytes 0 -Items 0 -Failures 0 -Status "inaccessible"
        return
    }

    if (-not $pathExists) {
        Write-Log "Skipped missing path for ${Label}: $Path"
        Add-CleanupResult -Label $Label -Path $Path -Days $OlderThanDays -Bytes 0 -Items 0 -Failures 0 -Status "missing"
        return
    }

    $cutoff = (Get-Date).AddDays(-[Math]::Abs($OlderThanDays))
    $targetBytes = [int64]0
    $targetItems = 0
    $targetFailures = 0
    $actionVerb = if ($DryRun) { "Scanning" } else { "Cleaning" }
    if ($DryRun) {
        Write-Log "$actionVerb $Label older than $OlderThanDays day(s): $Path" -Detail
    }
    else {
        Write-Log "$actionVerb $Label older than $OlderThanDays day(s): $Path"
    }

    try {
        $files = Get-ChildItem -LiteralPath $Path -File -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $cutoff }
    }
    catch {
        Write-Log "Could not enumerate files in $Path. $($_.Exception.Message)" "WARN"
        Add-AdminRetryHint
        Add-CleanupResult -Label $Label -Path $Path -Days $OlderThanDays -Bytes $targetBytes -Items $targetItems -Failures $targetFailures -Status "enumeration failed"
        return
    }

    foreach ($file in $files) {
        try {
            $length = [int64]$file.Length
            if ($DryRun) {
                $targetBytes += $length
                $targetItems += 1
                $script:PotentialBytes += $length
                $script:PotentialItems += 1
                Write-Log "[dry-run] Would remove file: $($file.FullName)" -Detail
                continue
            }

            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
            $targetBytes += $length
            $targetItems += 1
            $script:DeletedBytes += $length
            $script:DeletedItems += 1
        }
        catch {
            $script:FailedItems += 1
            $targetFailures += 1
            Add-CloseHint -Label $Label
            Write-Log "Could not remove file: $($file.FullName). $($_.Exception.Message)" "WARN"
        }
    }

    try {
        $directories = Get-ChildItem -LiteralPath $Path -Directory -Recurse -Force -ErrorAction SilentlyContinue |
            Sort-Object { $_.FullName.Length } -Descending
    }
    catch {
        Write-Log "Could not enumerate directories in $Path. $($_.Exception.Message)" "WARN"
        Add-CleanupResult -Label $Label -Path $Path -Days $OlderThanDays -Bytes $targetBytes -Items $targetItems -Failures $targetFailures -Status "partial"
        return
    }

    foreach ($directory in $directories) {
        if ($directory.LastWriteTime -ge $cutoff) {
            continue
        }

        try {
            $firstChild = Get-ChildItem -LiteralPath $directory.FullName -Force -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($null -ne $firstChild) {
                continue
            }

            if ($DryRun) {
                $targetItems += 1
                $script:PotentialItems += 1
                Write-Log "[dry-run] Would remove empty folder: $($directory.FullName)" -Detail
                continue
            }

            Remove-Item -LiteralPath $directory.FullName -Force -ErrorAction Stop
            $targetItems += 1
            $script:DeletedItems += 1
        }
        catch {
            $script:FailedItems += 1
            $targetFailures += 1
            Add-CloseHint -Label $Label
            Write-Log "Could not remove folder: $($directory.FullName). $($_.Exception.Message)" "WARN"
        }
    }

    if ($targetItems -gt 0) {
        if ($DryRun) {
            Write-Log ("Would clean {0}: {1} item(s), about {2}." -f $Label, $targetItems, (Format-ByteSize $targetBytes))
        }
        else {
            Write-Log ("Cleaned {0}: {1} item(s), about {2}." -f $Label, $targetItems, (Format-ByteSize $targetBytes))
        }
    }

    $status = if ($targetItems -gt 0) {
        if ($DryRun) { "would clean" } else { "cleaned" }
    }
    else {
        "empty"
    }
    Add-CleanupResult -Label $Label -Path $Path -Days $OlderThanDays -Bytes $targetBytes -Items $targetItems -Failures $targetFailures -Status $status
}

function Add-Target {
    param(
        [System.Collections.ArrayList]$Targets,
        [string]$Label,
        [string]$Path,
        [int]$Days
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    [void]$Targets.Add([pscustomobject]@{
        Label = $Label
        Path = $Path
        Days = $Days
    })
}

function Add-WildcardTargets {
    param(
        [System.Collections.ArrayList]$Targets,
        [string]$Label,
        [string]$Pattern,
        [int]$Days
    )

    if ([string]::IsNullOrWhiteSpace($Pattern)) {
        return
    }

    try {
        Get-ChildItem -Path $Pattern -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            Add-Target -Targets $Targets -Label $Label -Path $_.FullName -Days $Days
        }
    }
    catch {
        Write-Log "Could not resolve browser cache pattern: $Pattern. $($_.Exception.Message)" "WARN"
    }
}

function Add-SpotifyCacheTargets {
    param(
        [System.Collections.ArrayList]$Targets,
        [int]$Days
    )

    Add-Target -Targets $Targets -Label "Spotify stream cache" -Path (Join-Path $env:LOCALAPPDATA "Spotify\Data") -Days $Days
    Add-Target -Targets $Targets -Label "Spotify storage cache" -Path (Join-Path $env:LOCALAPPDATA "Spotify\Storage") -Days $Days
    Add-Target -Targets $Targets -Label "Spotify browser cache" -Path (Join-Path $env:LOCALAPPDATA "Spotify\Browser\Cache") -Days $Days
    Add-Target -Targets $Targets -Label "Spotify code cache" -Path (Join-Path $env:LOCALAPPDATA "Spotify\Browser\Code Cache") -Days $Days
    Add-Target -Targets $Targets -Label "Spotify roaming browser cache" -Path (Join-Path $env:APPDATA "Spotify\Browser\Cache") -Days $Days
    Add-Target -Targets $Targets -Label "Spotify roaming code cache" -Path (Join-Path $env:APPDATA "Spotify\Browser\Code Cache") -Days $Days
    Add-WildcardTargets -Targets $Targets -Label "Spotify user cache" -Pattern (Join-Path $env:APPDATA "Spotify\Users\*\Cache") -Days $Days
    Add-Target -Targets $Targets -Label "Spotify Store stream cache" -Path (Join-Path $env:LOCALAPPDATA "Packages\SpotifyAB.SpotifyMusic_zpdnekdrzrea0\LocalCache\Spotify\Data") -Days $Days
    Add-Target -Targets $Targets -Label "Spotify Store storage cache" -Path (Join-Path $env:LOCALAPPDATA "Packages\SpotifyAB.SpotifyMusic_zpdnekdrzrea0\LocalCache\Spotify\Storage") -Days $Days
    Add-Target -Targets $Targets -Label "Spotify Store browser cache" -Path (Join-Path $env:LOCALAPPDATA "Packages\SpotifyAB.SpotifyMusic_zpdnekdrzrea0\LocalCache\Spotify\Browser\Cache") -Days $Days
    Add-Target -Targets $Targets -Label "Spotify Store code cache" -Path (Join-Path $env:LOCALAPPDATA "Packages\SpotifyAB.SpotifyMusic_zpdnekdrzrea0\LocalCache\Spotify\Browser\Code Cache") -Days $Days

    $prefFiles = @(
        (Join-Path $env:APPDATA "Spotify\prefs"),
        (Join-Path $env:LOCALAPPDATA "Spotify\prefs"),
        (Join-Path $env:LOCALAPPDATA "Packages\SpotifyAB.SpotifyMusic_zpdnekdrzrea0\LocalCache\Spotify\prefs")
    )

    foreach ($prefFile in $prefFiles) {
        if (-not (Test-Path -LiteralPath $prefFile -PathType Leaf -ErrorAction SilentlyContinue)) {
            continue
        }

        try {
            Get-Content -LiteralPath $prefFile -ErrorAction Stop | ForEach-Object {
                $match = [regex]::Match($_, '^\s*storage\.location\s*=\s*"?(.+?)"?\s*$')
                if ($match.Success) {
                    $configuredPath = $match.Groups[1].Value.Trim('"') -replace '\\\\', '\'
                    if (-not [string]::IsNullOrWhiteSpace($configuredPath)) {
                        Add-Target -Targets $Targets -Label "Spotify configured storage cache" -Path $configuredPath -Days $Days
                    }
                }
            }
        }
        catch {
            Write-Log "Could not read Spotify prefs: $prefFile. $($_.Exception.Message)" "WARN"
        }
    }
}

function Add-AppCacheTargets {
    param(
        [System.Collections.ArrayList]$Targets,
        [int]$Days
    )

    Add-SpotifyCacheTargets -Targets $Targets -Days $Days

    foreach ($discordName in @("discord", "discordptb", "discordcanary")) {
        Add-Target -Targets $Targets -Label "$discordName cache" -Path (Join-Path $env:APPDATA "$discordName\Cache") -Days $Days
        Add-Target -Targets $Targets -Label "$discordName code cache" -Path (Join-Path $env:APPDATA "$discordName\Code Cache") -Days $Days
        Add-Target -Targets $Targets -Label "$discordName GPU cache" -Path (Join-Path $env:APPDATA "$discordName\GPUCache") -Days $Days
    }

    Add-Target -Targets $Targets -Label "Slack cache" -Path (Join-Path $env:APPDATA "Slack\Cache") -Days $Days
    Add-Target -Targets $Targets -Label "Slack code cache" -Path (Join-Path $env:APPDATA "Slack\Code Cache") -Days $Days
    Add-Target -Targets $Targets -Label "Slack GPU cache" -Path (Join-Path $env:APPDATA "Slack\GPUCache") -Days $Days
    Add-Target -Targets $Targets -Label "Telegram Desktop cache" -Path (Join-Path $env:APPDATA "Telegram Desktop\tdata\user_data\cache") -Days $Days
    Add-Target -Targets $Targets -Label "Telegram Desktop media cache" -Path (Join-Path $env:APPDATA "Telegram Desktop\tdata\user_data\media_cache") -Days $Days
    Add-Target -Targets $Targets -Label "Zoom webview cache" -Path (Join-Path $env:APPDATA "Zoom\data\WebviewCache") -Days $Days
    Add-Target -Targets $Targets -Label "Microsoft Teams cache" -Path (Join-Path $env:APPDATA "Microsoft\Teams\Cache") -Days $Days
    Add-Target -Targets $Targets -Label "Microsoft Teams code cache" -Path (Join-Path $env:APPDATA "Microsoft\Teams\Code Cache") -Days $Days
    Add-Target -Targets $Targets -Label "Microsoft Teams GPU cache" -Path (Join-Path $env:APPDATA "Microsoft\Teams\GPUCache") -Days $Days
    Add-WildcardTargets -Targets $Targets -Label "new Teams package cache" -Pattern (Join-Path $env:LOCALAPPDATA "Packages\MSTeams_*\LocalCache\Microsoft\MSTeams\Cache") -Days $Days
}

function Add-SystemCacheTargets {
    param(
        [System.Collections.ArrayList]$Targets,
        [int]$Days
    )

    Add-Target -Targets $Targets -Label "Explorer thumbnail/icon cache" -Path (Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Explorer") -Days $Days
    Add-Target -Targets $Targets -Label "user crash dumps" -Path (Join-Path $env:LOCALAPPDATA "CrashDumps") -Days $Days
    Add-Target -Targets $Targets -Label "Windows Prefetch" -Path (Join-Path $env:SystemRoot "Prefetch") -Days ([Math]::Max($Days, 7))
    Add-Target -Targets $Targets -Label "NVIDIA DirectX cache" -Path (Join-Path $env:LOCALAPPDATA "NVIDIA\DXCache") -Days $Days
    Add-Target -Targets $Targets -Label "NVIDIA OpenGL cache" -Path (Join-Path $env:LOCALAPPDATA "NVIDIA\GLCache") -Days $Days
    Add-Target -Targets $Targets -Label "NVIDIA compute cache" -Path (Join-Path $env:LOCALAPPDATA "NVIDIA\ComputeCache") -Days $Days
    Add-Target -Targets $Targets -Label "AMD DirectX cache" -Path (Join-Path $env:LOCALAPPDATA "AMD\DxCache") -Days $Days
    Add-Target -Targets $Targets -Label "AMD OpenGL cache" -Path (Join-Path $env:LOCALAPPDATA "AMD\GLCache") -Days $Days
}

function Add-DeveloperCacheTargets {
    param(
        [System.Collections.ArrayList]$Targets,
        [int]$Days
    )

    Add-Target -Targets $Targets -Label "npm cache" -Path (Join-Path $env:LOCALAPPDATA "npm-cache") -Days $Days
    Add-Target -Targets $Targets -Label "Yarn cache" -Path (Join-Path $env:LOCALAPPDATA "Yarn\Cache") -Days $Days
    Add-Target -Targets $Targets -Label "Yarn data cache" -Path (Join-Path $env:LOCALAPPDATA "Yarn\Data\cache") -Days $Days
    Add-Target -Targets $Targets -Label "pnpm store" -Path (Join-Path $env:LOCALAPPDATA "pnpm\store") -Days $Days
    Add-Target -Targets $Targets -Label "pip cache" -Path (Join-Path $env:LOCALAPPDATA "pip\Cache") -Days $Days
    Add-Target -Targets $Targets -Label "Poetry cache" -Path (Join-Path $env:LOCALAPPDATA "pypoetry\Cache") -Days $Days
    Add-Target -Targets $Targets -Label "NuGet http cache" -Path (Join-Path $env:LOCALAPPDATA "NuGet\v3-cache") -Days $Days
    Add-Target -Targets $Targets -Label "NuGet plugins cache" -Path (Join-Path $env:LOCALAPPDATA "NuGet\plugins-cache") -Days $Days
    Add-Target -Targets $Targets -Label "Gradle build cache" -Path (Join-Path $env:USERPROFILE ".gradle\caches\build-cache-1") -Days $Days
}

function Add-GameCacheTargets {
    param(
        [System.Collections.ArrayList]$Targets,
        [int]$Days
    )

    $programFilesX86 = ${env:ProgramFiles(x86)}
    if (-not [string]::IsNullOrWhiteSpace($programFilesX86)) {
        Add-Target -Targets $Targets -Label "Steam http cache" -Path (Join-Path $programFilesX86 "Steam\appcache\httpcache") -Days $Days
        Add-Target -Targets $Targets -Label "Steam shader cache" -Path (Join-Path $programFilesX86 "Steam\steamapps\shadercache") -Days $Days
    }

    Add-WildcardTargets -Targets $Targets -Label "Epic Games Launcher webcache" -Pattern (Join-Path $env:LOCALAPPDATA "EpicGamesLauncher\Saved\webcache*") -Days $Days
    Add-Target -Targets $Targets -Label "Battle.net cache" -Path (Join-Path $env:ProgramData "Battle.net\Cache") -Days $Days
    Add-Target -Targets $Targets -Label "Battle.net local cache" -Path (Join-Path $env:LOCALAPPDATA "Battle.net\Cache") -Days $Days
    Add-Target -Targets $Targets -Label "EA Desktop cache" -Path (Join-Path $env:LOCALAPPDATA "Electronic Arts\EA Desktop\cache") -Days $Days
    Add-Target -Targets $Targets -Label "Ubisoft Connect cache" -Path (Join-Path $env:LOCALAPPDATA "Ubisoft Game Launcher\cache") -Days $Days
    Add-Target -Targets $Targets -Label "Ubisoft Connect logs" -Path (Join-Path $env:LOCALAPPDATA "Ubisoft Game Launcher\logs") -Days $Days
    Add-Target -Targets $Targets -Label "Riot Client cache" -Path (Join-Path $env:LOCALAPPDATA "Riot Games\Riot Client\Data\Cache") -Days $Days
    Add-Target -Targets $Targets -Label "Riot Client logs" -Path (Join-Path $env:LOCALAPPDATA "Riot Games\Riot Client\Logs") -Days $Days
    Add-Target -Targets $Targets -Label "Rockstar Launcher cache" -Path (Join-Path $env:LOCALAPPDATA "Rockstar Games\Launcher\Cache") -Days $Days
    Add-Target -Targets $Targets -Label "Rockstar Launcher logs" -Path (Join-Path $env:LOCALAPPDATA "Rockstar Games\Launcher\Logs") -Days $Days
}

function Add-ExtraPathTargets {
    param(
        [System.Collections.ArrayList]$Targets,
        [string]$PathFile,
        [int]$Days
    )

    if ([string]::IsNullOrWhiteSpace($PathFile)) {
        return
    }

    if (-not (Test-Path -LiteralPath $PathFile -PathType Leaf -ErrorAction SilentlyContinue)) {
        Write-Log "Extra paths file is missing, skipped: $PathFile"
        return
    }

    try {
        Get-Content -LiteralPath $PathFile -ErrorAction Stop | ForEach-Object {
            $line = $_.Trim()
            if (-not [string]::IsNullOrWhiteSpace($line) -and -not $line.StartsWith("#")) {
                $expandedPath = [Environment]::ExpandEnvironmentVariables($line)
                Add-Target -Targets $Targets -Label "extra cache path" -Path $expandedPath -Days $Days
            }
        }
    }
    catch {
        Write-Log "Could not read extra paths file: $PathFile. $($_.Exception.Message)" "WARN"
    }
}

function Get-SafeFileName {
    param([string]$Name)

    $safe = $Name -replace '[\\/:*?"<>|\s]+', '_'
    return $safe.Trim("_")
}

function Backup-RegistryKey {
    param(
        [string]$RegistryKey,
        [string]$BackupRoot
    )

    $regExe = Join-Path $env:SystemRoot "System32\reg.exe"
    if (-not (Test-Path -LiteralPath $regExe -PathType Leaf)) {
        Write-Log "reg.exe was not found, registry backup skipped for $RegistryKey." "WARN"
        return
    }

    if ($DryRun) {
        Write-Log "[dry-run] Would export registry key before deleting it: $RegistryKey"
        return
    }

    try {
        New-Item -ItemType Directory -Path $BackupRoot -Force -ErrorAction Stop | Out-Null
        $backupPath = Join-Path $BackupRoot ("{0}.reg" -f (Get-SafeFileName -Name $RegistryKey))
        & $regExe export $RegistryKey $backupPath /y *> $null
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Registry backup saved: $backupPath"
        }
        else {
            Write-Log "Registry backup failed for $RegistryKey with exit code $LASTEXITCODE." "WARN"
        }
    }
    catch {
        Write-Log "Registry backup failed for $RegistryKey. $($_.Exception.Message)" "WARN"
    }
}

function Remove-RegistryTree {
    param(
        [string]$Label,
        [string]$ProviderPath,
        [string]$RegistryKey,
        [string]$BackupRoot
    )

    if (-not (Test-Path -LiteralPath $ProviderPath)) {
        Write-Log "Skipped missing registry key for ${Label}: $RegistryKey"
        return
    }

    Backup-RegistryKey -RegistryKey $RegistryKey -BackupRoot $BackupRoot

    if ($DryRun) {
        Write-Log "[dry-run] Would remove registry key for ${Label}: $RegistryKey"
        return
    }

    try {
        Remove-Item -LiteralPath $ProviderPath -Recurse -Force -ErrorAction Stop
        $script:DeletedItems += 1
        Write-Log "Removed registry key for ${Label}: $RegistryKey"
    }
    catch {
        $script:FailedItems += 1
        Write-Log "Could not remove registry key for ${Label}: $RegistryKey. $($_.Exception.Message)" "WARN"
    }
}

function Invoke-RegistryCleanup {
    if (-not $CleanRegistry) {
        return
    }

    $backupRoot = Join-Path $LogDir ("RegistryBackups\{0:yyyy-MM-dd-HHmmss}" -f (Get-Date))
    Write-Log "Registry cleanup enabled. Backups will be saved under: $backupRoot"

    $registryTargets = @(
        [pscustomobject]@{
            Label = "Run dialog history"
            ProviderPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU"
            RegistryKey = "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU"
        },
        [pscustomobject]@{
            Label = "Recent documents history"
            ProviderPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs"
            RegistryKey = "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs"
        },
        [pscustomobject]@{
            Label = "Explorer typed paths"
            ProviderPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\TypedPaths"
            RegistryKey = "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\TypedPaths"
        },
        [pscustomobject]@{
            Label = "Explorer search box history"
            ProviderPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\WordWheelQuery"
            RegistryKey = "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\WordWheelQuery"
        },
        [pscustomobject]@{
            Label = "Open/save dialog history"
            ProviderPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\OpenSavePidlMRU"
            RegistryKey = "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\OpenSavePidlMRU"
        },
        [pscustomobject]@{
            Label = "Last visited dialog history"
            ProviderPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\LastVisitedPidlMRU"
            RegistryKey = "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\LastVisitedPidlMRU"
        }
    )

    foreach ($target in $registryTargets) {
        Remove-RegistryTree -Label $target.Label -ProviderPath $target.ProviderPath -RegistryKey $target.RegistryKey -BackupRoot $backupRoot
    }
}

function Invoke-DismComponentCleanup {
    if (-not $Deep) {
        return
    }

    if (-not (Test-IsAdministrator)) {
        Write-Log "Skipped DISM component cleanup because the script is not running as administrator." "WARN"
        return
    }

    $dismPath = Join-Path $env:SystemRoot "System32\dism.exe"
    if (-not (Test-Path -LiteralPath $dismPath)) {
        Write-Log "DISM was not found: $dismPath" "WARN"
        return
    }

    if ($DryRun) {
        Write-Log "[dry-run] Would run: dism.exe /Online /Cleanup-Image /StartComponentCleanup"
        return
    }

    Write-Log "Running DISM component cleanup. This can take a while."
    try {
        $process = Start-Process -FilePath $dismPath -ArgumentList "/Online", "/Cleanup-Image", "/StartComponentCleanup" -Wait -PassThru -NoNewWindow
        Write-Log "DISM finished with exit code $($process.ExitCode)."
    }
    catch {
        Write-Log "DISM component cleanup failed. $($_.Exception.Message)" "WARN"
    }
}

function Invoke-RecycleBinCleanup {
    if (-not $ClearRecycleBin) {
        return
    }

    $cmd = Get-Command Clear-RecycleBin -ErrorAction SilentlyContinue
    if ($null -eq $cmd) {
        Write-Log "Clear-RecycleBin is not available on this Windows installation." "WARN"
        return
    }

    if ($DryRun) {
        Write-Log "[dry-run] Would clear the Recycle Bin."
        return
    }

    try {
        Clear-RecycleBin -Force -ErrorAction Stop
        Write-Log "Recycle Bin cleared."
    }
    catch {
        Write-Log "Could not clear Recycle Bin. $($_.Exception.Message)" "WARN"
    }
}

if (-not [string]::IsNullOrWhiteSpace($Profile)) {
    switch ($Profile) {
        "Safe" {
            $AggressiveSafe = $true
            $TempOlderThanDays = [Math]::Min($TempOlderThanDays, 1)
            $CacheOlderThanDays = [Math]::Min($CacheOlderThanDays, 3)
        }
        "Gaming" {
            $AggressiveSafe = $true
            $CleanBrowserCaches = $true
            $CleanAppCaches = $true
            $CleanGameCaches = $true
            $TempOlderThanDays = [Math]::Min($TempOlderThanDays, 1)
            $CacheOlderThanDays = [Math]::Min($CacheOlderThanDays, 1)
        }
        "Deep" {
            $Deep = $true
            $AggressiveSafe = $true
            $CleanDeveloperCaches = $true
            $CleanGameCaches = $true
            $CleanRegistry = $true
            $TempOlderThanDays = [Math]::Min($TempOlderThanDays, 1)
            $CacheOlderThanDays = [Math]::Min($CacheOlderThanDays, 3)
        }
        "Emergency" {
            $Deep = $true
            $AggressiveSafe = $true
            $CleanDeveloperCaches = $true
            $CleanGameCaches = $true
            $CleanRegistry = $true
            $TempOlderThanDays = 0
            $CacheOlderThanDays = 0
        }
    }
}

if ($Analyze) {
    $DryRun = $true
}

if ($AggressiveSafe) {
    $CleanBrowserCaches = $true
    $CleanAppCaches = $true
    $CleanSpotifyCache = $true
    $CleanExtraPaths = $true
    $CleanGameCaches = $true
}

if ($CleanAppCaches) {
    $CleanSpotifyCache = $true
}

if ([string]::IsNullOrWhiteSpace($ExtraPathsFile)) {
    $ExtraPathsFile = Join-Path $PSScriptRoot "extra-cache-paths.txt"
}

if ([string]::IsNullOrWhiteSpace($GuardDrive)) {
    $GuardDrive = $env:SystemDrive
}

$modeName = if ($Analyze) {
    "analyze"
}
elseif ($DryRun) {
    "preview"
}
else {
    "clean"
}

$introLines = @(
    ("mode: {0}{1}{2}" -f $modeName, ($(if ($Deep) { " + deep" } else { "" })), ($(if ($SmartGuard) { " + guard" } else { "" }))),
    ("profile: {0}" -f (Get-ProfileName)),
    ("log: {0}" -f $LogFile)
)
if (-not [string]::IsNullOrWhiteSpace($script:ConfigSource)) {
    $introLines = @($introLines[0], $introLines[1], ("config: {0}" -f $script:ConfigSource), $introLines[2])
}

Write-Panel -Title "WinSweep" -Lines $introLines

Write-Log "Windows cleanup started. Version=$script:WinSweepVersion Profile=$(Get-ProfileName) Config=$script:ConfigSource Analyze=$Analyze Deep=$Deep DryRun=$DryRun SmartGuard=$SmartGuard AggressiveSafe=$AggressiveSafe BrowserCaches=$CleanBrowserCaches AppCaches=$CleanAppCaches SpotifyCache=$CleanSpotifyCache Registry=$CleanRegistry ExtraPaths=$CleanExtraPaths DeveloperCaches=$CleanDeveloperCaches GameCaches=$CleanGameCaches ClearRecycleBin=$ClearRecycleBin"
Write-Log "Log file: $LogFile" -Detail
if (-not [string]::IsNullOrWhiteSpace($script:ConfigLoadWarning)) {
    Write-Log $script:ConfigLoadWarning "WARN"
}

if ($SmartGuard -and -not (Test-ShouldRunSmartGuard -Drive $GuardDrive -MinimumFreeGB $MinFreeGB -MinimumFreePercent $MinFreePercent)) {
    Write-Panel -Title "Done" -Lines @("No cleanup needed right now.")
    exit 0
}

$startSnapshot = Get-DriveSnapshot -Drive $GuardDrive

Invoke-PreflightCheck

$targets = New-Object System.Collections.ArrayList
Add-Target -Targets $targets -Label "user temp" -Path $env:TEMP -Days $TempOlderThanDays
Add-Target -Targets $targets -Label "local app temp" -Path (Join-Path $env:LOCALAPPDATA "Temp") -Days $TempOlderThanDays
Add-Target -Targets $targets -Label "Windows temp" -Path (Join-Path $env:SystemRoot "Temp") -Days $TempOlderThanDays
Add-Target -Targets $targets -Label "Windows error reports" -Path (Join-Path $env:LOCALAPPDATA "Microsoft\Windows\WER") -Days $CacheOlderThanDays
Add-Target -Targets $targets -Label "DirectX shader cache" -Path (Join-Path $env:LOCALAPPDATA "D3DSCache") -Days $CacheOlderThanDays
Add-SystemCacheTargets -Targets $targets -Days $CacheOlderThanDays

if ($Deep) {
    Add-Target -Targets $targets -Label "Windows Update download cache" -Path (Join-Path $env:SystemRoot "SoftwareDistribution\Download") -Days $CacheOlderThanDays
    Add-Target -Targets $targets -Label "Delivery Optimization cache" -Path (Join-Path $env:ProgramData "Microsoft\Windows\DeliveryOptimization\Cache") -Days $CacheOlderThanDays
}

if ($CleanBrowserCaches) {
    Add-WildcardTargets -Targets $targets -Label "Microsoft Edge cache" -Pattern (Join-Path $env:LOCALAPPDATA "Microsoft\Edge\User Data\*\Cache\Cache_Data") -Days $CacheOlderThanDays
    Add-WildcardTargets -Targets $targets -Label "Google Chrome cache" -Pattern (Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data\*\Cache\Cache_Data") -Days $CacheOlderThanDays
    Add-WildcardTargets -Targets $targets -Label "Brave cache" -Pattern (Join-Path $env:LOCALAPPDATA "BraveSoftware\Brave-Browser\User Data\*\Cache\Cache_Data") -Days $CacheOlderThanDays
    Add-WildcardTargets -Targets $targets -Label "Firefox cache" -Pattern (Join-Path $env:LOCALAPPDATA "Mozilla\Firefox\Profiles\*\cache2\entries") -Days $CacheOlderThanDays
}

if ($CleanSpotifyCache -and -not $CleanAppCaches) {
    Add-SpotifyCacheTargets -Targets $targets -Days $CacheOlderThanDays
}

if ($CleanAppCaches) {
    Add-AppCacheTargets -Targets $targets -Days $CacheOlderThanDays
}

if ($CleanDeveloperCaches) {
    Add-DeveloperCacheTargets -Targets $targets -Days $CacheOlderThanDays
}

if ($CleanGameCaches) {
    Add-GameCacheTargets -Targets $targets -Days $CacheOlderThanDays
}

if ($CleanRegistry) {
    Add-Target -Targets $targets -Label "Explorer recent shortcuts" -Path (Join-Path $env:APPDATA "Microsoft\Windows\Recent") -Days 0
}

if ($CleanExtraPaths) {
    Add-ExtraPathTargets -Targets $targets -PathFile $ExtraPathsFile -Days $CacheOlderThanDays
}

$seen = @{}
foreach ($target in $targets) {
    if ([string]::IsNullOrWhiteSpace($target.Path)) {
        continue
    }

    try {
        $key = [IO.Path]::GetFullPath($target.Path).TrimEnd("\").ToLowerInvariant()
    }
    catch {
        Write-Log "Skipped invalid path for $($target.Label): $($target.Path)" "WARN"
        continue
    }

    if ($seen.ContainsKey($key)) {
        continue
    }

    $seen[$key] = $true
    Remove-OldContents -Label $target.Label -Path $target.Path -OlderThanDays $target.Days
}

Invoke-RegistryCleanup
Invoke-RecycleBinCleanup
Invoke-DismComponentCleanup

try {
    $logCutoff = (Get-Date).AddDays(-[Math]::Abs($LogRetentionDays))
    Get-ChildItem -LiteralPath $LogDir -Filter "cleanup-*.log" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $logCutoff } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}
catch {
    Write-Log "Could not rotate old logs. $($_.Exception.Message)" "WARN"
}

$endSnapshot = Get-DriveSnapshot -Drive $GuardDrive
$diskSummaryLines = Get-DiskSummaryLines -Before $startSnapshot -After $endSnapshot

if ($DryRun) {
    $previewName = if ($Analyze) { "Analyze" } else { "Preview" }
    Write-Log ("{0} finished. Would clean {1} item(s), about {2}, failures: {3}." -f $previewName, $script:PotentialItems, (Format-ByteSize $script:PotentialBytes), $script:FailedItems)
    Show-ScanResults -Mode "preview"
    $summaryLines = @(
        ("would clean: {0} item(s)" -f $script:PotentialItems),
        ("estimated reclaim: {0}" -f (Format-ByteSize $script:PotentialBytes)),
        ("failures: {0}" -f $script:FailedItems)
    )
    $summaryLines += $diskSummaryLines
    Write-HtmlReport -Mode $previewName -Before $startSnapshot -After $endSnapshot -SummaryLines $summaryLines
    if (-not [string]::IsNullOrWhiteSpace($script:HtmlReportPath)) {
        $summaryLines += ("html report: {0}" -f $script:HtmlReportPath)
    }
    Write-Panel -Title "Summary" -Lines $summaryLines
}
else {
    Write-Log ("Windows cleanup finished. Removed {0} item(s), reclaimed about {1}, failures: {2}." -f $script:DeletedItems, (Format-ByteSize $script:DeletedBytes), $script:FailedItems)
    Show-ScanResults -Mode "clean"
    $summaryLines = @(
        ("removed: {0} item(s)" -f $script:DeletedItems),
        ("reclaimed: {0}" -f (Format-ByteSize $script:DeletedBytes)),
        ("failures: {0}" -f $script:FailedItems)
    )
    $summaryLines += $diskSummaryLines
    Write-HtmlReport -Mode "clean" -Before $startSnapshot -After $endSnapshot -SummaryLines $summaryLines
    if (-not [string]::IsNullOrWhiteSpace($script:HtmlReportPath)) {
        $summaryLines += ("html report: {0}" -f $script:HtmlReportPath)
    }
    Write-Panel -Title "Summary" -Lines $summaryLines
}

Show-CloseHints

if ($script:FailedItems -gt 0) {
    exit 1
}

exit 0
