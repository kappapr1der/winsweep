[CmdletBinding()]
param(
    [switch]$Test,
    [ValidateRange(0, 60)]
    [int]$AutoCloseSeconds = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$encodingHelper = Join-Path $PSScriptRoot "winsweep-encoding.ps1"
if (Test-Path -LiteralPath $encodingHelper -PathType Leaf) {
    . $encodingHelper
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$script:WinSweepVersion = "1.0.2"
$script:PowerShellPath = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$script:ConfigPath = Join-Path $PSScriptRoot "winsweep-config.json"
$script:ActiveProcess = $null
$script:ActiveAction = ""
$script:CacheCheckboxes = @{}
$script:Config = $null

if (-not (Test-Path -LiteralPath $script:PowerShellPath -PathType Leaf)) {
    throw "Windows PowerShell 5.1 was not found: $script:PowerShellPath"
}

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="WinSweep Control Center"
        Width="1120" Height="760" MinWidth="900" MinHeight="640"
        WindowStartupLocation="CenterScreen"
        Background="#F4F7F8"
        FontFamily="Segoe UI">
    <Window.Resources>
        <Style TargetType="{x:Type Button}">
            <Setter Property="Margin" Value="0,0,10,10"/>
            <Setter Property="Padding" Value="16,10"/>
            <Setter Property="MinHeight" Value="38"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="Background" Value="#147D78"/>
            <Setter Property="BorderBrush" Value="#0E5E5A"/>
            <Setter Property="BorderThickness" Value="1"/>
        </Style>
        <Style x:Key="SecondaryButton" TargetType="{x:Type Button}">
            <Setter Property="Margin" Value="0,0,10,10"/>
            <Setter Property="Padding" Value="14,9"/>
            <Setter Property="MinHeight" Value="36"/>
            <Setter Property="Foreground" Value="#1E2933"/>
            <Setter Property="Background" Value="#E4ECEE"/>
            <Setter Property="BorderBrush" Value="#B8C8CC"/>
            <Setter Property="BorderThickness" Value="1"/>
        </Style>
        <Style TargetType="{x:Type TabItem}">
            <Setter Property="Padding" Value="16,9"/>
            <Setter Property="FontSize" Value="14"/>
        </Style>
        <Style TargetType="{x:Type CheckBox}">
            <Setter Property="Margin" Value="0,5,16,5"/>
            <Setter Property="FontSize" Value="14"/>
        </Style>
    </Window.Resources>
    <Grid Margin="24">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="160"/>
        </Grid.RowDefinitions>

        <Grid Grid.Row="0" Margin="0,0,0,20">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <StackPanel>
                <TextBlock Text="WinSweep" FontSize="30" FontWeight="SemiBold" Foreground="#172B32"/>
                <TextBlock Text="Control Center · одна кнопка для безопасной очистки, места и настроек" FontSize="14" Foreground="#5A6B72" Margin="0,4,0,0"/>
            </StackPanel>
            <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                <Button x:Name="RefreshButton" Content="Обновить" Style="{StaticResource SecondaryButton}"/>
                <Button x:Name="OpenFolderButton" Content="Открыть папку" Style="{StaticResource SecondaryButton}"/>
            </StackPanel>
        </Grid>

        <ScrollViewer Grid.Row="1" HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Disabled" Margin="0,0,0,20">
            <StackPanel x:Name="DrivePanel" Orientation="Horizontal"/>
        </ScrollViewer>

        <TabControl Grid.Row="2" x:Name="MainTabs">
            <TabItem Header="Обзор">
                <Grid Margin="18">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <TextBlock Text="Быстрые действия" FontSize="20" FontWeight="SemiBold" Foreground="#172B32" Margin="0,0,0,14"/>
                    <WrapPanel Grid.Row="1">
                        <Button x:Name="RecommendedCleanupButton" Content="Очистить безопасно" FontWeight="SemiBold" Padding="20,11"/>
                        <Button x:Name="AnalyzeButton" Content="Анализ очистки"/>
                        <Button x:Name="SafeCleanupButton" Content="Безопасная очистка"/>
                        <Button x:Name="SmartCleanupButton" Content="Умная очистка"/>
                        <Button x:Name="SpaceHogButton" Content="Пожиратели места"/>
                        <Button x:Name="OpenReportButton" Content="Последний отчёт" Style="{StaticResource SecondaryButton}"/>
                        <Button x:Name="HistoryButton" Content="История" Style="{StaticResource SecondaryButton}"/>
                    </WrapPanel>
                    <Border Grid.Row="2" Background="White" BorderBrush="#D3DEE1" BorderThickness="1" Padding="16" Margin="0,8,0,0">
                        <StackPanel>
                            <TextBlock Text="Состояние" FontSize="16" FontWeight="SemiBold" Foreground="#172B32"/>
                            <TextBlock x:Name="OverviewText" TextWrapping="Wrap" Foreground="#5A6B72" Margin="0,8,0,0"/>
                            <TextBlock x:Name="ActivitySummaryText" Text="Готово к запуску действия." TextWrapping="Wrap" FontWeight="SemiBold" Foreground="#147D78" Margin="0,12,0,0"/>
                            <TextBlock Text="Очистка запускается существующими PowerShell-сценариями WinSweep, поэтому GUI не меняет их безопасные правила." TextWrapping="Wrap" Foreground="#5A6B72" Margin="0,16,0,0"/>
                        </StackPanel>
                    </Border>
                </Grid>
            </TabItem>
            <TabItem Header="Кэши и правила">
                <Grid Margin="18">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <TextBlock Text="Что разрешено очищать" FontSize="20" FontWeight="SemiBold" Foreground="#172B32" Margin="0,0,0,6"/>
                    <TextBlock Grid.Row="1" Text="Переключатели сохраняются в winsweep-config.json и применяются планировщиком." Foreground="#5A6B72" Margin="0,0,0,10"/>
                    <ScrollViewer Grid.Row="1" Margin="0,34,0,10" VerticalScrollBarVisibility="Auto">
                        <WrapPanel x:Name="CachePanel"/>
                    </ScrollViewer>
                    <StackPanel Grid.Row="2" Orientation="Horizontal">
                        <Button x:Name="SaveSettingsButton" Content="Сохранить настройки"/>
                        <Button x:Name="OpenConfigButton" Content="Открыть JSON" Style="{StaticResource SecondaryButton}"/>
                    </StackPanel>
                </Grid>
            </TabItem>
            <TabItem Header="Система">
                <StackPanel Margin="18">
                    <TextBlock Text="Системное обслуживание" FontSize="20" FontWeight="SemiBold" Foreground="#172B32"/>
                    <TextBlock Text="Обратимые действия и диагностика. Системные изменения запускаются с подтверждением UAC." TextWrapping="Wrap" Foreground="#5A6B72" Margin="0,8,0,18"/>
                    <WrapPanel>
                        <Button x:Name="SystemStatusButton" Content="Состояние системы" Style="{StaticResource SecondaryButton}"/>
                        <Button x:Name="AnalyzeComponentStoreButton" Content="Анализ хранилища компонентов" Style="{StaticResource SecondaryButton}"/>
                        <Button x:Name="DeepMaintenanceButton" Content="Глубокое обслуживание"/>
                        <Button x:Name="DisableHibernationButton" Content="Отключить гибернацию" Style="{StaticResource SecondaryButton}"/>
                        <Button x:Name="EnableHibernationButton" Content="Включить гибернацию" Style="{StaticResource SecondaryButton}"/>
                        <Button x:Name="LogEncodingButton" Content="Проверить кодировку логов" Style="{StaticResource SecondaryButton}"/>
                    </WrapPanel>
                    <Border Background="#FFF9ED" BorderBrush="#E4C46A" BorderThickness="1" Padding="14" Margin="0,8,0,0">
                        <TextBlock x:Name="SystemSafetyText" TextWrapping="Wrap" Foreground="#604A16"/>
                    </Border>
                </StackPanel>
            </TabItem>
            <TabItem Header="Планировщик">
                <StackPanel Margin="18">
                    <TextBlock Text="Автоматическая уборка" FontSize="20" FontWeight="SemiBold" Foreground="#172B32"/>
                    <TextBlock x:Name="ScheduleText" TextWrapping="Wrap" Foreground="#5A6B72" Margin="0,8,0,18"/>
                    <WrapPanel>
                        <Button x:Name="InstallScheduleButton" Content="Переустановить задачи"/>
                        <Button x:Name="RepairShortcutButton" Content="Починить ярлыки PowerShell" Style="{StaticResource SecondaryButton}"/>
                    </WrapPanel>
                    <TextBlock Text="Pressure Guard запускает безопасную очистку только при достижении порогов свободного места. Глубокая еженедельная задача остаётся отдельной." TextWrapping="Wrap" Foreground="#5A6B72" Margin="0,14,0,0"/>
                </StackPanel>
            </TabItem>
            <TabItem Header="Отчёты и история">
                <StackPanel Margin="18">
                    <TextBlock Text="Отчёты" FontSize="20" FontWeight="SemiBold" Foreground="#172B32"/>
                    <TextBlock Text="Все отчёты остаются локальными. HTML открывается в Chrome, если он установлен." Foreground="#5A6B72" Margin="0,8,0,18"/>
                    <WrapPanel>
                        <Button x:Name="SpaceReportButton" Content="Диагностика места"/>
                        <Button x:Name="OpenLatestReportButton" Content="Открыть последний HTML" Style="{StaticResource SecondaryButton}"/>
                        <Button x:Name="ShowHistoryButton" Content="Показать историю" Style="{StaticResource SecondaryButton}"/>
                        <Button x:Name="OpenLogsButton" Content="Открыть логи" Style="{StaticResource SecondaryButton}"/>
                    </WrapPanel>
                </StackPanel>
            </TabItem>
        </TabControl>

        <Border Grid.Row="3" Background="#172B32" Padding="14" Margin="0,18,0,0">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                <DockPanel LastChildFill="False">
                    <TextBlock Text="Журнал запуска" DockPanel.Dock="Left" Foreground="White" FontSize="15" FontWeight="SemiBold"/>
                    <ProgressBar x:Name="ActivityProgress" DockPanel.Dock="Right" Width="150" Height="10" IsIndeterminate="False" Margin="20,4,0,0"/>
                    <TextBlock x:Name="ActivityStatusText" DockPanel.Dock="Right" Text="Готово" Foreground="#D9F1ED" Margin="0,0,8,0" VerticalAlignment="Center"/>
                </DockPanel>
                <TextBox Grid.Row="1" x:Name="LogBox" Background="#0E1D22" Foreground="#D9F1ED" BorderThickness="0" IsReadOnly="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="8" Margin="0,10,0,0"/>
            </Grid>
        </Border>
    </Grid>
</Window>
'@

$window = [Windows.Markup.XamlReader]::Parse($xaml)

function Get-Control {
    param([string]$Name)
    $control = $window.FindName($Name)
    if ($null -eq $control) {
        throw "GUI control was not found: $Name"
    }
    return $control
}

$drivePanel = Get-Control "DrivePanel"
$cachePanel = Get-Control "CachePanel"
$overviewText = Get-Control "OverviewText"
$activitySummaryText = Get-Control "ActivitySummaryText"
$scheduleText = Get-Control "ScheduleText"
$systemSafetyText = Get-Control "SystemSafetyText"
$logBox = Get-Control "LogBox"
$activityProgress = Get-Control "ActivityProgress"
$activityStatusText = Get-Control "ActivityStatusText"

function Add-Log {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return
    }
    $logBox.AppendText(("[{0}] {1}{2}" -f (Get-Date).ToString("HH:mm:ss"), $Text.Trim(), [Environment]::NewLine))
    $logBox.ScrollToEnd()
}

function Read-Config {
    if (-not (Test-Path -LiteralPath $script:ConfigPath -PathType Leaf)) {
        throw "winsweep-config.json was not found: $script:ConfigPath"
    }
    $script:Config = Get-Content -LiteralPath $script:ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
}

function Get-ConfigValue {
    param(
        $Object,
        [string]$Name,
        $Fallback = $null
    )
    if ($null -eq $Object) {
        return $Fallback
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) {
        return $Fallback
    }
    return $property.Value
}

function Save-Config {
    foreach ($entry in $script:CacheCheckboxes.GetEnumerator()) {
        $script:Config.features | Add-Member -NotePropertyName $entry.Key -NotePropertyValue ([bool]$entry.Value.IsChecked) -Force
    }
    [IO.File]::WriteAllText($script:ConfigPath, ($script:Config | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
    Add-Log "Настройки сохранены: $script:ConfigPath"
    $overviewText.Text = "Настройки сохранены. Планировщик использует их при следующем запуске."
}

function Format-Bytes {
    param([int64]$Bytes)
    if ($Bytes -ge 1TB) { return "{0:N1} TB" -f ($Bytes / 1TB) }
    if ($Bytes -ge 1GB) { return "{0:N1} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N1} MB" -f ($Bytes / 1MB) }
    return "{0:N0} KB" -f ($Bytes / 1KB)
}

function Refresh-Drives {
    $drivePanel.Children.Clear()
    $driveCount = 0
    foreach ($drive in [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady -and $_.TotalSize -gt 0 } | Sort-Object Name) {
        $driveCount++
        $freePercent = [Math]::Round(($drive.AvailableFreeSpace / $drive.TotalSize) * 100, 1)
        $accent = if ($freePercent -lt 10) { '#C2413D' } elseif ($freePercent -lt 20) { '#C47A22' } else { '#147D78' }
        $border = New-Object System.Windows.Controls.Border
        $border.Background = [Windows.Media.BrushConverter]::new().ConvertFromString('#FFFFFF')
        $border.BorderBrush = [Windows.Media.BrushConverter]::new().ConvertFromString('#D3DEE1')
        $border.BorderThickness = New-Object Windows.Thickness(1)
        $border.Padding = New-Object Windows.Thickness(16)
        $border.Margin = New-Object Windows.Thickness(0,0,12,0)
        $border.Width = 220
        $stack = New-Object System.Windows.Controls.StackPanel
        $title = New-Object System.Windows.Controls.TextBlock
        $title.Text = $drive.Name.TrimEnd('\')
        $title.FontSize = 20
        $title.FontWeight = 'SemiBold'
        $title.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString($accent)
        $free = New-Object System.Windows.Controls.TextBlock
        $free.Text = "{0} свободно из {1}" -f (Format-Bytes $drive.AvailableFreeSpace), (Format-Bytes $drive.TotalSize)
        $free.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#344B52')
        $free.Margin = New-Object Windows.Thickness(0,5,0,0)
        $percent = New-Object System.Windows.Controls.TextBlock
        $percent.Text = "{0}% свободно" -f $freePercent
        $percent.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#5A6B72')
        $percent.Margin = New-Object Windows.Thickness(0,3,0,0)
        [void]$stack.Children.Add($title)
        [void]$stack.Children.Add($free)
        [void]$stack.Children.Add($percent)
        $border.Child = $stack
        [void]$drivePanel.Children.Add($border)
    }
    if ($driveCount -eq 0) {
        $overviewText.Text = "Локальные диски не найдены."
    }
}

function Refresh-CacheControls {
    $cachePanel.Children.Clear()
    $script:CacheCheckboxes = @{}
    $labels = [ordered]@{
        spotifyCache = 'Spotify'
        discordCache = 'Discord'
        telegramCache = 'Telegram Desktop'
        slackCache = 'Slack'
        teamsCache = 'Microsoft Teams'
        zoomCache = 'Zoom'
        browserCaches = 'Браузеры'
        developerCaches = 'Инструменты разработки'
        gameCaches = 'Игровые лаунчеры'
        notifyOnPressure = 'Уведомления о нехватке места'
    }
    foreach ($entry in $labels.GetEnumerator()) {
        $check = New-Object System.Windows.Controls.CheckBox
        $check.Content = $entry.Value
        $check.Tag = $entry.Key
        $check.Width = 280
        $check.IsChecked = [bool](Get-ConfigValue -Object $script:Config.features -Name $entry.Key -Fallback $false)
        [void]$cachePanel.Children.Add($check)
        $script:CacheCheckboxes[$entry.Key] = $check
    }
}

function Refresh-Summary {
    $features = $script:Config.features
    $enabled = @($script:CacheCheckboxes.GetEnumerator() | Where-Object { $_.Value.IsChecked } | ForEach-Object { $_.Value.Content })
    $profile = [string](Get-ConfigValue -Object $script:Config -Name 'defaultProfile' -Fallback 'Safe')
    $schedule = $script:Config.schedule
    $overviewText.Text = "Профиль по умолчанию: $profile. Включено переключателей: $($enabled.Count). Последняя проверка дисков обновляется кнопкой «Обновить»."
    $scheduleText.Text = "Pressure Guard: каждые $([int](Get-ConfigValue -Object $schedule -Name 'guardEveryHours' -Fallback 3)) ч. с $([string](Get-ConfigValue -Object $schedule -Name 'guardStart' -Fallback '00:15')). Deep Weekly: $([string](Get-ConfigValue -Object $schedule -Name 'deepDay' -Fallback 'Sunday')) в $([string](Get-ConfigValue -Object $schedule -Name 'deepWeekly' -Fallback '03:20'))."
}

function Refresh-SystemSummary {
    $drive = if ([string]::IsNullOrWhiteSpace($env:SystemDrive)) { 'C:' } else { $env:SystemDrive.TrimEnd('\') }
    $hiberFile = Join-Path "$drive\" 'hiberfil.sys'
    $hiberSize = [int64]0
    if (Test-Path -LiteralPath $hiberFile -PathType Leaf) {
        $hiberSize = [int64](Get-Item -LiteralPath $hiberFile).Length
    }
    $hiberText = if ($hiberSize -gt 0) { (Format-Bytes $hiberSize) } else { 'не найден' }
    $systemSafetyText.Text = "Файл гибернации: $hiberText. Отключение освобождает место, но выключает гибернацию и Fast Startup; включение полностью обратимо. Анализ компонентного хранилища ничего не меняет."
}

function ConvertTo-PowerShellLiteral {
    param([string]$Value)
    return "'" + ([string]$Value).Replace("'", "''") + "'"
}

function ConvertTo-ProcessArguments {
    param([string[]]$Arguments)
    return (($Arguments | ForEach-Object {
        $value = [string]$_
        if ($value -match '[\s"]') { '"' + $value.Replace('"', '\"') + '"' } else { $value }
    }) -join ' ')
}

function Get-ActionTitle {
    param([string]$FileName)

    switch ($FileName) {
        'cleanup-windows.ps1' { return 'Очистка' }
        'space-hog-report.ps1' { return 'Анализ места' }
        'system-maintenance-check.ps1' { return 'Проверка системы' }
        'system-tweaks.ps1' { return 'Системное действие' }
        'install-scheduled-cleanup.ps1' { return 'Настройка Планировщика' }
        'check-log-encoding.ps1' { return 'Проверка кодировки' }
        default { return $FileName }
    }
}

function Set-ActionState {
    param(
        [bool]$Running,
        [string]$Message
    )

    $activityProgress.IsIndeterminate = $Running
    if (-not $Running) {
        $activityProgress.Value = 0
    }
    $activityStatusText.Text = $Message
    $activitySummaryText.Text = $Message
    $activitySummaryText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString(
        $(if ($Running) { '#C47A22' } else { '#147D78' }))

    foreach ($name in @($script:ActionControlNames)) {
        $control = $window.FindName($name)
        if ($null -ne $control) {
            $control.IsEnabled = -not $Running
        }
    }
}

function Complete-WinSweepAction {
    param(
        [int]$ExitCode,
        [string]$ActionTitle,
        [switch]$Elevated
    )

    if ($null -eq $script:ActiveProcess) {
        return
    }

    $script:ActiveProcess = $null
    $script:ActiveAction = ''
    $result = if ($ExitCode -eq 0) { "$ActionTitle завершено." } else { "$ActionTitle завершено с кодом $ExitCode. Проверь журнал ниже." }
    Set-ActionState -Running $false -Message $result
    Add-Log $result
    try {
        Refresh-Drives
        Refresh-SystemSummary
    }
    catch {
        Add-Log ("Не удалось обновить состояние дисков: " + $_.Exception.Message)
    }
}

function Watch-WinSweepProcess {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$ActionTitle,
        [switch]$Elevated
    )

    $Process.EnableRaisingEvents = $true
    $Process.add_Exited({
        param($sender, $eventArgs)
        $exitCode = $sender.ExitCode
        $window.Dispatcher.BeginInvoke([Action]{
            Complete-WinSweepAction -ExitCode $exitCode -ActionTitle $ActionTitle -Elevated:$Elevated
        }.GetNewClosure()) | Out-Null
    }.GetNewClosure())

    if ($Process.HasExited) {
        Complete-WinSweepAction -ExitCode $Process.ExitCode -ActionTitle $ActionTitle -Elevated:$Elevated
    }
}

function Start-WinSweepScript {
    param(
        [string]$FileName,
        [string[]]$ScriptArguments = @(),
        [switch]$Elevated
    )

    if ($null -ne $script:ActiveProcess -and -not $script:ActiveProcess.HasExited) {
        Add-Log "Действие уже выполняется. Дождись завершения текущего запуска."
        return
    }
    $actionTitle = Get-ActionTitle -FileName $FileName
    $target = Join-Path $PSScriptRoot $FileName
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
        Add-Log "Файл не найден: $target"
        return
    }
    $commandParts = @(
        '[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)'
        '$global:OutputEncoding = [Console]::OutputEncoding'
        ('& ' + (ConvertTo-PowerShellLiteral $target) + ' ' + (($ScriptArguments | ForEach-Object { ConvertTo-PowerShellLiteral ([string]$_) }) -join ' '))
        'exit $LASTEXITCODE'
    )
    $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(($commandParts -join '; ')))
    $args = @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-EncodedCommand',$encodedCommand)
    Set-ActionState -Running $true -Message ("Выполняется: $actionTitle. Не закрывай WinSweep.")
    if ($Elevated) {
        try {
            $process = Start-Process -FilePath $script:PowerShellPath -ArgumentList (ConvertTo-ProcessArguments $args) -Verb RunAs -PassThru -ErrorAction Stop
            $script:ActiveProcess = $process
            $script:ActiveAction = $actionTitle
            Watch-WinSweepProcess -Process $process -ActionTitle $actionTitle -Elevated
            Add-Log "Запущено с правами администратора: $FileName. Подтверди UAC, затем прогресс останется здесь."
        }
        catch {
            $script:ActiveProcess = $null
            Set-ActionState -Running $false -Message ("Не удалось запустить $actionTitle.")
            Add-Log ("ОШИБКА запуска с правами администратора: " + $_.Exception.Message)
        }
        return
    }

    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $script:PowerShellPath
    $info.Arguments = ConvertTo-ProcessArguments $args
    $info.WorkingDirectory = $PSScriptRoot
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $info.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    $process.add_OutputDataReceived({
        param($sender, $eventArgs)
        $outputLine = $eventArgs.Data
        if (-not [string]::IsNullOrWhiteSpace($outputLine)) {
            $window.Dispatcher.BeginInvoke([Action]{ Add-Log $outputLine }.GetNewClosure()) | Out-Null
        }
    }.GetNewClosure())
    $process.add_ErrorDataReceived({
        param($sender, $eventArgs)
        $errorLine = $eventArgs.Data
        if (-not [string]::IsNullOrWhiteSpace($errorLine)) {
            $window.Dispatcher.BeginInvoke([Action]{ Add-Log ("ОШИБКА: " + $errorLine) }.GetNewClosure()) | Out-Null
        }
    }.GetNewClosure())
    try {
        if (-not $process.Start()) {
            throw "Процесс не был запущен."
        }
        $script:ActiveProcess = $process
        $script:ActiveAction = $actionTitle
        Watch-WinSweepProcess -Process $process -ActionTitle $actionTitle
        Add-Log "Запуск: $actionTitle"
        $process.BeginOutputReadLine()
        $process.BeginErrorReadLine()
    }
    catch {
        $script:ActiveProcess = $null
        Set-ActionState -Running $false -Message ("Не удалось запустить $actionTitle.")
        Add-Log ("ОШИБКА запуска: " + $_.Exception.Message)
    }
}

function Open-ExternalPath {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        Start-Process -FilePath $Path | Out-Null
    }
}

Read-Config
Refresh-Drives
Refresh-CacheControls
Refresh-Summary
Refresh-SystemSummary
Add-Log "Control Center v$script:WinSweepVersion готов."

$controls = @{
    RefreshButton = { Refresh-Drives; Refresh-Summary; Refresh-SystemSummary; Add-Log "Данные обновлены." }
    OpenFolderButton = { Open-ExternalPath -Path $PSScriptRoot }
    RecommendedCleanupButton = { Start-WinSweepScript -FileName 'cleanup-windows.ps1' -ScriptArguments @('-Profile','Safe','-SmartGuard','-OpenReport','-ConfigPath',$script:ConfigPath) }
    AnalyzeButton = { Start-WinSweepScript -FileName 'cleanup-windows.ps1' -ScriptArguments @('-Analyze','-Profile','Emergency','-OpenReport','-ConfigPath',$script:ConfigPath) }
    SafeCleanupButton = { Start-WinSweepScript -FileName 'cleanup-windows.ps1' -ScriptArguments @('-Profile','Safe','-OpenReport','-ConfigPath',$script:ConfigPath) }
    SmartCleanupButton = { Start-WinSweepScript -FileName 'cleanup-windows.ps1' -ScriptArguments @('-SmartGuard','-AggressiveSafe','-CleanDeveloperCaches','-CleanRegistry','-ConfigPath',$script:ConfigPath) }
    SpaceHogButton = { Start-WinSweepScript -FileName 'space-hog-report.ps1' -ScriptArguments @('-Top','12','-OpenReport') }
    OpenReportButton = { Start-WinSweepScript -FileName 'open-latest-report.ps1' }
    HistoryButton = { Start-WinSweepScript -FileName 'show-cleanup-history.ps1' }
    SaveSettingsButton = { Save-Config; Refresh-Summary }
    OpenConfigButton = { Start-Process -FilePath 'notepad.exe' -ArgumentList ('"{0}"' -f $script:ConfigPath) }
    InstallScheduleButton = { Start-WinSweepScript -FileName 'install-scheduled-cleanup.ps1' -ScriptArguments @('-ConfigPath',$script:ConfigPath) -Elevated }
    RepairShortcutButton = { Start-WinSweepScript -FileName 'repair-powershell-shortcut.ps1' }
    SystemStatusButton = { Start-WinSweepScript -FileName 'system-maintenance-check.ps1' }
    AnalyzeComponentStoreButton = { Start-WinSweepScript -FileName 'system-maintenance-check.ps1' -ScriptArguments @('-AnalyzeComponentStore') -Elevated }
    DeepMaintenanceButton = { Start-WinSweepScript -FileName 'cleanup-windows.ps1' -ScriptArguments @('-Profile','Deep','-OpenReport','-ConfigPath',$script:ConfigPath) -Elevated }
    DisableHibernationButton = { Start-WinSweepScript -FileName 'system-tweaks.ps1' -ScriptArguments @('-DisableHibernation') -Elevated; Refresh-SystemSummary }
    EnableHibernationButton = { Start-WinSweepScript -FileName 'system-tweaks.ps1' -ScriptArguments @('-EnableHibernation') -Elevated; Refresh-SystemSummary }
    LogEncodingButton = { Start-WinSweepScript -FileName 'check-log-encoding.ps1' }
    SpaceReportButton = { Start-WinSweepScript -FileName 'space-hog-report.ps1' -ScriptArguments @('-Top','12','-OpenReport') }
    OpenLatestReportButton = { Start-WinSweepScript -FileName 'open-latest-report.ps1' }
    ShowHistoryButton = { Start-WinSweepScript -FileName 'show-cleanup-history.ps1' }
    OpenLogsButton = { Open-ExternalPath -Path (Join-Path $env:ProgramData 'CodexWindowsCleanup\Logs') }
}

$script:ActionControlNames = @(
    'RecommendedCleanupButton', 'AnalyzeButton', 'SafeCleanupButton', 'SmartCleanupButton',
    'SpaceHogButton', 'OpenReportButton', 'HistoryButton', 'InstallScheduleButton',
    'RepairShortcutButton', 'SystemStatusButton', 'AnalyzeComponentStoreButton',
    'DeepMaintenanceButton', 'DisableHibernationButton', 'EnableHibernationButton',
    'LogEncodingButton', 'SpaceReportButton', 'OpenLatestReportButton', 'ShowHistoryButton'
)

foreach ($entry in $controls.GetEnumerator()) {
    $control = Get-Control $entry.Key
    $action = $entry.Value
    $control.Add_Click({
        try {
            & $action
        }
        catch {
            $message = $_.Exception.Message
            $script:ActiveProcess = $null
            Set-ActionState -Running $false -Message 'Действие не запустилось. Подробности в журнале.'
            Add-Log ("ОШИБКА интерфейса: " + $message)
        }
    }.GetNewClosure())
}

if ($Test) {
    Write-Output ("WINSWEEP_UI_TEST_OK controls={0} caches={1} version={2}" -f $controls.Count, $script:CacheCheckboxes.Count, $script:WinSweepVersion)
    return
}

if ($AutoCloseSeconds -gt 0) {
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = New-TimeSpan -Seconds $AutoCloseSeconds
    $timer.Add_Tick({ $timer.Stop(); $window.Close() })
    $timer.Start()
}

[void]$window.ShowDialog()
