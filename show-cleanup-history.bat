@echo off
setlocal
set "SCRIPT=%~dp0show-cleanup-history.ps1"

if not exist "%SCRIPT%" (
    echo show-cleanup-history.ps1 was not found next to this file.
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
set "EXITCODE=%ERRORLEVEL%"
echo.
echo History finished with exit code %EXITCODE%.
pause
exit /b %EXITCODE%
