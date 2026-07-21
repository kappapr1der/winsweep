@echo off
setlocal
set "SCRIPT=%~dp0check-log-encoding.ps1"
set "POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
chcp 65001 >nul

if not exist "%SCRIPT%" (
    echo check-log-encoding.ps1 was not found next to this file.
    pause
    exit /b 1
)

"%POWERSHELL%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
set "EXITCODE=%ERRORLEVEL%"
echo.
echo Finished with exit code %EXITCODE%.
pause
exit /b %EXITCODE%
