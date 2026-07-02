@echo off
setlocal
set "LOGDIR=%ProgramData%\CodexWindowsCleanup\Logs"

if not exist "%LOGDIR%" (
    set "LOGDIR=%TEMP%\CodexWindowsCleanup\Logs"
)

if not exist "%LOGDIR%" (
    mkdir "%LOGDIR%" >nul 2>&1
)

start "" "%LOGDIR%"
