@echo off
setlocal
set "SCRIPT=%~dp0repair-powershell-shortcut.ps1"
set "POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

if not exist "%SCRIPT%" (
    echo repair-powershell-shortcut.ps1 was not found next to this file.
    pause
    exit /b 1
)

if not exist "%POWERSHELL%" (
    echo Windows PowerShell was not found at "%POWERSHELL%".
    pause
    exit /b 1
)

"%POWERSHELL%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
set "EXITCODE=%ERRORLEVEL%"
echo.
echo PowerShell shortcut repair finished with exit code %EXITCODE%.
pause
exit /b %EXITCODE%
