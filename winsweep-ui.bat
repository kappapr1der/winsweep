@echo off
setlocal
set "SCRIPT=%~dp0winsweep-ui.ps1"
set "POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

if not exist "%SCRIPT%" (
    echo winsweep-ui.ps1 was not found next to this file.
    pause
    exit /b 1
)

if not exist "%POWERSHELL%" (
    echo Windows PowerShell 5.1 was not found at "%POWERSHELL%".
    pause
    exit /b 1
)

"%POWERSHELL%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
set "EXITCODE=%ERRORLEVEL%"
if not "%EXITCODE%"=="0" (
    echo.
    echo WinSweep Control Center exited with code %EXITCODE%.
    pause
)
exit /b %EXITCODE%
